class_name RadarView
extends Control
## Enemy Spawn Radar (design system "Radar"): the whole simulated world, the camera's
## playable rectangle, the gate and red hotspots with counts. Informational only — no rings,
## sweeps or trajectories.

var level: LevelData
var deployment: Array = []


func set_level(lv: LevelData, dep: Array = []) -> void:
	level = lv
	deployment = dep
	queue_redraw()


func _draw() -> void:
	if level == null:
		return
	var k := minf(size.x / level.cols, size.y / level.rows)
	var map_size := Vector2(level.cols, level.rows) * k
	var o := (size - map_size) * 0.5
	var cell := func(c: Vector2) -> Vector2: return o + c * k
	var r := UiKit.px(12)
	draw_style_box(UiKit.box(UiKit.TERRAIN_DEEP, 12, UiKit.LINE, 1, 0), Rect2(o, map_size))
	var vr := level.view_rect
	var view := Rect2(cell.call(Vector2(vr.position)), Vector2(vr.size) * k)
	draw_rect(view, Color(UiKit.FRIENDLY_SOFT, 0.55))
	draw_rect(view, UiKit.FRIENDLY, false, 3.0)
	for ob in level.obstacles:
		draw_rect(Rect2(cell.call(Vector2(ob.position)), Vector2(ob.size) * k), Color(UiKit.METAL, 0.5))
	var g0: Vector2 = cell.call(Vector2(level.gate_cols.x, level.wall_row))
	draw_rect(Rect2(cell.call(Vector2(0, level.wall_row)), Vector2(level.cols, 1) * k), UiKit.STRUCTURE)
	draw_rect(Rect2(g0, Vector2(level.gate_cols.y - level.gate_cols.x + 1, 1) * k), UiKit.AMBER)
	for d in deployment:
		draw_circle(cell.call(Vector2(d.cell) + Vector2(0.5, 0.5)), k * 0.35, UiKit.FRIENDLY)
	var font := UiKit.font("sans_bold")
	var fs := UiKit.px(11)
	for h in level.hotspots:
		var p: Vector2 = cell.call(h.cell + Vector2(0.5, 0.5))
		var n := level.hotspot_count(h)
		var rad := k * (0.55 + minf(n, 20) * 0.04)
		draw_circle(p, rad * 2.2, Color(UiKit.THREAT, 0.22))
		draw_circle(p, rad, UiKit.THREAT)
		var txt := str(n)
		var right := p.x > o.x + map_size.x * 0.8
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tx := p.x - rad * 2.2 - 6.0 - tw if right else p.x + rad * 2.2 + 6.0
		draw_string(font, Vector2(tx, p.y + fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.INK)
