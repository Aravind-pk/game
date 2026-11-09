class_name MonsterSprite
extends UnitView
## A monster drawn from a full sprite kit.
## View only. It reads the simulation and never changes it, so battles stay deterministic.
##
## The simulation walks a grid flow field, which turns sharply. The sprite trails its
## simulated position slightly, which rounds those corners into curves.

const ATLAS_PX_PER_M := 60.0      # atlas pixels per metre of game world
const FOLLOW_TIME := 0.28         # how far (seconds) the sprite trails the simulation
const STRIDE_M := 1.25            # ground covered by one 8-frame walk cycle
const MOVE_EPS := 0.06            # closer than this to the simulated position counts as standing
const TURN_FRAME_MS := 55.0       # time on each in-between facing
const CORPSE_SECONDS := 1.2
const FADE_SECONDS := 0.5
const FLASH_SECONDS := 0.13
const SHADOW_HEIGHT := 0.3        # on-screen ellipse height as a share of its width
const SHADOW_EASE := 12.0         # how quickly the shadow width follows a change of facing
const LUNGE_EASE := 24.0
const LUNGE_BACK_M := -0.12
const LUNGE_STRIKE_M := 0.26

const SOUTH := PI / 2.0           # toward the gate and the camera
const SLICE := PI / 8.0
const TURN_TRIGGER := SLICE * 0.8 # how far off its facing a monster may walk before turning

# 16 facings. Each names the atlas row that shows it, and whether to mirror it.
# The new kit has a true north walk and a separate sixteen-pose turntable.
# Eight authored walk facings; intermediate headings use the nearest walk.
const DIRS := {
	"E": ["walk_E", false], "ESE": ["walk_E", false], "SE": ["walk_SW", true], "SSE": ["walk_S", false],
	"S": ["walk_S", false], "SSW": ["walk_S", false], "SW": ["walk_SW", false], "WSW": ["walk_E", true],
	"W": ["walk_E", true], "WNW": ["walk_E", true], "NW": ["walk_NE", true], "NNW": ["walk_N", false],
	"N": ["walk_N", false], "NNE": ["walk_N", false], "NE": ["walk_NE", false], "ENE": ["walk_E", false],
}
const DIR_ORDER: Array[String] = ["E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW", "N", "NNE", "NE", "ENE"]
# Facings drawn in the same sheet match closely enough to swap directly mid-stride.
const FRONT_ART: Array[String] = ["ESE", "SE", "SSE", "S", "SSW", "SW", "WSW"]

# Milliseconds per frame. The strike frames are short so the hit snaps.
const FRAME_MS := {
	"emerge": [130, 100, 90, 80, 80, 60, 60, 70, 90, 100, 110, 130],
	"attack": [110, 130, 170, 45, 85, 130],
	"death": [70, 70, 80, 90, 100, 110, 120, 130, 150, 180],
}
const ATTACK_IMPACT_MS := 410.0   # the strike lands this far into the attack frames
const ATTACK_TOTAL_MS := 670.0

var _anims: Dictionary
var _wheel: Array
var _sprite: Sprite2D
var _shadow: Sprite2D

var _state := "emerge"
var _dir := "S"
var _walk_frame := 0.0
var _turn_ms := 0.0
var _turn_pos := 0
var _turn_goal := 0
var _turn_target := 0.0
var _after_turn := "walk"
var _attack_anim := "attack_S"
var _attack_flip := false
var _aim := SOUTH
var _lunge := 0.0
var _shadow_width := 0.0
var _shadow_target := 0.0
var _death_anim := "death_S"
var _death_flip := false
var _death_time := 0.0
var _speed := 1.0


func setup(kit_name: String, start: Vector2) -> void:
	var kit := SpriteKits.get_kit("monsters", kit_name)
	_anims = kit.anims
	if not kit.has("wheel"):
		kit.wheel = _build_wheel(kit.anims)
	_wheel = kit.wheel
	ground = start
	_shadow = Sprite2D.new()
	_shadow.texture = ShadowSprite.texture()
	_shadow.visible = false
	add_child(_shadow)
	_sprite = Sprite2D.new()
	_sprite.texture = kit.texture
	_sprite.centered = false
	_sprite.region_enabled = true
	_sprite.scale = Vector2.ONE * PX_PER_M / ATLAS_PX_PER_M
	add_child(_sprite)
	_show("emerge", 0, false)


func _ready() -> void:
	set_process(false)  # only the death sequence runs on its own clock


## Call once per rendered frame while the simulation has this monster alive.
func tick(m: Dictionary, sim_pos: Vector2, dt: float) -> void:
	_ease_shadow(dt)
	if m.state == "emerging":
		ground = sim_pos
		var progress := clampf(1.0 - float(m.state_t) / Defs.EMERGE_TIME, 0.0, 1.0)
		_show("emerge", _frame_at("emerge", progress * _total_ms("emerge")), false)
		return
	if _state == "emerge":
		_state = "walk"

	var gap := sim_pos - ground
	var before := ground
	ground += gap * (1.0 - exp(-dt / FOLLOW_TIME))
	if _state == "turn":
		_advance_turn(dt)
		if _state == "turn":
			return
	if m.attacking:
		_update_attack(m, dt)
	elif gap.length() > MOVE_EPS:
		_walk(atan2(gap.y, gap.x), ground.distance_to(before))
	else:
		_settle_lunge(0.0, dt)
		_state = "walk"
		_show_walk()


## Moves the monster directly, for scripted moments such as charging through the breach.
func move_by(step: Vector2, dt: float) -> void:
	_ease_shadow(dt)
	ground += step
	if _state == "turn":
		_advance_turn(dt)
		return
	_walk(atan2(step.y, step.x), step.length())


func die(speed: float) -> void:
	var facing := _facing()
	if absf(angle_difference(facing, SOUTH)) < PI / 4.0:
		_death_anim = "death_S"
		_death_flip = false
	else:
		_death_anim = "death_E"  # this art faces right
		_death_flip = cos(facing) < 0.0
	_state = "dead"
	_speed = maxf(speed, 1.0)
	_death_time = 0.0
	_settle_lunge(0.0, 1.0)
	_sprite.modulate = Color(2.2, 2.2, 2.2)
	_show(_death_anim, 0, _death_flip)
	set_process(true)


func _process(delta: float) -> void:
	_death_time += delta * _speed
	_ease_shadow(delta)
	if _death_time >= FLASH_SECONDS:
		_sprite.modulate = Color.WHITE
	var total := _total_ms("death") / 1000.0
	_show(_death_anim, _frame_at("death", _death_time * 1000.0), _death_flip)
	var fade := (_death_time - total - CORPSE_SECONDS) / FADE_SECONDS
	if fade <= 0.0:
		return
	if fade >= 1.0:
		queue_free()
		return
	_sprite.modulate.a = 1.0 - fade
	_shadow.modulate.a = 1.0 - fade


func _walk(want: float, distance: float) -> void:
	_settle_lunge(0.0, 1.0 / 60.0)
	_state = "walk"
	if absf(angle_difference(_facing(), want)) > TURN_TRIGGER and not _step_facing(want):
		_start_turn(want, "walk")
		return
	_walk_frame = fposmod(_walk_frame + distance * 8.0 / STRIDE_M, 8.0)
	_show_walk()


## On a gentle curve the walk carries on into the neighbouring facing with its stride
## intact. Returns false when the change is too large and needs the turn poses.
func _step_facing(want: float) -> bool:
	var from := DIR_ORDER.find(_dir)
	var to := _nearest_dir(want)
	var apart := mini((to - from + 16) % 16, (from - to + 16) % 16)
	if apart != 1 or FRONT_ART.has(DIR_ORDER[from]) != FRONT_ART.has(DIR_ORDER[to]):
		return false
	_dir = DIR_ORDER[to]
	return true


## Rotates through every in-between pose on the wheel, the short way round,
## so a change of direction never cuts straight from one view to another.
func _start_turn(target: float, next: String) -> void:
	_state = "turn"
	_after_turn = next
	_turn_target = target
	_turn_ms = 0.0
	_turn_pos = _nearest_wheel(_facing())
	_turn_goal = _nearest_wheel(target)
	_show_wheel()


func _advance_turn(dt: float) -> void:
	_turn_ms += dt * 1000.0
	while _turn_ms >= TURN_FRAME_MS and _turn_pos != _turn_goal:
		_turn_ms -= TURN_FRAME_MS
		var way := 1 if angle_difference(_wheel[_turn_pos].a, _turn_target) > 0.0 else -1
		_turn_pos = posmod(_turn_pos + way, _wheel.size())
	_show_wheel()
	if _turn_pos != _turn_goal:
		return
	_dir = DIR_ORDER[_nearest_dir(_turn_target)]
	_state = _after_turn


func _update_attack(m: Dictionary, dt: float) -> void:
	var aim := atan2(float(m.facing.y), float(m.facing.x))
	if _state != "attack":
		_aim = aim
		_choose_attack(aim)
		_start_turn(aim, "attack")
		return
	var interval := 1.0 / float(m.attack_rate)
	var pace := minf(1.0, interval * 1000.0 / ATTACK_TOTAL_MS)
	var wind_up := ATTACK_IMPACT_MS / 1000.0 * pace
	var recover := (ATTACK_TOTAL_MS - ATTACK_IMPACT_MS) / 1000.0 * pace
	# m.cooldown counts down to the next hit, so the strike frame lands exactly on it.
	var to_hit := float(m.cooldown)
	var since_hit := interval - to_hit
	var ms := 0.0
	if to_hit <= wind_up:
		ms = (wind_up - to_hit) / pace * 1000.0
	elif since_hit < recover:
		ms = ATTACK_IMPACT_MS + since_hit / pace * 1000.0
	var frame := _frame_at("attack", ms)
	_show(_attack_anim, frame, _attack_flip)
	var reach := LUNGE_BACK_M if frame == 1 or frame == 2 else LUNGE_STRIKE_M if frame == 3 or frame == 4 else 0.0
	_settle_lunge(reach, dt)


func _choose_attack(aim: float) -> void:
	var off := angle_difference(SOUTH, aim)  # positive toward the west
	if absf(off) < deg_to_rad(22.5):
		_attack_anim = "attack_S"
		_attack_flip = false
	elif absf(off) < deg_to_rad(67.5):
		_attack_anim = "attack_SW"  # this art faces left
		_attack_flip = off < 0.0
	else:
		_attack_anim = "attack_E"  # this art faces right
		_attack_flip = off > 0.0


func _settle_lunge(target: float, dt: float) -> void:
	_lunge += (target - _lunge) * minf(1.0, dt * LUNGE_EASE)
	var offset := Vector2(cos(_aim), sin(_aim) * DEPTH) * _lunge * PX_PER_M
	_sprite.position = offset
	_shadow.position = offset


func _ease_shadow(dt: float) -> void:
	_shadow_width += (_shadow_target - _shadow_width) * minf(1.0, dt * SHADOW_EASE)
	_shadow.visible = _shadow_width > 0.1
	var w := _shadow_width * PX_PER_M / float(ShadowSprite.SIZE)
	_shadow.scale = Vector2(w, w * SHADOW_HEIGHT)


func _facing() -> float:
	return DIR_ORDER.find(_dir) * SLICE


func _nearest_dir(angle: float) -> int:
	return posmod(int(round(angle / SLICE)), 16)


func _nearest_wheel(angle: float) -> int:
	var best := 0
	for i in _wheel.size():
		if absf(angle_difference(_wheel[i].a, angle)) < absf(angle_difference(_wheel[best].a, angle)):
			best = i
	return best


func _show_walk() -> void:
	var row: Array = DIRS[_dir]
	_show(row[0], int(_walk_frame), row[1])


func _show_wheel() -> void:
	_apply(_wheel[_turn_pos].f, _wheel[_turn_pos].flip)


func _show(anim: String, index: int, flip: bool) -> void:
	var frames: Array = _anims[anim].frames
	_apply(frames[mini(index, frames.size() - 1)], flip)


func _apply(f: Dictionary, flip: bool) -> void:
	var w := float(f.w)
	var ax := float(f.ax)
	_sprite.region_rect = Rect2(float(f.x), float(f.y), w, float(f.h))
	_sprite.flip_h = flip
	# Sprite2D mirrors within the frame, so the anchor has to be mirrored too.
	_sprite.offset = Vector2(-(w - ax) if flip else -ax, -float(f.ay))
	_shadow_target = float(f.sh) / ATLAS_PX_PER_M


static func _frame_at(table: String, ms: float) -> int:
	var total := 0.0
	var times: Array = FRAME_MS[table]
	for i in times.size():
		total += float(times[i])
		if ms < total:
			return i
	return times.size() - 1


static func _total_ms(table: String) -> float:
	var total := 0.0
	for t in FRAME_MS[table]:
		total += float(t)
	return total


## Lays the turn strips out around the circle by the angle each pose shows. Clockwise on
## screen from the camera: S to W, W to N, N to E, then S to W mirrored for E to S.
static func _build_wheel(anims: Dictionary) -> Array:
	var wheel: Array = []
	var frames: Array = anims.turntable.frames
	for i in frames.size():
		wheel.append({"f": frames[i], "flip": false, "a": fposmod(PI / 2.0 + i * TAU / frames.size(), TAU)})
	wheel.sort_custom(func(a, b): return a.a < b.a)
	return wheel
