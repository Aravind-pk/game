class_name TurretSprite
extends UnitView
## A turret drawn from a sprite kit: 14 aim directions, muzzle flash, recoil and destruction.

const ATLAS_PX_PER_M := 47.7       # the base is about 2.6 m across
const PAN_FRAME_MS := 45.0         # time on each aim direction while swinging round
const FIRE_MS := 70.0              # how long the muzzle flash shows
const RECOIL_MS := 90.0
const DESTROY_FRAME_MS := 95.0
const REST_AIM := 7                # faces north, toward the threat, until it has a target

# Angle each aim frame shows, in degrees, clockwise on screen with 0 facing east.
const AIM_DEGREES: Array[float] = [90.0, 62.0, 38.0, 12.0, -8.0, -35.0, -65.0, -90.0, -115.0, -145.0, -172.0, 168.0, 142.0, 118.0]
const LAST_DESTROY_FRAME := 11

var _anims: Dictionary
var _sprite: Sprite2D
var _aim := REST_AIM
var _pan_ms := 0.0
var _shot_ms := -1.0
var _destroy_ms := -1.0
var _destroy_flip := false


func setup(kit_name: String) -> void:
	var kit := SpriteKits.get_kit("turrets", kit_name)
	_anims = kit.anims
	_sprite = Sprite2D.new()
	_sprite.texture = kit.texture
	_sprite.region_enabled = true
	_sprite.centered = false
	_sprite.scale = Vector2.ONE * PX_PER_M / ATLAS_PX_PER_M
	add_child(_sprite)
	_show("aim", _aim, false)


func update_turret(has_target: bool, aim_angle: float, dt: float) -> void:
	if _destroy_ms >= 0.0:
		_destroy_ms += dt * 1000.0
		_show("destroy", mini(int(_destroy_ms / DESTROY_FRAME_MS), LAST_DESTROY_FRAME), _destroy_flip)
		return
	if has_target:
		_pan_toward(aim_angle, dt)
	if _shot_ms >= 0.0:
		_shot_ms += dt * 1000.0
		if _shot_ms < FIRE_MS:
			_show("fire", _aim, false)
			return
		if _shot_ms < FIRE_MS + RECOIL_MS:
			_show("recoil", _aim, false)
			return
		_shot_ms = -1.0
	_show("aim", _aim, false)


func fired() -> void:
	if _destroy_ms < 0.0:
		_shot_ms = 0.0


func destroyed() -> void:
	_destroy_ms = 0.0
	# The destruction art points east, so mirror it for a turret aimed west.
	_destroy_flip = cos(deg_to_rad(AIM_DEGREES[_aim])) < 0.0
	if bar:
		bar.visible = false


## Swings one aim frame at a time, so the barrel never snaps across.
func _pan_toward(angle: float, dt: float) -> void:
	var goal := _nearest_aim(angle)
	if goal == _aim:
		_pan_ms = 0.0
		return
	_pan_ms += dt * 1000.0
	var count := AIM_DEGREES.size()
	while _pan_ms >= PAN_FRAME_MS and _aim != goal:
		_pan_ms -= PAN_FRAME_MS
		var way := 1 if posmod(goal - _aim, count) <= count / 2 else -1
		_aim = posmod(_aim + way, count)


func _nearest_aim(angle: float) -> int:
	var best := 0
	for i in AIM_DEGREES.size():
		if absf(angle_difference(deg_to_rad(AIM_DEGREES[i]), angle)) < absf(angle_difference(deg_to_rad(AIM_DEGREES[best]), angle)):
			best = i
	return best


func _show(anim: String, index: int, flip: bool) -> void:
	var f: Dictionary = _anims[anim].frames[index]
	var w := float(f.w)
	_sprite.region_rect = Rect2(float(f.x), float(f.y), w, float(f.h))
	_sprite.flip_h = flip
	_sprite.offset = Vector2(-(w - float(f.ax)) if flip else -float(f.ax), -float(f.ay))
