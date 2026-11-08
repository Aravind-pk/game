extends Node
## North Gate game controller: BRIEFING -> DEPLOYMENT -> COMBAT -> RESULT -> retry/next.
## Builds the portrait mobile UI in code and drives the deterministic BattleSim.
##
## Screenshot/automation flags (after `--`):
##   level=05  phase=briefing|deploy|radar|combat|result  shot=/path.png  shot_time=6  auto_deploy

enum Phase { BRIEFING, DEPLOYMENT, COMBAT, RESULT }

const C_BG := Color("#0f1722")
const C_PANEL := Color("#16212e")
const C_PANEL2 := Color("#1f2c3b")
const C_ACCENT := Color("#f5c56b")
const C_THREAT := Color("#ff6b63")
const C_CYAN := Color("#4fd6e0")
const C_TEXT := Color("#ffffff")
const C_MUTED := Color("#9fb0c2")
const MAX_STEPS_PER_FRAME := 12
const PROGRESS_FILE := "user://progress.json"

var battlefield: Battlefield
var level_paths: Array = []
var level_index := 0
var unlocked := 0
var level: LevelData
var deployment: Array = []   # [{type, level, ammo, cell, stock}]
var stock: Array = []        # remaining guns per level.guns entry
var held := -1               # level.guns index currently held for placement
var phase := Phase.BRIEFING
var sim: BattleSim
var speed := 1.0
var _accum := 0.0
var _end_timer := -1.0
var _args := {}
var _shot_done := false

# UI
var _ui: CanvasLayer
var _top_title: Label
var _top_sub: Label
var _top_enemies: Label
var _gate_bar: ProgressBar
var _gate_label: Label
var _tray: Control
var _cards_box: HBoxContainer
var _cards: Array = []
var _combat_bar: Control
var _speed_btn: Button
var _combat_label: Label
var _overlay: Control
var _toast: Label
var _toast_t := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var dir := DirAccess.open("res://levels")
	for f in dir.get_files():
		if f.ends_with(".json"):
			level_paths.append("res://levels/" + f)
	level_paths.sort()
	_load_progress()
	battlefield = Battlefield.new()
	add_child(battlefield)
	battlefield.cell_tapped.connect(_on_cell_tapped)
	battlefield.cell_dragged.connect(_on_cell_dragged)
	battlefield.hover_changed.connect(_on_hover)
	_build_ui()
	var start := unlocked
	if _args.has("level"):
		start = clampi(int(_args.level) - 1, 0, level_paths.size() - 1)
	start_level(start)
	_apply_automation()


# ================================================================== flow

func start_level(i: int) -> void:
	level_index = i
	level = LevelData.load_file(level_paths[i])
	battlefield.build(level)
	deployment.clear()
	stock.clear()
	for g in level.guns:
		stock.append(int(g.count))
	held = -1
	sim = null
	_set_phase(Phase.BRIEFING)


func _set_phase(p: Phase) -> void:
	phase = p
	battlefield.input_enabled = p == Phase.DEPLOYMENT
	_tray.visible = p == Phase.DEPLOYMENT
	_combat_bar.visible = p == Phase.COMBAT
	_close_overlay()
	match p:
		Phase.BRIEFING:
			battlefield.show_deployment(deployment)
			_show_briefing()
		Phase.DEPLOYMENT:
			battlefield.show_deployment(deployment)
			battlefield.set_held(level.guns[held].type if held >= 0 else "")
		Phase.COMBAT:
			pass
		Phase.RESULT:
			_show_result()
	_refresh()


func begin_deployment() -> void:
	_set_phase(Phase.DEPLOYMENT)
	if deployment.is_empty():
		_toast_msg("Pick a turret below, then tap the field to deploy it")


func defend() -> void:
	if deployment.is_empty():
		_toast_msg("Deploy at least one turret first")
		return
	held = -1
	battlefield.set_held("")
	sim = BattleSim.new()
	sim.setup(level, deployment)
	battlefield.begin_battle(sim)
	_accum = 0.0
	_end_timer = -1.0
	_set_phase(Phase.COMBAT)


func retry() -> void:
	# restore the previous deployment so the player can adjust instead of starting over
	sim = null
	battlefield.sim = null
	_set_phase(Phase.DEPLOYMENT)


func next_level() -> void:
	if level_index + 1 < level_paths.size():
		start_level(level_index + 1)
	else:
		start_level(0)


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t * 2.0, 0.0, 1.0)
	if phase != Phase.COMBAT or sim == null:
		return
	_accum += delta * speed
	var steps := 0
	while _accum >= Defs.SIM_DT and sim.state == BattleSim.State.RUNNING and steps < MAX_STEPS_PER_FRAME:
		sim.step()
		for e in sim.events:
			if e.type == "gate_hit":
				battlefield.shake_gate()
		battlefield.handle_events(sim.events)
		sim.events.clear()
		_accum -= Defs.SIM_DT
		steps += 1
	if steps == MAX_STEPS_PER_FRAME:
		_accum = 0.0
	battlefield.sync(clampf(_accum / Defs.SIM_DT, 0.0, 1.0))
	_refresh_combat()
	if sim.state != BattleSim.State.RUNNING:
		if _end_timer < 0.0:
			_end_timer = 1.4
		_end_timer -= delta
		if _end_timer <= 0.0:
			if sim.state == BattleSim.State.VICTORY:
				unlocked = maxi(unlocked, mini(level_index + 1, level_paths.size() - 1))
				_save_progress()
			_set_phase(Phase.RESULT)


# ================================================================== placement

func _valid_cell(c: Vector2i) -> bool:
	return level.is_deployable(c) and _gun_at(c) < 0


func _gun_at(c: Vector2i) -> int:
	for i in deployment.size():
		if deployment[i].cell == c:
			return i
	return -1


func select_card(i: int) -> void:
	if phase != Phase.DEPLOYMENT:
		return
	if held == i or stock[i] <= 0:
		held = -1
	else:
		held = i
	battlefield.set_held(level.guns[held].type if held >= 0 else "")
	_refresh()


func place(stock_i: int, c: Vector2i) -> bool:
	if stock[stock_i] <= 0 or not _valid_cell(c):
		return false
	var g: Dictionary = level.guns[stock_i]
	deployment.append({"type": g.type, "level": g.level, "ammo": g.ammo, "cell": c, "stock": stock_i})
	stock[stock_i] -= 1
	return true


func _on_cell_tapped(c: Vector2i) -> void:
	if phase != Phase.DEPLOYMENT:
		return
	if held >= 0:
		if place(held, c):
			if stock[held] <= 0:
				held = -1
			battlefield.show_deployment(deployment)
			battlefield.set_held(level.guns[held].type if held >= 0 else "")
		else:
			_toast_msg("Can't deploy there")
	else:
		var gi := _gun_at(c)
		if gi >= 0:  # pick the gun back up to move it
			var d: Dictionary = deployment[gi]
			deployment.remove_at(gi)
			stock[d.stock] += 1
			held = d.stock
			battlefield.show_deployment(deployment)
			battlefield.set_held(d.type)
			battlefield.update_ghost(c, true)
			_toast_msg("Tap a new spot, or REMOVE to return it")
	_refresh()


func _on_cell_dragged(from: Vector2i, to: Vector2i) -> void:
	if phase != Phase.DEPLOYMENT:
		return
	if held >= 0:
		_on_cell_tapped(to)
		return
	var gi := _gun_at(from)
	if gi < 0:
		return
	if _valid_cell(to):
		deployment[gi].cell = to
		battlefield.show_deployment(deployment)
	else:
		_toast_msg("Can't deploy there")
	_refresh()


func _on_hover(c: Vector2i) -> void:
	if phase == Phase.DEPLOYMENT and held >= 0:
		battlefield.update_ghost(c, _valid_cell(c))


func remove_held() -> void:
	held = -1
	battlefield.set_held("")
	_refresh()


func clear_deployment() -> void:
	for d in deployment:
		stock[d.stock] += 1
	deployment.clear()
	held = -1
	battlefield.show_deployment(deployment)
	battlefield.set_held("")
	_refresh()


# ================================================================== UI construction

func _style(color: Color, radius := 18, border := 0, border_col := Color.TRANSPARENT,
		pad := 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_col
	s.set_content_margin_all(pad)
	return s


func _label(text: String, size := 30, color := C_TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, cb: Callable, color := C_PANEL2, text_col := C_TEXT, size := 30) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", text_col)
	b.add_theme_color_override("font_hover_color", text_col)
	b.add_theme_color_override("font_pressed_color", text_col)
	b.add_theme_stylebox_override("normal", _style(color, 16, 0, Color.TRANSPARENT, 18))
	b.add_theme_stylebox_override("hover", _style(color.lightened(0.08), 16, 0, Color.TRANSPARENT, 18))
	b.add_theme_stylebox_override("pressed", _style(color.darkened(0.15), 16, 0, Color.TRANSPARENT, 18))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b


func _icon(model: String) -> Texture2D:
	var p := "res://assets/ui/icons/%s.png" % model
	return load(p) if ResourceLoader.exists(p) else null


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	# ---- top bar
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _style(Color(C_BG, 0.88), 0, 0, Color.TRANSPARENT, 22))
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	root.add_child(top)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 24)
	top.add_child(th)
	var tl := VBoxContainer.new()
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(tl)
	_top_title = _label("North Gate", 40, C_TEXT)
	_top_sub = _label("", 26, C_ACCENT)
	tl.add_child(_top_title)
	tl.add_child(_top_sub)
	var tr := VBoxContainer.new()
	tr.custom_minimum_size.x = 380
	th.add_child(tr)
	_top_enemies = _label("", 30, C_THREAT, HORIZONTAL_ALIGNMENT_RIGHT)
	tr.add_child(_top_enemies)
	_gate_bar = ProgressBar.new()
	_gate_bar.show_percentage = false
	_gate_bar.custom_minimum_size = Vector2(360, 22)
	_gate_bar.add_theme_stylebox_override("background", _style(Color("#2a3644"), 11, 0, Color.TRANSPARENT, 0))
	_gate_bar.add_theme_stylebox_override("fill", _style(Color("#5ee08a"), 11, 0, Color.TRANSPARENT, 0))
	tr.add_child(_gate_bar)
	_gate_label = _label("", 24, C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	tr.add_child(_gate_label)

	# ---- deployment tray
	var tray := PanelContainer.new()
	tray.add_theme_stylebox_override("panel", _style(Color(C_BG, 0.92), 0, 0, Color.TRANSPARENT, 18))
	tray.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tray.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(tray)
	_tray = tray
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 14)
	tray.add_child(tv)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 12)
	tv.add_child(tools)
	tools.add_child(_button("RADAR", _show_radar, C_PANEL2, C_THREAT, 26))
	tools.add_child(_button("BRIEFING", _show_briefing, C_PANEL2, C_TEXT, 26))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(spacer)
	tools.add_child(_button("REMOVE", remove_held, C_PANEL2, C_MUTED, 26))
	tools.add_child(_button("CLEAR", clear_deployment, C_PANEL2, C_MUTED, 26))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	tv.add_child(row)
	_cards_box = HBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 12)
	_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_cards_box)
	var defend_btn := _button("DEFEND", defend, C_ACCENT, C_BG, 40)
	defend_btn.custom_minimum_size = Vector2(230, 200)
	row.add_child(defend_btn)

	# ---- combat bar
	var cb := PanelContainer.new()
	cb.add_theme_stylebox_override("panel", _style(Color(C_BG, 0.9), 0, 0, Color.TRANSPARENT, 22))
	cb.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	cb.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(cb)
	_combat_bar = cb
	var ch := HBoxContainer.new()
	cb.add_child(ch)
	_combat_label = _label("Battle in progress — guns fire automatically", 28, C_MUTED)
	_combat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch.add_child(_combat_label)
	_speed_btn = _button("1×", _toggle_speed, C_PANEL2, C_ACCENT, 34)
	_speed_btn.custom_minimum_size = Vector2(150, 90)
	ch.add_child(_speed_btn)

	# ---- overlay host + toast
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_overlay)
	_toast = _label("", 30, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position.y = 210
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 10)
	_toast.modulate.a = 0.0
	root.add_child(_toast)


func _toggle_speed() -> void:
	speed = 2.0 if speed == 1.0 else 1.0
	_speed_btn.text = "2×" if speed == 2.0 else "1×"


func _toast_msg(t: String) -> void:
	_toast.text = t
	_toast.size.x = 0
	_toast.position.x = (get_viewport().get_visible_rect().size.x - _toast.get_minimum_size().x) * 0.5
	_toast_t = 2.5


func _make_card(i: int) -> Button:
	var g: Dictionary = level.guns[i]
	var def: Dictionary = Defs.GUNS[g.type]
	var b := Button.new()
	b.custom_minimum_size = Vector2(190, 200)
	b.toggle_mode = false
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(select_card.bind(i))
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 8
	v.offset_right = -8
	v.offset_top = 6
	v.offset_bottom = -6
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var tex := TextureRect.new()
	tex.texture = _icon(def.model)
	tex.custom_minimum_size = Vector2(0, 92)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tex)
	v.add_child(_label(def.name, 24, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_label("Lv.%d" % g.level, 20, C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_label("ammo %d" % g.ammo, 22, C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	var badge := _label("", 26, C_BG, HORIZONTAL_ALIGNMENT_CENTER)
	badge.name = "Badge"
	badge.add_theme_stylebox_override("normal", _style(C_ACCENT, 14, 0, Color.TRANSPARENT, 4))
	badge.position = Vector2(140, -10)
	badge.custom_minimum_size = Vector2(52, 36)
	b.add_child(badge)
	return b


func _refresh() -> void:
	if level == null:
		return
	_top_title.text = "Level %s — %s" % [level.id, level.title]
	var phase_names := {Phase.BRIEFING: "Briefing", Phase.DEPLOYMENT: "Plan & Deploy",
		Phase.COMBAT: "Battle", Phase.RESULT: "Result"}
	_top_sub.text = "NORTH GATE  ·  " + str(phase_names[phase]).to_upper()
	_top_enemies.text = "%d incoming" % level.total_enemies()
	_gate_bar.max_value = level.gate_max_hp
	_gate_bar.value = level.gate_max_hp
	_gate_label.text = "Gate %d / %d" % [level.gate_max_hp, level.gate_max_hp]
	_gate_bar.add_theme_stylebox_override("fill", _style(Color("#5ee08a"), 11, 0, Color.TRANSPARENT, 0))
	if sim != null and phase in [Phase.COMBAT, Phase.RESULT]:
		_refresh_combat()
	# cards
	if _cards.size() != level.guns.size() or (_cards.size() > 0 and _cards[0].get_meta("level", "") != level.id):
		for c in _cards:
			c.queue_free()
		_cards.clear()
		for i in level.guns.size():
			var c := _make_card(i)
			c.set_meta("level", level.id)
			_cards_box.add_child(c)
			_cards.append(c)
	for i in _cards.size():
		var c: Button = _cards[i]
		var sel := held == i
		var empty: bool = stock[i] <= 0
		var col := C_PANEL2 if not empty else Color("#141c26")
		var st := _style(col, 18, 5 if sel else 2, C_ACCENT if sel else Color("#2f3d4f"), 8)
		for k in ["normal", "hover", "pressed", "focus"]:
			c.add_theme_stylebox_override(k, st)
		c.modulate.a = 0.45 if empty and not sel else 1.0
		(c.get_node("Badge") as Label).text = "×%d" % stock[i]


func _refresh_combat() -> void:
	_gate_bar.value = sim.gate_hp
	_gate_label.text = "Gate %d / %d" % [ceili(sim.gate_hp), level.gate_max_hp]
	_top_enemies.text = "%d remaining" % sim.remaining_enemies()
	var frac := sim.gate_hp / level.gate_max_hp
	var fill := Color("#5ee08a") if frac > 0.5 else (C_ACCENT if frac > 0.25 else C_THREAT)
	_gate_bar.add_theme_stylebox_override("fill", _style(fill, 11, 0, Color.TRANSPARENT, 0))


# ================================================================== overlays

func _close_overlay() -> void:
	for c in _overlay.get_children():
		c.queue_free()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _open_overlay(min_h := 0.0) -> VBoxContainer:
	_close_overlay()
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	margin.add_theme_constant_override("margin_top", 150)
	margin.add_theme_constant_override("margin_bottom", 60)
	_overlay.add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(C_PANEL, 26, 2, Color("#2f3d4f"), 34))
	panel.custom_minimum_size = Vector2(960, min_h)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)
	return v


func _section(v: VBoxContainer, title: String) -> void:
	var l := _label(title.to_upper(), 26, C_ACCENT)
	v.add_child(l)


func _show_briefing() -> void:
	var v := _open_overlay()
	v.add_child(_label("Level %s" % level.id, 28, C_MUTED))
	v.add_child(_label(level.title, 52, C_TEXT))
	v.add_child(_label("Gate HP  %d" % level.gate_max_hp, 28, Color("#5ee08a")))
	_section(v, "Incoming  ·  %d monsters" % level.total_enemies())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	for e in level.enemy_summary():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var t := TextureRect.new()
		t.texture = _icon(Defs.MONSTERS[e.type].model)
		t.custom_minimum_size = Vector2(96, 72)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(t)
		var tv := VBoxContainer.new()
		tv.add_child(_label("%d × %s" % [e.count, Defs.MONSTERS[e.type].name], 30, C_TEXT))
		tv.add_child(_label("Level %d · %s" % [e.level, Defs.MONSTERS[e.type].desc], 22, C_MUTED))
		row.add_child(tv)
		grid.add_child(row)
	_section(v, "Spawn radar")
	var radar := RadarView.new()
	radar.custom_minimum_size = Vector2(880, 560)
	radar.set_level(level, deployment)
	v.add_child(radar)
	_section(v, "Your defenses")
	var gl := HBoxContainer.new()
	gl.add_theme_constant_override("separation", 24)
	v.add_child(gl)
	for g in level.guns:
		gl.add_child(_label("%d× %s Lv.%d  (%d ammo)" % [g.count, Defs.GUNS[g.type].name, g.level, g.ammo], 24, C_TEXT))
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 14)
	v.add_child(nav)
	if level_index > 0:
		nav.add_child(_button("◀", func(): start_level(level_index - 1), C_PANEL2, C_TEXT, 30))
	if level_index < unlocked:
		nav.add_child(_button("▶", func(): start_level(level_index + 1), C_PANEL2, C_TEXT, 30))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(sp)
	var go := _button("PLAN DEPLOYMENT", begin_deployment, C_ACCENT, C_BG, 34)
	go.custom_minimum_size = Vector2(420, 96)
	nav.add_child(go)


func _show_radar() -> void:
	var v := _open_overlay()
	v.add_child(_label("Enemy Spawn Radar", 44, C_TEXT))
	v.add_child(_label("Full battlefield. Green frame = your camera / deploy area.", 24, C_MUTED))
	var radar := RadarView.new()
	radar.custom_minimum_size = Vector2(880, 1100)
	radar.set_level(level, deployment)
	v.add_child(radar)
	for h in level.hotspots:
		var parts := []
		for g in h.groups:
			parts.append("%d %s Lv%d" % [g.count, Defs.MONSTERS[g.type].name, g.level])
		var delay := "" if h.delay <= 0.0 else "  (after %ds)" % int(h.delay)
		v.add_child(_label("● %s: %s%s" % [h.name, ", ".join(parts), delay], 26, C_THREAT))
	v.add_child(_button("CLOSE", _close_overlay, C_PANEL2, C_TEXT, 30))


func _show_result() -> void:
	var s := sim.summary()
	var won := sim.state == BattleSim.State.VICTORY
	var v := _open_overlay()
	var title := _label("GATE HELD" if won else "GATE BREACHED", 64, Color("#5ee08a") if won else C_THREAT,
		HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(title)
	v.add_child(_label("VICTORY" if won else "DEFEAT", 30, C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_label("Gate HP remaining:  %d / %d" % [ceili(s.gate_hp), s.gate_max], 32, C_TEXT))
	v.add_child(_label("Monsters destroyed:  %d / %d" % [s.kills, s.total_enemies], 32, C_TEXT))
	v.add_child(_label("Turrets survived:  %d / %d" % [s.guns_survived, s.guns_total], 32, C_TEXT))
	v.add_child(_label("Battle time:  %.1fs" % s.time, 26, C_MUTED))
	if not won:
		v.add_child(_label("Your deployment is kept — adjust it and try again.", 26, C_ACCENT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	if won:
		row.add_child(_button("REPLAY", retry, C_PANEL2, C_TEXT, 32))
		var last := level_index + 1 >= level_paths.size()
		var nb := _button("ALL LEVELS CLEAR — RESTART" if last else "NEXT LEVEL", next_level, C_ACCENT, C_BG, 34)
		nb.custom_minimum_size.y = 96
		row.add_child(nb)
	else:
		var rb := _button("RETRY", retry, C_ACCENT, C_BG, 38)
		rb.custom_minimum_size = Vector2(360, 100)
		row.add_child(rb)


# ================================================================== progress

func _load_progress() -> void:
	if not FileAccess.file_exists(PROGRESS_FILE):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(PROGRESS_FILE))
	if d is Dictionary:
		unlocked = int(d.get("unlocked", 0))


func _save_progress() -> void:
	var f := FileAccess.open(PROGRESS_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"unlocked": unlocked}))


# ================================================================== automation (screenshots / CI)

func _apply_automation() -> void:
	if _args.has("unlock_all"):
		unlocked = level_paths.size() - 1
	var p := str(_args.get("phase", ""))
	if _args.has("auto_deploy") or p in ["combat", "result", "deploy_full"]:
		_auto_deploy()
	match p:
		"deploy", "deploy_full":
			begin_deployment()
			if _args.has("hold"):
				select_card(0)
				var vr := level.view_rect
				var c := vr.position + Vector2i(vr.size.x / 2, vr.size.y / 3)
				battlefield.update_ghost(c, _valid_cell(c))
		"radar":
			begin_deployment()
			_show_radar()
		"combat", "result":
			begin_deployment()
			defend()
			if p == "result":
				speed = 8.0
	if _args.has("shot"):
		var t := float(_args.get("shot_time", "1.5"))
		get_tree().create_timer(t).timeout.connect(_take_shot)


func _auto_deploy() -> void:
	# a readable demo layout: guns spread across the middle of the field
	var vr := level.view_rect
	var spots := []
	var n := 0
	for g in level.guns:
		n += int(g.count)
	for k in n:
		var x := vr.position.x + int(round(float(k + 1) * vr.size.x / float(n + 1)))
		var y := vr.position.y + vr.size.y - 6 - (k % 2) * 3
		spots.append(Vector2i(x, y))
	var si := 0
	for i in level.guns.size():
		while stock[i] > 0 and si < spots.size():
			var c: Vector2i = spots[si]
			while not _valid_cell(c):
				c.y -= 1
			place(i, c)
			si += 1


func _take_shot() -> void:
	if _shot_done:
		return
	_shot_done = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(str(_args.shot))
	print("[shot] saved ", _args.shot)
	get_tree().quit()
