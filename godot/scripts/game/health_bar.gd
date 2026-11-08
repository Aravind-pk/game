class_name HealthBar
extends Node2D

const HEIGHT_PX := 7.0
const BORDER_PX := 2.0

var _width := 48.0
var _color := Color.WHITE
var _fraction := 1.0


func setup(width_px: float, color: Color) -> void:
	_width = width_px
	_color = color
	z_index = 20


func set_fraction(value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	if clamped != _fraction:
		_fraction = clamped
		queue_redraw()


func _draw() -> void:
	var outer := Rect2(-_width * 0.5, -HEIGHT_PX * 0.5, _width, HEIGHT_PX)
	draw_rect(outer, Color(0.05, 0.06, 0.08, 0.85))
	var inner := outer.grow(-BORDER_PX * 0.5)
	inner.size.x *= _fraction
	draw_rect(inner, _color)
