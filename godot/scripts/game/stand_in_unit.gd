class_name StandInUnit
extends UnitView
## A single piece of artwork standing in for a unit that has no sprite kit yet.

const BOB_PX := 3.0
const BOB_SPEED := 10.0
const FOLLOW_TIME := 0.2
const DEATH_SECONDS := 0.7
const RISE_PX := 50.0

var _sprite: Sprite2D
var _shadow: Sprite2D
var _anchor := Vector2.ZERO
var _phase := 0.0


func setup(texture: Texture2D, width_m: float, start: Vector2) -> void:
	ground = start
	var used := _used_rect(texture)
	var size := used.size
	var factor := width_m * PX_PER_M / float(size.x)
	_shadow = Sprite2D.new()
	_shadow.texture = ShadowSprite.texture()
	var shadow_width := width_m * PX_PER_M * 0.85
	_shadow.scale = Vector2(shadow_width, shadow_width * 0.3) / float(ShadowSprite.SIZE)
	add_child(_shadow)
	_sprite = Sprite2D.new()
	_sprite.texture = texture
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(used)
	_sprite.centered = false
	_sprite.scale = Vector2.ONE * factor
	_anchor = Vector2(-size.x * 0.5, -size.y * 0.94)
	_sprite.offset = _anchor
	add_child(_sprite)


func tick(m: Dictionary, sim_pos: Vector2, dt: float) -> void:
	if m.state == "emerging":
		ground = sim_pos
		var progress := clampf(1.0 - float(m.state_t) / Defs.EMERGE_TIME, 0.0, 1.0)
		_sprite.position.y = (1.0 - progress) * RISE_PX
		_sprite.modulate.a = progress
		_shadow.modulate.a = progress
		return
	_sprite.position.y = 0.0
	_sprite.modulate.a = 1.0
	_shadow.modulate.a = 1.0
	var gap := sim_pos - ground
	ground += gap * (1.0 - exp(-dt / FOLLOW_TIME))
	if abs(float(m.facing.x)) > 0.2:
		_sprite.flip_h = float(m.facing.x) > 0.0
	if gap.length() > 0.06:
		_phase += dt * BOB_SPEED
		_sprite.position.y = -absf(sin(_phase)) * BOB_PX


func move_by(step: Vector2, dt: float) -> void:
	ground += step
	_phase += dt * BOB_SPEED
	_sprite.position.y = -absf(sin(_phase)) * BOB_PX


func die(speed: float) -> void:
	if bar:
		bar.visible = false
	var tween := create_tween().set_parallel(true)
	var time := DEATH_SECONDS / maxf(speed, 1.0)
	tween.tween_property(_sprite, "scale:y", _sprite.scale.y * 0.3, time)
	tween.tween_property(self, "modulate:a", 0.0, time)
	tween.chain().tween_callback(queue_free)


func fired() -> void:
	var tween := create_tween()
	tween.tween_property(_sprite, "position:y", 3.0, 0.04)
	tween.tween_property(_sprite, "position:y", 0.0, 0.14)


func destroyed() -> void:
	_sprite.modulate = Color(0.25, 0.23, 0.22)
	if bar:
		bar.visible = false


static func _used_rect(texture: Texture2D) -> Rect2i:
	var image := texture.get_image()
	if image == null:
		return Rect2i(Vector2i.ZERO, Vector2i(texture.get_size()))
	if image.is_compressed():
		image = image.duplicate()
		image.decompress()
	var used := image.get_used_rect()
	return used if used.has_area() else Rect2i(Vector2i.ZERO, image.get_size())
