class_name UiKit
extends RefCounted
## North Gate UI kit: dark chamfered field-manual panels, cream type, amber actions, cyan vitals.
## Sizes are points multiplied by S: 390pt phone width -> 1080px canvas.

const S := 2.7

# ---- colour tokens
const BG := Color("#14171a")
const PANEL := Color("#1d2124")
const PANEL_SOLID := Color(0.114, 0.129, 0.141, 0.97)
const PANEL_RAISED := Color("#2a2f33")
const STRUCTURE := Color("#3a4044")
const LINE := Color("#cfc7b4")
const LINE_DIM := Color(0.812, 0.78, 0.706, 0.35)
const INK := Color("#f1e9d6")
const INK_MUTED := Color("#c4bdab")
const AMBER := Color("#e9ae3e")
const AMBER_STRONG := Color("#b98323")
const ON_AMBER := Color("#1c1710")
const THREAT := Color("#e2553f")
const FRIENDLY := Color("#5cdbd8")
const CAMO_DARK := Color("#26292a")
const CAMO_LIGHT := Color("#5b5e46")

const CHAMFER := 7.0
const SLAB_NARROW := 0.86  # horizontal squeeze that gives Rokkitt its condensed poster look
const SLAB_TIGHTEN := 0.07  # letter-spacing reduction, as a share of font size

static var _fonts := {}
static var _icons := {}


static func px(pt: float) -> int:
	return int(round(pt * S))


## size_px only matters for the slab faces, whose letter spacing is tightened per size.
static func font(kind: String, size_px := 0) -> Font:
	var key := "%s:%d" % [kind, size_px] if kind.begins_with("slab") else kind
	if _fonts.has(key):
		return _fonts[key]
	var f: Font
	match kind:
		"slab", "slab_heavy":
			var fv := FontVariation.new()
			fv.base_font = load("res://assets/ui/fonts/Rokkitt-Variable.ttf")
			fv.variation_opentype = {"wght": 900 if kind == "slab_heavy" else 800}
			fv.variation_transform = Transform2D(Vector2(SLAB_NARROW, 0), Vector2(0, 1), Vector2.ZERO)
			# the squeeze narrows the outlines but not their advances, so pull the letters back in
			fv.spacing_glyph = -int(round(size_px * SLAB_TIGHTEN))
			f = fv
		"cond":  # tracked condensed caps for labels
			var fv := FontVariation.new()
			fv.base_font = load("res://assets/ui/fonts/BarlowCondensed-Bold.ttf")
			fv.spacing_glyph = 3
			f = fv
		"sans", "sans_semi", "sans_bold":
			var file: String = {"sans": "Barlow-Medium", "sans_semi": "Barlow-SemiBold", "sans_bold": "Barlow-Bold"}[kind]
			var fv := FontVariation.new()
			fv.base_font = load("res://assets/ui/fonts/%s.ttf" % file)
			fv.opentype_features = {"tnum": 1}  # tabular figures for changing numbers
			f = fv
	_fonts[key] = f
	return f


static func icon(name: String) -> Texture2D:
	if not _icons.has(name):
		_icons[name] = load("res://assets/ui/glyphs/%s.svg" % name)
	return _icons[name]


## style -> [font kind, size pt, upper-case]
const TYPE := {
	"result": ["slab_heavy", 50, true],
	"title": ["slab", 31, true],
	"plate": ["slab", 23, true],
	"button": ["slab", 26, true],
	"counter": ["slab", 21, true],
	"label": ["cond", 16, true],
	"label_lg": ["cond", 18, true],
	"small": ["cond", 12.5, true],
	"body": ["sans", 15, false],
	"caption": ["sans", 12.5, false],
}


static func text(t: String, style: String, color := INK, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	var spec: Array = TYPE[style]
	l.text = t.to_upper() if spec[2] else t
	l.add_theme_font_override("font", font(spec[0], px(spec[1])))
	l.add_theme_font_size_override("font_size", px(spec[1]))
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Chamfered box: corner_detail 1 turns each rounded corner into a straight cut.
static func box(bg: Color, chamfer_pt := CHAMFER, border := LINE, border_pt := 1.0, pad_pt := 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(px(chamfer_pt))
	s.corner_detail = 1
	s.border_color = border
	s.set_border_width_all(maxi(1, px(border_pt)) if border_pt > 0 else 0)
	s.set_content_margin_all(px(pad_pt))
	s.anti_aliasing = true
	return s


static func glyph(name: String, size_pt: float, color := INK) -> TextureRect:
	var t := TextureRect.new()
	t.texture = icon(name)
	t.custom_minimum_size = Vector2.ONE * px(size_pt)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.modulate = color
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


static func image(tex: Texture2D, w_pt: float, h_pt: float, fill := false) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.custom_minimum_size = Vector2(px(w_pt), px(h_pt))
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if fill else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


static func hbox(sep_pt := 8.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", px(sep_pt))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


static func vbox(sep_pt := 8.0) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", px(sep_pt))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func gap(h_pt: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = px(h_pt)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func rule(color := LINE_DIM, w_pt := 0.0, thickness_pt := 0.6) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(px(w_pt), maxi(2, px(thickness_pt)))
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL if w_pt == 0.0 else Control.SIZE_SHRINK_BEGIN
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## The diagonal accent stroke used before headings and counters.
static func slash(color := THREAT, h_pt := 18.0) -> SkewPlate:
	var p := SkewPlate.new()
	p.fill = color
	p.pad = Vector2(px(2.4), px(h_pt * 0.5))
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


# ---------------------------------------------------------------- buttons
static func _button_base(cb: Callable, bg: Color, border: Color, border_pt: float) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	for st in ["normal", "hover", "pressed", "disabled"]:
		var c := bg
		if st == "pressed":
			c = bg.darkened(0.15)
		elif st == "hover":
			c = bg.lightened(0.05)
		b.add_theme_stylebox_override(st, box(c, 8, border, border_pt))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


static func _fill_rect(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	return c


## Full-width action. variant: primary (amber) | secondary (outlined).
## icon_side: "right" for a trailing chevron, "left" for a leading icon, "" for text only.
static func action(label: String, cb: Callable, variant := "primary", icon_name := "chevron", icon_side := "right") -> Button:
	var primary := variant == "primary"
	var b := _button_base(cb, AMBER if primary else PANEL, ON_AMBER if primary else LINE, 1.0)
	if primary:
		for st in ["normal", "hover", "pressed", "disabled"]:
			var sb := b.get_theme_stylebox(st) as StyleBoxFlat
			sb.border_color = AMBER_STRONG
			sb.border_width_bottom = px(2.5)
	b.custom_minimum_size.y = px(50) if primary else px(42)
	var fg := ON_AMBER if primary else INK
	var h := hbox(10)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	_fill_rect(h)
	if icon_name != "" and icon_side == "left":
		h.add_child(glyph(icon_name, 22, fg))
	h.add_child(text(label, "button" if primary else "plate", fg, HORIZONTAL_ALIGNMENT_CENTER))
	if icon_name != "" and icon_side == "right":
		h.add_child(glyph(icon_name, 18, fg))
	b.add_child(h)
	return b


## Small square tool tile: icon over a caption (RADAR / BRIEFING / CLEAR).
static func tool_tile(label: String, cb: Callable, icon_name: String) -> Button:
	var b := _button_base(cb, PANEL, LINE, 1.0)
	b.custom_minimum_size.y = px(30)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := hbox(5)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	_fill_rect(h)
	h.add_child(glyph(icon_name, 15))
	h.add_child(text(label, "small", INK, HORIZONTAL_ALIGNMENT_CENTER))
	b.add_child(h)
	return b


static func icon_button(icon_name: String, cb: Callable, size_pt := 36.0, glyph_pt := 18.0) -> Button:
	var b := _button_base(cb, PANEL_SOLID, LINE, 1.0)
	b.custom_minimum_size = Vector2.ONE * px(size_pt)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_rect(c)
	c.add_child(glyph(icon_name, glyph_pt))
	b.add_child(c)
	return b


# ---------------------------------------------------------------- panels
static func panel(pad_pt := 16.0, sep_pt := 10.0, bg := PANEL_SOLID) -> Array:
	## returns [panel_container, body_vbox]
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(bg, 9, LINE, 1, pad_pt))
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var v := vbox(sep_pt)
	p.add_child(v)
	return [p, v]


## Thin outlined sub-panel inside a panel.
static func inset(pad_h := 10.0, pad_v := 6.0, border := LINE_DIM) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(Color(0, 0, 0, 0.18), 5, border, 1, 0)
	sb.content_margin_left = px(pad_h)
	sb.content_margin_right = px(pad_h)
	sb.content_margin_top = px(pad_v)
	sb.content_margin_bottom = px(pad_v)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Title with a thin ruled subtitle line underneath: THE EASTERN BREACH / -- MISSION BRIEFING ----
static func titled(v: VBoxContainer, title: String, subtitle: String) -> void:
	v.add_child(text(title, "title"))
	var h := hbox(8)
	h.add_child(rule(LINE, 18))
	h.add_child(text(subtitle, "label", INK_MUTED))
	h.add_child(rule(LINE))
	v.add_child(h)


static func section(t: String, color := THREAT, style := "plate") -> HBoxContainer:
	var h := hbox(8)
	h.add_child(slash(color, 15))
	h.add_child(text(t, style))
	return h


# ---------------------------------------------------------------- header + HUD
## Full-width painted strip with the slanted title plate. Returns [root, subtitle_label].
static func header() -> Array:
	var root := Control.new()
	root.custom_minimum_size.y = px(50)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.clip_contents = true
	var bg := TextureRect.new()
	bg.texture = load("res://assets/ui/art/header_skyline.jpg")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_rect(bg)
	root.add_child(bg)
	var plate := HeaderPlate.new()
	_fill_rect(plate)
	root.add_child(plate)
	var h := hbox(10)
	h.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	h.offset_left = px(14)
	h.offset_right = px(300)
	root.add_child(h)
	h.add_child(slash(LINE, 25))
	var v := vbox(-3)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(text("North Gate", "plate"))
	var sub := text("", "label", INK_MUTED)
	v.add_child(sub)
	h.add_child(v)
	return [root, sub]


## Counter pill: slash or icon, big value, tracked caption. Returns [panel, value_label, caption_label].
static func counter(icon_name: String, caption: String) -> Array:
	var p := PanelContainer.new()
	var sb := box(PANEL_SOLID, 6, LINE, 1, 0)
	sb.content_margin_left = px(10)
	sb.content_margin_right = px(12)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size.y = px(32)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := hbox(8)
	p.add_child(h)
	if icon_name == "":
		h.add_child(slash(THREAT, 15))
	else:
		h.add_child(glyph(icon_name, 20))
	var v := text("0", "counter")
	h.add_child(v)
	var c := text(caption, "label")
	h.add_child(c)
	return [p, v, c]


## Gate integrity bar that sits on the gate. Returns [panel, progress, value_label].
static func gate_bar() -> Array:
	var p := PanelContainer.new()
	var sb := box(PANEL_SOLID, 5, LINE_DIM, 1, 0)
	sb.content_margin_left = px(11)
	sb.content_margin_right = px(11)
	sb.content_margin_top = px(3)
	sb.content_margin_bottom = px(6)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size.x = px(160)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := vbox(1)
	p.add_child(v)
	var h := hbox(8)
	v.add_child(h)
	h.add_child(text("Gate", "label"))
	h.add_child(spacer())
	var val := text("1000 / 1000", "label")
	h.add_child(val)
	var bar := vital_bar(4)
	v.add_child(bar)
	return [p, bar, val]


static func vital_bar(h_pt: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = px(h_pt)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = STRUCTURE
	var fill := StyleBoxFlat.new()
	fill.bg_color = FRIENDLY
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


static func set_gate(bar: ProgressBar, val: Label, v: float, maxv: float) -> void:
	bar.max_value = maxv
	bar.value = v
	val.text = "%d / %d" % [ceili(v), maxv]
	val.add_theme_color_override("font_color", THREAT if v / maxv <= 0.25 else INK)


## Small chip floated over a turret: "37 / 45", or amber "EMPTY".
static func ammo_chip() -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := text("", "label")
	l.name = "Value"
	p.add_child(l)
	set_ammo_chip(p, 0, 0)
	return p


static func set_ammo_chip(p: PanelContainer, ammo: int, max_ammo: int) -> void:
	var empty := ammo <= 0
	var sb := box(PANEL_SOLID, 3, AMBER if empty else LINE_DIM, 1, 0)
	sb.content_margin_left = px(7)
	sb.content_margin_right = px(7)
	sb.content_margin_top = px(1)
	sb.content_margin_bottom = px(1)
	p.add_theme_stylebox_override("panel", sb)
	var l := p.get_node("Value") as Label
	l.text = "EMPTY" if empty else "%d / %d" % [ammo, max_ammo]
	l.add_theme_color_override("font_color", AMBER if empty else INK)


# ---------------------------------------------------------------- deployment tray card
static func turret_card(label_text: String, art: Texture2D, cb: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(px(58), px(58))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	var v := vbox(0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_fill_rect(v)
	v.offset_top = px(3)
	v.offset_bottom = -px(3)
	b.add_child(v)
	var img := image(art, 54, 36)
	img.name = "Art"
	v.add_child(img)
	var n := text(label_text, "small", INK, HORIZONTAL_ALIGNMENT_CENTER)
	n.name = "Name"
	v.add_child(n)
	var check := glyph("check", 16, FRIENDLY)
	check.name = "Flag"
	check.visible = false
	check.position = Vector2(px(4), px(4))
	b.add_child(check)
	set_card_state(b, false, false)
	return b


static func set_card_state(b: Button, selected: bool, placed: bool) -> void:
	for st in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(st, box(PANEL, 6, AMBER if selected else LINE, 2.0 if selected else 1.0))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var dim := placed and not selected
	for n in ["Art", "Name"]:
		(b.find_child(n, true, false) as CanvasItem).modulate.a = 0.55 if dim else 1.0
	(b.find_child("Flag", true, false) as Control).visible = dim


# ---------------------------------------------------------------- briefing rows
static func enemy_row(title: String, desc: String, art: Texture2D) -> PanelContainer:
	var p := inset(6, 2)
	var h := hbox(12)
	p.add_child(h)
	h.add_child(image(art, 76, 36))
	var v := vbox(-2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(text(title, "label_lg"))
	v.add_child(text(desc, "caption", INK_MUTED))
	h.add_child(v)
	return p


static func defense_card(title: String, ammo_text: String, art: Texture2D) -> PanelContainer:
	var p := inset(4, 4, LINE)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := vbox(0)
	p.add_child(v)
	v.add_child(image(art, 84, 44))
	v.add_child(text(title, "label", INK, HORIZONTAL_ALIGNMENT_CENTER))
	var h := hbox(4)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(glyph("rounds", 13, AMBER))
	h.add_child(text(ammo_text, "small", INK_MUTED))
	v.add_child(h)
	return p


## Label + value row of the victory / defeat table.
static func stat_row(label_text: String, value: String) -> HBoxContainer:
	var h := hbox(8)
	h.add_child(text(label_text, "label_lg"))
	h.add_child(spacer())
	h.add_child(text(value, "label_lg"))
	return h
