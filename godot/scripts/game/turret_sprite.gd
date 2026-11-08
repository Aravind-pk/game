class_name TurretSprite
extends UnitView
## A turret drawn from a sprite kit: 14 aim directions, a muzzle flash and destruction.

const ATLAS_PX_PER_M := 47.7       # the base is about 2.6 m across
const PAN_FRAME_MS := 30.0         # time on each aim direction while swinging round
const FLASH_MS := 70.0             # how long the muzzle flash shows
const KICK_MS := 140.0             # how long the barrel takes to settle after a shot
const KICK_PX := 3.5
const FLASH_LENGTH_PX := 40.0
const FLASH_WIDTH_PX := 22.0
const DOT_SIZE := 64.0             # size of the soft dot the flash is made from
const DESTROY_FRAME_MS := 95.0
const REST_AIM := 7                # faces north, toward the threat, until it has a target

# The direction each aim frame's barrel points on screen, in degrees, with 0 facing east.
const AIM_DEGREES: Array[float] = [90.0, 59.0, 45.0, -1.0, -4.0, -33.0, -64.0, -90.0, -120.0, -145.0, -169.0, 178.0, 161.0, 140.0]
# The centre of the barrel's end in each aim frame, in atlas pixels from the turret's ground point.
const MUZZLE_PX: Array[Vector2] = [
	Vector2(0, -44), Vector2(11, -42), Vector2(23, -37), Vector2(45, -61), Vector2(52, -64),
	Vector2(34, -82), Vector2(17, -95), Vector2(-2, -96), Vector2(-20, -94), Vector2(-34, -84),
	Vector2(-46, -69), Vector2(-53, -58), Vector2(-43, -45), Vector2(-31, -34),
]
const LAST_DESTROY_FRAME := 11

var _anims: Dictionary
var _sprite: Sprite2D
var _flash: Sprite2D
var _aim := REST_AIM
var _pan_ms := 0.0
var _shot_ms := -1.0
var _destroy_ms := -1.0
var _destroy_flip := false


func setup(kit_name: String, flash_texture: Texture2D, flash_material: Material) -> void:
	var kit := SpriteKits.get_kit("turrets", kit_name)
	_anims = kit.anims
	_sprite = Sprite2D.new()
	_sprite.texture = kit.texture
	_sprite.region_enabled = true
	_sprite.centered = false
	_sprite.scale = Vector2.ONE * _art_scale()
	add_child(_sprite)
	_flash = Sprite2D.new()
	_flash.texture = flash_texture
	_flash.material = flash_material
	_flash.modulate = Color("#ffd27a")
	_flash.visible = false
	add_child(_flash)
	_show("aim", _aim, false)


## `aim_angle` is the direction to the target as it appears on screen.
func update_turret(has_target: bool, aim_angle: float, dt: float) -> void:
	if _destroy_ms >= 0.0:
		_destroy_ms += dt * 1000.0
		_show("destroy", mini(int(_destroy_ms / DESTROY_FRAME_MS), LAST_DESTROY_FRAME), _destroy_flip)
		return
	if has_target:
		_pan_toward(aim_angle, dt)
	_show("aim", _aim, false)
	_update_shot(dt)


func _update_shot(dt: float) -> void:
	if _shot_ms < 0.0:
		return
	_shot_ms += dt * 1000.0
	if _shot_ms >= KICK_MS:
		_shot_ms = -1.0
		_sprite.position = Vector2.ZERO
		_flash.visible = false
		return
	var barrel := _barrel_direction()
	_sprite.position = -barrel * KICK_PX * (1.0 - _shot_ms / KICK_MS)
	_flash.visible = _shot_ms < FLASH_MS
	# The flash starts at the muzzle and points the way the barrel does.
	_flash.rotation = barrel.angle()
	_flash.position = muzzle_offset() + barrel * FLASH_LENGTH_PX * 0.35


func fired() -> void:
	if _destroy_ms < 0.0:
		_shot_ms = 0.0
		_flash.scale = Vector2(FLASH_LENGTH_PX, FLASH_WIDTH_PX) * randf_range(0.85, 1.15) / DOT_SIZE


func muzzle_offset() -> Vector2:
	return MUZZLE_PX[_aim] * _art_scale()


func _barrel_direction() -> Vector2:
	return Vector2.from_angle(deg_to_rad(AIM_DEGREES[_aim]))


func _art_scale() -> float:
	return PX_PER_M / ATLAS_PX_PER_M


func destroyed() -> void:
	_destroy_ms = 0.0
	_shot_ms = -1.0
	_sprite.position = Vector2.ZERO
	_flash.visible = false
	# The destruction art points east, so mirror it for a turret aimed west.
	_destroy_flip = cos(deg_to_rad(AIM_DEGREES[_aim])) < 0.0
	if bar:
		bar.visible = false


func tint(color: Color) -> void:
	_sprite.modulate = color


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
