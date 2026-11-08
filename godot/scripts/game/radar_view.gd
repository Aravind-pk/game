class_name RadarView
extends Control
## Enemy Spawn Radar: a schematic of the whole simulated world on a camouflage field, with the
## camera's playable rectangle, the gate and red hotspots. The map stretches to fill its frame.
## `compact` is the small briefing preview: dots only, no hotspot labels.

const CAMO_W := 150
const CAMO_H := 150

static var _camo_by_seed := {}

var level: LevelData
var deployment: Array = []
var compact := false


func set_level(lv: LevelData, dep: Array = []) -> void:
	level = lv
	deployment = dep
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


static func _camo(level_seed: int) -> Texture2D:
	if _camo_by_seed.has(level_seed):
		return _camo_by_seed[level_seed]
	var n := FastNoiseLite.new()
	n.seed = level_seed * 37 + 11
	n.frequency = 0.022
	n.fractal_octaves = 3
	var img := Image.create(CAMO_W, CAMO_H, false, Image.FORMAT_RGB8)
	for y in CAMO_H:
		for x in CAMO_W:
			img.set_pixel(x, y, UiKit.CAMO_LIGHT if n.get_noise_2d(x, y) > 0.12 else UiKit.CAMO_DARK)
	var tex := ImageTexture.create_from_image(img)
	_camo_by_seed[level_seed] = tex
	return tex


func _draw() -> void:
	if level == null:
		return
	draw_texture_rect(_camo(int(level.id)), Rect2(Vector2.ZERO, size), false)
	var k := Vector2(size.x / level.cols, size.y / level.rows)
	var cell := func(c: Vector2) -> Vector2: return c * k

	for ob in level.obstacles:
		draw_rect(Rect2(cell.call(Vector2(ob.position)), Vector2(ob.size) * k), Color("#8b8c72"))

	var vr := level.view_rect
	var view := Rect2(cell.call(Vector2(vr.position)), Vector2(vr.size) * k)
	draw_rect(view, Color(0, 0, 0, 0.32))
	draw_rect(view, UiKit.LINE, false, 2.0)

	_draw_gate(cell)
	if not compact:
		_label_centered("CAMERA AREA", view.get_center() + Vector2(0, -UiKit.px(8)), UiKit.px(14), UiKit.INK)

	for d in deployment:
		draw_circle(cell.call(Vector2(d.cell) + Vector2(0.5, 0.5)), UiKit.px(2.4), UiKit.FRIENDLY)
	for h in level.hotspots:
		_draw_hotspot(h, cell.call(h.cell + Vector2(0.5, 0.5)))
	draw_rect(Rect2(Vector2.ZERO, size), UiKit.LINE, false, 2.0)


func _draw_gate(cell: Callable) -> void:
	var wall_y: float = cell.call(Vector2(0, level.wall_row)).y
	var strip := Rect2(0, wall_y, size.x, size.y - wall_y)
	draw_rect(strip, Color("#cfc7b4"))
	var a: float = cell.call(Vector2(level.gate_cols.x, 0)).x
	var b: float = cell.call(Vector2(level.gate_cols.y + 1, 0)).x
	var rise := UiKit.px(7.0 if compact else 11.0)
	draw_rect(Rect2(a, wall_y - rise, b - a, strip.size.y + rise), Color("#cfc7b4"))
	draw_rect(Rect2(a - UiKit.px(5), wall_y - rise * 0.55, b - a + UiKit.px(10), rise * 0.55), Color("#aaa492"))
	_label_centered("GATE", Vector2((a + b) * 0.5, size.y - maxf(strip.size.y, UiKit.px(4)) * 0.5 - rise * 0.35),
		UiKit.px(10 if compact else 12), UiKit.BG)


func _draw_hotspot(h: Dictionary, p: Vector2) -> void:
	var r := UiKit.px(3.2 if compact else 4.5)
	draw_circle(p, r * 1.7, Color(UiKit.THREAT, 0.3))
	draw_circle(p, r, UiKit.THREAT)
	if compact:
		return
	var font := UiKit.font("cond")
	var fs := UiKit.px(14)
	var txt := "%s · %d" % [str(h.name).to_upper(), level.hotspot_count(h)]
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var chip := Vector2(tw + UiKit.px(14), UiKit.px(21))
	var pos := p + Vector2(-chip.x * 0.5, r + UiKit.px(6))
	pos.x = clampf(pos.x, UiKit.px(5), size.x - chip.x - UiKit.px(5))
	draw_style_box(UiKit.box(UiKit.PANEL, 2, UiKit.LINE, 1), Rect2(pos, chip))
	draw_string(font, pos + Vector2(UiKit.px(7), chip.y * 0.5 + fs * 0.33), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.INK)


func _label_centered(txt: String, centre: Vector2, fs: int, col: Color) -> void:
	var font := UiKit.font("cond")
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, centre + Vector2(-tw * 0.5, fs * 0.33), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
