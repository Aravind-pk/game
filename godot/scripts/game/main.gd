extends Node
## North Gate game controller: BRIEFING -> DEPLOYMENT -> COMBAT -> RESULT -> retry/next.
## UI follows the North Gate design system (scripts/ui/ui_kit.gd): WaveHeader + HudCounters
## + pause on top, GateHealthBar over the wall, deploy tray of TurretCards ending in DEFEND,
## Panel sheets for the briefing / radar, ResultBanner at the end.
##
## Screenshot/automation flags (after `--`):
##   level=05  phase=briefing|deploy|radar|combat|result|pause  shot=/path.png  shot_time=6
##   hold  auto_deploy  unlock_all

enum Phase { BRIEFING, DEPLOYMENT, COMBAT, RESULT }

const MAX_STEPS_PER_FRAME := 12
const PROGRESS_FILE := "user://progress.json"

var battlefield: Battlefield
var level_paths: Array = []
var level_index := 0
var unlocked := 0
var level: LevelData
var guns: Array = []          # one entry per available turret: {type, level, ammo}
var deployment: Array = []    # [{type, level, ammo, cell, gun}]
var held := -1                # index into guns currently held for placement
var phase := Phase.BRIEFING
var sim: BattleSim
var speed := 1.0
var paused := false
var _accum := 0.0
var _end_timer := -1.0
var _args := {}
var _shot_done := false

# UI
var _ui: CanvasLayer
var _wave_title: Label
var _wave_sub: Label
var _skull_val: Label
var _turret_val: Label
var _pause_btn: Button
var _gate_box: Control
var _gate_bar: ProgressBar
var _gate_val: Label
var _tray: Control
var _cards_box: HBoxContainer
var _cards: Array = []
var _combat_bar: Control
var _speed_btn: Button
var _overlay: Control
var _toast: Label
var _toast_t := 0.0
var _sheet_scroll: ScrollContainer   # the open Panel sheet, for drag-to-scroll
var _drag_from := Vector2.ZERO
var _drag_scroll := 0
var _dragging_sheet := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var dir := DirAccess.open("res://levels")
	for f in dir.get_files():
		if f.begins_with("level_") and f.ends_with(".json"):
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
	guns.clear()
	for g in level.guns:
		for k in int(g.count):
			guns.append({"type": g.type, "level": g.level, "ammo": g.ammo})
	deployment.clear()
	held = -1
	sim = null
	_rebuild_cards()
	_set_phase(Phase.BRIEFING)


func _set_phase(p: Phase) -> void:
	phase = p
	paused = false
	battlefield.input_enabled = p == Phase.DEPLOYMENT
	_tray.visible = p == Phase.DEPLOYMENT
	_combat_bar.visible = p == Phase.COMBAT
	_pause_btn.visible = p == Phase.COMBAT
	_gate_box.visible = p != Phase.BRIEFING
	_close_overlay()
	match p:
		Phase.BRIEFING:
			battlefield.show_deployment(deployment)
			_show_briefing()
		Phase.DEPLOYMENT:
			battlefield.show_deployment(deployment)
			battlefield.set_held(guns[held].type if held >= 0 else "")
		Phase.RESULT:
			_show_result()
	_refresh()


func begin_deployment() -> void:
	_set_phase(Phase.DEPLOYMENT)
	if deployment.is_empty():
		_toast_msg("Select a turret, then tap a tile to deploy it.")


func defend() -> void:
	if deployment.is_empty():
		_toast_msg("Deploy at least one turret.", UiKit.THREAT)
		return
	held = -1
	battlefield.set_held("")
	sim = BattleSim.new()
	sim.setup(level, deployment)
	battlefield.begin_battle(sim)
	battlefield.sim_speed = speed
	_accum = 0.0
	_end_timer = -1.0
	_set_phase(Phase.COMBAT)


func retry() -> void:
	# the previous deployment is kept so the player adjusts instead of starting over
	sim = null
	battlefield.sim = null
	_set_phase(Phase.DEPLOYMENT)


func next_level() -> void:
	start_level(level_index + 1 if level_index + 1 < level_paths.size() else 0)


func toggle_pause() -> void:
	if phase != Phase.COMBAT:
		return
	paused = not paused
	if paused:
		_show_pause()
	else:
		_close_overlay()


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t * 2.0, 0.0, 1.0)
	if phase != Phase.COMBAT or sim == null or paused:
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
	_refresh_hud()
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
	return level.is_deployable(c) and _dep_at(c) < 0


func _dep_at(c: Vector2i) -> int:
	for i in deployment.size():
		if deployment[i].cell == c:
			return i
	return -1


func _dep_of_gun(gi: int) -> int:
	for i in deployment.size():
		if deployment[i].gun == gi:
			return i
	return -1


func select_card(gi: int) -> void:
	if phase != Phase.DEPLOYMENT:
		return
	if held == gi:
		held = -1
	else:
		var di := _dep_of_gun(gi)
		if di >= 0:  # tapping a placed card picks that turret back up
			deployment.remove_at(di)
			battlefield.show_deployment(deployment)
		held = gi
	battlefield.set_held(guns[held].type if held >= 0 else "")
	_refresh()


func place(gi: int, c: Vector2i) -> bool:
	if not _valid_cell(c) or _dep_of_gun(gi) >= 0:
		return false
	var g: Dictionary = guns[gi]
	deployment.append({"type": g.type, "level": g.level, "ammo": g.ammo, "cell": c, "gun": gi})
	return true


func _next_unplaced() -> int:
	for gi in guns.size():
		if _dep_of_gun(gi) < 0 and gi != held:
			return gi
	return -1


func _on_cell_tapped(c: Vector2i) -> void:
	if phase != Phase.DEPLOYMENT:
		return
	if held >= 0:
		if place(held, c):
			held = -1
			battlefield.show_deployment(deployment)
			battlefield.set_held("")
		else:
			_toast_msg("Invalid tile", UiKit.THREAT)
	else:
		var di := _dep_at(c)
		if di >= 0:
			var d: Dictionary = deployment[di]
			deployment.remove_at(di)
			held = d.gun
			battlefield.show_deployment(deployment)
			battlefield.set_held(d.type)
			battlefield.update_ghost(c, true)
			_toast_msg("Tap a new tile. Tap its card to put it back.")
	_refresh()


func _on_cell_dragged(from: Vector2i, to: Vector2i) -> void:
	if phase != Phase.DEPLOYMENT:
		return
	if held >= 0:
		_on_cell_tapped(to)
		return
	var di := _dep_at(from)
	if di < 0:
		return
	if _valid_cell(to):
		deployment[di].cell = to
		battlefield.show_deployment(deployment)
	else:
		_toast_msg("Invalid tile", UiKit.THREAT)
	_refresh()


func _on_hover(c: Vector2i) -> void:
	if phase == Phase.DEPLOYMENT and held >= 0:
		battlefield.update_ghost(c, _valid_cell(c))


func clear_deployment() -> void:
	deployment.clear()
	held = -1
	battlefield.show_deployment(deployment)
	battlefield.set_held("")
	_refresh()


# ================================================================== UI construction

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)
	var m := UiKit.px(16)

	# ---- top HUD row: WaveHeader | HudCounters + pause
	var top := UiKit.hbox(8)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = m
	top.offset_right = -m
	top.offset_top = m
	root.add_child(top)
	var wh := UiKit.wave_header()
	top.add_child(wh[0])
	_wave_title = wh[1]
	_wave_sub = wh[2]
	top.add_child(UiKit.spacer())
	var counters := UiKit.hbox(16)
	var sk := UiKit.hud_counter("skull", UiKit.THREAT)
	_skull_val = sk[1]
	counters.add_child(sk[0])
	var tc := UiKit.hud_counter("ammo", UiKit.AMBER)
	_turret_val = tc[1]
	counters.add_child(tc[0])
	top.add_child(UiKit.pill(counters))
	_pause_btn = UiKit.button("Pause", toggle_pause, "secondary", "pause", "md", false, true)
	top.add_child(_pause_btn)

	# ---- deploy tray
	var tray := PanelContainer.new()
	var tsb := UiKit.box(UiKit.BG, 0, UiKit.LINE, 0, 16)
	tsb.border_width_top = 2
	tsb.content_margin_top = UiKit.px(10)
	tray.add_theme_stylebox_override("panel", tsb)
	tray.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tray.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(tray)
	_tray = tray
	var tv := UiKit.vbox(8)
	tray.add_child(tv)
	var tools := UiKit.hbox(8)
	tools.add_child(UiKit.button("Radar", _show_radar, "secondary", "radar"))
	tools.add_child(UiKit.button("Briefing", _show_briefing, "secondary"))
	tools.add_child(UiKit.spacer())
	tools.add_child(UiKit.button("Clear all", clear_deployment, "ghost", "close"))
	tv.add_child(tools)
	var row := UiKit.hbox(8)
	tv.add_child(row)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = UiKit.px(116)
	row.add_child(scroll)
	_cards_box = UiKit.hbox(8)
	scroll.add_child(_cards_box)
	row.add_child(UiKit.button("Defend", defend, "primary", "play", "lg", true))

	# ---- combat bar
	var cb := PanelContainer.new()
	cb.add_theme_stylebox_override("panel", tsb)
	cb.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	cb.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(cb)
	_combat_bar = cb
	var ch := UiKit.hbox(8)
	cb.add_child(ch)
	var info := UiKit.text("Turrets fire automatically.", "body", UiKit.INK_MUTED)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ch.add_child(info)
	_speed_btn = UiKit.button("1×", _toggle_speed, "secondary")
	_speed_btn.custom_minimum_size.x = UiKit.px(64)
	ch.add_child(_speed_btn)

	# ---- gate health pill, floats above the tray over the wall
	var gb := UiKit.gate_bar()
	_gate_box = gb[0]
	_gate_bar = gb[1]
	_gate_val = gb[2]
	_gate_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_gate_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_gate_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_gate_box)

	# ---- overlays + toast
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_overlay)
	_toast = UiKit.text("", "label", UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_toast.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toast.offset_top = UiKit.px(80)
	_toast.add_theme_color_override("font_outline_color", UiKit.BG)
	_toast.add_theme_constant_override("outline_size", UiKit.px(4))
	_toast.modulate.a = 0.0
	root.add_child(_toast)


func _layout_gate_pill() -> void:
	# sit just above whichever bottom bar is showing
	var bar: Control = _tray if _tray.visible else _combat_bar
	var h := bar.get_combined_minimum_size().y if bar.visible else 0.0
	_gate_box.offset_bottom = -h - UiKit.px(10)
	_gate_box.offset_top = _gate_box.offset_bottom - _gate_box.get_combined_minimum_size().y
	var w := _gate_box.get_combined_minimum_size().x
	_gate_box.offset_left = -w * 0.5
	_gate_box.offset_right = w * 0.5


func _toggle_speed() -> void:
	speed = 2.0 if speed == 1.0 else 1.0
	battlefield.sim_speed = speed
	(_speed_btn.find_children("*", "Label", true, false)[0] as Label).text = "2×" if speed == 2.0 else "1×"


func _toast_msg(t: String, col := UiKit.INK) -> void:
	_toast.text = t
	_toast.add_theme_color_override("font_color", col)
	_toast_t = 2.5


func _art(model: String) -> Texture2D:
	var p := "res://assets/ui/icons/%s.png" % model
	return load(p) if ResourceLoader.exists(p) else null


func _rebuild_cards() -> void:
	for c in _cards:
		c.queue_free()
	_cards.clear()
	for gi in guns.size():
		var g: Dictionary = guns[gi]
		var def: Dictionary = Defs.GUNS[g.type]
		var c := UiKit.turret_card(def.name, g.level, g.ammo, _art(def.model), select_card.bind(gi))
		_cards_box.add_child(c)
		_cards.append(c)


func _refresh() -> void:
	if level == null:
		return
	_wave_title.text = "NORTH GATE"
	_wave_sub.text = "Level %s" % level.id
	for gi in _cards.size():
		UiKit.set_card_state(_cards[gi], held == gi, _dep_of_gun(gi) >= 0)
	_refresh_hud()
	_layout_gate_pill.call_deferred()


func _refresh_hud() -> void:
	if sim != null and phase in [Phase.COMBAT, Phase.RESULT]:
		_skull_val.text = str(sim.remaining_enemies())
		var alive := 0
		for g in sim.guns:
			if g.alive:
				alive += 1
		_turret_val.text = "%d/%d" % [alive, sim.guns.size()]
		UiKit.set_gate(_gate_bar, _gate_val, sim.gate_hp, level.gate_max_hp)
	else:
		_skull_val.text = str(level.total_enemies())
		_turret_val.text = "%d/%d" % [deployment.size(), guns.size()]
		UiKit.set_gate(_gate_bar, _gate_val, level.gate_max_hp, level.gate_max_hp)


# ================================================================== overlays (Panel sheets)

func _close_overlay() -> void:
	_sheet_scroll = null
	for c in _overlay.get_children():
		c.queue_free()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _open_sheet() -> VBoxContainer:
	_close_overlay()
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = UiKit.SCRIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = UiKit.px(16)
	scroll.offset_right = -UiKit.px(16)
	scroll.offset_top = UiKit.px(76)
	scroll.offset_bottom = -UiKit.px(16)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_overlay.add_child(scroll)
	_sheet_scroll = scroll
	var v := UiKit.vbox(16)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(v)
	return v


func _show_briefing() -> void:
	var v := _open_sheet()
	var head := UiKit.hbox(12)
	head.add_child(UiKit.label_plate(level.title, level.id, "threat" if level_index >= 4 else "neutral"))
	v.add_child(head)
	var gate := UiKit.hbox(8)
	gate.add_child(UiKit.glyph("shield", 18, UiKit.AMBER))
	gate.add_child(UiKit.text("Gate HP %d" % level.gate_max_hp, "label"))
	v.add_child(gate)

	var roster: Array = UiKit.panel("Incoming", "(%d monsters)" % level.total_enemies())
	v.add_child(roster[0])
	var rows := level.enemy_summary()
	rows.sort_custom(func(a, b): return a.count > b.count)
	for e in rows:
		var d: Dictionary = Defs.MONSTERS[e.type]
		roster[1].add_child(UiKit.enemy_row(d.name, e.level, d.desc, e.count, _art(d.model)))

	var rp: Array = UiKit.panel("Enemy Spawn Radar", "(Full Battlefield)")
	v.add_child(rp[0])
	var radar := RadarView.new()
	radar.custom_minimum_size = Vector2(0, UiKit.px(220))
	radar.set_level(level, deployment)
	rp[1].add_child(radar)
	rp[1].add_child(_radar_legend())

	var tp: Array = UiKit.panel("Turrets", "(Unmanned)")
	v.add_child(tp[0])
	var tr := UiKit.hbox(8)
	for g in level.guns:
		var d: Dictionary = Defs.GUNS[g.type]
		var row := UiKit.vbox(2)
		var t := UiKit.hbox(4)
		t.add_child(UiKit.text("%d× %s" % [g.count, d.name], "label"))
		t.add_child(UiKit.tag("Lv.%d" % g.level, "friendly"))
		row.add_child(t)
		row.add_child(UiKit.text("(%s) · ammo ×%d" % [d.desc, g.ammo], "caption", UiKit.INK_MUTED))
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tr.add_child(row)
	tp[1].add_child(tr)

	if level_index == 0:  # first level: the loop, as step markers
		var fp: Array = UiKit.panel("Gameplay Flow", "(One Wave)")
		v.add_child(fp[0])
		fp[1].add_child(UiKit.step(1, "Plan & Deploy", "Place turrets anywhere in the field."))
		fp[1].add_child(UiKit.step(2, "Monsters Emerge", "They spawn underground, even off screen.", "upcoming"))
		fp[1].add_child(UiKit.step(3, "Battle Plays Out", "Combat is automatic. Turrets can be destroyed.", "upcoming"))
		fp[1].add_child(UiKit.step(4, "Result", "Hold the gate to win.", "upcoming"))

	var nav := UiKit.hbox(8)
	if level_index > 0:
		nav.add_child(UiKit.button("Prev", func(): start_level(level_index - 1), "secondary"))
	if level_index < unlocked:
		nav.add_child(UiKit.button("Next", func(): start_level(level_index + 1), "secondary", "next"))
	nav.add_child(UiKit.spacer())
	nav.add_child(UiKit.button("Deploy", begin_deployment if phase == Phase.BRIEFING else _close_overlay,
		"primary", "next", "lg"))
	v.add_child(nav)


func _radar_legend() -> HBoxContainer:
	var h := UiKit.hbox(12)
	for item in [["Spawn hotspot", UiKit.THREAT], ["Camera view", UiKit.FRIENDLY], ["Gate", UiKit.AMBER]]:
		var dot := ColorRect.new()
		dot.color = item[1]
		dot.custom_minimum_size = Vector2(UiKit.px(10), UiKit.px(10))
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(dot)
		h.add_child(UiKit.text(item[0], "caption", UiKit.INK_MUTED))
	return h


func _show_radar() -> void:
	var v := _open_sheet()
	var p: Array = UiKit.panel("Enemy Spawn Radar", "(Full Battlefield)",
		UiKit.button("Close", _close_overlay, "secondary", "close", "md", false, true))
	v.add_child(p[0])
	var radar := RadarView.new()
	radar.custom_minimum_size = Vector2(0, UiKit.px(440))
	radar.set_level(level, deployment)
	p[1].add_child(radar)
	p[1].add_child(_radar_legend())
	for h in level.hotspots:
		var row := UiKit.hbox(8)
		row.add_child(UiKit.tag("×%d" % level.hotspot_count(h), "threat"))
		var parts := []
		for g in h.groups:
			parts.append("%d %s Lv.%d" % [g.count, Defs.MONSTERS[g.type].name, g.level])
		var delay := "" if h.delay <= 0.0 else "  (after %ds)" % int(h.delay)
		var l := UiKit.text("%s — %s%s" % [h.name, ", ".join(parts), delay], "body")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		p[1].add_child(row)


func _show_pause() -> void:
	var v := _open_sheet()
	var p: Array = UiKit.panel("Paused")
	v.add_child(p[0])
	p[1].add_child(UiKit.text("The battle is frozen. Turrets keep their targets.", "body", UiKit.INK_MUTED))
	var row := UiKit.hbox(8)
	row.add_child(UiKit.button("Retry", retry, "secondary", "retry"))
	row.add_child(UiKit.spacer())
	row.add_child(UiKit.button("Resume", toggle_pause, "primary", "play", "lg"))
	p[1].add_child(row)


func _show_result() -> void:
	var s := sim.summary()
	var won := sim.state == BattleSim.State.VICTORY
	var v := _open_sheet()
	var pad := Control.new()
	pad.custom_minimum_size.y = UiKit.px(120)
	v.add_child(pad)
	var card := PanelContainer.new()
	var sb := UiKit.box(UiKit.PANEL, 16, UiKit.LINE, 1, 24, true)
	card.add_theme_stylebox_override("panel", sb)
	v.add_child(card)
	var c := UiKit.vbox(8)
	card.add_child(c)
	c.add_child(UiKit.text("Victory" if won else "Defeat", "result", UiKit.VITAL if won else UiKit.THREAT,
		HORIZONTAL_ALIGNMENT_CENTER))
	c.add_child(UiKit.text("The gate holds." if won else "The gate has fallen. Your deployment is saved.",
		"body", UiKit.INK_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var stats := UiKit.hbox(24)
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	for st in [["%d / %d" % [ceili(s.gate_hp), s.gate_max], "Gate HP"],
			["%d/%d" % [s.guns_survived, s.guns_total], "Turrets"],
			["%d/%d" % [s.kills, s.total_enemies], "Monsters"]]:
		var col := UiKit.vbox(0)
		var b := UiKit.text(st[0], "hud-value", UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
		b.add_theme_font_size_override("font_size", UiKit.px(22))
		col.add_child(b)
		col.add_child(UiKit.text(st[1], "caption", UiKit.INK_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		stats.add_child(col)
	var gap := Control.new()
	gap.custom_minimum_size.y = UiKit.px(8)
	c.add_child(gap)
	c.add_child(stats)
	var gap2 := Control.new()
	gap2.custom_minimum_size.y = UiKit.px(16)
	c.add_child(gap2)
	var row := UiKit.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if won:
		row.add_child(UiKit.button("Replay", retry, "secondary", "retry"))
		row.add_child(UiKit.button("Next level", next_level, "primary", "next"))
	else:
		row.add_child(UiKit.button("Retry", retry, "primary", "retry", "lg"))
	c.add_child(row)


## Drag anywhere on an open sheet to scroll it, with mouse or touch. Godot's ScrollContainer
## only drag-scrolls on touchscreens and not when the drag starts on a panel inside it.
func _input(event: InputEvent) -> void:
	if _sheet_scroll == null or not is_instance_valid(_sheet_scroll):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_from = event.position
			_drag_scroll = _sheet_scroll.scroll_vertical
			_dragging_sheet = false
		elif _dragging_sheet:
			_dragging_sheet = false
			get_viewport().set_input_as_handled()  # a drag is not a tap on a button
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		var dy: float = event.position.y - _drag_from.y
		if absf(dy) > 12.0:
			_dragging_sheet = true
		if _dragging_sheet:
			_sheet_scroll.scroll_vertical = _drag_scroll - int(dy)


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
	if _args.has("auto_deploy") or p in ["combat", "result", "pause", "deploy_full"]:
		_auto_deploy()
	match p:
		"briefing":
			_show_briefing()
		"deploy", "deploy_full":
			begin_deployment()
			if _args.has("hold"):
				var gi := _next_unplaced()
				if gi >= 0:
					select_card(gi)
					var vr := level.view_rect
					var c := vr.position + Vector2i(vr.size.x / 2, vr.size.y / 3)
					battlefield.update_ghost(c, _valid_cell(c))
		"radar":
			begin_deployment()
			_show_radar()
		"combat", "result", "pause":
			begin_deployment()
			defend()
			if p == "result":
				speed = 8.0
	if p == "pause":
		get_tree().create_timer(float(_args.get("shot_time", "3")) - 0.5).timeout.connect(toggle_pause)
	if _args.has("shot"):
		get_tree().create_timer(float(_args.get("shot_time", "1.5"))).timeout.connect(_take_shot)


func _auto_deploy() -> void:
	var vr := level.view_rect
	var n := guns.size()
	for k in n:
		var x := vr.position.x + int(round(float(k + 1) * vr.size.x / float(n + 1)))
		var c := Vector2i(x, vr.position.y + vr.size.y - 6 - (k % 2) * 3)
		while not _valid_cell(c):
			c.y -= 1
		place(k, c)


func _take_shot() -> void:
	if _shot_done:
		return
	_shot_done = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(str(_args.shot))
	print("[shot] saved ", _args.shot)
	get_tree().quit()
