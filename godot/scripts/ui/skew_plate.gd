class_name SkewPlate
extends Container
## LabelPlate background: a parallelogram skewed by plate-skew (-18deg) behind its child.

var fill := Color("#2e3a48")
var pad := Vector2(64, 10)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		for c in get_children():
			if c is Control:
				fit_child_in_rect(c, Rect2(pad, size - pad * 2.0))


func _get_minimum_size() -> Vector2:
	var m := Vector2.ZERO
	for c in get_children():
		if c is Control:
			m = m.max((c as Control).get_combined_minimum_size())
	return m + pad * 2.0


func _draw() -> void:
	var off := size.y * tan(deg_to_rad(18.0)) * 0.5
	var pts := PackedVector2Array([Vector2(off, 0), Vector2(size.x + off, 0),
		Vector2(size.x - off, size.y), Vector2(-off, size.y)])
	draw_colored_polygon(pts, fill)
