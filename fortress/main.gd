extends Node2D
## FORTRESS: gameplay prototype drawn with basic shapes. See DESIGN.md.
## You live behind a fence with one small door. Outside: trees, rocks and the monster lanes.
## Inside: the ammo machine, launchers and everything else you build. Monsters march straight
## down three lanes and wait at the fence; too many waiting and the fence gives. Step outside to
## gather and they come for you: a few touches and you are down, and if one follows you through the
## door, the fortress falls.
##
## Automation (after `--`):
##   sim=bot | sim=idle      headless balance run: prints a log and quits (pace=0.7 slows the bot)
##   autoplay                the built-in bot plays (screenshots, demos)
##   warp=120                fast-forward this many seconds before showing anything
##   shot=/path.png shot_time=2

# ---------------------------------------------------------------- layout (design pixels)
const W := 720.0
const H := 1280.0
const HUD_H := 92.0
const SPAWN_Y := 104.0
const FENCE_Y := 860.0
const FENCE_H := 18.0
const DOOR_X := 430.0
const DOOR_W := 64.0
const LANES := [220.0, 360.0, 500.0]
const MACHINE_POS := Vector2(250, 1010)
const OUTPUT_POS := Vector2(250, 928)
const PAD_HALF := 34.0
const DOOR_OUT := Vector2(DOOR_X, FENCE_Y - 34.0)
const DOOR_IN := Vector2(DOOR_X, FENCE_Y + FENCE_H + 36.0)

# ---------------------------------------------------------------- tuning
const PLAYER_SPEED := 240.0
const PLAYER_R := 16.0
const REACH := 54.0            # how close you must stand to harvest, pick up or deposit
const HARVEST_TIME := 0.32
const ACT_TIME := 0.07         # one item moves per tick when depositing or picking up
const START_CAPACITY := 10
const HEARTS := 6
const HEART_REGEN := 4.0       # seconds per heart while inside the fence
const HURT_GRACE := 0.7        # seconds you can't be hit again after a touch
const BAG_MAX := 30            # your own gun's shots, separate from what you carry
const GUN_RANGE := 130.0
const GUN_RATE := 3.0
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
const LAUNCH_RANGE := 270.0
const LAUNCH_TIME := 1.2
const FENCE_START := 8         # monsters that can wait at the fence before it gives
const WAVES := 10
const FIRST_WAVE := 30.0
const WAVE_BREAK := 16.0
const SPAWN_GAP := 1.1
const BOT_SPEED := 150.0
const BOT_CARRY := 4
const CUT_TIME := 0.6
const SCRAP_LIFE := 30.0
const HP_GROWTH := 0.08
const GIVE_UP := 260.0         # a chasing monster loses interest beyond this distance

const ITEM_COLOR := {
	"wood": Color("#b07a3e"), "stone": Color("#a3a8ad"), "scrap": Color("#6fb3e0"), "ammo": Color("#f2c14e"),
}
const MONSTERS := {
	"grunt": {"hp": 3, "speed": 42.0, "r": 14.0, "notice": 90.0, "hit": 1, "drop": 1, "color": Color("#e5534b")},
	"runner": {"hp": 2, "speed": 86.0, "r": 12.0, "notice": 130.0, "hit": 1, "drop": 1, "color": Color("#ff9561")},
	"brute": {"hp": 14, "speed": 30.0, "r": 22.0, "notice": 70.0, "hit": 2, "drop": 4, "color": Color("#a8323a")},
}

# ---------------------------------------------------------------- state
var rng := RandomNumberGenerator.new()
var state := "play"            # play | won | lost
var lose_reason := ""
var time := 0.0
var player := {}
var stack: Array = []
var capacity := START_CAPACITY
var bag := BAG_MAX
var hearts := HEARTS
var heal_t := 0.0
var hurt_t := 0.0
var gun_cool := 0.0
var harvest_t := 0.0
var act_t := 0.0
var nodes: Array = []
var pickups: Array = []
var turrets: Array = []
var machine := {}
var launchers: Array = []      # {pos, cool}
var lobs: Array = []           # boxes in flight from a launcher: {from, to, t, dur, turret}
var pads: Array = []
var bots: Array = []
var monsters: Array = []
var shots: Array = []
var fx: Array = []
var wave := 0
var wave_t := FIRST_WAVE
var spawn_queue: Array = []
var spawn_t := 0.0
var fence_max := FENCE_START
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
	rng.seed = int(args.get("seed", "7"))
	state = "play"
	lose_reason = ""
	time = 0.0
	player = {"pos": Vector2(DOOR_X, 1030), "face": Vector2.UP}
	stack = []
	capacity = START_CAPACITY
	bag = BAG_MAX
	hearts = HEARTS
	heal_t = 0.0
	hurt_t = 0.0
	gun_cool = 0.0
	harvest_t = 0.0
	act_t = 0.0
	nodes = []
	for i in 6:
		nodes.append({"kind": "wood", "pos": Vector2(48 + (i % 2) * 44, 240 + i * 92), "stock": NODE_STOCK, "regrow": 0.0})
		nodes.append({"kind": "stone", "pos": Vector2(672 - (i % 2) * 44, 270 + i * 92), "stock": NODE_STOCK, "regrow": 0.0})
	pickups = []
	turrets = []
	for i in 3:
		turrets.append({"pos": Vector2(LANES[i], FENCE_Y + FENCE_H * 0.5), "built": i == 1,
			"ammo": SHOTS_PER_BOX * 2 if i == 1 else 0, "cool": 0.0, "aim": Vector2.UP, "flash": 0.0})
	machine = {"built": false, "input": 0, "out": 0, "t": 0.0}
	launchers = []
	lobs = []
	pads = [
		_pad("machine", "AMMO", MACHINE_POS, {"wood": 8}),
		_pad("turret_l", "TURRET", turrets[0].pos, {"wood": 5, "stone": 5}),
		_pad("turret_r", "TURRET", turrets[2].pos, {"wood": 5, "stone": 5}),
		_pad("launcher_l", "LAUNCHER", Vector2(110, 960), {"stone": 6, "scrap": 4}),
		_pad("fence", "FENCE +4", Vector2(610, 1080), {"stone": 8}),
		_pad("rapid", "RAPID FIRE", Vector2(110, 1090), {"scrap": 10, "stone": 6}),
		_pad("backpack", "BIGGER PACK", Vector2(380, 1100), {"wood": 10}),
		_pad("launcher_r", "LAUNCHER", Vector2(610, 960), {"stone": 8, "scrap": 8}),
		_pad("cutter", "WOODCUTTER", Vector2(520, 1180), {"scrap": 12, "wood": 6}),
	]
	bots = []
	monsters = []
	shots = []
	fx = []
	wave = 0
	wave_t = FIRST_WAVE
	spawn_queue = []
	spawn_t = 0.0
	fence_max = FENCE_START
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
	_update_player_gun(dt)
	_update_hearts(dt)
	_update_nodes(dt)
	_update_machine(dt)
	_update_launchers(dt)
	_update_bots(dt)
	_update_waves(dt)
	_update_monsters(dt)
	_update_turrets(dt)


func _inside(p: Vector2) -> bool:
	return p.y > FENCE_Y + FENCE_H * 0.5


func _in_door(x: float, r: float) -> bool:
	return absf(x - DOOR_X) <= DOOR_W * 0.5 - r


## The next waypoint toward `to`: through the door when it is on the other side of the fence.
func _route(from: Vector2, to: Vector2) -> Vector2:
	if _inside(from) == _inside(to):
		return to
	var near_side := DOOR_IN if _inside(from) else DOOR_OUT
	var far_side := DOOR_OUT if _inside(from) else DOOR_IN
	if absf(from.x - DOOR_X) < 10.0 and from.distance_to(near_side) < 60.0:
		return far_side
	return near_side


## Moves a body, letting it through the fence only at the door.
func _slide(p: Vector2, delta: Vector2, r: float) -> Vector2:
	var n := p + delta
	var band_top := FENCE_Y - r
	var band_bottom := FENCE_Y + FENCE_H + r
	if n.y > band_top and n.y < band_bottom and not _in_door(n.x, r * 0.6):
		if p.y <= band_top:
			n.y = band_top
		elif p.y >= band_bottom:
			n.y = band_bottom
		else:  # inside the doorway and drifting sideways: stay in it
			n.x = clampf(n.x, DOOR_X - DOOR_W * 0.5 + r * 0.6, DOOR_X + DOOR_W * 0.5 - r * 0.6)
	return Vector2(clampf(n.x, 22.0, W - 22.0), clampf(n.y, SPAWN_Y + 30.0, H - 26.0))


func _move_player(dt: float) -> void:
	var dir := Vector2.ZERO
	if autoplay:
		var to := _route(player.pos, _advice()) - (player.pos as Vector2)
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
	player.pos = _slide(player.pos, dir.limit_length(1.0) * PLAYER_SPEED * pace * dt, PLAYER_R)


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
		if t.built and _inside(p) and _near(p, t.pos, REACH + 10.0) and _free_boxes(t) > 0 and _take("ammo"):
			t.ammo += SHOTS_PER_BOX
			_fly(p, t.pos, "ammo")
			return true
	if machine.built and machine.out > 0 and _near(p, OUTPUT_POS, REACH):
		if bag + SHOTS_PER_BOX <= BAG_MAX:  # your own bag first
			machine.out -= 1
			bag += SHOTS_PER_BOX
			_fly(OUTPUT_POS, p, "ammo")
			return true
		if stack.size() < capacity and _useful("ammo"):
			machine.out -= 1
			stack.append("ammo")
			_fly(OUTPUT_POS, p, "ammo")
			return true
	if stack.size() < capacity:
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
		"fence":
			fence_max += 4
		"launcher_l", "launcher_r":
			launchers.append({"pos": pad.pos, "cool": 0.0})
		"rapid":
			rapid = true
		"backpack":
			capacity += 8
		"cutter":
			bots.append({"kind": "cutter", "pos": pad.pos, "carry": 0, "node": -1, "t": 0.0})
	for i in 10:
		var a := TAU * i / 10.0
		fx.append({"from": pad.pos, "to": pad.pos + Vector2(cos(a), sin(a)) * 60.0, "t": 0.0, "dur": 0.45, "kind": "ammo"})
	_log("built %s at %ds (wave %d, fence %d/%d, hearts %d)" % [pad.id, int(time), wave, _waiting(), fence_max, hearts])


## Your own gun: fires at the nearest monster within close range while the bag has shots.
func _update_player_gun(dt: float) -> void:
	gun_cool = maxf(gun_cool - dt, -dt)
	if bag <= 0 or gun_cool > 0.0:
		return
	var best := -1
	var best_d := GUN_RANGE
	for j in monsters.size():
		var d: float = (monsters[j].pos as Vector2).distance_to(player.pos)
		if d < best_d:
			best_d = d
			best = j
	if best < 0:
		return
	bag -= 1
	gun_cool += 1.0 / GUN_RATE
	shots.append({"a": player.pos, "b": monsters[best].pos, "t": 0.08, "player": true})
	_hit(best)


func _update_hearts(dt: float) -> void:
	hurt_t = maxf(hurt_t - dt, 0.0)
	if _inside(player.pos) and hearts < HEARTS:
		heal_t += dt
		if heal_t >= HEART_REGEN:
			heal_t = 0.0
			hearts += 1
	else:
		heal_t = 0.0


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


## Launchers take boxes from the machine's output and lob them to turrets within reach.
func _update_launchers(dt: float) -> void:
	for l in launchers:
		l.cool = maxf(l.cool - dt, 0.0)
		if l.cool > 0.0 or machine.out <= 0:
			continue
		var best := -1
		for i in turrets.size():
			var t: Dictionary = turrets[i]
			if _free_boxes(t) - _boxes_in_flight(i) > 0 and (l.pos as Vector2).distance_to(t.pos) <= LAUNCH_RANGE:
				if best < 0 or t.ammo < turrets[best].ammo:
					best = i
		if best < 0:
			continue
		machine.out -= 1
		l.cool = LAUNCH_TIME
		lobs.append({"from": l.pos, "to": turrets[best].pos, "t": 0.0, "dur": 0.7, "turret": best})
	var k := 0
	while k < lobs.size():
		lobs[k].t += dt
		if lobs[k].t >= lobs[k].dur:
			turrets[lobs[k].turret].ammo += SHOTS_PER_BOX
			lobs.remove_at(k)
		else:
			k += 1


func _boxes_in_flight(turret: int) -> int:
	var n := 0
	for b in lobs:
		if b.turret == turret:
			n += 1
	return n


func _update_bots(dt: float) -> void:
	for b in bots:
		_cutter(b, dt)


## Woodcutter: walks out through the door, chops trees and feeds the ammo machine. Monsters ignore it.
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
	if _move_to(b, MACHINE_POS + Vector2(46, 0), dt) and machine.built and machine.input < MACHINE_IN_MAX:
		var n2 := mini(b.carry, MACHINE_IN_MAX - machine.input)
		machine.input += n2
		b.carry -= n2


func _move_to(b: Dictionary, target: Vector2, dt: float) -> bool:
	var step_to := _route(b.pos, target)
	var to: Vector2 = step_to - b.pos
	if step_to == target and to.length() <= 6.0:
		return true
	b.pos = _slide(b.pos, to.normalized() * minf(to.length(), BOT_SPEED * dt), 10.0)
	return false


func _update_waves(dt: float) -> void:
	if spawn_queue.is_empty():
		if wave < WAVES:
			wave_t -= dt
			if wave_t <= 0.0:
				_start_wave()
		elif monsters.is_empty():
			state = "won"
			_log("WON at %ds, hearts %d, kills %d" % [int(time), hearts, kills])
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
	_log("wave %d at %ds: %d monsters | fence %d/%d | hearts %d | turret shots %d | built %d" % [wave, int(time),
		list.size(), _waiting(), fence_max, hearts, ammo, built_count])


func _spawn(type: String) -> void:
	var d: Dictionary = MONSTERS[type]
	var lane := rng.randi_range(0, 2)
	var hp := roundi(d.hp * (1.0 + HP_GROWTH * (wave - 1)))
	monsters.append({"type": type, "pos": Vector2(LANES[lane] + rng.randf_range(-22.0, 22.0), SPAWN_Y), "lane": lane,
		"hp": hp, "max": hp, "speed": d.speed * rng.randf_range(0.92, 1.08), "r": d.r, "chase": false,
		"waiting": false, "hit_cool": 0.0})


func _waiting() -> int:
	var n := 0
	for m in monsters:
		if m.waiting:
			n += 1
	return n


func _update_monsters(dt: float) -> void:
	var p: Vector2 = player.pos
	for m in monsters:
		var d: Dictionary = MONSTERS[m.type]
		var mp: Vector2 = m.pos
		var to_player := mp.distance_to(p)
		# notice you when you are outside and close; lose interest once you are far away
		if not m.chase and not _inside(p) and to_player <= d.notice:
			m.chase = true
			m.waiting = false
		elif m.chase and to_player > GIVE_UP:
			m.chase = false
		m.hit_cool = maxf(m.hit_cool - dt, 0.0)
		if m.chase:
			var goal := _route(mp, p)
			m.pos = _slide(mp, (goal - mp).normalized() * minf(goal.distance_to(mp), m.speed * dt), m.r)
			if _inside(m.pos):
				_lose("A monster followed you in")
				return
			if (m.pos as Vector2).distance_to(p) <= m.r + PLAYER_R and m.hit_cool <= 0.0 and hurt_t <= 0.0:
				m.hit_cool = 1.0
				hurt_t = HURT_GRACE
				hearts -= int(d.hit)
				for k in 5:
					fx.append({"from": p, "to": p + Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 10)),
						"t": 0.0, "dur": 0.35, "kind": "hurt"})
				if hearts <= 0:
					hearts = 0
					_lose("You were overrun")
					return
			continue
		# march: drift back to the lane, then straight down to the fence and wait there
		var lane_x: float = LANES[m.lane]
		m.pos.x = move_toward(mp.x, clampf(mp.x, lane_x - 26.0, lane_x + 26.0), 40.0 * dt)
		var stop: float = FENCE_Y - m.r - 2.0
		if mp.y < stop:
			m.pos.y = minf(mp.y + m.speed * dt, stop)
		elif not m.waiting:
			m.waiting = true
	_spread_waiting()
	if _waiting() >= fence_max:
		_lose("The fence gave way")


## Monsters waiting at the fence stand shoulder to shoulder instead of on top of each other.
func _spread_waiting() -> void:
	for i in monsters.size():
		var a: Dictionary = monsters[i]
		if not a.waiting:
			continue
		for j in range(i + 1, monsters.size()):
			var b: Dictionary = monsters[j]
			if not b.waiting:
				continue
			var dx: float = b.pos.x - a.pos.x
			var min_d: float = a.r + b.r + 2.0
			if absf(dx) < min_d:
				var push := (min_d - absf(dx)) * 0.5 * (1.0 if dx >= 0.0 else -1.0)
				a.pos.x = clampf(a.pos.x - push, 20.0, W - 20.0)
				b.pos.x = clampf(b.pos.x + push, 20.0, W - 20.0)
	for m in monsters:  # the doorway stays clear: waiting monsters stand to either side of it
		var half: float = DOOR_W * 0.5 + m.r + 4.0
		if m.waiting and absf(m.pos.x - DOOR_X) < half:
			m.pos.x = DOOR_X - half if m.pos.x < DOOR_X else DOOR_X + half


func _lose(reason: String) -> void:
	state = "lost"
	lose_reason = reason
	_log("LOST (%s) at %ds in wave %d, kills %d" % [reason, int(time), wave, kills])


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
		t.aim = ((monsters[best].pos as Vector2) - (t.pos as Vector2)).normalized()
		if t.ammo <= 0 or t.cool > 0.0:
			continue
		t.ammo -= 1
		t.cool += 1.0 / rate
		t.flash = 0.06
		shots.append({"a": t.pos + t.aim * 28.0, "b": monsters[best].pos, "t": 0.08, "player": false})
		_hit(best)


func _hit(index: int) -> void:
	var m: Dictionary = monsters[index]
	m.hp -= 1
	if m.hp > 0:
		return
	kills += 1
	if _scrap_wanted_later():
		for k in int(MONSTERS[m.type].drop):
			pickups.append({"kind": "scrap", "life": SCRAP_LIFE,
				"pos": m.pos + Vector2(rng.randf_range(-16, 16), rng.randf_range(-16, 16))})
	monsters.remove_at(index)


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


func _need(kind: String) -> int:
	var n := 0
	for p in _visible_pads():
		n += maxi(_remaining(p, kind), 0)
	return n


## You only pick up what something needs, so your stack never fills with junk.
func _useful(kind: String) -> bool:
	match kind:
		"wood":
			if machine.built:
				return true
		"ammo":
			return _count("ammo") < _manual_free_boxes()
	return _count(kind) < _need(kind)


func _free_boxes(t: Dictionary) -> int:
	return (TURRET_BOXES * SHOTS_PER_BOX - int(t.ammo)) / SHOTS_PER_BOX if t.built else 0


func _total_free_boxes() -> int:
	var n := 0
	for t in turrets:
		n += _free_boxes(t)
	return n


func _covered(t: Dictionary) -> bool:
	for l in launchers:
		if (l.pos as Vector2).distance_to(t.pos) <= LAUNCH_RANGE:
			return true
	return false


## Space in the turrets no launcher reaches: those are the ones you still carry boxes to.
func _manual_free_boxes() -> int:
	var n := 0
	for t in turrets:
		if not _covered(t):
			n += _free_boxes(t)
	return n


func _neediest_turret() -> Dictionary:
	var best := {}
	for t in turrets:
		if _free_boxes(t) > 0 and not _covered(t) and (best.is_empty() or t.ammo < best.ammo):
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


## No monster close enough to notice you there.
func _safe(at: Vector2) -> bool:
	for m in monsters:
		if (m.pos as Vector2).distance_to(at) < float(MONSTERS[m.type].notice) + 40.0:
			return false
	return true


func _nearest_safe_node(p: Vector2, kind: String) -> Dictionary:
	var best := {}
	for n in nodes:
		if n.stock > 0 and n.kind == kind and _safe(n.pos) and (best.is_empty() or p.distance_to(n.pos) < p.distance_to(best.pos)):
			best = n
	return best


func _scrap_wanted_later() -> bool:
	for p in pads:
		if not p.done and _remaining(p, "scrap") > 0:
			return true
	return false


func _ammo_short() -> bool:
	return machine.built and machine.input * BOXES_PER_WOOD + machine.out < _total_free_boxes() + (BAG_MAX - bag) / SHOTS_PER_BOX


## The most useful place to go next. Drives the guide arrow and the bot.
func _advice() -> Vector2:
	var p: Vector2 = player.pos
	var space := capacity - stack.size()
	# outside and in trouble: get back in through the door
	if not _inside(p):
		var threat := false
		for m in monsters:
			if m.chase and (m.pos as Vector2).distance_to(p) < 110.0:
				threat = true
		if hearts <= 2 or (threat and (bag <= 0 or hearts <= 3)):
			return DOOR_IN + Vector2(0, 60)
	if _count("ammo") > 0:
		var t := _neediest_turret()
		if not t.is_empty():
			return t.pos + Vector2(0, 46)
	if machine.built and machine.out > 0 and (bag <= BAG_MAX - SHOTS_PER_BOX * 2 or (_manual_free_boxes() >= 2 and space > 0)):
		return OUTPUT_POS + Vector2(0, 26)
	for pad in _visible_pads():  # already at a pad that takes something you carry: finish unloading
		if _near(p, pad.pos, PAD_HALF + 10.0):
			for kind in pad.cost:
				if _remaining(pad, kind) > 0 and _count(kind) > 0:
					return _stand(pad.pos)
	var want := _want_kind()
	var can_gather := space > 0 and (not _inside(p) or _outside_ok())
	if space == 0 or want == "" or not can_gather or _count(want) == 0 and want == "scrap":  # fill up first, then deliver
		for pad in _visible_pads():
			for kind in pad.cost:
				if _remaining(pad, kind) > 0 and _count(kind) > 0:
					return _stand(pad.pos)
	if machine.built and _count("wood") > 0 and machine.input < MACHINE_IN_MAX and (_ammo_short() or _need("wood") == 0) \
			and (space == 0 or want != "wood" or not can_gather or _near(p, MACHINE_POS, REACH)):
		return MACHINE_POS + Vector2(0, 40)
	if can_gather:
		if _useful("scrap"):
			var best := {}
			for k in pickups:
				if k.kind == "scrap" and _safe(k.pos) and (best.is_empty() or p.distance_to(k.pos) < p.distance_to(best.pos)):
					best = k
			if not best.is_empty():
				return best.pos
		if want != "":
			var n := _nearest_safe_node(p, want)
			if not n.is_empty():
				return n.pos + (Vector2(34, 0) if want == "wood" else Vector2(-34, 0))
	return p if _inside(p) else DOOR_IN + Vector2(0, 60)


## Where to stand for a spot: pads in the fence line are worked from the inside.
func _stand(at: Vector2) -> Vector2:
	if absf(at.y - (FENCE_Y + FENCE_H * 0.5)) < 30.0:
		return at + Vector2(0, 40)
	return at


## Gathering means going out: not while monsters wait at the door, unless your bag is well stocked.
func _outside_ok() -> bool:
	return _safe(DOOR_OUT) or bag >= 20


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
	if stone > 0 and stone >= wood:
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
	draw_rect(Rect2(0, 0, W, H), Color("#56663f"))
	draw_rect(Rect2(0, HUD_H, W, SPAWN_Y - HUD_H + 26), Color("#3f3530"))
	draw_rect(Rect2(0, FENCE_Y, W, H - FENCE_Y), Color("#6b5d48"))
	for x in LANES:
		draw_rect(Rect2(x - 32, SPAWN_Y, 64, FENCE_Y - SPAWN_Y), Color(0.8, 0.72, 0.5, 0.18))
	_draw_fortress()
	_draw_fence()
	for n in nodes:
		_draw_node(n)
	for pad in _visible_pads():
		_draw_pad(pad)
	_draw_machine()
	for l in launchers:
		_draw_launcher(l)
	for t in turrets:
		_draw_turret(t)
	for k in pickups:
		if k.life > 6.0 or fmod(k.life, 0.5) > 0.2:
			_item(k.pos, k.kind, 6)
	for m in monsters:
		_draw_monster(m)
	for s in shots:
		var c := Color(0.6, 0.95, 1.0) if s.player else Color(1, 0.92, 0.55)
		draw_line(s.a, s.b, Color(c, clampf(s.t / 0.08, 0, 1)), 3.0)
	for b in bots:
		_draw_bot(b)
	_draw_player()
	for b in lobs:
		var k := clampf(b.t / b.dur, 0, 1)
		_item((b.from as Vector2).lerp(b.to, k) + Vector2(0, -sin(k * PI) * 90.0), "ammo", 7)
	for f in fx:
		var k := clampf(f.t / f.dur, 0, 1)
		var pos: Vector2 = (f.from as Vector2).lerp(f.to, k) + Vector2(0, -sin(k * PI) * 30.0)
		if f.kind == "spark":
			draw_circle(pos, 4.0 * (1.0 - k) + 1.0, Color("#ffcf6b"))
		elif f.kind == "hurt":
			draw_circle(pos, 5.0 * (1.0 - k) + 1.0, Color("#ff5e5e"))
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
		var x := 60.0 + (i % 6) * 120.0
		var y := H - 34.0 - (i / 6) * 48.0
		draw_rect(Rect2(x - 22, y - 10, 44, 28), Color("#b9a27c"))
		draw_colored_polygon(PackedVector2Array([Vector2(x - 28, y - 10), Vector2(x, y - 32), Vector2(x + 28, y - 10)]), Color("#8c3b2e"))


func _draw_fence() -> void:
	var col := Color("#8a6a45")
	var dark := Color("#4a3624")
	var gap0 := DOOR_X - DOOR_W * 0.5
	var gap1 := DOOR_X + DOOR_W * 0.5
	for seg in [[0.0, gap0], [gap1, W]]:
		draw_rect(Rect2(seg[0], FENCE_Y + 4, seg[1] - seg[0], 5), col)
		draw_rect(Rect2(seg[0], FENCE_Y + 11, seg[1] - seg[0], 5), col)
		var x: float = seg[0] + 6.0
		while x < seg[1] - 4.0:
			draw_rect(Rect2(x - 3, FENCE_Y - 6, 6, FENCE_H + 8), dark)
			x += 22.0
	# door posts
	draw_rect(Rect2(gap0 - 6, FENCE_Y - 12, 8, FENCE_H + 16), dark)
	draw_rect(Rect2(gap1 - 2, FENCE_Y - 12, 8, FENCE_H + 16), dark)
	# strain: the fence glows red as it fills
	var strain := float(_waiting()) / float(fence_max)
	if strain > 0.0:
		draw_rect(Rect2(0, FENCE_Y + 2, W, FENCE_H - 2), Color(1.0, 0.25, 0.2, 0.25 * strain + 0.1 * sin(time * 6.0) * strain))


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
	if str(pad.id).begins_with("launcher"):  # show what it will reach
		draw_arc(pad.pos, LAUNCH_RANGE, PI, TAU, 48, Color(0.95, 0.76, 0.3, 0.35), 2.0)


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
		_item(MACHINE_POS + Vector2(48, 18), "wood", 6)
		_text("%d" % machine.input, MACHINE_POS + Vector2(48, 36), 14, Color.WHITE)
	draw_rect(Rect2(OUTPUT_POS - Vector2(30, 18), Vector2(60, 40)), Color(0, 0, 0, 0.18))
	for i in machine.out:
		var col: int = i % 4
		var row: int = i / 4
		_item(OUTPUT_POS + Vector2(-18 + col * 12, 10 - row * 9), "ammo", 6)


func _draw_launcher(l: Dictionary) -> void:
	var p: Vector2 = l.pos
	draw_line(OUTPUT_POS, p, Color(0.95, 0.76, 0.3, 0.35), 3.0)  # fed from the output pile
	draw_rect(Rect2(p - Vector2(22, 18), Vector2(44, 36)), Color("#5b4a7a"))
	draw_rect(Rect2(p - Vector2(22, 18), Vector2(44, 36)), Color("#2b2140"), false, 3.0)
	var arm := Vector2(0, -1).rotated(-0.6 + 0.6 * (l.cool / LAUNCH_TIME))
	draw_line(p, p + arm * 28.0, Color("#2b2140"), 7.0)
	draw_circle(p + arm * 28.0, 6.0, Color("#f2c14e"))


func _draw_turret(t: Dictionary) -> void:
	if not t.built:
		draw_rect(Rect2(t.pos - Vector2(20, 20), Vector2(40, 40)), Color(1, 1, 1, 0.12))
		return
	if _near(player.pos, t.pos, 120.0):
		draw_arc(t.pos, TURRET_RANGE, PI, TAU, 64, Color(0.48, 0.95, 0.92, 0.25), 2.0)
	draw_rect(Rect2(t.pos - Vector2(26, 26), Vector2(52, 52)), Color("#2e5d8a"))
	draw_rect(Rect2(t.pos - Vector2(26, 26), Vector2(52, 52)), Color("#16304a"), false, 3.0)
	draw_line(t.pos, t.pos + (t.aim as Vector2) * 36.0, Color("#16304a"), 10.0)
	draw_circle(t.pos, 12.0, Color("#3f7cb5"))
	if t.flash > 0.0:
		draw_circle(t.pos + (t.aim as Vector2) * 40.0, 7.0, Color("#ffe08f"))
	var max_ammo := TURRET_BOXES * SHOTS_PER_BOX
	draw_rect(Rect2(t.pos + Vector2(-26, 32), Vector2(52, 7)), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(t.pos + Vector2(-26, 32), Vector2(52.0 * t.ammo / max_ammo, 7)), Color("#f2c14e"))
	if t.ammo <= 0:
		var pulse := 0.5 + 0.5 * sin(time * 8.0)
		draw_arc(t.pos, 36.0 + pulse * 6.0, 0, TAU, 32, Color(0.95, 0.35, 0.3, 0.9), 4.0)


func _draw_monster(m: Dictionary) -> void:
	var c: Color = MONSTERS[m.type].color
	var p: Vector2 = m.pos
	var r: float = m.r
	if m.chase:
		draw_arc(p, r + 5.0, 0, TAU, 20, Color(1, 0.3, 0.3, 0.8), 2.0)
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
	var c := Color("#5fbf6a")
	draw_circle(b.pos, 12.0, c)
	draw_circle(b.pos, 12.0, c.darkened(0.5), false, 2.0)
	for i in b.carry:
		_item(b.pos + Vector2(0, -20 - i * 8), "wood", 5)


func _draw_player() -> void:
	var p: Vector2 = player.pos
	if not _inside(p):
		draw_arc(p, GUN_RANGE, 0, TAU, 48, Color(0.6, 0.95, 1.0, 0.12 if bag > 0 else 0.0), 2.0)
	draw_circle(p + Vector2(0, 14), 14.0, Color(0, 0, 0, 0.25))
	var blink := hurt_t > 0.0 and fmod(hurt_t, 0.16) < 0.08
	draw_circle(p, PLAYER_R + 1.0, Color("#ff5e5e") if blink else Color("#f2e4cb"))
	draw_circle(p, PLAYER_R + 1.0, Color("#2b2f36"), false, 3.0)
	draw_circle(p + (player.face as Vector2) * 9.0, 4.5, Color("#2b2f36"))
	# your own ammo bag, separate from the stack
	draw_rect(Rect2(p + Vector2(-20, 22), Vector2(40, 5)), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(p + Vector2(-20, 22), Vector2(40.0 * bag / BAG_MAX, 5)), Color("#7af1eb"))
	for i in stack.size():
		_item(p + Vector2(0, -30 - i * 9), stack[i], 9)
	if stack.size() >= capacity:
		_text("FULL", p + Vector2(0, 38), 13, Color("#ffcb5e"))


func _draw_arrow() -> void:
	var target := _route(player.pos, _advice())
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
	_text("WAVE %d/%d" % [wave, WAVES], Vector2(80, 30), 20, Color("#f2e4cb"))
	if not spawn_queue.is_empty():
		_text("INCOMING %d" % spawn_queue.size(), Vector2(80, 62), 15, Color("#ff7b6b"))
	elif wave < WAVES:
		_text("NEXT IN %ds" % int(ceil(wave_t)), Vector2(80, 62), 15, Color("#a9a395"))
	# fence: how many monsters it can hold
	_text("FENCE", Vector2(W * 0.5 - 40, 24), 14, Color("#a9a395"))
	var pw := minf(16.0, 190.0 / fence_max)
	var x0 := W * 0.5 - 40 - pw * fence_max * 0.5
	var waiting := _waiting()
	for i in fence_max:
		draw_rect(Rect2(x0 + i * pw + 1, 40, pw - 3, 20), Color("#ff6b5e") if i < waiting else Color("#8a6a45"))
	# hearts
	for i in HEARTS:
		var c := Color("#ff6b6b") if i < hearts else Color("#3a2a2a")
		var hp := Vector2(W * 0.5 + 92 + i * 22, 30)
		draw_circle(hp + Vector2(-4, 0), 5.0, c)
		draw_circle(hp + Vector2(4, 0), 5.0, c)
		draw_colored_polygon(PackedVector2Array([hp + Vector2(-9, 1), hp + Vector2(9, 1), hp + Vector2(0, 11)]), c)
	_text("BAG %d" % bag, Vector2(W * 0.5 + 136, 64), 14, Color("#7af1eb"))
	_text("%d/%d" % [stack.size(), capacity], Vector2(W - 50, 30), 20, Color("#f2e4cb"))
	_text("CARRY", Vector2(W - 50, 62), 13, Color("#a9a395"))


func _draw_end() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.55))
	var won := state == "won"
	draw_rect(Rect2(80, 430, W - 160, 340), Color("#1f2328"))
	draw_rect(Rect2(80, 430, W - 160, 340), Color("#7af1eb") if won else Color("#ff6b5e"), false, 4.0)
	_text("FORTRESS HOLDS" if won else "FORTRESS FELL", Vector2(W * 0.5, 495), 40, Color.WHITE)
	if not won:
		_text(lose_reason, Vector2(W * 0.5, 545), 22, Color("#ff9a8f"))
	_text("Waves survived: %d / %d" % [wave if won else wave - 1, WAVES], Vector2(W * 0.5, 600), 22, Color("#f2e4cb"))
	_text("Monsters stopped: %d" % kills, Vector2(W * 0.5, 640), 22, Color("#f2e4cb"))
	_text("TAP TO PLAY AGAIN", Vector2(W * 0.5, 715), 22, Color("#ffcb5e"))


# ================================================================== automation

func _log(line: String) -> void:
	log_lines.append(line)
	if args.has("sim"):
		print(line)


func _run_sim() -> void:
	var next_trace := 0.0
	while state == "play" and time < 1500.0:
		step(1.0 / 30.0)
		if args.has("trace") and time >= next_trace and time < float(args.trace) and time >= float(args.get("from", "0")):
			next_trace = time + 1.0
			var near := 0
			for m in monsters:
				if m.chase:
					near += 1
			print("  t=%d pos=%s hearts=%d bag=%d chasers=%d stack=%d target=%s" % [int(time), player.pos.round(), hearts, bag, near, stack.size(), _advice().round()])
	if args.has("dump"):
		for m in monsters:
			print("  monster %s at %s waiting=%s chase=%s hp=%d" % [m.type, (m.pos as Vector2).round(), m.waiting, m.chase, m.hp])
		for t in turrets:
			print("  turret at %s built=%s ammo=%d" % [t.pos, t.built, t.ammo])
		print("  player %s bag=%d stack=%s machine=%s advice=%s" % [player.pos.round(), bag, stack, machine, _advice().round()])
	print("RESULT %s at %ds, wave %d, hearts %d, fence %d/%d, kills %d, built %d" % [state, int(time), wave,
		hearts, _waiting(), fence_max, kills, built_count])
	get_tree().quit()


func _take_shot() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(str(args.shot))
	print("[shot] saved ", args.shot)
	get_tree().quit()
