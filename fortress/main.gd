extends Node2D
## FORTRESS: gameplay prototype drawn with basic shapes. See DESIGN.md.
## You live behind a fence that you vault over anywhere but at its towers; monsters can't climb it.
## Outside: trees, rocks and three winding monster paths that come in from off the map. Inside: the
## ammo machine, launchers and everything else you build. Monsters follow their path to the fence and
## wait there; too many waiting and the fence gives. Step outside to gather and they come for you: a
## few touches and you are down.
##
## Automation (after `--`):
##   sim=bot | sim=idle      headless balance run: prints a log and quits (pace=0.7 slows the bot)
##   autoplay                the built-in bot plays (screenshots, demos)
##   warp=120                fast-forward this many seconds before showing anything
##   shot=/path.png shot_time=2

# ---------------------------------------------------------------- layout (design pixels)
const W := 1200.0                # the world; the camera follows you around it
const H := 1640.0
const HUD_H := 92.0
const SW := 720.0                 # the screen (HUD) size, apart from the world
const SH := 1280.0
const FENCE_Y := 1100.0
const FENCE_H := 18.0
const LANES := [380.0, 600.0, 820.0]   # where each path meets the fence, under its turret
const TOWER_HALF := 44.0          # you can't climb the fence within this of a tower
const VAULT_TIME := 0.42
const MACHINE_POS := Vector2(600, 1450)
const OUTPUT_POS := Vector2(600, 1350)
const PAD_HALF := 34.0
## The monster paths, from off the top of the map to the fence (smoothed into curves).
const PATHS := [
	[Vector2(170, -80), Vector2(300, 180), Vector2(150, 400), Vector2(330, 610), Vector2(320, 850), Vector2(380, 1074)],
	[Vector2(640, -80), Vector2(500, 180), Vector2(700, 390), Vector2(540, 610), Vector2(660, 850), Vector2(600, 1074)],
	[Vector2(1030, -80), Vector2(900, 190), Vector2(1050, 400), Vector2(870, 610), Vector2(880, 850), Vector2(820, 1074)],
]

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
const RAPID_MULT := 2.0
const POWER_MAX := 12          # monster coins to charge the power-up
const POWER_TIME := 12.0       # seconds of rapid fire once activated
const POWER_BTN := Vector2(SW - 54, 46)
const POWER_R := 32.0
const FREEZE_TIME := 8.0
const FREEZE_MULT := 0.35
const BOMB_DAMAGE := 8.0
const SUPPLY_BOXES := 2
## Powers offered when the meter is full; tap the meter, then one of these.
const POWERS := [
	{"id": "rapid", "label": "RAPID", "color": Color("#7af1eb")},
	{"id": "freeze", "label": "FREEZE", "color": Color("#9fd3ff")},
	{"id": "bomb", "label": "BOMB", "color": Color("#ff7b5e")},
	{"id": "supply", "label": "SUPPLY", "color": Color("#f2c14e")},
]
const UPGRADE_DWELL := 0.6     # stand still this long on an upgrade pad to buy it
const UPGRADE_R := 20.0
const LEVEL2_COST := 8
const EVOLVE_COST := 15
## Turret evolutions, bought at level 2: damage per shot, and fire rate as a multiple of the base turret's.
const EVOLUTIONS := {
	"gatling": {"label": "GATLING", "dmg": 1.0, "rate": 2.0, "splash": 0.0, "slow": 0.0, "color": Color("#c98a2b")},
	"cannon": {"label": "CANNON", "dmg": 3.0, "rate": 0.45, "splash": 55.0, "slow": 0.0, "color": Color("#5a5f66")},
	"frost": {"label": "FROST", "dmg": 1.5, "rate": 1.0, "splash": 0.0, "slow": 2.0, "color": Color("#62b6e8")},
}
const LAUNCH_RANGE := 270.0
const LAUNCH_TIME := 1.2
const FENCE_START := 10         # monsters that can wait at the fence before it gives
const WAVES := 12
const FIRST_WAVE := 30.0
const WAVE_BREAK := 16.0
const SPAWN_GAP := 1.1
const BOT_SPEED := 150.0
const BOT_CARRY := 4
const CUT_TIME := 0.6
const COIN_LIFE := 30.0
const HP_GROWTH := 0.21
const GIVE_UP := 260.0         # a chasing monster loses interest beyond this distance

const ITEM_COLOR := {
	"wood": Color("#b07a3e"), "stone": Color("#a3a8ad"), "coin": Color("#ffd24a"), "ammo": Color("#f2c14e"),
}
const MONSTERS := {
	"grunt": {"hp": 3, "speed": 56.0, "r": 14.0, "notice": 90.0, "hit": 1, "drop": 1, "color": Color("#e5534b")},
	"runner": {"hp": 2, "speed": 112.0, "r": 12.0, "notice": 130.0, "hit": 1, "drop": 1, "color": Color("#ff9561")},
	"brute": {"hp": 14, "speed": 40.0, "r": 22.0, "notice": 70.0, "hit": 2, "drop": 4, "color": Color("#a8323a")},
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
var wallet := 0               # monster coins in hand (not on the stack)
var power := 0                # power meter, filled by every coin you pick up
var power_t := 0.0            # rapid fire time left
var freeze_t := 0.0
var power_menu := false
var dwell_key := ""
var dwell_t := 0.0
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
var hud_font: Font
var next_uid := 0
var paths: Array = []          # {pts, len, total} per lane: the smoothed path and its running length


func _ready() -> void:
	font = ThemeDB.fallback_font
	hud_font = load("res://fonts/BarlowCondensed-ExtraBold.ttf")
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
	if args.has("menu"):  # screenshots: the meter full and its power choice open
		power = POWER_MAX
		power_menu = true
		autoplay = false
	if args.has("shot"):
		get_tree().create_timer(float(args.get("shot_time", "1.5"))).timeout.connect(_take_shot)


func reset() -> void:
	rng.seed = int(args.get("seed", "7"))
	state = "play"
	lose_reason = ""
	time = 0.0
	player = {"pos": Vector2(600, 1250), "face": Vector2.UP}
	if paths.is_empty():
		for raw in PATHS:
			paths.append(_smooth_path(raw))
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
	for i in 8:  # trees on the left flank, rocks on the right
		nodes.append({"kind": "wood", "pos": Vector2(70 + (i % 2) * 90 + (i % 3) * 12, 600 + i * 60), "stock": NODE_STOCK, "regrow": 0.0})
		nodes.append({"kind": "stone", "pos": Vector2(1130 - (i % 2) * 90 - (i % 3) * 12, 620 + i * 58), "stock": NODE_STOCK, "regrow": 0.0})
	pickups = []
	turrets = []
	for i in 3:
		turrets.append({"pos": Vector2(LANES[i], FENCE_Y + FENCE_H * 0.5), "built": i == 1, "level": 1, "evo": "",
			"ammo": SHOTS_PER_BOX * 2 if i == 1 else 0, "cool": 0.0, "aim": Vector2.UP, "flash": 0.0})
	machine = {"built": false, "input": 0, "out": 0, "t": 0.0}
	launchers = []
	lobs = []
	pads = [
		_pad("machine", "AMMO", MACHINE_POS, {"wood": 8}),
		_pad("turret_l", "TURRET", turrets[0].pos, {"wood": 5, "stone": 5}),
		_pad("turret_r", "TURRET", turrets[2].pos, {"wood": 5, "stone": 5}),
		_pad("launcher_l", "LAUNCHER", Vector2(480, 1260), {"stone": 6, "coin": 3}),
		_pad("fence", "FENCE +4", Vector2(980, 1330), {"stone": 8}),
		_pad("backpack", "BIGGER PACK", Vector2(800, 1460), {"wood": 10}),
		_pad("launcher_r", "LAUNCHER", Vector2(720, 1260), {"stone": 6, "coin": 4}),
		_pad("cutter", "WOODCUTTER", Vector2(300, 1450), {"coin": 5, "wood": 6}),
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
	wallet = 0
	power = 0
	power_t = 0.0
	freeze_t = 0.0
	power_menu = false
	dwell_key = ""
	dwell_t = 0.0
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
	_collect_coins()
	power_t = maxf(power_t - dt, 0.0)
	freeze_t = maxf(freeze_t - dt, 0.0)
	_update_upgrades(dt)
	if autoplay and power >= POWER_MAX and monsters.size() >= 6:
		activate_power("bomb" if monsters.size() >= 12 else ("supply" if _total_free_boxes() >= 6 else "rapid"))
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


## The next waypoint toward `to`. Across the fence that is a spot to climb it: clear of the towers
## and, if possible, of monsters waiting there.
func _route(from: Vector2, to: Vector2) -> Vector2:
	if _inside(from) == _inside(to):
		return to
	var cx := _crossing_x(from, to)
	var near_y := FENCE_Y + FENCE_H + 26.0 if _inside(from) else FENCE_Y - 26.0
	var far_y := FENCE_Y - 40.0 if _inside(from) else FENCE_Y + FENCE_H + 40.0
	if absf(from.x - cx) < 14.0 and absf(from.y - near_y) < 24.0:
		return Vector2(cx, far_y)  # at the fence: push across and climb
	return Vector2(cx, near_y)


func _crossing_x(from: Vector2, to: Vector2) -> float:
	var k := clampf((FENCE_Y - from.y) / (to.y - from.y), 0.0, 1.0) if absf(to.y - from.y) > 0.1 else 0.0
	if absf(from.y - (FENCE_Y + FENCE_H * 0.5)) < 70.0:  # already at the fence: climb right here
		k = 0.0
	var base := clampf(lerpf(from.x, to.x, k), 40.0, W - 40.0)
	var fallback := -1.0
	for step in 40:
		var d := (step + 1) / 2 * 24.0 * (1.0 if step % 2 == 0 else -1.0)
		var x := base + d
		if x < 40.0 or x > W - 40.0 or _tower_at(x):
			continue
		if fallback < 0.0:
			fallback = x
		if _safe(Vector2(x, FENCE_Y - 20.0)):
			return x
	return fallback if fallback >= 0.0 else base


func _tower_at(x: float) -> bool:
	for t in turrets:
		if absf(x - float(t.pos.x)) < TOWER_HALF:
			return true
	return false


## Moves a body; nothing passes through the fence (climbing over it is `_walk`).
func _slide(p: Vector2, delta: Vector2, r: float) -> Vector2:
	var n := p + delta
	var top := FENCE_Y - r
	var bottom := FENCE_Y + FENCE_H + r
	if p.y <= top and n.y > top:
		n.y = top
	elif p.y >= bottom and n.y < bottom:
		n.y = bottom
	return Vector2(clampf(n.x, 22.0, W - 22.0), clampf(n.y, -140.0, H - 26.0))


## Moves a walker (you or a helper) who climbs over the fence when pushing into it away from a tower.
func _walk(b: Dictionary, delta: Vector2, r: float, dt: float) -> void:
	if b.has("vault"):
		var v: Dictionary = b.vault
		v.t += dt
		var k := minf(float(v.t) / VAULT_TIME, 1.0)
		b.pos = (v.from as Vector2).lerp(v.to, k)
		if k >= 1.0:
			b.erase("vault")
		return
	var p: Vector2 = b.pos
	var outside := p.y < FENCE_Y
	var touching := (outside and p.y >= FENCE_Y - r - 2.0) or (not outside and p.y <= FENCE_Y + FENCE_H + r + 2.0)
	var toward := delta.y > 0.0 if outside else delta.y < 0.0
	if touching and toward and absf(delta.y) > delta.length() * 0.45 and not _tower_at(p.x):
		var to := Vector2(p.x, FENCE_Y + FENCE_H + r + 2.0 if outside else FENCE_Y - r - 2.0)
		b.vault = {"t": 0.0, "from": p, "to": to}
		return
	var n := _slide(p, delta, r)
	n.y = maxf(n.y, 70.0)  # walkers stay on the map
	b.pos = n


## A path smoothed through its points (Catmull-Rom), with the running length at every sample.
func _smooth_path(raw: Array) -> Dictionary:
	var pts := PackedVector2Array()
	for i in raw.size() - 1:
		var p0: Vector2 = raw[maxi(i - 1, 0)]
		var p1: Vector2 = raw[i]
		var p2: Vector2 = raw[i + 1]
		var p3: Vector2 = raw[mini(i + 2, raw.size() - 1)]
		for k in 16:
			var t := k / 16.0
			var t2 := t * t
			var t3 := t2 * t
			pts.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	pts.append(raw[raw.size() - 1])
	var lens := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		lens.append(lens[i - 1] + pts[i].distance_to(pts[i - 1]))
	return {"pts": pts, "len": lens, "total": lens[lens.size() - 1]}


func _path_point(path: Dictionary, s: float) -> Vector2:
	var lens: PackedFloat32Array = path.len
	var pts: PackedVector2Array = path.pts
	var i := clampi(lens.bsearch(s), 1, pts.size() - 1)
	var span := lens[i] - lens[i - 1]
	return pts[i - 1].lerp(pts[i], clampf((s - lens[i - 1]) / span, 0.0, 1.0) if span > 0.0 else 1.0)


func _nearest_s(path: Dictionary, p: Vector2) -> float:
	var pts: PackedVector2Array = path.pts
	var best := 0
	for i in pts.size():
		if pts[i].distance_squared_to(p) < pts[best].distance_squared_to(p):
			best = i
	return (path.len as PackedFloat32Array)[best]


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
	_walk(player, dir.limit_length(1.0) * PLAYER_SPEED * pace * dt, PLAYER_R, dt)


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
				if _remaining(pad, kind) > 0 and _take_item(kind):
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
	return false


## Coins are scooped up as you walk over them, straight into your wallet and the power meter.
func _collect_coins() -> void:
	var i := 0
	while i < pickups.size():
		var k: Dictionary = pickups[i]
		if _near(player.pos, k.pos, REACH):
			wallet += 1
			power = mini(power + 1, POWER_MAX)
			_fly(k.pos, POWER_BTN, "coin")
			pickups.remove_at(i)
		else:
			i += 1


## Fires one of the powers once the meter is full.
func activate_power(id: String = "rapid") -> void:
	if power < POWER_MAX or state != "play":
		return
	power = 0
	power_menu = false
	match id:
		"rapid":
			power_t = POWER_TIME
		"freeze":
			freeze_t = FREEZE_TIME
		"bomb":
			var i := monsters.size() - 1
			while i >= 0:
				for k in 6:
					fx.append({"uid": _uid(), "from": monsters[i].pos, "to": monsters[i].pos + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 10)),
						"t": 0.0, "dur": 0.4, "kind": "spark"})
				_hit(i, BOMB_DAMAGE)
				i -= 1
		"supply":
			for t in turrets:
				if t.built:
					t.ammo = mini(int(t.ammo) + SUPPLY_BOXES * SHOTS_PER_BOX, TURRET_BOXES * SHOTS_PER_BOX)
			bag = BAG_MAX
	_log("power %s at %ds (wave %d)" % [id, int(time), wave])


func _power_button(k: int) -> Vector2:
	return POWER_BTN + Vector2(0, 78 + k * 66)


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
		"backpack":
			capacity += 8
		"cutter":
			bots.append({"kind": "cutter", "pos": pad.pos, "carry": 0, "node": -1, "t": 0.0})
	for i in 10:
		var a := TAU * i / 10.0
		fx.append({"uid": _uid(), "from": pad.pos, "to": pad.pos + Vector2(cos(a), sin(a)) * 60.0, "t": 0.0, "dur": 0.45, "kind": "ammo"})
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
	shots.append({"uid": _uid(), "a": player.pos, "b": monsters[best].pos, "t": 0.08, "player": true})
	_hit(best)


## Upgrade pads under each built turret: level 2, then a choice of three evolutions.
func _upgrade_pads() -> Array:
	var out := []
	for i in turrets.size():
		var t: Dictionary = turrets[i]
		if not t.built:
			continue
		var base := Vector2(t.pos.x, FENCE_Y + 66.0)
		if t.level == 1:
			out.append({"key": "%d:lv2" % i, "turret": i, "choice": "lv2", "pos": base, "cost": LEVEL2_COST, "label": "LV 2"})
		elif t.evo == "":
			var k := 0
			for e in EVOLUTIONS:
				out.append({"key": "%d:%s" % [i, e], "turret": i, "choice": e, "pos": base + Vector2(0, k * 50.0),
					"cost": EVOLVE_COST, "label": EVOLUTIONS[e].label})
				k += 1
	return out


func _update_upgrades(dt: float) -> void:
	var here := {}
	for u in _upgrade_pads():
		if _near(player.pos, u.pos, UPGRADE_R + 12.0):
			here = u
	if here.is_empty() or wallet < int(here.cost):
		dwell_key = ""
		dwell_t = 0.0
		return
	if here.key != dwell_key:
		dwell_key = here.key
		dwell_t = 0.0
	dwell_t += dt
	if dwell_t < UPGRADE_DWELL:
		return
	wallet -= int(here.cost)
	var t: Dictionary = turrets[here.turret]
	if here.choice == "lv2":
		t.level = 2
	else:
		t.evo = here.choice
		t.level = 3
	dwell_key = ""
	dwell_t = 0.0
	for k in 10:
		var a := TAU * k / 10.0
		fx.append({"uid": _uid(), "from": t.pos, "to": t.pos + Vector2(cos(a), sin(a)) * 50.0, "t": 0.0, "dur": 0.45, "kind": "coin"})
	_log("turret %d -> %s at %ds (wave %d)" % [here.turret, here.choice, int(time), wave])


## Damage, rate and effects of a turret after its upgrades.
func _turret_stats(t: Dictionary) -> Dictionary:
	var st := {"dmg": 1.0, "rate": TURRET_RATE, "splash": 0.0, "slow": 0.0}
	if t.level >= 2:
		st.dmg = 1.5
	if t.evo != "":
		var e: Dictionary = EVOLUTIONS[t.evo]
		st.dmg = float(e.dmg)
		st.rate = TURRET_RATE * float(e.rate)
		st.splash = float(e.splash)
		st.slow = float(e.slow)
	if power_t > 0.0:
		st.rate *= RAPID_MULT
	return st


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
		lobs.append({"uid": _uid(), "from": l.pos, "to": turrets[best].pos, "t": 0.0, "dur": 0.7, "turret": best})
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


## Woodcutter: climbs out over the fence, chops trees and feeds the ammo machine. Monsters ignore it.
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
	_walk(b, to.normalized() * minf(to.length(), BOT_SPEED * dt), 10.0, dt)
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
	for i in 4 + 3 * wave:
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
	var off := rng.randf_range(-20.0, 20.0)
	monsters.append({"uid": _uid(), "type": type, "pos": _path_point(paths[lane], 0.0) + Vector2(off, 0), "lane": lane, "s": 0.0, "off": off,
		"hp": float(hp), "max": float(hp), "slow_t": 0.0, "speed": d.speed * rng.randf_range(0.92, 1.08), "r": d.r, "chase": false,
		"waiting": false, "hit_cool": 0.0})


func _speed_mult(m: Dictionary) -> float:
	return (0.5 if m.slow_t > 0.0 else 1.0) * (FREEZE_MULT if freeze_t > 0.0 else 1.0)


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
		elif m.chase and (to_player > GIVE_UP or _inside(p)):  # gave up, or you got over the fence
			m.chase = false
			m.s = _nearest_s(paths[m.lane], mp)
		m.hit_cool = maxf(m.hit_cool - dt, 0.0)
		m.slow_t = maxf(m.slow_t - dt, 0.0)
		if m.chase:
			var goal := _route(mp, p)
			m.pos = _slide(mp, (goal - mp).normalized() * minf(goal.distance_to(mp), m.speed * _speed_mult(m) * dt), m.r)
			if (m.pos as Vector2).distance_to(p) <= m.r + PLAYER_R and m.hit_cool <= 0.0 and hurt_t <= 0.0:
				m.hit_cool = 1.0
				hurt_t = HURT_GRACE
				hearts -= int(d.hit)
				for k in 5:
					fx.append({"uid": _uid(), "from": p, "to": p + Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 10)),
						"t": 0.0, "dur": 0.35, "kind": "hurt"})
				if hearts <= 0:
					hearts = 0
					_lose("You were overrun")
					return
			continue
		# march: along the path to the fence and wait there (back onto the path first after a chase)
		if m.waiting:
			continue
		var path: Dictionary = paths[m.lane]
		var step_len: float = m.speed * _speed_mult(m) * dt
		var target := _path_point(path, m.s) + Vector2(m.off, 0)
		if mp.distance_to(target) > step_len + 3.0:
			m.pos = _slide(mp, (target - mp).normalized() * step_len, m.r)
		elif m.s >= float(path.total):
			m.pos = target
			m.waiting = true
		else:
			m.s = minf(m.s + step_len, float(path.total))
			m.pos = _path_point(path, m.s) + Vector2(m.off, 0)
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


func _lose(reason: String) -> void:
	state = "lost"
	lose_reason = reason
	_log("LOST (%s) at %ds in wave %d, kills %d" % [reason, int(time), wave, kills])


func _update_turrets(dt: float) -> void:
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
		var st := _turret_stats(t)
		t.ammo -= 1
		t.cool += 1.0 / float(st.rate)
		t.flash = 0.06
		var target: Vector2 = monsters[best].pos
		shots.append({"uid": _uid(), "a": t.pos + t.aim * 28.0, "b": target, "t": 0.08, "player": false, "evo": t.evo})
		if float(st.slow) > 0.0:
			monsters[best].slow_t = float(st.slow)
		if float(st.splash) > 0.0:
			fx.append({"uid": _uid(), "from": target, "to": target, "t": 0.0, "dur": 0.25, "kind": "blast", "r": st.splash})
			var j := monsters.size() - 1
			while j >= 0:
				if (monsters[j].pos as Vector2).distance_to(target) <= float(st.splash):
					_hit(j, float(st.dmg))
				j -= 1
		else:
			_hit(best, float(st.dmg))


func _hit(index: int, dmg: float = 1.0) -> void:
	var m: Dictionary = monsters[index]
	m.hp -= dmg
	if m.hp > 0.0:
		return
	kills += 1
	for k in int(MONSTERS[m.type].drop):
		pickups.append({"uid": _uid(), "kind": "coin", "life": COIN_LIFE,
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


func _have(kind: String) -> int:
	return wallet if kind == "coin" else _count(kind)


func _take_item(kind: String) -> bool:
	if kind == "coin":
		if wallet <= 0:
			return false
		wallet -= 1
		return true
	return _take(kind)


func _ammo_short() -> bool:
	return machine.built and machine.input * BOXES_PER_WOOD + machine.out < _total_free_boxes() + (BAG_MAX - bag) / SHOTS_PER_BOX


## The most useful place to go next. Drives the guide arrow and the bot.
func _advice() -> Vector2:
	var p: Vector2 = player.pos
	var space := capacity - stack.size()
	# outside and in trouble: get back over the fence
	if not _inside(p):
		var close := {}
		for m in monsters:
			if m.chase and (close.is_empty() or (m.pos as Vector2).distance_to(p) < (close.pos as Vector2).distance_to(p)):
				close = m
		if not close.is_empty() and (close.pos as Vector2).distance_to(p) < 200.0:
			# fight it if you have shots, else get back over the fence (it can't follow)
			var away: Vector2 = (p - (close.pos as Vector2)).normalized()
			if bag > 0 and hearts > 2:
				return p + away * 40.0
			return Vector2(p.x, FENCE_Y + 90.0)
		if hearts <= 2:
			return Vector2(p.x, FENCE_Y + 90.0)
	if _count("ammo") > 0:
		var t := _neediest_turret()
		if not t.is_empty():
			return t.pos + Vector2(0, 46)
	if machine.built and machine.out > 0 and (bag <= BAG_MAX - SHOTS_PER_BOX * 2 or (_manual_free_boxes() >= 2 and space > 0)):
		return OUTPUT_POS + Vector2(0, 26)
	for pad in _visible_pads():  # already at a pad that takes something you carry: finish unloading
		if _near(p, pad.pos, PAD_HALF + 10.0):
			for kind in pad.cost:
				if _remaining(pad, kind) > 0 and _have(kind) > 0:
					return _stand(pad.pos)
	# coins to spend on a turret: go and stand on its upgrade pad
	for u in _upgrade_pads():
		if wallet >= int(u.cost) and (u.choice == "lv2" or u.choice == ["gatling", "cannon", "frost"][u.turret]):
			return u.pos
	var want := _want_kind()
	var can_gather := space > 0 and (not _inside(p) or _outside_ok())
	var coin_ready := false  # a pad that takes coins you already hold
	for pad in _visible_pads():
		if _remaining(pad, "coin") > 0 and wallet > 0 and _remaining(pad, "coin") <= wallet and not _stack_needed_by(pad):
			coin_ready = true
	if space == 0 or want == "" or not can_gather or coin_ready:  # fill up first, then deliver
		for pad in _visible_pads():
			for kind in pad.cost:
				if _remaining(pad, kind) > 0 and _have(kind) > 0:
					return _stand(pad.pos)
	if machine.built and _count("wood") > 0 and machine.input < MACHINE_IN_MAX and (_ammo_short() or _need("wood") == 0) \
			and (space == 0 or want != "wood" or not can_gather or _near(p, MACHINE_POS, REACH)):
		return MACHINE_POS + Vector2(0, 40)
	if not _inside(p) or _outside_ok():
		if space >= 0:
			var best := {}
			for k in pickups:
				if k.kind == "coin" and _safe(k.pos) and (_need("coin") > wallet or p.distance_to(k.pos) < 180.0) and (best.is_empty() or p.distance_to(k.pos) < p.distance_to(best.pos)):
					best = k
			if not best.is_empty():
				return best.pos
		if want != "":
			var n := _nearest_safe_node(p, want)
			if not n.is_empty():
				return n.pos + (Vector2(34, 0) if want == "wood" else Vector2(-34, 0))
	return p if _inside(p) else Vector2(p.x, FENCE_Y + 90.0)


## Where to stand for a spot: pads in the fence line are worked from the inside.
func _stand(at: Vector2) -> Vector2:
	if absf(at.y - (FENCE_Y + FENCE_H * 0.5)) < 30.0:
		return at + Vector2(0, 40)
	return at


## Does the pad still need something from the stack (not coins)?
func _stack_needed_by(pad: Dictionary) -> bool:
	for kind in pad.cost:
		if kind != "coin" and _remaining(pad, kind) > _count(kind):
			return true
	return false


## Gathering means going out: not while monsters wait all along the fence, unless your bag is well stocked.
func _outside_ok() -> bool:
	return bag >= 20 or _safe(Vector2(_crossing_x(player.pos, Vector2(player.pos.x, FENCE_Y - 200.0)), FENCE_Y - 20.0))


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
			if p.distance_to(POWER_BTN) <= POWER_R + 10.0:
				power_menu = power >= POWER_MAX and not power_menu
				return
			if power_menu:
				for k in POWERS.size():
					if p.distance_to(_power_button(k)) <= 30.0:
						activate_power(POWERS[k].id)
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

func _uid() -> int:
	next_uid += 1
	return next_uid


func _fly(from: Vector2, to: Vector2, kind: String) -> void:
	fx.append({"uid": _uid(), "from": from, "to": to, "t": 0.0, "dur": 0.22, "kind": kind})


func _text(s: String, centre: Vector2, size: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, centre + Vector2(-w * 0.5, size * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _item(pos: Vector2, kind: String, s: float) -> void:
	var c: Color = ITEM_COLOR[kind]
	if kind == "coin":
		draw_circle(pos, s * 0.9, c)
		draw_circle(pos, s * 0.9, c.darkened(0.45), false, 2.0)
		draw_circle(pos, s * 0.35, c.lightened(0.4))
		return
	draw_rect(Rect2(pos - Vector2(s, s * 0.8), Vector2(s * 2, s * 1.6)), c)
	draw_rect(Rect2(pos - Vector2(s, s * 0.8), Vector2(s * 2, s * 1.6)), c.darkened(0.45), false, 2.0)


func _draw() -> void:
	_draw_overlay()


## The screen-space layer drawn over either view: top bar, joystick, end panel.
func _draw_overlay() -> void:
	_draw_hud()
	if joy_active:
		draw_circle(joy_origin, 70.0, Color(1, 1, 1, 0.12))
		draw_circle(joy_origin + joy_vec * 70.0, 28.0, Color(1, 1, 1, 0.35))
	if state != "play":
		_draw_end()














func _draw_hud() -> void:
	var dark := Color(0.09, 0.07, 0.14, 0.62)
	# wave
	_panel(Rect2(16, 16, 196, 62), dark)
	_otext("WAVE %d/%d" % [wave, WAVES], Vector2(114, 38), 26, Color.WHITE)
	if not spawn_queue.is_empty():
		_otext("INCOMING %d" % spawn_queue.size(), Vector2(114, 64), 17, Color("#ff8a7a"))
	elif wave < WAVES:
		_otext("NEXT IN %ds" % int(ceil(wave_t)), Vector2(114, 64), 17, Color("#d6d0e6"))
	# fence: how many monsters it can hold before it gives
	var waiting := _waiting()
	var gw := 196.0
	_panel(Rect2(SW * 0.5 - gw * 0.5 - 12, 16, gw + 24, 62), dark)
	_otext("FENCE", Vector2(SW * 0.5, 32), 15, Color("#d6d0e6"))
	var pw := gw / fence_max
	for i in fence_max:
		var r := Rect2(SW * 0.5 - gw * 0.5 + i * pw + 1.5, 46, pw - 3.0, 20)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(4)
		sb.bg_color = Color("#ff5a4e") if i < waiting else Color("#5b5670")
		if i < waiting and waiting >= fence_max - 2:
			sb.bg_color = sb.bg_color.lightened(0.25 * (0.5 + 0.5 * sin(time * 10.0)))
		draw_style_box(sb, r)
	# hearts and coins
	for i in HEARTS:
		var c := Color("#ff5a64") if i < hearts else Color(0.25, 0.2, 0.3, 0.8)
		var hp := Vector2(SW * 0.5 + 146 + i * 23, 30)
		_heart(hp, c)
	_panel(Rect2(SW * 0.5 + 138, 48, 128, 32), dark)
	draw_circle(Vector2(SW * 0.5 + 158, 64), 10.0, Color("#ffc23a"))
	draw_circle(Vector2(SW * 0.5 + 158, 64), 5.5, Color("#ffe08a"))
	_otext("%d" % wallet, Vector2(SW * 0.5 + 210, 64), 22, Color.WHITE)
	_draw_power()


func _panel(r: Rect2, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(minf(r.size.y * 0.5, 20.0)))
	draw_style_box(sb, r)


func _otext(s: String, centre: Vector2, size: int, col: Color) -> void:
	var f: Font = hud_font if hud_font else font
	var tw := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := centre + Vector2(-tw * 0.5, size * 0.36)
	draw_string_outline(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color("#241d2c"))
	draw_string(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _heart(hp: Vector2, c: Color) -> void:
	draw_circle(hp + Vector2(-5, -2), 6.5, Color("#241d2c"))
	draw_circle(hp + Vector2(5, -2), 6.5, Color("#241d2c"))
	draw_colored_polygon(PackedVector2Array([hp + Vector2(-11.5, 0), hp + Vector2(11.5, 0), hp + Vector2(0, 13)]), Color("#241d2c"))
	draw_circle(hp + Vector2(-4.5, -2), 5.0, c)
	draw_circle(hp + Vector2(4.5, -2), 5.0, c)
	draw_colored_polygon(PackedVector2Array([hp + Vector2(-9.3, 0), hp + Vector2(9.3, 0), hp + Vector2(0, 10.5)]), c)
	draw_circle(hp + Vector2(-5, -3.5), 1.8, Color(1, 1, 1, 0.6))


## The power meter: fills with every monster coin; full, it pulses and a tap fires it.
func _draw_power() -> void:
	var c := POWER_BTN
	var full := power >= POWER_MAX
	var active := power_t > 0.0
	var pulse := 0.5 + 0.5 * sin(time * 7.0)
	var gold := Color("#ffc23a")
	if full and not active:  # ready: a pulsing halo
		draw_circle(c, POWER_R + 8.0 + pulse * 5.0, Color(1.0, 0.76, 0.23, 0.25))
	draw_circle(c, POWER_R + 4.0, Color("#241d2c"))
	draw_circle(c, POWER_R, Color("#3a3150"))
	var frac := power_t / POWER_TIME if active else float(power) / POWER_MAX
	var col := Color("#7af1eb") if active else gold
	if frac > 0.0:
		draw_arc(c, POWER_R - 5.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, col, 9.0)
	if full and not active:
		draw_circle(c, POWER_R - 10.0, gold.lerp(Color.WHITE, 0.2 * pulse))
	var bolt := PackedVector2Array([c + Vector2(3, -15), c + Vector2(-8, 2), c + Vector2(-1, 2), c + Vector2(-4, 15),
		c + Vector2(8, -3), c + Vector2(1, -3)])
	draw_colored_polygon(bolt, Color("#241d2c") if full and not active else (col if active else Color("#8a83a0")))
	if full and not active:
		_otext("TAP!", c + Vector2(0, POWER_R + 18), 18, gold)
	if freeze_t > 0.0:
		draw_arc(c, POWER_R + 8.0, -PI * 0.5, -PI * 0.5 + TAU * freeze_t / FREEZE_TIME, 40, Color("#9fd3ff"), 4.0)
	if power_menu:
		for k in POWERS.size():
			var b := _power_button(k)
			var pc: Color = POWERS[k].color
			draw_circle(b, 31.0, Color("#241d2c"))
			draw_circle(b, 28.0, Color("#3a3150"))
			draw_arc(b, 28.0, 0, TAU, 32, pc, 3.0)
			_power_icon(POWERS[k].id, b, pc)
			_panel(Rect2(b + Vector2(-122, -16), Vector2(82, 32)), Color(0.09, 0.07, 0.14, 0.7))
			_otext(POWERS[k].label, b + Vector2(-81, 0), 18, pc)


func _power_icon(id: String, c: Vector2, col: Color) -> void:
	match id:
		"rapid":
			draw_colored_polygon(PackedVector2Array([c + Vector2(3, -13), c + Vector2(-7, 2), c + Vector2(-1, 2), c + Vector2(-3, 13),
				c + Vector2(7, -3), c + Vector2(1, -3)]), col)
		"freeze":
			for k in 3:
				var a := PI * k / 3.0
				draw_line(c - Vector2(cos(a), sin(a)) * 12.0, c + Vector2(cos(a), sin(a)) * 12.0, col, 3.0)
		"bomb":
			draw_circle(c + Vector2(0, 3), 10.0, col)
			draw_line(c + Vector2(4, -6), c + Vector2(9, -13), col, 3.0)
		"supply":
			_item(c + Vector2(-6, 4), "ammo", 7)
			_item(c + Vector2(6, -2), "ammo", 7)


func _draw_end() -> void:
	draw_rect(Rect2(0, 0, SW, SH), Color(0.05, 0.03, 0.1, 0.55))
	var won := state == "won"
	var r := Rect2(70, 420, SW - 140, 360)
	_panel(Rect2(r.position + Vector2(0, 8), r.size), Color("#241d2c"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#3a3150")
	sb.set_corner_radius_all(26)
	sb.border_color = Color("#7af1eb") if won else Color("#ff6b5e")
	sb.set_border_width_all(5)
	draw_style_box(sb, r)
	_otext("FORTRESS HOLDS" if won else "FORTRESS FELL", Vector2(SW * 0.5, 490), 48, Color.WHITE)
	if not won:
		_otext(lose_reason.to_upper(), Vector2(SW * 0.5, 545), 24, Color("#ff9a8f"))
	_otext("WAVES SURVIVED  %d / %d" % [wave if won else wave - 1, WAVES], Vector2(SW * 0.5, 610), 26, Color("#f2e4cb"))
	_otext("MONSTERS STOPPED  %d" % kills, Vector2(SW * 0.5, 650), 26, Color("#f2e4cb"))
	_otext("TAP TO PLAY AGAIN", Vector2(SW * 0.5, 725), 28, Color("#ffc23a"))


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
