extends Node2D
## FORTRESS: gameplay prototype drawn with basic shapes. See DESIGN.md.
## Loop: gather wood and stone, carry them to build pads, turn wood into ammo at the machine and
## carry the boxes to the turrets. Monsters march straight down three lanes; each one that reaches
## the wall cracks the gate, and the gate breaks after enough cracks.
##
## Automation (after `--`):
##   sim=bot | sim=idle      headless balance run: prints a log and quits
##   autoplay                the built-in bot plays (screenshots, demos)
##   warp=120                fast-forward this many seconds before showing anything
##   shot=/path.png shot_time=2

# ---------------------------------------------------------------- layout (design pixels)
const W := 720.0
const H := 1280.0
const HUD_H := 92.0
const SPAWN_Y := 104.0
const WALL_Y := 1110.0
const WALL_H := 34.0
const GATE_W := 150.0
const LANES := [180.0, 360.0, 540.0]
const TURRET_Y := 990.0
const MACHINE_POS := Vector2(270, 1004)
const OUTPUT_POS := Vector2(270, 916)
const GATE_PAD_POS := Vector2(360, 1068)
const PAD_HALF := 34.0

# ---------------------------------------------------------------- tuning
const PLAYER_SPEED := 240.0
const REACH := 54.0            # how close you must stand to harvest, pick up or deposit
const HARVEST_TIME := 0.32
const ACT_TIME := 0.07         # one item moves per tick when depositing or picking up
const START_CAPACITY := 10
const NODE_STOCK := 5
const NODE_REGROW := 7.0
const MACHINE_TIME := 0.5      # seconds per ammo box
const BOXES_PER_WOOD := 2
const MACHINE_IN_MAX := 20
const MACHINE_OUT_MAX := 16
const SHOTS_PER_BOX := 10
const TURRET_BOXES := 5
const TURRET_RANGE := 230.0
const TURRET_RATE := 2.0
const RAPID_MULT := 1.8
const GATE_START := 12
const STONE_PER_REPAIR := 3
const WAVES := 10
const FIRST_WAVE := 30.0
const WAVE_BREAK := 16.0
const SPAWN_GAP := 1.1
const BOT_SPEED := 150.0
const BOT_CARRY := 4
const CUT_TIME := 0.6
const SCRAP_LIFE := 30.0       # scrap on the ground fades after this long
const HP_GROWTH := 0.08        # monsters get this much tougher every wave

const ITEM_COLOR := {
	"wood": Color("#b07a3e"), "stone": Color("#a3a8ad"), "scrap": Color("#6fb3e0"), "ammo": Color("#f2c14e"),
}
const MONSTERS := {
	"grunt": {"hp": 3, "speed": 42.0, "r": 14.0, "breach": 1, "drop": 1, "color": Color("#e5534b")},
	"runner": {"hp": 2, "speed": 86.0, "r": 12.0, "breach": 1, "drop": 1, "color": Color("#ff9561")},
	"brute": {"hp": 14, "speed": 26.0, "r": 22.0, "breach": 3, "drop": 4, "color": Color("#a8323a")},
}

# ---------------------------------------------------------------- state
var rng := RandomNumberGenerator.new()
var state := "play"            # play | won | lost
var time := 0.0
var player := {}
var stack: Array = []          # item kinds carried, bottom first
var capacity := START_CAPACITY
var harvest_t := 0.0
var act_t := 0.0
var nodes: Array = []          # {kind, pos, stock, regrow}
var pickups: Array = []        # {kind, pos}
var turrets: Array = []        # {pos, built, ammo, cool, aim, flash}
var machine := {}
var pads: Array = []           # {id, label, pos, cost, paid, done}
var bots: Array = []
var monsters: Array = []
var shots: Array = []
var fx: Array = []
var wave := 0
var wave_t := FIRST_WAVE
var spawn_queue: Array = []
var spawn_t := 0.0
var gate_max := GATE_START
var breaches := 0
var gate_stone := 0
var rapid := false
var kills := 0
var built_count := 0
var log_lines: Array = []

var joy_active := false
var joy_origin := Vector2.ZERO
var joy_vec := Vector2.ZERO
var autoplay := false
var idle := false
var args := {}
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	autoplay = args.has("autoplay") or args.get("sim", "") == "bot"
	idle = args.get("sim", "") == "idle"
	reset()
	if args.has("sim"):
		_run_sim()
		return
	if args.has("warp"):
		var t := float(args.warp)
		while time < t and state == "play":
			step(1.0 / 30.0)
	if args.has("shot"):
		get_tree().create_timer(float(args.get("shot_time", "1.5"))).timeout.connect(_take_shot)


func reset() -> void:
	rng.seed = 7
	state = "play"
	time = 0.0
	player = {"pos": Vector2(360, 820), "face": Vector2.UP}
	stack = []
	capacity = START_CAPACITY
	harvest_t = 0.0
	act_t = 0.0
	nodes = []
	for i in 6:
		nodes.append({"kind": "wood", "pos": Vector2(56 + (i % 2) * 48, 300 + i * 95), "stock": NODE_STOCK, "regrow": 0.0})
		nodes.append({"kind": "stone", "pos": Vector2(664 - (i % 2) * 48, 330 + i * 95), "stock": NODE_STOCK, "regrow": 0.0})
	pickups = []
	turrets = []
	for i in 3:
		turrets.append({"pos": Vector2(LANES[i], TURRET_Y), "built": i == 1,
			"ammo": SHOTS_PER_BOX * 2 if i == 1 else 0, "cool": 0.0, "aim": Vector2.UP, "flash": 0.0})
	machine = {"built": false, "input": 0, "out": 0, "t": 0.0}
	pads = [
		_pad("machine", "AMMO", MACHINE_POS, {"wood": 8}),
		_pad("turret_l", "TURRET", Vector2(180, TURRET_Y), {"wood": 5, "stone": 5}),
		_pad("turret_r", "TURRET", Vector2(540, TURRET_Y), {"wood": 5, "stone": 5}),
		_pad("gate", "GATE +5", Vector2(470, 1060), {"stone": 10}),
		_pad("runner", "AMMO RUNNER", Vector2(620, 1060), {"scrap": 8}),
		_pad("rapid", "RAPID FIRE", Vector2(100, 1060), {"scrap": 10, "stone": 6}),
		_pad("backpack", "BIGGER PACK", Vector2(620, 900), {"wood": 10}),
		_pad("cutter", "WOODCUTTER", Vector2(100, 900), {"scrap": 12, "wood": 6}),
	]
	bots = []
	monsters = []
	shots = []
	fx = []
	wave = 0
	wave_t = FIRST_WAVE
	spawn_queue = []
	spawn_t = 0.0
	gate_max = GATE_START
	breaches = 0
	gate_stone = 0
	rapid = false
	kills = 0
	built_count = 0
	log_lines = []


func _pad(id: String, label: String, pos: Vector2, cost: Dictionary) -> Dictionary:
	return {"id": id, "label": label, "pos": pos, "cost": cost, "paid": {}, "done": false}


# ================================================================== simulation

func _process(delta: float) -> void:
	if not args.has("sim"):
		step(minf(delta, 0.05))
	queue_redraw()


func step(dt: float) -> void:
	_update_fx(dt)
	if state != "play":
		return
	time += dt
	_move_player(dt)
	_harvest(dt)
	act_t -= dt
	if act_t <= 0.0:
		act_t = ACT_TIME if _try_act() else 0.0
	_update_nodes(dt)
	_update_machine(dt)
	_update_bots(dt)
	_update_waves(dt)
	_update_monsters(dt)
	_update_turrets(dt)


func _move_player(dt: float) -> void:
	var dir := Vector2.ZERO
	if autoplay:
		var to := _advice() - (player.pos as Vector2)
		if to.length() > 6.0:
			dir = to.normalized() * minf(1.0, to.length() / (PLAYER_SPEED * dt))
	elif not idle:
		dir = joy_vec
		var k := Vector2(float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
			float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
		if k != Vector2.ZERO:
			dir = k.normalized()
	if dir.length() > 0.05:
		player.face = dir.normalized()
	var pace := float(args.get("pace", "1")) if autoplay else 1.0  # slower bot = a human-like player
	var p: Vector2 = player.pos + dir.limit_length(1.0) * PLAYER_SPEED * pace * dt
	player.pos = Vector2(clampf(p.x, 22.0, W - 22.0), clampf(p.y, SPAWN_Y + 30.0, WALL_Y - 22.0))


func _harvest(dt: float) -> void:
	if stack.size() >= capacity:
		harvest_t = 0.0
		return
	var n := _nearest_node(player.pos, REACH + 14.0, "")
	if n.is_empty() or not _useful(n.kind):
		harvest_t = 0.0
		return
	harvest_t += dt
	if harvest_t >= HARVEST_TIME:
		harvest_t = 0.0
		n.stock -= 1
		stack.append(n.kind)
		_fly(n.pos, player.pos, n.kind)
		if n.stock <= 0:
			n.regrow = NODE_REGROW


## Moves one item between the player and whatever they stand next to. True if something moved.
func _try_act() -> bool:
	var p: Vector2 = player.pos
	for pad in _visible_pads():
		if _near(p, pad.pos, PAD_HALF + 10.0):
			for kind in pad.cost:
				if _remaining(pad, kind) > 0 and _take(kind):
					pad.paid[kind] = int(pad.paid.get(kind, 0)) + 1
					_fly(p, pad.pos, kind)
					if _pad_complete(pad):
						_complete(pad)
					return true
	if machine.built and _near(p, MACHINE_POS, REACH) and machine.input < MACHINE_IN_MAX and _take("wood"):
		machine.input += 1
		_fly(p, MACHINE_POS, "wood")
		return true
	for t in turrets:
		if t.built and _near(p, t.pos, REACH) and _free_boxes(t) > 0 and _take("ammo"):
			t.ammo += SHOTS_PER_BOX
			_fly(p, t.pos, "ammo")
			return true
	if breaches > 0 and _near(p, GATE_PAD_POS, REACH) and _take("stone"):
		gate_stone += 1
		_fly(p, GATE_PAD_POS, "stone")
		if gate_stone >= STONE_PER_REPAIR:
			gate_stone = 0
			breaches -= 1
		return true
	if stack.size() < capacity:
		if machine.built and machine.out > 0 and _near(p, OUTPUT_POS, REACH) and _useful("ammo"):
			machine.out -= 1
			stack.append("ammo")
			_fly(OUTPUT_POS, p, "ammo")
			return true
		for i in pickups.size():
			var k: Dictionary = pickups[i]
			if _near(p, k.pos, REACH) and _useful(k.kind):
				stack.append(k.kind)
				_fly(k.pos, p, k.kind)
				pickups.remove_at(i)
				return true
	return false


func _complete(pad: Dictionary) -> void:
	pad.done = true
	built_count += 1
	match pad.id:
		"machine":
			machine.built = true
		"turret_l":
			turrets[0].built = true
			turrets[0].ammo = SHOTS_PER_BOX
		"turret_r":
			turrets[2].built = true
			turrets[2].ammo = SHOTS_PER_BOX
		"gate":
			gate_max += 5
		"runner":
			bots.append({"kind": "runner", "pos": OUTPUT_POS + Vector2(40, 0), "carry": 0, "node": -1, "t": 0.0})
		"rapid":
			rapid = true
		"backpack":
			capacity += 8
		"cutter":
			bots.append({"kind": "cutter", "pos": Vector2(150, 900), "carry": 0, "node": -1, "t": 0.0})
	for i in 10:
		var a := TAU * i / 10.0
		fx.append({"from": pad.pos, "to": pad.pos + Vector2(cos(a), sin(a)) * 60.0, "t": 0.0, "dur": 0.45, "kind": "ammo"})
	_log("built %s at %ds (wave %d, gate %d/%d)" % [pad.id, int(time), wave, gate_max - breaches, gate_max])


func _update_nodes(dt: float) -> void:
	for n in nodes:
		if n.stock <= 0:
			n.regrow -= dt
			if n.regrow <= 0.0:
				n.stock = NODE_STOCK


func _update_machine(dt: float) -> void:
	if not machine.built or machine.input <= 0 or machine.out >= MACHINE_OUT_MAX:
		machine.t = 0.0
		return
	machine.t += dt
	if machine.t >= MACHINE_TIME * BOXES_PER_WOOD:
		machine.t = 0.0
		machine.input -= 1
		machine.out = mini(machine.out + BOXES_PER_WOOD, MACHINE_OUT_MAX)


func _update_bots(dt: float) -> void:
	for b in bots:
		if b.kind == "runner":
			_runner(b, dt)
		else:
			_cutter(b, dt)


## Ammo runner: boxes from the machine's output to the emptiest turret.
func _runner(b: Dictionary, dt: float) -> void:
	if b.carry == 0:
		var want := _total_free_boxes() - _count("ammo")
		if machine.out > 0 and want > 0:
			if _move_to(b, OUTPUT_POS + Vector2(28, 0), dt):
				var n := mini(mini(BOT_CARRY, machine.out), want)
				machine.out -= n
				b.carry = n
		else:
			_move_to(b, OUTPUT_POS + Vector2(44, -20), dt)
		return
	var t := _neediest_turret()
	if t.is_empty():
		return
	if _move_to(b, t.pos + Vector2(0, -38), dt):
		while b.carry > 0 and _free_boxes(t) > 0:
			t.ammo += SHOTS_PER_BOX
			b.carry -= 1


## Woodcutter: chops trees and feeds the ammo machine.
func _cutter(b: Dictionary, dt: float) -> void:
	if b.carry < BOT_CARRY:
		if b.node < 0 or nodes[b.node].stock <= 0:
			b.node = _nearest_node_index(b.pos, "wood")
		if b.node >= 0:
			var n: Dictionary = nodes[b.node]
			if _move_to(b, n.pos + Vector2(30, 6), dt):
				b.t += dt
				if b.t >= CUT_TIME:
					b.t = 0.0
					n.stock -= 1
					b.carry += 1
					if n.stock <= 0:
						n.regrow = NODE_REGROW
						b.node = -1
			return
		if b.carry == 0:
			return
	if _move_to(b, MACHINE_POS + Vector2(-46, 0), dt) and machine.built and machine.input < MACHINE_IN_MAX:
		var n2 := mini(b.carry, MACHINE_IN_MAX - machine.input)
		machine.input += n2
		b.carry -= n2


func _move_to(b: Dictionary, target: Vector2, dt: float) -> bool:
	var to: Vector2 = target - b.pos
	if to.length() <= 6.0:
		return true
	b.pos += to.normalized() * minf(to.length(), BOT_SPEED * dt)
	return false


func _update_waves(dt: float) -> void:
	if spawn_queue.is_empty():
		if wave < WAVES:
			wave_t -= dt
			if wave_t <= 0.0:
				_start_wave()
		elif monsters.is_empty():
			state = "won"
			_log("WON at %ds, gate %d/%d, kills %d" % [int(time), gate_max - breaches, gate_max, kills])
		return
	spawn_t -= dt
	if spawn_t <= 0.0:
		spawn_t = SPAWN_GAP
		_spawn(spawn_queue.pop_front())
		if spawn_queue.is_empty():
			wave_t = WAVE_BREAK


func _start_wave() -> void:
	wave += 1
	var list := []
	for i in 3 + 2 * wave:
		list.append("grunt")
	for i in maxi(0, wave - 2):
		list.append("runner")
	for i in maxi(0, (wave - 3) / 2):
		list.append("brute")
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = list[i]
		list[i] = list[j]
		list[j] = tmp
	spawn_queue = list
	spawn_t = 0.0
	var ammo := 0
	for t in turrets:
		if t.built:
			ammo += t.ammo
	_log("wave %d at %ds: %d monsters | gate %d/%d | turret shots %d | built %d" % [wave, int(time),
		list.size(), gate_max - breaches, gate_max, ammo, built_count])


func _spawn(type: String) -> void:
	var d: Dictionary = MONSTERS[type]
	var lane := rng.randi_range(0, 2)
	monsters.append({"type": type, "pos": Vector2(LANES[lane] + rng.randf_range(-22.0, 22.0), SPAWN_Y),
		"hp": roundi(d.hp * (1.0 + HP_GROWTH * (wave - 1))), "max": roundi(d.hp * (1.0 + HP_GROWTH * (wave - 1))), "speed": d.speed * rng.randf_range(0.92, 1.08), "r": d.r})


func _update_monsters(dt: float) -> void:
	var i := 0
	while i < monsters.size():
		var m: Dictionary = monsters[i]
		m.pos.y += m.speed * dt
		if m.pos.y + m.r >= WALL_Y:
			breaches += int(MONSTERS[m.type].breach)
			for k in 6:
				fx.append({"from": m.pos, "to": m.pos + Vector2(rng.randf_range(-50, 50), rng.randf_range(-40, 0)),
					"t": 0.0, "dur": 0.4, "kind": "spark"})
			monsters.remove_at(i)
			if breaches >= gate_max:
				state = "lost"
				_log("LOST at %ds in wave %d, kills %d" % [int(time), wave, kills])
				return
			continue
		i += 1


func _update_turrets(dt: float) -> void:
	var rate := TURRET_RATE * (RAPID_MULT if rapid else 1.0)
	for t in turrets:
		t.cool = maxf(t.cool - dt, -dt)
		t.flash = maxf(t.flash - dt, 0.0)
		if not t.built:
			continue
		var best := -1
		var best_d := TURRET_RANGE
		for j in monsters.size():
			var d: float = (monsters[j].pos as Vector2).distance_to(t.pos)
			if d < best_d:
				best_d = d
				best = j
		if best < 0:
			continue
		var m: Dictionary = monsters[best]
		t.aim = ((m.pos as Vector2) - (t.pos as Vector2)).normalized()
		if t.ammo <= 0 or t.cool > 0.0:
			continue
		t.ammo -= 1
		t.cool += 1.0 / rate
		t.flash = 0.06
		shots.append({"a": t.pos + t.aim * 28.0, "b": m.pos, "t": 0.08})
		m.hp -= 1
		if m.hp <= 0:
			kills += 1
			if _scrap_wanted_later():
				for k in int(MONSTERS[m.type].drop):
					pickups.append({"kind": "scrap", "life": SCRAP_LIFE,
						"pos": m.pos + Vector2(rng.randf_range(-16, 16), rng.randf_range(-16, 16))})
			monsters.remove_at(best)


func _update_fx(dt: float) -> void:
	var j := 0
	while j < pickups.size():
		pickups[j].life -= dt
		if pickups[j].life <= 0.0:
			pickups.remove_at(j)
		else:
			j += 1
	var i := 0
	while i < fx.size():
		fx[i].t += dt
		if fx[i].t >= fx[i].dur:
			fx.remove_at(i)
		else:
			i += 1
	i = 0
	while i < shots.size():
		shots[i].t -= dt
		if shots[i].t <= 0.0:
			shots.remove_at(i)
		else:
			i += 1


# ================================================================== queries

func _near(a: Vector2, b: Vector2, r: float) -> bool:
	return a.distance_to(b) <= r


func _count(kind: String) -> int:
	return stack.count(kind)


func _take(kind: String) -> bool:
	var i := stack.rfind(kind)
	if i < 0:
		return false
	stack.remove_at(i)
	return true


func _remaining(pad: Dictionary, kind: String) -> int:
	return int(pad.cost.get(kind, 0)) - int(pad.paid.get(kind, 0))


func _pad_complete(pad: Dictionary) -> bool:
	for kind in pad.cost:
		if _remaining(pad, kind) > 0:
			return false
	return true


## The two build pads that are open: finish one and the next appears.
func _visible_pads() -> Array:
	var out := []
	for p in pads:
		if not p.done:
			out.append(p)
			if out.size() == 2:
				break
	return out


## How many more of `kind` the open pads and the gate can still take.
func _need(kind: String) -> int:
	var n := 0
	for p in _visible_pads():
		n += maxi(_remaining(p, kind), 0)
	if kind == "stone" and breaches > 0:
		n += breaches * STONE_PER_REPAIR - gate_stone
	return n


## You only pick up what something needs, so your stack never fills with junk.
func _useful(kind: String) -> bool:
	match kind:
		"wood":
			if machine.built:
				return true
		"ammo":
			return _count("ammo") < _total_free_boxes()
	return _count(kind) < _need(kind)


func _free_boxes(t: Dictionary) -> int:
	return (TURRET_BOXES * SHOTS_PER_BOX - int(t.ammo)) / SHOTS_PER_BOX if t.built else 0


func _total_free_boxes() -> int:
	var n := 0
	for t in turrets:
		n += _free_boxes(t)
	return n


func _neediest_turret() -> Dictionary:
	var best := {}
	for t in turrets:
		if _free_boxes(t) > 0 and (best.is_empty() or t.ammo < best.ammo):
			best = t
	return best


func _nearest_node(p: Vector2, r: float, kind: String) -> Dictionary:
	var best := {}
	var best_d := r
	for n in nodes:
		if n.stock > 0 and (kind == "" or n.kind == kind):
			var d := p.distance_to(n.pos)
			if d <= best_d:
				best_d = d
				best = n
	return best


func _nearest_node_index(p: Vector2, kind: String) -> int:
	var best := -1
	var best_d := INF
	for i in nodes.size():
		var n: Dictionary = nodes[i]
		if n.stock > 0 and n.kind == kind and p.distance_to(n.pos) < best_d:
			best_d = p.distance_to(n.pos)
			best = i
	return best


## Monsters only drop scrap while something still to be built needs it.
func _scrap_wanted_later() -> bool:
	for p in pads:
		if not p.done and _remaining(p, "scrap") > 0:
			return true
	return false


## The most useful place to go next. Drives the guide arrow and the bot.
func _advice() -> Vector2:
	var p: Vector2 = player.pos
	var space := capacity - stack.size()
	if _count("ammo") > 0:
		var t := _neediest_turret()
		if not t.is_empty():
			return t.pos + Vector2(0, -40)
	var hungry := false
	for t in turrets:
		if _free_boxes(t) >= 2:
			hungry = true
	if hungry and machine.built and machine.out > 0 and space > 0:
		return OUTPUT_POS + Vector2(0, -20)
	if breaches > 0 and _count("stone") > 0:
		return GATE_PAD_POS + Vector2(0, -24)
	if machine.built and _count("wood") > 0 and machine.input < MACHINE_IN_MAX and _ammo_short():
		return MACHINE_POS + Vector2(0, -36)
	for pad in _visible_pads():
		for kind in pad.cost:
			if _remaining(pad, kind) > 0 and _count(kind) > 0:
				return pad.pos
	if machine.built and _count("wood") > 0 and machine.input < MACHINE_IN_MAX:
		return MACHINE_POS + Vector2(0, -36)
	if space > 0:
		if _useful("scrap"):
			var best := {}
			for k in pickups:
				if k.kind == "scrap" and (best.is_empty() or p.distance_to(k.pos) < p.distance_to(best.pos)):
					best = k
			if not best.is_empty():
				return best.pos
		var want := _want_kind()
		if want != "":
			var n := _nearest_node(p, INF, want)
			if not n.is_empty():
				return n.pos + (Vector2(34, 0) if want == "wood" else Vector2(-34, 0))
	return p


## The turrets need more boxes than the machine has queued.
func _ammo_short() -> bool:
	return machine.built and machine.input * BOXES_PER_WOOD + machine.out < _total_free_boxes()


func _want_kind() -> String:
	if _ammo_short() and (machine.input + _count("wood")) * BOXES_PER_WOOD + machine.out < _total_free_boxes():
		return "wood"
	for pad in _visible_pads():  # an open lane comes first
		if str(pad.id).begins_with("turret"):
			if _remaining(pad, "stone") > _count("stone"):
				return "stone"
			if _remaining(pad, "wood") > _count("wood"):
				return "wood"
	var wood := _need("wood") - _count("wood")
	var stone := _need("stone") - _count("stone")
	if stone > 0 and (stone >= wood or breaches > 0):
		return "stone"
	if wood > 0:
		return "wood"
	if machine.built and (machine.input + machine.out < 8):
		return "wood"
	return ""


# ================================================================== input

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = (make_input_local(event) as InputEventMouseButton).position
		if event.pressed:
			if state != "play":
				reset()
				return
			joy_active = true
			joy_origin = p
			joy_vec = Vector2.ZERO
		else:
			joy_active = false
			joy_vec = Vector2.ZERO
	elif event is InputEventMouseMotion and joy_active:
		var p2: Vector2 = (make_input_local(event) as InputEventMouseMotion).position
		joy_vec = ((p2 - joy_origin) / 70.0).limit_length(1.0)


# ================================================================== drawing

func _fly(from: Vector2, to: Vector2, kind: String) -> void:
	fx.append({"from": from, "to": to, "t": 0.0, "dur": 0.22, "kind": kind})


func _text(s: String, centre: Vector2, size: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, centre + Vector2(-w * 0.5, size * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _item(pos: Vector2, kind: String, s: float) -> void:
	var c: Color = ITEM_COLOR[kind]
	draw_rect(Rect2(pos - Vector2(s, s * 0.8), Vector2(s * 2, s * 1.6)), c)
	draw_rect(Rect2(pos - Vector2(s, s * 0.8), Vector2(s * 2, s * 1.6)), c.darkened(0.45), false, 2.0)


func _draw() -> void:
	# ground, spawn strip, fortress interior
	draw_rect(Rect2(0, 0, W, H), Color("#56663f"))
	draw_rect(Rect2(0, HUD_H, W, SPAWN_Y - HUD_H + 26), Color("#3f3530"))
	draw_rect(Rect2(0, WALL_Y, W, H - WALL_Y), Color("#2c3138"))
	for x in LANES:
		draw_rect(Rect2(x - 32, SPAWN_Y, 64, WALL_Y - SPAWN_Y), Color(0.8, 0.72, 0.5, 0.18))
	_draw_fortress()
	# wall and gate
	draw_rect(Rect2(0, WALL_Y, W, WALL_H), Color("#8a919a"))
	for x in range(0, int(W), 40):
		draw_rect(Rect2(x + 4, WALL_Y - 10, 24, 12), Color("#8a919a"))
	var g := Rect2(W * 0.5 - GATE_W * 0.5, WALL_Y - 6, GATE_W, WALL_H + 6)
	draw_rect(g, Color("#6b4f33"))
	var crack := float(breaches) / float(gate_max)
	for k in int(crack * 8.0):
		var x := g.position.x + 12 + k * 16
		draw_line(Vector2(x, g.position.y + 4), Vector2(x + 8, g.end.y - 4), Color("#1d1410"), 3.0)
	for n in nodes:
		_draw_node(n)
	for pad in _visible_pads():
		_draw_pad(pad)
	if breaches > 0 and state == "play":
		var need := STONE_PER_REPAIR - gate_stone
		draw_rect(Rect2(GATE_PAD_POS - Vector2(28, 22), Vector2(56, 44)), Color(1, 1, 1, 0.1))
		draw_rect(Rect2(GATE_PAD_POS - Vector2(28, 22), Vector2(56, 44)), Color("#f2e4cb"), false, 2.0)
		_item(GATE_PAD_POS + Vector2(-10, 0), "stone", 7)
		_text("%d" % need, GATE_PAD_POS + Vector2(12, 0), 18, Color.WHITE)
	_draw_machine()
	for t in turrets:
		_draw_turret(t)
	for k in pickups:
		if k.life > 6.0 or fmod(k.life, 0.5) > 0.2:  # blinks in its last seconds
			_item(k.pos, k.kind, 6)
	for m in monsters:
		_draw_monster(m)
	for s in shots:
		draw_line(s.a, s.b, Color(1, 0.92, 0.55, clampf(s.t / 0.08, 0, 1)), 3.0)
	for b in bots:
		_draw_bot(b)
	_draw_player()
	for f in fx:
		var k := clampf(f.t / f.dur, 0, 1)
		var pos: Vector2 = (f.from as Vector2).lerp(f.to, k) + Vector2(0, -sin(k * PI) * 30.0)
		if f.kind == "spark":
			draw_circle(pos, 4.0 * (1.0 - k) + 1.0, Color("#ffcf6b"))
		else:
			_item(pos, f.kind, 6)
	if state == "play" and not autoplay:
		_draw_arrow()
	_draw_hud()
	if joy_active:
		draw_circle(joy_origin, 70.0, Color(1, 1, 1, 0.12))
		draw_circle(joy_origin + joy_vec * 70.0, 28.0, Color(1, 1, 1, 0.35))
	if state != "play":
		_draw_end()


func _draw_fortress() -> void:
	var houses := 2 + built_count
	for i in houses:
		var x := 50.0 + (i % 6) * 112.0 + (28.0 if (i / 6) % 2 == 1 else 0.0)
		var y := WALL_Y + 74.0 + (i / 6) * 64.0
		if y > H - 20:
			break
		draw_rect(Rect2(x - 26, y - 14, 52, 34), Color("#b9a27c"))
		draw_colored_polygon(PackedVector2Array([Vector2(x - 32, y - 14), Vector2(x, y - 40), Vector2(x + 32, y - 14)]), Color("#8c3b2e"))


func _draw_node(n: Dictionary) -> void:
	var useful := _useful(n.kind)
	var a := 1.0 if useful else 0.55
	if n.kind == "wood":
		if n.stock > 0:
			draw_rect(Rect2(n.pos + Vector2(-5, 4), Vector2(10, 16)), Color(0.42, 0.28, 0.16, a))
			draw_circle(n.pos, 22.0, Color(0.24, 0.55, 0.29, a))
			draw_circle(n.pos + Vector2(-6, -6), 10.0, Color(0.33, 0.66, 0.38, a))
		else:
			draw_circle(n.pos + Vector2(0, 10), 8.0, Color("#6b4a2b"))
	else:
		if n.stock > 0:
			var pts := PackedVector2Array([n.pos + Vector2(-24, 12), n.pos + Vector2(-16, -14), n.pos + Vector2(6, -20),
				n.pos + Vector2(24, -4), n.pos + Vector2(20, 14)])
			draw_colored_polygon(pts, Color(0.55, 0.57, 0.6, a))
			draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.3, 0.32, 0.35, a), 2.0)
		else:
			draw_circle(n.pos + Vector2(-8, 8), 5.0, Color("#6e7378"))
			draw_circle(n.pos + Vector2(6, 10), 4.0, Color("#6e7378"))
	if n.stock > 0 and n.stock < NODE_STOCK:
		for i in n.stock:
			draw_circle(n.pos + Vector2(-12 + i * 6, 28), 2.2, Color(1, 1, 1, 0.7))


func _draw_pad(pad: Dictionary) -> void:
	var r := Rect2(pad.pos - Vector2(PAD_HALF, PAD_HALF), Vector2(PAD_HALF * 2, PAD_HALF * 2))
	draw_rect(r, Color(1, 1, 1, 0.1))
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in 4:
		for k in 5:
			if k % 2 == 0:
				draw_line((pts[i] as Vector2).lerp(pts[i + 1], k / 5.0), (pts[i] as Vector2).lerp(pts[i + 1], (k + 1) / 5.0),
					Color("#f2e4cb"), 3.0)
	_text(pad.label, pad.pos + Vector2(0, -PAD_HALF - 12), 14, Color("#f2e4cb"))
	var kinds := []
	var total := 0
	var paid := 0
	for kind in pad.cost:
		total += int(pad.cost[kind])
		paid += int(pad.paid.get(kind, 0))
		if _remaining(pad, kind) > 0:
			kinds.append(kind)
	for i in kinds.size():
		var y: float = pad.pos.y - 10 + i * 24 - (kinds.size() - 1) * 6
		_item(Vector2(pad.pos.x - 12, y), kinds[i], 8)
		_text("%d" % _remaining(pad, kinds[i]), Vector2(pad.pos.x + 14, y), 18, Color.WHITE)
	draw_rect(Rect2(r.position.x + 4, r.end.y - 8, (r.size.x - 8) * paid / float(total), 4), Color("#7af1eb"))


func _draw_machine() -> void:
	if not machine.built:
		return
	var r := Rect2(MACHINE_POS - Vector2(34, 28), Vector2(68, 56))
	draw_rect(r, Color("#4b5563"))
	draw_rect(r, Color("#22272e"), false, 3.0)
	var spin := time * 4.0 if machine.input > 0 else 0.0
	for k in 6:
		var a := spin + TAU * k / 6.0
		draw_line(MACHINE_POS, MACHINE_POS + Vector2(cos(a), sin(a)) * 16.0, Color("#f2c14e"), 4.0)
	draw_circle(MACHINE_POS, 7.0, Color("#22272e"))
	if machine.input > 0:
		_item(MACHINE_POS + Vector2(-48, 18), "wood", 6)
		_text("%d" % machine.input, MACHINE_POS + Vector2(-48, 36), 14, Color.WHITE)
	# output pile
	draw_rect(Rect2(OUTPUT_POS - Vector2(30, 18), Vector2(60, 40)), Color(0, 0, 0, 0.18))
	for i in machine.out:
		var col: int = i % 4
		var row: int = i / 4
		_item(OUTPUT_POS + Vector2(-18 + col * 12, 10 - row * 9), "ammo", 6)


func _draw_turret(t: Dictionary) -> void:
	if not t.built:
		var pad_open := false
		for p in _visible_pads():
			if p.pos == t.pos:
				pad_open = true
		if not pad_open:
			draw_arc(t.pos, 26.0, 0, TAU, 32, Color(1, 1, 1, 0.18), 2.0)
		return
	var near: bool = _near(player.pos, t.pos, 140.0)
	if near:
		draw_arc(t.pos, TURRET_RANGE, 0, TAU, 64, Color(0.48, 0.95, 0.92, 0.25), 2.0)
	draw_rect(Rect2(t.pos - Vector2(24, 24), Vector2(48, 48)), Color("#2e5d8a"))
	draw_rect(Rect2(t.pos - Vector2(24, 24), Vector2(48, 48)), Color("#16304a"), false, 3.0)
	draw_line(t.pos, t.pos + (t.aim as Vector2) * 34.0, Color("#16304a"), 10.0)
	draw_circle(t.pos, 12.0, Color("#3f7cb5"))
	if t.flash > 0.0:
		draw_circle(t.pos + (t.aim as Vector2) * 38.0, 7.0, Color("#ffe08f"))
	var max_ammo := TURRET_BOXES * SHOTS_PER_BOX
	draw_rect(Rect2(t.pos + Vector2(-26, 30), Vector2(52, 7)), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(t.pos + Vector2(-26, 30), Vector2(52.0 * t.ammo / max_ammo, 7)), Color("#f2c14e"))
	if t.ammo <= 0:
		var pulse := 0.5 + 0.5 * sin(time * 8.0)
		draw_arc(t.pos, 34.0 + pulse * 6.0, 0, TAU, 32, Color(0.95, 0.35, 0.3, 0.9), 4.0)


func _draw_monster(m: Dictionary) -> void:
	var c: Color = MONSTERS[m.type].color
	var p: Vector2 = m.pos
	var r: float = m.r
	match m.type:
		"grunt":
			draw_circle(p, r, c)
			draw_circle(p, r, c.darkened(0.5), false, 2.0)
		"runner":
			var pts := PackedVector2Array([p + Vector2(-r, -r), p + Vector2(r, -r), p + Vector2(0, r * 1.2)])
			draw_colored_polygon(pts, c)
		"brute":
			draw_rect(Rect2(p - Vector2(r, r), Vector2(r * 2, r * 2)), c)
			draw_rect(Rect2(p - Vector2(r, r), Vector2(r * 2, r * 2)), c.darkened(0.5), false, 3.0)
	if m.hp < m.max:
		draw_rect(Rect2(p + Vector2(-r, -r - 9), Vector2(r * 2, 4)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(p + Vector2(-r, -r - 9), Vector2(r * 2 * m.hp / float(m.max), 4)), Color("#ff6b5e"))


func _draw_bot(b: Dictionary) -> void:
	var c := Color("#f2c14e") if b.kind == "runner" else Color("#5fbf6a")
	draw_circle(b.pos, 12.0, c)
	draw_circle(b.pos, 12.0, c.darkened(0.5), false, 2.0)
	for i in b.carry:
		_item(b.pos + Vector2(0, -20 - i * 8), "ammo" if b.kind == "runner" else "wood", 5)


func _draw_player() -> void:
	var p: Vector2 = player.pos
	draw_circle(p + Vector2(0, 14), 14.0, Color(0, 0, 0, 0.25))
	draw_circle(p, 17.0, Color("#f2e4cb"))
	draw_circle(p, 17.0, Color("#2b2f36"), false, 3.0)
	draw_circle(p + (player.face as Vector2) * 9.0, 4.5, Color("#2b2f36"))
	for i in stack.size():
		_item(p + Vector2(0, -30 - i * 9), stack[i], 9)
	if stack.size() >= capacity:
		_text("FULL", p + Vector2(0, 30), 13, Color("#ffcb5e"))


func _draw_arrow() -> void:
	var target := _advice()
	var p: Vector2 = player.pos
	var d := target - p
	if d.length() < 90.0:
		return
	var dir := d.normalized()
	var tip := p + dir * 52.0
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([tip, tip - dir * 16.0 + side * 10.0, tip - dir * 16.0 - side * 10.0]),
		Color(1, 1, 1, 0.85))
	var pulse := 0.5 + 0.5 * sin(time * 5.0)
	draw_arc(target, 18.0 + pulse * 6.0, 0, TAU, 24, Color(1, 1, 1, 0.5), 2.0)


func _draw_hud() -> void:
	draw_rect(Rect2(0, 0, W, HUD_H), Color("#16181c"))
	_text("WAVE %d/%d" % [wave, WAVES], Vector2(90, 34), 22, Color("#f2e4cb"))
	if not spawn_queue.is_empty() or (wave > 0 and not monsters.is_empty() and wave_t >= WAVE_BREAK - 0.01):
		_text("INCOMING %d" % (spawn_queue.size() + monsters.size()), Vector2(90, 66), 16, Color("#ff7b6b"))
	elif wave < WAVES:
		_text("NEXT IN %ds" % int(ceil(wave_t)), Vector2(90, 66), 16, Color("#a9a395"))
	_text("GATE", Vector2(W * 0.5, 26), 16, Color("#a9a395"))
	var pw := minf(18.0, 300.0 / gate_max)
	var x0 := W * 0.5 - pw * gate_max * 0.5
	for i in gate_max:
		var c := Color("#7af1eb") if i < gate_max - breaches else Color("#5a2a2a")
		draw_rect(Rect2(x0 + i * pw + 1, 44, pw - 3, 22), c)
	_text("%d/%d" % [stack.size(), capacity], Vector2(W - 70, 34), 20, Color("#f2e4cb"))
	_text("CARRY", Vector2(W - 70, 64), 14, Color("#a9a395"))


func _draw_end() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.55))
	var won := state == "won"
	draw_rect(Rect2(90, 440, W - 180, 320), Color("#1f2328"))
	draw_rect(Rect2(90, 440, W - 180, 320), Color("#7af1eb") if won else Color("#ff6b5e"), false, 4.0)
	_text("FORTRESS HOLDS" if won else "GATE BROKEN", Vector2(W * 0.5, 510), 40, Color.WHITE)
	_text("Waves survived: %d / %d" % [wave if won else wave - 1, WAVES], Vector2(W * 0.5, 580), 22, Color("#f2e4cb"))
	_text("Monsters stopped: %d" % kills, Vector2(W * 0.5, 620), 22, Color("#f2e4cb"))
	_text("TAP TO PLAY AGAIN", Vector2(W * 0.5, 700), 22, Color("#ffcb5e"))


# ================================================================== automation

func _log(line: String) -> void:
	log_lines.append(line)
	if args.has("sim"):
		print(line)


func _run_sim() -> void:
	while state == "play" and time < 1500.0:
		step(1.0 / 30.0)
	print("RESULT %s at %ds, wave %d, gate %d/%d, kills %d, built %d" % [state, int(time), wave,
		gate_max - breaches, gate_max, kills, built_count])
	get_tree().quit()


func _take_shot() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(str(args.shot))
	print("[shot] saved ", args.shot)
	get_tree().quit()
