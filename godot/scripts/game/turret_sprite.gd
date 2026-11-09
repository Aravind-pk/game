class_name TurretSprite
extends UnitView
## A turret drawn from a sprite kit: 16 aim directions, a muzzle flash and destruction.

const ATLAS_PX_PER_M := 47.7       # the base is about 2.6 m across
const PAN_SPEED := TAU             # radians per second, independent of uneven atlas spacing
const FLASH_MS := 70.0             # how long the muzzle flash shows
const KICK_MS := 140.0             # how long the barrel takes to settle after a shot
const KICK_PX := 1.5
const FLASH_LENGTH_PX := 40.0
const FLASH_WIDTH_PX := 22.0
const DOT_SIZE := 64.0             # size of the soft dot the flash is made from
const DESTROY_FRAME_MS := 95.0
const REST_AIM := 8                # faces north, toward the threat, until it has a target

# The direction each aim frame's barrel points on screen, in degrees, with 0 facing east.
const AIM_DEGREES: Array[float] = [90.0, 57.211, 32.741, 14.914, 0.0, -14.914, -32.741, -57.211, -90.0, -122.789, -147.259, -165.086, -180.0, 165.086, 147.259, 122.789]
# Calibrated muzzle tips in the registered 16-direction atlas.
const MUZZLE_PX: Array[Vector2] = [
	Vector2(0.300, -44.000),
	Vector2(20.400, -48.200),
	Vector2(30.300, -44.900),
	Vector2(40.500, -52.700),
	Vector2(53.400, -70.100),
	Vector2(44.100, -82.100),
	Vector2(31.800, -93.500),
	Vector2(20.400, -101.900),
	Vector2(0.300, -100.700),
	Vector2(-22.500, -99.800),
	Vector2(-31.800, -93.800),
	Vector2(-41.400, -83.300),
	Vector2(-52.500, -72.200),
	Vector2(-41.100, -58.100),
	Vector2(-31.500, -46.700),
	Vector2(-9.000, -43.100),
]
const LAST_DESTROY_FRAME := 11

var _anims: Dictionary
var _base_sprite: Sprite2D
var _sprite: Sprite2D
var _flash: Sprite2D
var _aim := REST_AIM
var _aim_angle := deg_to_rad(AIM_DEGREES[REST_AIM])
var _shot_ms := -1.0
var _destroy_ms := -1.0
var _destroy_flip := false


func setup(kit_name: String, flash_texture: Texture2D, flash_material: Material) -> void:
	var kit := SpriteKits.get_kit("turrets", kit_name)
	_anims = kit.anims
	_base_sprite = Sprite2D.new()
	_base_sprite.texture = kit.texture
	_base_sprite.centered = false
	_base_sprite.region_enabled = true
	_base_sprite.scale = Vector2.ONE * _art_scale()
	var base_frame: Dictionary = _anims.base.frames[0]
	_base_sprite.region_rect = Rect2(base_frame.x, base_frame.y, base_frame.w, base_frame.h)
	_base_sprite.offset = Vector2(-base_frame.ax, -base_frame.ay)
	add_child(_base_sprite)
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
	# Only the rotating head recoils; the bearing and pedestal stay planted.
	var recovery := 1.0 - _shot_ms / KICK_MS
	_sprite.position = -barrel * KICK_PX * recovery * recovery
	_flash.visible = _shot_ms < FLASH_MS
	# The flash starts at the muzzle and points the way the barrel does.
	_flash.rotation = barrel.angle()
	_flash.position = muzzle_offset() + barrel * FLASH_LENGTH_PX * 0.35


func fired() -> void:
	if _destroy_ms < 0.0:
		_shot_ms = 0.0
		_flash.scale = Vector2(FLASH_LENGTH_PX, FLASH_WIDTH_PX) * randf_range(0.85, 1.15) / DOT_SIZE
		_update_shot(0.0)  # show the flash on the firing frame, including low frame rates


func muzzle_offset() -> Vector2:
	return MUZZLE_PX[_aim] * _art_scale() + _sprite.position


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
	_base_sprite.modulate = color


## Turn at a constant angular speed, then select the nearest available pose.
## Counting atlas indices gives unequal speeds and can choose the longer arc.
func _pan_toward(angle: float, dt: float) -> void:
	var delta := angle_difference(_aim_angle, angle)
	_aim_angle = wrapf(_aim_angle + clampf(delta, -PAN_SPEED * dt, PAN_SPEED * dt), -PI, PI)
	_aim = _nearest_aim(_aim_angle)


func _nearest_aim(angle: float) -> int:
	var best := 0
	for i in AIM_DEGREES.size():
		if absf(angle_difference(deg_to_rad(AIM_DEGREES[i]), angle)) < absf(angle_difference(deg_to_rad(AIM_DEGREES[best]), angle)):
			best = i
	return best


func _show(anim: String, index: int, flip: bool) -> void:
	_base_sprite.visible = anim == "aim"
	var f: Dictionary = _anims[anim].frames[index]
	var w := float(f.w)
	_sprite.region_rect = Rect2(float(f.x), float(f.y), w, float(f.h))
	_sprite.flip_h = flip
	_sprite.offset = Vector2(-(w - float(f.ax)) if flip else -float(f.ax), -float(f.ay))
