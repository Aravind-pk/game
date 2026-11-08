class_name ShadowSprite
extends RefCounted
## The soft ground shadow every unit shares.

const SIZE := 128

static var _texture: Texture2D


static func texture() -> Texture2D:
	if _texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
		gradient.colors = PackedColorArray([Color(0.06, 0.05, 0.03, 0.8), Color(0.06, 0.05, 0.03, 0.58), Color(0.06, 0.05, 0.03, 0.0)])
		var radial := GradientTexture2D.new()
		radial.gradient = gradient
		radial.width = SIZE
		radial.height = SIZE
		radial.fill = GradientTexture2D.FILL_RADIAL
		radial.fill_from = Vector2(0.5, 0.5)
		radial.fill_to = Vector2(1.0, 0.5)
		_texture = radial
	return _texture
