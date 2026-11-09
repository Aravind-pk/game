class_name HeaderPlate
extends Control
## Dark slanted title plate over the left side of the painted header strip.

const COVER := 0.56  # share of the width the plate covers before the slant


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var slant := size.y * 0.9
	var w := size.x * COVER
	draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0),
		Vector2(w + slant, size.y), Vector2(0, size.y)]), Color("#23272a"))
	draw_line(Vector2(w, 0), Vector2(w + slant, size.y), Color(UiKit.LINE, 0.5), 2.0, true)
