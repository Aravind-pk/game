class_name RadarView
extends Control
## Clean top-down information map of the whole battlefield: boundary, normal camera area,
## gate, obstacles and red spawn hotspots with monster counts. Deliberately no rings,
## trajectories or decoration — it is a planning map, not a second battlefield.

var level: LevelData
var deployment: Array = []
var compact := false


func set_level(lv: LevelData, dep: Array = []) -> void:
	level = lv
	deployment = dep
	queue_redraw()


func _draw() -> void:
	if level == null:
		return
	var pad := 10.0
	var avail := size - Vector2(pad, pad) * 2.0
	var k := minf(avail.x / level.cols, avail.y / level.rows)
	var map_size := Vector2(level.cols, level.rows) * k
	var o := (size - map_size) * 0.5
	var cell := func(c: Vector2) -> Vector2: return o + c * k
	# world
	draw_rect(Rect2(o, map_size), Color("#1d2833"))
	# visible / deployable camera area
	var vr := level.view_rect
	draw_rect(Rect2(cell.call(Vector2(vr.position)), Vector2(vr.size) * k), Color("#2f4a3a"))
	draw_rect(Rect2(cell.call(Vector2(vr.position)), Vector2(vr.size) * k), Color("#5ee08a", 0.8), false, 2.0)
	# obstacles
	for r in level.obstacles:
		draw_rect(Rect2(cell.call(Vector2(r.position)), Vector2(r.size) * k), Color("#6b7c8c"))
	# wall + gate
	draw_rect(Rect2(cell.call(Vector2(0, level.wall_row)), Vector2(level.cols, 1) * k), Color("#8a96a5"))
	var g0: Vector2 = cell.call(Vector2(level.gate_cols.x, level.wall_row))
	draw_rect(Rect2(g0, Vector2(level.gate_cols.y - level.gate_cols.x + 1, 1) * k), Color("#f5c56b"))
	# deployed guns
	for d in deployment:
		draw_circle(cell.call(Vector2(d.cell) + Vector2(0.5, 0.5)), k * 0.38, Color("#4fd6e0"))
	# hotspots
	var font := get_theme_default_font()
	for h in level.hotspots:
		var p: Vector2 = cell.call(h.cell + Vector2(0.5, 0.5))
		var n := level.hotspot_count(h)
		draw_circle(p, k * 1.25, Color("#ff6b63", 0.28))
		draw_circle(p, k * 0.6, Color("#ff6b63"))
		if not compact:
			var fs := int(clampf(k * 1.1, 12, 30))
			var txt := "%s  %d" % [h.name, n]
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var tp := p + Vector2(-tw * 0.5, -k * 1.5)
			tp.x = clampf(tp.x, o.x + 2.0, o.x + map_size.x - tw - 2.0)
			draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	draw_rect(Rect2(o, map_size), Color("#9fb0c2"), false, 2.0)
