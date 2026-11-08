extends Node
## North Gate game controller: BRIEFING -> DEPLOYMENT -> COMBAT -> RESULT -> retry/next.
## UI is built from scripts/ui/ui_kit.gd: painted header + counters on top, gate plate on the
## gate, deployment tray ending in DEFEND, sheets for briefing / radar, dialogs for pause / result.
##
## Screenshot/automation flags (after `--`):
##   level=05  phase=briefing|deploy|radar|combat|result|pause  shot=/path.png  shot_time=6
##   hold  auto_deploy  unlock_all

enum Phase { BRIEFING, DEPLOYMENT, COMBAT, RESULT }

const MAX_STEPS_PER_FRAME := 12
const PROGRESS_FILE := "user://progress.json"

const EDGE_PT := 12.0
const HEADER_PT := 50.0
const EMBLEM_PT := 62.0
const GATE_PILL_HEIGHT_M := 5.0
const AMMO_CHIP_HEIGHT_M := 4.6

## On-screen wording for the keys used in level data.
const GUN_UI := {
	"mg": {"name": "MG Turret", "short": "MG", "ammo": "Rounds"},
	"cannon": {"name": "Cannon", "short": "Cannon", "ammo": "Shells"},
	"sniper": {"name": "Sniper", "short": "Sniper", "ammo": "Rounds"},
}
const MONSTER_UI := {
	"burrower": {"one": "Burrower", "many": "Burrowers", "desc": "Fast diggers. Emerge in groups."},
	"stalker": {"one": "Stalker", "many": "Stalkers", "desc": "Armored and aggressive."},
	"brute": {"one": "Brute", "many": "Brutes", "desc": "Heavily armored. High durability."},
}

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
var _chips_layer: Control
var _wave_sub: Label
var _counters: Control
var _skull_val: Label
var _skull_cap: Label
var _turret_val: Label
var _turret_cap: Label
var _pause_btn: Button
var _gate_box: Control
var _gate_bar: ProgressBar
var _gate_val: Label
var _tray: Control
var _cards_box: HBoxContainer
var _cards: Array = []
var _combat_bar: Control
var _speed_label: Label
var _hint_label: Label
var _ammo_chips := {}         # gun id -> chip
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
	_pause_btn.visible = p == Phase.COMBAT
	_clear_chips()
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
	if sim.state == BattleSim.State.DEFEAT:
		battlefield.animate_breach(delta)
	else:
		battlefield.sync(clampf(_accum / Defs.SIM_DT, 0.0, 1.0))
	_refresh_hud()
	if sim.state != BattleSim.State.RUNNING:
		if _end_timer < 0.0:
			_end_timer = 1.4
			if sim.state == BattleSim.State.DEFEAT:
				_end_timer = 3.6  # let the gate fall and the breach play out
				battlefield.play_breach()
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
	var m := UiKit.px(EDGE_PT)

	# ---- turret ammo chips, under every other piece of UI
	_chips_layer = Control.new()
	_chips_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chips_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_chips_layer)

	# ---- painted header strip
	var hd := UiKit.header()
	hd[0].set_anchors_preset(Control.PRESET_TOP_WIDE)
	root.add_child(hd[0])
	_wave_sub = hd[1]

	# ---- counters + pause, under the header
	_counters = UiKit.hbox(8)
	_counters.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_counters.offset_left = m
	_counters.offset_right = -m
	_counters.offset_top = UiKit.px(HEADER_PT + 8)
	root.add_child(_counters)
	var enemies := UiKit.counter("", "Incoming")
	_counters.add_child(enemies[0])
	_skull_val = enemies[1]
	_skull_cap = enemies[2]
	_counters.add_child(UiKit.spacer())
	var turrets := UiKit.counter("turret", "Deployed")
	_counters.add_child(turrets[0])
	_turret_val = turrets[1]
	_turret_cap = turrets[2]
	_pause_btn = UiKit.icon_button("pause_solid", toggle_pause, 32, 16)
	_counters.add_child(_pause_btn)

	# ---- deployment tray: hint, tools + turret cards, DEFEND
	_tray = UiKit.vbox(7)
	_anchor_bottom(_tray, root)
	var hint := UiKit.inset(10, 3)
	var hint_row := UiKit.hbox(8)
	hint.add_child(hint_row)
	hint_row.add_child(UiKit.glyph("info", 15, UiKit.FRIENDLY))
	_hint_label = UiKit.text("", "caption")
	hint_row.add_child(_hint_label)
	_set_panel_fill(hint)
	_tray.add_child(hint)
	var row := UiKit.hbox(5)
	_tray.add_child(row)
	row.add_child(UiKit.tool_tile("Radar", _show_radar, "pin"))
	row.add_child(UiKit.tool_tile("Briefing", _show_briefing, "doc"))
	row.add_child(UiKit.tool_tile("Clear", clear_deployment, "close"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.custom_minimum_size.y = UiKit.px(66)
	row.add_child(scroll)
	_cards_box = UiKit.hbox(5)
	_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_cards_box)
	_tray.add_child(UiKit.action("Defend", defend))

	# ---- combat bar
	_combat_bar = UiKit.hbox(7)
	_anchor_bottom(_combat_bar, root)
	var auto := UiKit.inset(12, 7, UiKit.LINE)
	_set_panel_fill(auto)
	auto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var auto_row := UiKit.hbox(10)
	auto.add_child(auto_row)
	auto_row.add_child(UiKit.glyph("gear", 20))
	auto_row.add_child(UiKit.text("Automatic Defense", "label_lg"))
	_combat_bar.add_child(auto)
	var speed_btn := UiKit.icon_button("chevron", _toggle_speed, 38, 12)
	speed_btn.custom_minimum_size.x = UiKit.px(64)
	var speed_row := UiKit.hbox(2)
	speed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	speed_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_speed_label = UiKit.text("1×", "plate")
	speed_row.add_child(_speed_label)
	speed_row.add_child(UiKit.glyph("chevron", 12))
	speed_btn.get_child(0).queue_free()
	speed_btn.add_child(speed_row)
	_combat_bar.add_child(speed_btn)

	# ---- gate integrity plate, sits on the gate itself
	var gb := UiKit.gate_bar()
	_gate_box = gb[0]
	_gate_bar = gb[1]
	_gate_val = gb[2]
	root.add_child(_gate_box)
	get_viewport().size_changed.connect(_layout_gate_pill)

	# ---- overlays + toast
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_overlay)
	_toast = UiKit.text("", "label_lg", UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_toast.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toast.offset_top = UiKit.px(HEADER_PT + 50)
	_toast.add_theme_color_override("font_outline_color", UiKit.BG)
	_toast.add_theme_constant_override("outline_size", UiKit.px(4))
	_toast.modulate.a = 0.0
	root.add_child(_toast)


func _anchor_bottom(c: Control, root: Control) -> void:
	var m := UiKit.px(EDGE_PT)
	c.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN
	c.offset_left = m
	c.offset_right = -m
	c.offset_bottom = -m
	root.add_child(c)


func _set_panel_fill(p: PanelContainer) -> void:
	(p.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = UiKit.PANEL_SOLID


func _layout_gate_pill() -> void:
	# centred on the gate's upper edge, but never under the bottom controls
	if battlefield == null or battlefield.camera == null or level == null:
		return
	var s := _gate_box.get_combined_minimum_size()
	var p := battlefield.gate_screen_pos(GATE_PILL_HEIGHT_M)
	var limit := _gate_box.get_parent_control().size.y - _bottom_ui_height() - s.y - UiKit.px(8)
	_gate_box.size = s
	_gate_box.position = Vector2(p.x - s.x * 0.5, minf(p.y - s.y * 0.5, limit))


func _bottom_ui_height() -> float:
	var c: Control = _tray if phase == Phase.DEPLOYMENT else (_combat_bar if phase == Phase.COMBAT else null)
	return 0.0 if c == null else c.get_combined_minimum_size().y + UiKit.px(EDGE_PT)


func _toggle_speed() -> void:
	speed = 2.0 if speed == 1.0 else 1.0
	battlefield.sim_speed = speed
	_speed_label.text = "2×" if speed == 2.0 else "1×"


func _toast_msg(t: String, col := UiKit.INK) -> void:
	_toast.text = t
	_toast.add_theme_color_override("font_color", col)
	_toast_t = 2.5


func _art(model: String) -> Texture2D:
	var p := "res://assets/ui/art/%s.png" % model
	return load(p) if ResourceLoader.exists(p) else null


func _rebuild_cards() -> void:
	for c in _cards:
		c.queue_free()
	_cards.clear()
	for gi in guns.size():
		var g: Dictionary = guns[gi]
		var c := UiKit.turret_card("%s · %d" % [GUN_UI[g.type].short, g.ammo], _art(Defs.GUNS[g.type].model),
			select_card.bind(gi))
		_cards_box.add_child(c)
		_cards.append(c)


func _refresh() -> void:
	if level == null:
		return
	_wave_sub.text = "WAVE %s · %s" % [level.id, level.title.trim_prefix("The ").to_upper()]
	for gi in _cards.size():
		UiKit.set_card_state(_cards[gi], held == gi, _dep_of_gun(gi) >= 0)
	_hint_label.text = "Tap an open tile to place it." if held >= 0 else "Select a turret. Tap an open tile."
	_refresh_hud()
	_layout_gate_pill.call_deferred()


func _refresh_hud() -> void:
	if sim != null and phase in [Phase.COMBAT, Phase.RESULT]:
		_skull_val.text = str(sim.remaining_enemies())
		_skull_cap.text = "REMAINING"
		var alive := 0
		for g in sim.guns:
			if g.alive:
				alive += 1
		_turret_val.text = str(alive)
		_turret_cap.text = "TURRET" if alive == 1 else "TURRETS"
		UiKit.set_gate(_gate_bar, _gate_val, sim.gate_hp, level.gate_max_hp)
		_refresh_chips()
	else:
		_skull_val.text = str(level.total_enemies())
		_skull_cap.text = "INCOMING"
		_turret_val.text = "%d / %d" % [deployment.size(), guns.size()]
		_turret_cap.text = "DEPLOYED"
		UiKit.set_gate(_gate_bar, _gate_val, level.gate_max_hp, level.gate_max_hp)


func _clear_chips() -> void:
	for id in _ammo_chips:
		_ammo_chips[id].queue_free()
	_ammo_chips.clear()


func _refresh_chips() -> void:
	if phase != Phase.COMBAT:
		return
	for g in sim.guns:
		if not _ammo_chips.has(g.id):
			var made := UiKit.ammo_chip()
			_chips_layer.add_child(made)
			_ammo_chips[g.id] = made
		var chip: PanelContainer = _ammo_chips[g.id]
		chip.visible = g.alive
		if not g.alive:
			continue
		UiKit.set_ammo_chip(chip, g.ammo, g.max_ammo)
		var s := chip.get_combined_minimum_size()
		chip.size = s
		chip.position = battlefield.gun_screen_pos(g.id, AMMO_CHIP_HEIGHT_M) - Vector2(s.x * 0.5, s.y)


# ================================================================== overlays

func _close_overlay() -> void:
	_sheet_scroll = null
	for c in _overlay.get_children():
		c.queue_free()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sync_chrome(false)


## Field controls for the current phase; full-screen sheets hide them.
func _sync_chrome(sheet_open: bool) -> void:
	_tray.visible = phase == Phase.DEPLOYMENT and not sheet_open
	_combat_bar.visible = phase == Phase.COMBAT and not sheet_open
	_gate_box.visible = phase != Phase.BRIEFING and not sheet_open
	_counters.visible = phase in [Phase.DEPLOYMENT, Phase.COMBAT] and not sheet_open


## A scrollable sheet that fills the screen under the header.
func _open_sheet() -> VBoxContainer:
	_close_overlay()
	_sync_chrome(true)
	_toast_t = 0.0
	_toast.modulate.a = 0.0
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = UiKit.px(EDGE_PT)
	scroll.offset_right = -UiKit.px(EDGE_PT)
	scroll.offset_top = UiKit.px(HEADER_PT + 8)
	scroll.offset_bottom = -UiKit.px(EDGE_PT)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER  # drag to scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_overlay.add_child(scroll)
	_sheet_scroll = scroll
	var v := UiKit.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(v)
	return v


## A fixed-width dialog column centred over the field, nudged up by `raise_pt`.
func _open_dialog(width_pt: float, raise_pt: float, emblem: Control) -> VBoxContainer:
	_close_overlay()
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_top = UiKit.px(HEADER_PT)
	center.offset_bottom = -UiKit.px(raise_pt)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)
	var col := UiKit.vbox(0)
	col.add_theme_constant_override("separation", -UiKit.px(EMBLEM_PT * 0.5))
	col.custom_minimum_size.x = UiKit.px(width_pt)
	center.add_child(col)
	var holder := CenterContainer.new()
	holder.z_index = 1
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(emblem)
	col.add_child(holder)
	var p: Array = UiKit.panel(16, 8)
	col.add_child(p[0])
	return p[1]


func _show_briefing() -> void:
	var s := _open_sheet()
	var p: Array = UiKit.panel(12, 5)
	s.add_child(p[0])
	var v: VBoxContainer = p[1]

	var head := UiKit.hbox(6)
	var title_col := UiKit.vbox(0)
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.titled(title_col, level.title, "Mission Briefing")
	head.add_child(title_col)
	if level_index > 0:
		head.add_child(UiKit.icon_button("chevron_left", func(): start_level(level_index - 1), 30, 14))
	if level_index < unlocked:
		head.add_child(UiKit.icon_button("chevron", func(): start_level(level_index + 1), 30, 14))
	v.add_child(head)

	v.add_child(UiKit.image(load("res://assets/ui/art/hero_gate.jpg"), 0, 72, true))

	var gate := UiKit.hbox(8)
	gate.add_child(UiKit.text("Gate Integrity", "label"))
	gate.add_child(UiKit.spacer())
	gate.add_child(UiKit.text("%d / %d" % [level.gate_max_hp, level.gate_max_hp], "label"))
	v.add_child(gate)
	var bar := UiKit.vital_bar(4)
	bar.max_value = 1.0
	bar.value = 1.0
	v.add_child(bar)
	v.add_child(UiKit.rule())

	v.add_child(UiKit.section("Incoming · %d" % level.total_enemies()))
	for e in level.enemy_summary():
		var ui: Dictionary = MONSTER_UI[e.type]
		var noun: String = ui.one if e.count == 1 else ui.many
		v.add_child(UiKit.enemy_row("%d %s · Lv %d" % [e.count, noun, e.level], ui.desc,
			_art(Defs.MONSTERS[e.type].model)))

	v.add_child(UiKit.section("Available Defenses", UiKit.AMBER, "label_lg"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", UiKit.px(6))
	grid.add_theme_constant_override("v_separation", UiKit.px(6))
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for g in guns:
		var ui: Dictionary = GUN_UI[g.type]
		grid.add_child(UiKit.defense_card(ui.name, "%d %s" % [g.ammo, ui.ammo], _art(Defs.GUNS[g.type].model)))
	v.add_child(grid)

	var preview := UiKit.inset(10, 7, UiKit.LINE_DIM)
	var pr := UiKit.hbox(10)
	preview.add_child(pr)
	var cap := UiKit.vbox(-2)
	cap.alignment = BoxContainer.ALIGNMENT_CENTER
	cap.add_child(UiKit.text("Spawn", "label_lg"))
	cap.add_child(UiKit.text("Preview", "label_lg"))
	pr.add_child(cap)
	var radar := RadarView.new()
	radar.compact = true
	radar.custom_minimum_size = Vector2(0, UiKit.px(70))
	radar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radar.set_level(level, deployment)
	pr.add_child(radar)
	v.add_child(preview)

	v.add_child(UiKit.action("Plan Deployment", begin_deployment if phase == Phase.BRIEFING else _close_overlay))


func _show_radar() -> void:
	var s := _open_sheet()
	var p: Array = UiKit.panel(15, 10)
	s.add_child(p[0])
	var v: VBoxContainer = p[1]
	UiKit.titled(v, "Enemy Spawn Radar", "Full Battlefield")
	var radar := RadarView.new()
	radar.custom_minimum_size = Vector2(0, UiKit.px(345))
	radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radar.set_level(level, deployment)
	v.add_child(radar)

	var stats := UiKit.inset(8, 6, UiKit.LINE)
	var row := UiKit.hbox(6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_child(row)
	var totals := {}
	for e in level.enemy_summary():
		totals[e.type] = int(totals.get(e.type, 0)) + int(e.count)
	var first := true
	for type in totals:
		if not first:
			row.add_child(UiKit.slash(UiKit.LINE, 22))
		first = false
		var col := UiKit.vbox(-3)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UiKit.text(str(totals[type]), "plate", UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
		var ui: Dictionary = MONSTER_UI[type]
		col.add_child(UiKit.text(ui.one if totals[type] == 1 else ui.many, "label", UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
		row.add_child(col)
	v.add_child(stats)
	v.add_child(_radar_legend())
	s.add_child(UiKit.action("Back to Deployment", _close_overlay))


func _radar_legend() -> HBoxContainer:
	var h := UiKit.hbox(8)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	var dot := PanelContainer.new()
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = UiKit.THREAT
	dsb.set_corner_radius_all(UiKit.px(6))
	dot.add_theme_stylebox_override("panel", dsb)
	dot.custom_minimum_size = Vector2.ONE * UiKit.px(11)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(dot)
	h.add_child(UiKit.text("Spawn hotspot", "caption"))
	var gap := Control.new()
	gap.custom_minimum_size.x = UiKit.px(22)
	h.add_child(gap)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.3), 0, UiKit.LINE, 1))
	frame.custom_minimum_size = Vector2(UiKit.px(26), UiKit.px(15))
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(frame)
	h.add_child(UiKit.text("Visible battlefield", "caption"))
	return h


func _show_pause() -> void:
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL, 6, UiKit.LINE, 1.4))
	tile.custom_minimum_size = Vector2.ONE * UiKit.px(EMBLEM_PT * 0.8)
	var c := CenterContainer.new()
	c.add_child(UiKit.glyph("pause_solid", 22))
	tile.add_child(c)
	var v := _open_dialog(290, 170, tile)
	v.add_child(UiKit.gap(EMBLEM_PT * 0.4))
	v.add_child(UiKit.text("Battle Paused", "title", UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.rule(UiKit.LINE))
	v.add_child(UiKit.gap(2))
	v.add_child(UiKit.text("Simulation is paused.", "body", UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.text("Your deployment remains locked.", "caption", UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.image(load("res://assets/ui/art/pause_gate.jpg"), 0, 70, true))
	v.add_child(UiKit.action("Resume Battle", toggle_pause, "primary", "play_solid", "left"))
	v.add_child(UiKit.action("Adjust Deployment", retry, "secondary", ""))
	v.add_child(UiKit.text("Restarts this wave with your placement saved.", "caption", UiKit.INK,
		HORIZONTAL_ALIGNMENT_CENTER))


func _show_result() -> void:
	var s := sim.summary()
	var won := sim.state == BattleSim.State.VICTORY
	var accent := UiKit.FRIENDLY if won else UiKit.THREAT
	var emblem := UiKit.image(load("res://assets/ui/glyphs/emblem_%s.svg" % ("held" if won else "breached")),
		EMBLEM_PT, EMBLEM_PT)
	var v := _open_dialog(320, 230, emblem)

	var top := UiKit.hbox(0)
	top.add_child(UiKit.rule(UiKit.LINE))
	var hole := Control.new()
	hole.custom_minimum_size.x = UiKit.px(EMBLEM_PT + 8)
	top.add_child(hole)
	top.add_child(UiKit.rule(UiKit.LINE))
	v.add_child(top)
	v.add_child(UiKit.gap(EMBLEM_PT * 0.3))
	v.add_child(UiKit.text("Gate Held" if won else "Gate Breached", "result", UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	var sub := UiKit.text("Victory" if won else "Defeat", "plate", accent, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(sub)
	v.add_child(UiKit.rule(accent, 0, 1.2))
	v.add_child(UiKit.text("%s secured." % level.title if won else "Your deployment has been saved.",
		"body", UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER))

	var table := UiKit.inset(10, 4, UiKit.LINE)
	var rows := UiKit.vbox(3)
	table.add_child(rows)
	var data := [["Gate Integrity", "%d / %d" % [ceili(s.gate_hp), s.gate_max]],
		["Hostiles Eliminated", "%d / %d" % [s.kills, s.total_enemies]],
		["Turrets Survived", "%d / %d" % [s.guns_survived, s.guns_total]]]
	for i in data.size():
		if i > 0:
			rows.add_child(UiKit.rule(UiKit.LINE_DIM))
		rows.add_child(UiKit.stat_row(data[i][0], data[i][1]))
	v.add_child(table)

	var empty := 0
	for g in sim.guns:
		if g.ammo <= 0:
			empty += 1
	if empty > 0:
		var note := UiKit.hbox(6)
		note.alignment = BoxContainer.ALIGNMENT_CENTER
		note.add_child(UiKit.slash(UiKit.AMBER, 11))
		note.add_child(UiKit.slash(UiKit.AMBER, 11))
		note.add_child(UiKit.text("%d %s exhausted %s ammunition." % [empty, "turret" if empty == 1 else "turrets",
			"its" if empty == 1 else "their"], "caption", UiKit.INK))
		v.add_child(note)

	v.add_child(UiKit.gap(2))
	if won:
		v.add_child(UiKit.action("Next Wave", next_level))
		v.add_child(UiKit.action("Replay Wave", retry, "secondary", ""))
	else:
		v.add_child(UiKit.action("Adjust Deployment", retry, "primary", ""))
		v.add_child(UiKit.text("Return to planning with your turrets in place.", "caption", UiKit.INK,
			HORIZONTAL_ALIGNMENT_CENTER))


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
	if _args.has("weak"):  # one turret in a corner: lets monsters reach the gate (screenshots)
		place(0, level.view_rect.position + Vector2i(0, 1))
	elif _args.has("auto_deploy") or p in ["combat", "result", "pause", "deploy_full"]:
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
