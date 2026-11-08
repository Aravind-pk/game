class_name UiKit
extends RefCounted
## North Gate design system, reproduced in Godot from its tokens (Night theme).
## Sizes are the system's points multiplied by S: 390pt phone width -> 1080px canvas.

const S := 2.7

# ---- colour tokens (night)
const BG := Color("#0f1722")
const PANEL := Color("#18222d")
const PANEL_RAISED := Color("#212c38")
const STRUCTURE := Color("#2e3a48")
const LINE := Color("#3a4757")
const METAL := Color("#6b7c8c")
const INK := Color("#ffffff")
const INK_MUTED := Color("#a9b6c3")
const AMBER := Color("#f5c56b")
const AMBER_STRONG := Color("#f6ae36")
const ON_AMBER := Color("#1a1306")
const THREAT := Color("#ff6b63")
const THREAT_SOFT := Color("#3a1d22")
const FRIENDLY := Color("#52d2de")
const FRIENDLY_SOFT := Color("#12313a")
const VITAL := Color("#6dd155")
const TERRAIN_DEEP := Color("#2f3d34")
const SCRIM := Color(0.059, 0.09, 0.133, 0.8)

const PLATE_SKEW := -18.0

static var _fonts := {}
static var _icons := {}


static func px(pt: float) -> int:
	return int(round(pt * S))


static func font(kind: String) -> Font:
	# kind: display (Barlow Condensed 700), display_heavy (800), sans (500), sans_semi (600), sans_bold (700)
	if _fonts.has(kind):
		return _fonts[kind]
	var file: String = {
		"display": "BarlowCondensed-Bold", "display_heavy": "BarlowCondensed-ExtraBold",
		"sans": "Barlow-Medium", "sans_semi": "Barlow-SemiBold", "sans_bold": "Barlow-Bold",
	}[kind]
	var f: Font = load("res://assets/ui/fonts/%s.ttf" % file)
	if kind.begins_with("sans"):
		var fv := FontVariation.new()
		fv.base_font = f
		fv.opentype_features = {"tnum": 1}  # tabular figures for changing numbers
		f = fv
	_fonts[kind] = f
	return f


static func icon(name: String) -> Texture2D:
	if not _icons.has(name):
		_icons[name] = load("res://assets/ui/glyphs/%s.svg" % name)
	return _icons[name]


## Type styles from tokens.json (size in pt).
const TYPE := {
	"result": ["display_heavy", 48], "title": ["display", 28], "plate": ["display", 20], "tag": ["display", 12],
	"hud-value": ["sans_bold", 20], "label": ["sans_semi", 14], "body": ["sans", 15], "caption": ["sans", 12],
}


static func text(t: String, style: String, color := INK, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	var spec: Array = TYPE[style]
	if spec[0].begins_with("display"):
		t = t.to_upper()
	l.text = t
	l.add_theme_font_override("font", font(spec[0]))
	l.add_theme_font_size_override("font_size", px(spec[1]))
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func box(bg: Color, radius_pt := 16.0, border := LINE, border_pt := 1.0, pad_pt := 16.0,
		shadow := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(px(radius_pt))
	s.border_color = border
	s.set_border_width_all(maxi(1, px(border_pt)) if border_pt > 0 else 0)
	s.set_content_margin_all(px(pad_pt))
	s.anti_aliasing = true
	if shadow:  # shadow-panel
		s.shadow_color = Color(0, 0, 0, 0.5)
		s.shadow_size = px(10)
		s.shadow_offset = Vector2(0, px(6))
	return s


static func glyph(name: String, size_pt: float, color: Color) -> TextureRect:
	var t := TextureRect.new()
	t.texture = icon(name)
	t.custom_minimum_size = Vector2.ONE * px(size_pt)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.modulate = color
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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


# ---------------------------------------------------------------- Button
## variant: primary | secondary | ghost ; size: md | lg ; stacked = DEFEND (icon over label)
static func button(label: String, cb: Callable, variant := "secondary", icon_name := "", size := "md",
		stacked := false, icon_only := false) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	b.custom_minimum_size = Vector2(px(44), px(44))
	var bg := PANEL_RAISED
	var fg := INK
	var border := METAL
	if variant == "primary":
		bg = AMBER
		fg = ON_AMBER
		border = AMBER_STRONG
	elif variant == "ghost":
		bg = Color(0, 0, 0, 0)
		fg = INK_MUTED
		border = Color(0, 0, 0, 0)
	var radius := 8.0 if icon_only else 12.0
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var c := bg
		if st == "pressed":
			c = AMBER_STRONG if variant == "primary" else bg.darkened(0.15)
		elif st == "hover":
			c = bg.lightened(0.05) if variant != "ghost" else bg
		var sb := box(c, radius, border, 1.0 if variant != "ghost" else 0.0, 0.0)
		if variant == "primary":  # amber -> amber-strong bottom edge
			sb.border_width_bottom = px(4)
		sb.content_margin_left = px(16)
		sb.content_margin_right = px(16)
		b.add_theme_stylebox_override(st, sb if st != "focus" else StyleBoxEmpty.new())
	var font_pt := 22.0 if size == "lg" else 16.0
	var content := vbox(4) if stacked else hbox(8)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	if icon_name != "":
		var g := glyph(icon_name, (32.0 if stacked else (24.0 if size == "lg" else 20.0)), fg)
		g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		content.add_child(g)
	if not icon_only:
		var l := text(label, "plate", fg, HORIZONTAL_ALIGNMENT_CENTER)
		l.add_theme_font_size_override("font_size", px(font_pt))
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		content.add_child(l)
	b.add_child(content)
	var min_w := 0.0
	if icon_only:
		b.custom_minimum_size = Vector2(px(48), px(48))
	elif stacked:
		b.custom_minimum_size = Vector2(px(96), px(96))
	else:
		var l2 := text(label, "plate")
		l2.add_theme_font_size_override("font_size", px(font_pt))
		min_w = l2.get_minimum_size().x + px(32) + (px(28) if icon_name != "" else 0)
		b.custom_minimum_size = Vector2(maxf(min_w, px(44)), px(64) if size == "lg" else px(44))
	return b


# ---------------------------------------------------------------- Tag
static func tag(t: String, tone := "neutral") -> PanelContainer:
	var bg := STRUCTURE
	var fg := INK
	match tone:
		"friendly":
			bg = FRIENDLY_SOFT
			fg = FRIENDLY
		"threat":
			bg = THREAT_SOFT
			fg = THREAT
		"amber":
			bg = AMBER
			fg = ON_AMBER
	var p := PanelContainer.new()
	var sb := box(bg, 4, bg, 0, 0)
	sb.content_margin_left = px(8)
	sb.content_margin_right = px(8)
	sb.content_margin_top = px(2)
	sb.content_margin_bottom = px(2)
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(text(t, "tag", fg))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


# ---------------------------------------------------------------- Panel
static func panel(title := "", subtitle := "", action: Control = null) -> Array:
	## returns [panel_container, body_vbox]
	var p := PanelContainer.new()
	var sb := box(PANEL, 16, LINE, 1, 16, true)
	sb.content_margin_top = px(12)
	p.add_theme_stylebox_override("panel", sb)
	var v := vbox(12)
	p.add_child(v)
	if title != "" or action:
		var head := hbox(8)
		if title != "":
			var t := text(title, "label")
			t.add_theme_font_override("font", font("sans_bold"))
			t.add_theme_font_size_override("font_size", px(17))
			head.add_child(t)
		if subtitle != "":
			head.add_child(text(subtitle, "body", INK_MUTED))
		if action:
			head.add_child(spacer())
			head.add_child(action)
		v.add_child(head)
	return [p, v]


# ---------------------------------------------------------------- HudCounter group
static func hud_counter(icon_name: String, tone_color: Color) -> Array:
	## returns [hbox, value_label]
	var h := hbox(4)
	h.add_child(glyph(icon_name, 22, tone_color))
	var v := text("0", "hud-value")
	h.add_child(v)
	return [h, v]


static func pill(child: Control, pad_h_pt := 12.0) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(PANEL, 8, LINE, 1, 0, true)
	sb.content_margin_left = px(pad_h_pt)
	sb.content_margin_right = px(pad_h_pt)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size.y = px(48)
	p.add_child(child)
	return p


# ---------------------------------------------------------------- WaveHeader
static func wave_header() -> Array:
	## returns [pill, title_label, sub_label]
	var h := hbox(12)
	var mark := TextureRect.new()
	mark.texture = load("res://assets/ui/north_gate_mark.svg")
	mark.custom_minimum_size = Vector2(px(40), px(40))
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(mark)
	var v := vbox(0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var t := text("North Gate", "plate")
	var sub := text("Level 01", "caption", INK_MUTED)
	sub.add_theme_font_override("font", font("sans_semi"))
	sub.add_theme_font_size_override("font_size", px(13))
	v.add_child(t)
	v.add_child(sub)
	h.add_child(v)
	var p := pill(h, 4)
	(p.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_right = px(16)
	return [p, t, sub]


# ---------------------------------------------------------------- GateHealthBar
static func gate_bar() -> Array:
	## returns [container, progress, value_label]
	var p := PanelContainer.new()
	var sb := box(PANEL, 999, LINE, 1, 0)
	sb.content_margin_left = px(12)
	sb.content_margin_right = px(12)
	sb.content_margin_top = px(8)
	sb.content_margin_bottom = px(8)
	p.add_theme_stylebox_override("panel", sb)
	var h := hbox(8)
	p.add_child(h)
	h.add_child(glyph("shield", 18, AMBER))
	var lab := text("Gate HP", "label")
	lab.add_theme_font_size_override("font_size", px(13))
	h.add_child(lab)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(px(130), px(10))
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("background", box(PANEL_RAISED, 4, METAL, 1, 0))
	bar.add_theme_stylebox_override("fill", box(VITAL, 4, VITAL, 0, 0))
	h.add_child(bar)
	var val := text("1000 / 1000", "label")
	val.add_theme_font_override("font", font("sans_bold"))
	val.add_theme_font_size_override("font_size", px(13))
	h.add_child(val)
	p.custom_minimum_size.x = px(280)
	return [p, bar, val]


static func set_gate(bar: ProgressBar, val: Label, v: float, maxv: float) -> void:
	bar.max_value = maxv
	bar.value = v
	var pct := v / maxv
	var c := VITAL if pct > 0.5 else (AMBER if pct > 0.25 else THREAT)
	bar.add_theme_stylebox_override("fill", box(c, 4, c, 0, 0))
	val.text = "%d / %d" % [ceili(v), maxv]
	val.add_theme_color_override("font_color", THREAT if pct <= 0.25 else INK)


# ---------------------------------------------------------------- TurretCard
static func turret_card(name: String, level: int, ammo: int, art: Texture2D, cb: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(px(84), px(112))
	b.pressed.connect(cb)
	var v := vbox(2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_top = px(6)
	v.offset_bottom = -px(6)
	b.add_child(v)
	var img := TextureRect.new()
	img.texture = art
	img.custom_minimum_size = Vector2(px(72), px(48))
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	img.name = "Art"
	v.add_child(img)
	var n := text(name, "label", INK, HORIZONTAL_ALIGNMENT_CENTER)
	n.add_theme_font_size_override("font_size", px(13))
	n.name = "Name"
	v.add_child(n)
	var lv := text("Lv.%d" % level, "caption", FRIENDLY, HORIZONTAL_ALIGNMENT_CENTER)
	lv.add_theme_font_override("font", font("sans_bold"))
	lv.name = "Level"
	v.add_child(lv)
	var ah := hbox(2)
	ah.alignment = BoxContainer.ALIGNMENT_CENTER
	ah.add_child(glyph("ammo", 14, AMBER))
	var al := text("×%d" % ammo, "label")
	al.add_theme_font_override("font", font("sans_bold"))
	ah.add_child(al)
	ah.name = "Ammo"
	v.add_child(ah)
	var flag := text("Placed", "tag", FRIENDLY, HORIZONTAL_ALIGNMENT_CENTER)
	flag.add_theme_font_size_override("font_size", px(10))
	flag.name = "Flag"
	flag.set_anchors_preset(Control.PRESET_CENTER_TOP)
	flag.position = Vector2(-px(22), px(2))
	flag.add_theme_stylebox_override("normal", box(PANEL_RAISED, 4, PANEL_RAISED, 0, 2))
	flag.visible = false
	b.add_child(flag)
	set_card_state(b, false, false)
	return b


static func set_card_state(b: Button, selected: bool, placed: bool) -> void:
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := box(PANEL_RAISED, 12, AMBER if selected else LINE, 2.0 if selected else 1.0, 0)
		if selected:  # glow-selected
			sb.shadow_color = Color(AMBER, 0.4)
			sb.shadow_size = px(8)
		b.add_theme_stylebox_override(st, sb)
	for n in ["Art", "Name", "Level", "Ammo"]:
		(b.find_child(n, true, false) as CanvasItem).modulate.a = 0.5 if placed and not selected else 1.0
	(b.find_child("Flag", true, false) as Control).visible = placed and not selected


# ---------------------------------------------------------------- EnemyRow
static func enemy_row(name: String, level: int, role: String, count: int, art: Texture2D) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(PANEL_RAISED, 12, LINE, 1, 0)
	sb.content_margin_left = px(12)
	sb.content_margin_right = px(12)
	sb.content_margin_top = px(8)
	sb.content_margin_bottom = px(8)
	p.add_theme_stylebox_override("panel", sb)
	var h := hbox(12)
	p.add_child(h)
	var img := TextureRect.new()
	img.texture = art
	img.custom_minimum_size = Vector2(px(56), px(40))
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(img)
	var v := vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(text(name, "label"))
	var tags := hbox(4)
	tags.add_child(tag("Lv.%d" % level, "threat"))
	tags.add_child(tag(role))
	v.add_child(tags)
	h.add_child(v)
	var c := text("×%d" % count, "result", THREAT, HORIZONTAL_ALIGNMENT_RIGHT)
	c.add_theme_font_size_override("font_size", px(26))
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(c)
	return p


# ---------------------------------------------------------------- LabelPlate
static func label_plate(t: String, code := "", tone := "neutral") -> Control:
	var plate := SkewPlate.new()
	plate.fill = AMBER if tone == "amber" else (THREAT_SOFT if tone == "threat" else STRUCTURE)
	var h := hbox(12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if code != "":
		var codebox := SkewPlate.new()
		codebox.fill = INK
		var cl := text(code, "plate", BG, HORIZONTAL_ALIGNMENT_CENTER)
		codebox.add_child(cl)
		codebox.pad = Vector2(px(10), px(2))
		h.add_child(codebox)
	h.add_child(text(t, "plate", ON_AMBER if tone == "amber" else (THREAT if tone == "threat" else INK)))
	plate.add_child(h)
	plate.pad = Vector2(px(24), px(4))
	return plate


# ---------------------------------------------------------------- StepMarker
static func step(n: int, title: String, caption: String, state := "active") -> HBoxContainer:
	var h := hbox(8)
	var disc := PanelContainer.new()
	var bg := AMBER if state == "active" else (FRIENDLY_SOFT if state == "done" else STRUCTURE)
	var fg := ON_AMBER if state == "active" else (FRIENDLY if state == "done" else INK_MUTED)
	disc.add_theme_stylebox_override("panel", box(bg, 999, bg, 0, 0))
	disc.custom_minimum_size = Vector2(px(28), px(28))
	var num := text(str(n), "label", fg, HORIZONTAL_ALIGNMENT_CENTER)
	num.add_theme_font_override("font", font("sans_bold"))
	num.add_theme_font_size_override("font_size", px(15))
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	disc.add_child(num)
	disc.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(disc)
	var v := vbox(0)
	var t := text(title, "label")
	t.add_theme_font_size_override("font_size", px(15))
	v.add_child(t)
	v.add_child(text(caption, "caption", INK_MUTED))
	h.add_child(v)
	return h
