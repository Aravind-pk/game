class_name ReconTimeline
extends Control
## Recon timeline: for each hotspot, when its monsters surface (bar) and when the first of them
## reaches the gate if nothing stops it (tick). Times come straight from the level data.

const ROW_PT := 22.0
const LABEL_PT := 70.0

var _rows: Array = []   # [{label, start, end, eta, heavy}]
var _span := 60.0


func set_level(lv: LevelData, dep: Array) -> void:
	_rows.clear()
	var routes := RadarView.routes_of(lv, dep)
	for i in lv.hotspots.size():
		var h: Dictionary = lv.hotspots[i]
		var start: float = float(h.delay) + Defs.EMERGE_WARN
		var t := start
		var slowest := 99.0
		var heavy := false
		for g in h.groups:
			t += float(g.interval) * float(int(g.count) - 1)
			slowest = minf(slowest, float(Defs.MONSTERS[g.type].speed))
			heavy = heavy or g.type == "brute"
		var length := 0.0
		var pts: PackedVector2Array = routes[i].points
		for k in pts.size() - 1:
			length += pts[k].distance_to(pts[k + 1])
		var eta := start + Defs.EMERGE_TIME + length / slowest
		_rows.append({"label": "%s · %d" % [_short(str(h.name)), lv.hotspot_count(h)], "start": start, "end": t, "eta": eta, "heavy": heavy})
	_span = 20.0
	for r in _rows:
		_span = maxf(_span, ceilf(maxf(r.end, r.eta) / 20.0 + 0.25) * 20.0)
	custom_minimum_size.y = UiKit.px(16 + ROW_PT * _rows.size())
	queue_redraw()


static func _short(name: String) -> String:
	var map := {"North": "N", "South": "S", "East": "E", "West": "W", "Northeast": "NE", "Northwest": "NW", "Southeast": "SE", "Southwest": "SW"}
	return map.get(name, name.left(3).to_upper())


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var font := UiKit.font("cond")
	var fs := UiKit.px(11)
	var x0 := float(UiKit.px(LABEL_PT))
	var w := size.x - x0 - UiKit.px(30)
	var tx := func(t: float) -> float: return x0 + w * t / _span
	for k in int(_span / 20.0) + 1:
		var t := k * 20.0
		var txt := "%d:%02d" % [int(t) / 60, int(t) % 60]
		draw_string(font, Vector2(tx.call(t) - UiKit.px(8), fs), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.INK_MUTED)
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		var y := UiKit.px(16 + ROW_PT * i + ROW_PT * 0.5)
		draw_string(font, Vector2(0, y + fs * 0.35), r.label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.px(12), UiKit.INK)
		draw_line(Vector2(x0, y), Vector2(x0 + w, y), UiKit.STRUCTURE, UiKit.px(0.8))
		var col := Color("#ffcb5e") if r.heavy else UiKit.THREAT
		draw_rect(Rect2(tx.call(r.start), y - UiKit.px(4), maxf(tx.call(r.end) - tx.call(r.start), UiKit.px(3)), UiKit.px(8)), col)
		var e: float = tx.call(r.eta)
		draw_rect(Rect2(e - UiKit.px(1), y - UiKit.px(8), UiKit.px(2.4), UiKit.px(16)), UiKit.INK)
		var lbl := "~%d:%02d" % [int(r.eta) / 60, int(r.eta) % 60]
		draw_string(font, Vector2(e + UiKit.px(4), y + fs * 0.35), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.INK)
