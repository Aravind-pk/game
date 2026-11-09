extends Node
## North Gate game controller: BRIEFING -> DEPLOYMENT -> COMBAT -> RESULT -> retry/next.
## UI is built from scripts/ui/ui_kit.gd: painted header + counters on top, gate plate on the
## gate, deployment tray ending in DEFEND, sheets for briefing / radar, dialogs for pause / result.
##
## Screenshot/automation flags (after `--`):
##   level=05  phase=briefing|deploy|radar|combat|result|pause  shot=/path.png  shot_time=6
##   hold  auto_deploy  unlock_all  hint=3 (presses Hint that many times once deployment is open)

enum Phase { BRIEFING, DEPLOYMENT, COMBAT, RESULT }

const MAX_STEPS_PER_FRAME := 12
const PROGRESS_FILE := "user://progress.json"

const EDGE_PT := 12.0
const HEADER_PT := 50.0
const EMBLEM_PT := 62.0
const AMMO_CHIP_HEIGHT_M := 4.6
const FOCUS_X_HEIGHT_M := 4.6
const CARRY_START_PX := 14.0
const LEVEL_GRID_COLUMNS := 4
const GATE_PLATE_ABOVE_FOOT_PT := 6.0

## On-screen wording for the keys used in level data.
const GUN_UI := {
	"mg": {"name": "MG Turret", "short": "MG", "ammo": "Rounds"},
	"cannon": {"name": "Cannon", "short": "Cannon", "ammo": "Shells"},
	"sniper": {"name": "Sniper", "short": "Sniper", "ammo": "Rounds"},
	"decoy": {"name": "Decoy", "short": "Decoy", "ammo": ""},
	"rigged": {"name": "Rigged Decoy", "short": "Rigged", "ammo": ""},
}
const MONSTER_UI := {
	"burrower": {"one": "Burrower", "many": "Burrowers", "desc": "Swarm. Attacks turrets near its route.", "counter": ["mg", "cannon"]},
	"stalker": {"one": "Runner", "many": "Runners", "desc": "Fast. Slips past slow turrets.", "counter": ["mg", "sniper"]},
	"brute": {"one": "Brute", "many": "Brutes", "desc": "Armoured, 300 HP. MG rounds barely scratch it.", "counter": ["cannon", "sniper"]},
}

var battlefield: Battlefield
var level_paths: Array = []
var level_index := 0
var unlocked := 0
var _cleared := {}            # level index -> true, for every level won
var _level_titles: Array[String] = []
var level: LevelData
var guns: Array = []          # one entry per available turret: {type, level, ammo}
var deployment: Array = []    # [{type, level, ammo, cell, gun}]
var _orders := {}             # gun index -> order key, from the wave's small order budget
var held := -1                # index into guns currently held for placement
var focused := -1             # index into guns of the placed turret selected for moving or removing
var phase := Phase.BRIEFING
var sim: BattleSim
var speed := 1.0
var paused := false
var _accum := 0.0
var _end_timer := -1.0
var _log: Array = []          # key moments of the current battle: [{t, kind, text}]
var _ammo_seen := {}          # gun id -> ammo last frame, to notice a turret running dry
var _first_brute_t := -1.0
var _seen_hotspots := {}
var _breach_hotspot := -1     # hotspot of the first monster to hit the gate
var _depleted_shown := false
var _last_dep: Array = []     # the layout of the last battle, ghosted on retry
var _last_cause := ""         # one-line reason the last battle was lost
var _last_breach := -1
var _stars := {}              # level index -> best stars earned
var _tutorials_seen := {}     # wave id -> true once its coach cards were read
var _tutorial_step := -1
var _tutorial_card: Control
var _speed_btns: Array = []
var _ticker: VBoxContainer
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
var _remove_x: Button
var _carry_gun := -1          # turret being dragged, or -1
var _carry_home := Vector2i(-1, -1)  # where it stood before the drag, if it was placed
var _carry_press := -1        # card pressed but not yet moved far enough to count as a drag
var _carry_press_pos := Vector2.ZERO
var _suppress_card_tap := false
var _combat_bar: Control
var _hint_label: Label
var _hint_box: Control
var _order_btn: Button
var _ammo_chips := {}         # gun id -> chip
var _overlay: Control
var _toast: Label
var _toast_t := 0.0
var _sheet_scroll: ScrollContainer   # the open Panel sheet, for drag-to-scroll
var _drag_from := Vector2.ZERO
var _drag_scroll := 0
var _dragging_sheet := false

# hints: the first taps give written clues, then a marked area, then the exact tile
var _hint_slot := {}          # the solution slot currently marked on the field
var _hint_text := ""
var _hint_dep_hash := 0       # the layout a written clue was given for
var _hints_used := 0
var _intel_shown := 0
var _hint_solution := -1      # once a hint points at a solution, later hints follow the same one


func _ready() -> void:
	RenderingServer.set_default_clear_color(UiKit.BG)  # tall phones see past the painting's bottom edge
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
	battlefield.drag_started.connect(_on_drag_started)
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
	battlefield.set_last_plan([], -1)
	_last_cause = ""
	battlefield.build(level)
	guns.clear()
	for g in level.guns:
		for k in int(g.count):
			guns.append({"type": g.type, "level": g.level, "ammo": g.ammo})
	deployment.clear()
	for g in level.fixed:  # holdouts are part of the layout from the start; gun -1 means not movable
		deployment.append({"type": g.type, "level": g.level, "ammo": g.ammo, "cell": g.cell, "gun": -1})
	held = -1
	focused = -1
	_orders.clear()
	sim = null
	_hints_used = 0
	_intel_shown = 0
	_hint_solution = -1
	_clear_hint_mark()
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
	if TUTORIALS.has(level.id) and (not _tutorials_seen.has(level.id) or _args.has("tutorial")):
		_tutorial_step = 0
		_show_tutorial()


## Wave 01 only: three cards that name the field's markings once. Every later wave shows the
## markings without words.
## Each new mechanic is named once, on the wave that brings it in.
const TUTORIALS := {
	"01": [
		["Routes", "Monsters follow the dashed red lines to the gate. Turrets bend them."],
		["Range", "Pick up a turret: it hits anything inside the blue ring. Closer hits harder."],
		["Lure", "Monsters inside the dashed red ring leave their route and attack the turret."],
	],
	"02": [["Blind zone", "The Cannon splashes groups but can't fire inside its hatched ring. Keep it behind the line."]],
	"03": [["Sniper", "One shot kills a runner. It reaches across the field but carries few rounds."]],
	"04": [["Orders", "Brutes shrug off MG fire. Select the Cannon and set Heavy only to save its shells for them."]],
}


func _show_tutorial() -> void:
	if is_instance_valid(_tutorial_card):
		_tutorial_card.queue_free()
	var cards: Array = TUTORIALS.get(level.id, [])
	if _tutorial_step < 0 or _tutorial_step >= cards.size():
		return
	var p: Array = UiKit.panel(11, 6)
	var card: PanelContainer = p[0]
	(card.get_theme_stylebox("panel") as StyleBoxFlat).border_color = UiKit.FRIENDLY
	card.set_anchors_preset(Control.PRESET_TOP_WIDE)
	card.offset_left = UiKit.px(EDGE_PT)
	card.offset_right = -UiKit.px(EDGE_PT + 120)
	card.offset_top = UiKit.px(HEADER_PT + 10)
	var v: VBoxContainer = p[1]
	var head := UiKit.hbox(8)
	head.add_child(UiKit.text(cards[_tutorial_step][0], "label", UiKit.FRIENDLY))
	head.add_child(UiKit.spacer())
	if cards.size() > 1:
		head.add_child(UiKit.text("%d / %d" % [_tutorial_step + 1, cards.size()], "small", UiKit.INK_MUTED))
	v.add_child(head)
	var body := UiKit.text(cards[_tutorial_step][1], "body")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(body)
	var next := UiKit.action("Next" if _tutorial_step < cards.size() - 1 else "Got it", _tutorial_next, "secondary", "")
	next.custom_minimum_size.y = UiKit.px(34)
	v.add_child(next)
	_ui.get_child(0).add_child(card)
	_tutorial_card = card


func _tutorial_next() -> void:
	_tutorial_step += 1
	if _tutorial_step >= TUTORIALS.get(level.id, []).size():
		_end_tutorial()
	else:
		_show_tutorial()


func _end_tutorial() -> void:
	if _tutorial_step >= 0:
		_tutorials_seen[level.id] = true
		_save_progress()
	_tutorial_step = -1
	if is_instance_valid(_tutorial_card):
		_tutorial_card.queue_free()
	_tutorial_card = null


func defend() -> void:
	if _placed_count() == 0:
		_toast_msg("Deploy at least one turret.", UiKit.THREAT)
		return
	held = -1
	focused = -1
	battlefield.set_held("")
	_clear_hint_mark()
	deployment = BattleSim.canonical_order(deployment)
	battlefield.show_deployment(deployment)  # turret nodes are numbered like the sim's turrets
	sim = BattleSim.new()
	sim.setup(level, deployment)
	battlefield.begin_battle(sim)
	battlefield.sim_speed = speed
	_accum = 0.0
	_end_timer = -1.0
	_set_speed(speed if speed in [1.0, 2.0, 4.0] else 1.0)
	if _args.get("phase", "") == "result":
		speed = 8.0
	_log.clear()
	_ammo_seen.clear()
	_first_brute_t = -1.0
	_seen_hotspots.clear()
	_breach_hotspot = -1
	_depleted_shown = false
	_last_dep = deployment.duplicate(true)
	_end_tutorial()
	_set_phase(Phase.COMBAT)
	_refresh_ticker()


func retry() -> void:
	# the previous deployment is kept so the player adjusts instead of starting over
	sim = null
	battlefield.sim = null
	battlefield.set_last_plan(_last_dep, _last_breach)
	_set_phase(Phase.DEPLOYMENT)


func _is_last_level() -> bool:
	return level_index + 1 >= level_paths.size()


## The campaign ends on its last wave: there is no next level to wrap around to.
func next_level() -> void:
	if not _is_last_level():
		start_level(level_index + 1)


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
		_record(sim.events)
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
	if sim.state == BattleSim.State.RUNNING and not _depleted_shown and _defense_spent():
		_depleted_shown = true
		_show_depleted()
		return
	if sim.state != BattleSim.State.RUNNING:
		if _end_timer < 0.0:
			_end_timer = 1.4
			if sim.state == BattleSim.State.DEFEAT:
				_end_timer = 3.6  # let the gate fall and the breach play out
				battlefield.play_breach()
		_end_timer -= delta
		if _end_timer <= 0.0:
			_finish_battle()


## Everything that happens once a battle is over, whether watched or skipped.
func _finish_battle() -> void:
	if sim.state == BattleSim.State.VICTORY:
		unlocked = maxi(unlocked, mini(level_index + 1, level_paths.size() - 1))
		_cleared[level_index] = true
		_stars[level_index] = maxi(int(_stars.get(level_index, 0)), _stars_earned())
		_save_progress()
		_last_cause = ""
		_last_breach = -1
	else:
		_last_cause = _cause()
		_last_breach = _breach_hotspot
	_set_phase(Phase.RESULT)
	if _args.has("retry"):
		retry.call_deferred()


## Runs the rest of the battle at once and goes to the result.
func skip_battle() -> void:
	if phase != Phase.COMBAT or sim == null:
		return
	paused = false
	while sim.state == BattleSim.State.RUNNING:
		sim.step()
		_record(sim.events)
		sim.events.clear()
	_finish_battle()


## Nothing left that can hurt a monster while some are still coming: the wave is lost.
func _defense_spent() -> bool:
	if sim.remaining_enemies() == 0:
		return false
	for g in sim.guns:
		if g.alive and (int(g.ammo) > 0 or float(g.blast) > 0.0):
			return false
	return true


## "Cannon", or "MG West" / "MG 2" when the wave has more than one of that turret.
func _gun_name(g: Dictionary) -> String:
	var same := sim.guns.filter(func(x): return x.type == g.type)
	if same.size() < 2:
		return GUN_UI[g.type].name
	if same.size() == 2:
		var other: Dictionary = same[1] if same[0].id == g.id else same[0]
		if absf(other.pos.x - g.pos.x) >= Defs.CELL:
			return "%s %s" % [GUN_UI[g.type].short, "Left" if g.pos.x < other.pos.x else "Right"]
		return "%s %s" % [GUN_UI[g.type].short, "Front" if g.pos.y < other.pos.y else "Back"]
	return "%s %d" % [GUN_UI[g.type].short, same.find(g) + 1]


## Turns the simulation's events into the few moments a player cares about.
func _record(events: Array) -> void:
	var t := sim.time
	for e in events:
		match e.type:
			"emerge":
				var m: Dictionary = sim.monsters[e.monster]
				if not _seen_hotspots.has(e.hotspot):
					_seen_hotspots[e.hotspot] = true
					if m.type != "brute":
						_log_moment(t, "%s surfacing · %s" % [MONSTER_UI[m.type].many, level.hotspots[e.hotspot].name], "info")
				if m.type == "brute":
					if _first_brute_t < 0.0:
						_first_brute_t = t
					var n := sim.monsters.filter(func(x): return x.type == "brute").size()
					_log_moment(t, "Brute %d surfaced" % n, "brute")
			"gun_destroyed":
				_log_moment(t, "%s destroyed" % _gun_name(sim.guns[e.gun]), "lost")
			"gate_hit":
				if _breach_hotspot < 0:
					_breach_hotspot = int(sim.monsters[e.monster].hotspot)
					_log_moment(t, "Gate under attack", "lost")
	for g in sim.guns:
		var before := int(_ammo_seen.get(g.id, g.max_ammo))
		if before > 0 and int(g.ammo) == 0 and int(g.max_ammo) > 0:
			_log_moment(t, "%s out of %s" % [_gun_name(g), GUN_UI[g.type].ammo.to_lower()], "empty")
		elif before > 1 and int(g.ammo) == 1 and int(g.max_ammo) <= 10:
			_log_moment(t, "%s · 1 %s left" % [_gun_name(g), GUN_UI[g.type].ammo.to_lower().trim_suffix("s")], "empty")
		_ammo_seen[g.id] = int(g.ammo)


func _log_moment(t: float, text: String, kind: String) -> void:
	_log.append({"t": t, "text": text, "kind": kind})
	if phase == Phase.COMBAT:
		_refresh_ticker()


static func _clock(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


## One line on why the wave was lost, built from what actually happened.
func _cause() -> String:
	for g in sim.guns:
		if g.type in ["cannon", "sniper"] and _first_brute_t >= 0.0 and int(g.ammo) == 0:
			for m in _log:
				if m.kind == "empty" and m.text == "%s out of %s" % [_gun_name(g), GUN_UI[g.type].ammo.to_lower()] \
						and m.t < _first_brute_t + 2.0:
					return "The %s spent every %s before the brutes arrived." % [_gun_name(g),
						GUN_UI[g.type].ammo.to_lower().trim_suffix("s")]
	var lost := sim.guns.filter(func(x): return not x.alive and int(x.max_ammo) > 0)
	if lost.size() > 0:
		var gun: Dictionary = lost[0]
		var at := ""
		for m in _log:
			if m.kind == "lost" and m.text == "%s destroyed" % _gun_name(gun):
				at = " at %s" % _clock(m.t)
		if float(gun.min_range) > 0.0:
			return "%s was destroyed%s. Monsters got inside its blind zone." % [_gun_name(gun), at]
		return "%s was destroyed%s. Monsters near a route attack turrets." % [_gun_name(gun), at]
	if _defense_spent():
		return "Every turret ran dry with %d still coming." % sim.remaining_enemies()
	return "%d monsters got through to the gate." % sim.remaining_enemies()


## The three stars, in the order their tiles are shown: gate held, gate untouched, and at least
## a fifth of the ammunition left. The last two are independent of each other.
func _star_flags() -> Array[bool]:
	var total := 0
	var left := 0
	for g in sim.guns:
		total += int(g.max_ammo)
		left += int(g.ammo)
	return [true, sim.gate_hp >= level.gate_max_hp, total > 0 and float(left) / float(total) >= 0.2]


func _stars_earned() -> int:
	return _star_flags().count(true)


# ================================================================== placement

func _valid_cell(c: Vector2i) -> bool:
	return level.is_deployable(c) and _dep_at(c) < 0


func _placed_count() -> int:
	return deployment.filter(func(d): return d.gun >= 0).size()


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
	if phase != Phase.DEPLOYMENT or _suppress_card_tap:
		return
	if _dep_of_gun(gi) >= 0:  # a placed turret is selected, so it can be found, moved or removed
		held = -1
		focused = -1 if focused == gi else gi
	else:
		focused = -1
		held = -1 if held == gi else gi
	battlefield.set_held(guns[held].type if held >= 0 else "")
	_refresh()


func remove_gun(gi: int) -> void:
	var di := _dep_of_gun(gi)
	if di < 0:
		return
	deployment.remove_at(di)
	focused = -1
	battlefield.show_deployment(deployment)
	_refresh()


func place(gi: int, c: Vector2i) -> bool:
	if not _valid_cell(c) or _dep_of_gun(gi) >= 0:
		return false
	var g: Dictionary = guns[gi]
	deployment.append({"type": g.type, "level": g.level, "ammo": g.ammo, "cell": c, "gun": gi,
		"order": _orders.get(gi, "")})
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
		var di: int = battlefield.pressed_gun if battlefield.pressed_gun >= 0 else _dep_at(c)
		if di >= 0 and deployment[di].gun < 0:
			_toast_msg("This holdout is dug in.")
		elif di >= 0:
			focused = -1 if focused == deployment[di].gun else deployment[di].gun
		else:
			focused = -1
	_refresh()


func _on_drag_started(cell: Vector2i) -> void:
	if phase != Phase.DEPLOYMENT or held >= 0:
		return
	var di: int = battlefield.pressed_gun if battlefield.pressed_gun >= 0 else _dep_at(cell)
	if di < 0 or deployment[di].gun < 0:
		return
	battlefield.cancel_press()
	_begin_carry(deployment[di].gun)


# ------------------------------------------------------------------ dragging turrets

## Lifts a turret, from its card or from the field, and shows it following the pointer.
func _begin_carry(gi: int) -> void:
	_carry_home = Vector2i(-1, -1)
	var di := _dep_of_gun(gi)
	if di >= 0:
		_carry_home = deployment[di].cell
		deployment.remove_at(di)
		battlefield.show_deployment(deployment)
	_carry_gun = gi
	held = gi
	focused = -1
	battlefield.set_held(guns[gi].type)
	_refresh()


## Drops the carried turret: on a free tile it goes there, on the tray it is put away,
## anywhere else it returns to where it was.
func _drop_carry(c: Vector2i, over_tray: bool) -> void:
	var gi := _carry_gun
	var home := _carry_home
	_carry_gun = -1
	_carry_home = Vector2i(-1, -1)
	held = -1
	battlefield.set_held("")
	if not over_tray:
		if not place(gi, c):
			if home.x >= 0:
				place(gi, home)
			_toast_msg("Invalid tile", UiKit.THREAT)
	battlefield.show_deployment(deployment)
	_refresh()


func _card_at(pos: Vector2) -> int:
	for gi in _cards.size():
		var card: Button = _cards[gi]
		if not card.get_global_rect().has_point(pos):
			continue
		var remove := card.find_child("Remove", true, false) as Control
		return -1 if remove.visible and remove.get_global_rect().has_point(pos) else gi
	return -1


## Returns true when the event belonged to a turret drag.
func _handle_carry(event: InputEvent) -> bool:
	if phase != Phase.DEPLOYMENT:
		return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_carry_press = _card_at(event.position) if _carry_gun < 0 and _tray.visible else -1
			_carry_press_pos = event.position
			return false
		_carry_press = -1
		if _carry_gun < 0:
			return false
		_drop_carry(battlefield.screen_to_cell(event.position), _tray.get_global_rect().has_point(event.position))
		_suppress_card_tap = true
		set_deferred("_suppress_card_tap", false)
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventMouseMotion:
		if _carry_press >= 0 and event.position.distance_to(_carry_press_pos) > CARRY_START_PX:
			var gi := _carry_press
			_carry_press = -1
			_begin_carry(gi)
		if _carry_gun >= 0:
			var c := battlefield.screen_to_cell(event.position)
			battlefield.update_ghost(c, _valid_cell(c))
			get_viewport().set_input_as_handled()
			return true
	return false


func _on_hover(c: Vector2i) -> void:
	if phase == Phase.DEPLOYMENT and held >= 0:
		battlefield.update_ghost(c, _valid_cell(c))


func clear_deployment() -> void:
	deployment = deployment.filter(func(d): return d.gun < 0)
	held = -1
	focused = -1
	battlefield.show_deployment(deployment)
	battlefield.set_held("")
	_refresh()


# ================================================================== hints

func _clear_hint_mark() -> void:
	_hint_slot = {}
	_hint_text = ""
	battlefield.clear_hint()


func _say_hint(line: String) -> void:
	_hint_slot = {}
	battlefield.clear_hint()
	_hint_text = line
	_hint_dep_hash = deployment.hash()
	_refresh()


func request_hint() -> void:
	if phase != Phase.DEPLOYMENT:
		return
	var step := LevelHints.next_step(level, deployment, _hint_solution)
	if step.is_empty():
		_toast_msg("No hints for this wave.")
		return
	if step.solved:
		_say_hint("This layout holds the gate. Press Defend.")
		return
	_hints_used += 1
	if _last_cause != "" and _intel_shown == 0 and _hint_text != _last_cause:
		_say_hint(_last_cause)
		return
	if _intel_shown < mini(level.intel.size(), 2):
		_intel_shown += 1
		_say_hint(level.intel[_intel_shown - 1])
		return
	# a second tap on the same target narrows the marked area down to the exact tile
	_hint_solution = int(step.get("solution", -1))
	var slot: Dictionary = step.slot
	var exact: bool = not _hint_slot.is_empty() and _hint_slot.cell == slot.cell
	_hint_slot = slot
	var verb := "Move" if step.move else "Place"
	_hint_text = "%s %s %s %s." % [verb, "an" if slot.type == "mg" else "a", GUN_UI[slot.type].name,
		"on the marked tile" if exact else "inside the marked area"]
	battlefield.show_hint([slot.cell] if exact else slot.zone, exact)
	_refresh()


## A hint stops applying once the player has acted on it.
func _sync_hint() -> void:
	if not _hint_slot.is_empty():
		var step := LevelHints.next_step(level, deployment, _hint_solution)
		if step.is_empty() or step.solved or step.slot.cell != _hint_slot.cell:
			_clear_hint_mark()
	elif _hint_text != "" and deployment.hash() != _hint_dep_hash:
		_hint_text = ""


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

	# ---- counters + pause, in the right side of the header so the field below stays clear
	_counters = UiKit.hbox(5)
	_counters.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_counters.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_counters.offset_right = -UiKit.px(8)
	_counters.offset_top = UiKit.px((HEADER_PT - 32.0) * 0.5)
	root.add_child(_counters)
	var enemies := UiKit.counter("", "Incoming")
	_counters.add_child(enemies[0])
	_skull_val = enemies[1]
	_skull_cap = enemies[2]
	_skull_cap.visible = false
	var turrets := UiKit.counter("turret", "Deployed")
	_counters.add_child(turrets[0])
	_turret_val = turrets[1]
	_turret_cap = turrets[2]
	_turret_cap.visible = false
	_pause_btn = UiKit.icon_button("pause_solid", toggle_pause, 32, 16)
	_counters.add_child(_pause_btn)

	# ---- deployment tray: hint, turret cards, tools + DEFEND
	_tray = UiKit.vbox(7)
	_anchor_bottom(_tray, root)
	var hint := UiKit.inset(10, 3)
	var hint_row := UiKit.hbox(8)
	hint.add_child(hint_row)
	hint_row.add_child(UiKit.glyph("info", 15, UiKit.FRIENDLY))
	_hint_label = UiKit.text("", "caption")
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_row.add_child(_hint_label)
	_set_panel_fill(hint)
	_tray.add_child(hint)
	_hint_box = hint
	_order_btn = UiKit.order_button(toggle_order)
	_order_btn.visible = false
	_tray.add_child(_order_btn)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  # a drag on a card lifts the turret
	scroll.custom_minimum_size.y = UiKit.px(58)
	_tray.add_child(scroll)
	_cards_box = UiKit.hbox(5)
	_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_cards_box)
	var row := UiKit.hbox(5)
	_tray.add_child(row)
	row.add_child(UiKit.icon_button("radar", _show_radar, 50, 22))
	row.add_child(UiKit.icon_button("bulb", request_hint, 50, 22))
	row.add_child(UiKit.icon_button("close", clear_deployment, 50, 20))
	var defend_btn := UiKit.action("Defend", defend)
	defend_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(defend_btn)

	# ---- combat bar: the last three key moments, then speed and skip
	_combat_bar = UiKit.vbox(6)
	_anchor_bottom(_combat_bar, root)
	var tbox := UiKit.inset(10, 5, UiKit.LINE_DIM)
	(tbox.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = UiKit.PANEL_GLASS
	_ticker = UiKit.vbox(2)
	tbox.add_child(_ticker)
	_combat_bar.add_child(tbox)
	var crow := UiKit.hbox(6)
	_combat_bar.add_child(crow)
	for n in [1, 2, 4]:
		var b := UiKit.speed_button("%d×" % n, _set_speed.bind(float(n)))
		crow.add_child(b)
		_speed_btns.append(b)
	var skip := UiKit.action("Skip", skip_battle, "secondary", "skip")
	skip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skip.custom_minimum_size.y = UiKit.px(46)
	crow.add_child(skip)

	# ---- gate integrity plate, sits on the gate itself
	var gb := UiKit.gate_bar()
	_gate_box = gb[0]
	_gate_bar = gb[1]
	_gate_val = gb[2]
	root.add_child(_gate_box)
	_remove_x = UiKit.remove_button(func(): remove_gun(focused), 36)
	_remove_x.visible = false
	root.add_child(_remove_x)
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
	# on the gate door itself, never in the field where turrets go
	if battlefield == null or battlefield.level == null or level == null:
		return
	var s := _gate_box.get_combined_minimum_size()
	var p := battlefield.wall_foot_screen_pos()
	_gate_box.size = s
	# on the door, or just above the bottom controls when they cover the door
	var y := p.y - s.y - UiKit.px(GATE_PLATE_ABOVE_FOOT_PT)
	var root_h := _gate_box.get_parent_control().size.y
	y = minf(y, root_h - _bottom_ui_height() - s.y - UiKit.px(6))
	_gate_box.position = Vector2(p.x - s.x * 0.5, y)


func _bottom_ui_height() -> float:
	var c: Control = _tray if phase == Phase.DEPLOYMENT else (_combat_bar if phase == Phase.COMBAT else null)
	return 0.0 if c == null else c.get_combined_minimum_size().y + UiKit.px(EDGE_PT)


func _set_speed(v: float) -> void:
	speed = v
	battlefield.sim_speed = speed
	for i in _speed_btns.size():
		UiKit.set_speed_button(_speed_btns[i], [1.0, 2.0, 4.0][i] == speed)


func _refresh_ticker() -> void:
	for c in _ticker.get_children():
		c.queue_free()
	var recent := _log.slice(maxi(0, _log.size() - 3))
	recent.reverse()
	for k in 3:
		var line := UiKit.hbox(8)
		line.custom_minimum_size.y = UiKit.px(18)
		if k < recent.size():
			var m: Dictionary = recent[k]
			line.modulate.a = 1.0 - 0.28 * k
			line.add_child(UiKit.text(_clock(m.t), "small", UiKit.INK_MUTED))
			var col: Color = {"brute": UiKit.AMBER, "lost": UiKit.THREAT, "empty": UiKit.AMBER}.get(m.kind, UiKit.INK)
			line.add_child(UiKit.text(m.text, "small", col))
		_ticker.add_child(line)
	(_ticker.get_parent() as Control).modulate.a = 0.0 if _log.is_empty() else 1.0  # keeps its space, so the gate plate never jumps


func _toast_msg(t: String, col := UiKit.INK) -> void:
	_toast.text = t
	_toast.add_theme_color_override("font_color", col)
	_toast_t = 2.5


var _art_cache := {}

## Tray art for a turret type. Decoys reuse the MG art, washed amber (Decoy) or red (Rigged Decoy),
## so a card never reads as a live turret.
func _gun_art(type: String) -> Texture2D:
	var base := _art(Defs.GUNS[type].model)
	if base == null or Defs.GUNS[type].damage > 0.0:
		return base
	if not _art_cache.has(type):
		var img := base.get_image()
		img.decompress()
		var tint := Color("#ff6b63") if Defs.GUNS[type].blast > 0.0 else Color("#f2b13a")
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				var l := 0.25 + 0.75 * c.get_luminance()
				img.set_pixel(x, y, Color(tint.r * l, tint.g * l, tint.b * l, c.a))
		_art_cache[type] = ImageTexture.create_from_image(img)
	return _art_cache[type]


func _art(model: String) -> Texture2D:
	var p := "res://assets/ui/art/%s.png" % model
	return load(p) if ResourceLoader.exists(p) else null


func _rebuild_cards() -> void:
	for c in _cards:
		c.queue_free()
	_cards.clear()
	for gi in guns.size():
		var g: Dictionary = guns[gi]
		var label: String = GUN_UI[g.type].short if g.ammo <= 0 else "%s · %d" % [GUN_UI[g.type].short, g.ammo]
		var c := UiKit.turret_card(label, _gun_art(g.type),
			select_card.bind(gi), remove_gun.bind(gi))
		_cards_box.add_child(c)
		_cards.append(c)


func _refresh() -> void:
	if level == null:
		return
	_wave_sub.text = _subtitle()
	for gi in _cards.size():
		UiKit.set_card_state(_cards[gi], held == gi or focused == gi, _dep_of_gun(gi) >= 0, focused == gi)
	_update_focus()
	_sync_order_button()
	_sync_hint()
	if _hint_text != "":
		_hint_label.text = _hint_text
	else:
		if focused >= 0:
			_hint_label.text = "Drag it to move it, or tap the X to remove it."
		elif held >= 0:
			_hint_label.text = "Tap an open tile to place it."
		else:
			_hint_label.text = "Tap a turret, then a tile. Or drag it onto the field."
	_refresh_hud()
	_layout_gate_pill.call_deferred()


## Header subtitle: the wave name while reading, the step once on the field.
func _subtitle() -> String:
	match phase:
		Phase.DEPLOYMENT:
			return "WAVE %s · DEPLOY" % level.id
		Phase.COMBAT:
			var t := int(sim.time) if sim != null else 0
			return "WAVE %s · %d:%02d" % [level.id, t / 60, t % 60]
		Phase.RESULT:
			return "WAVE %s · DEBRIEF" % level.id
	return "WAVE %s · %s" % [level.id, level.title.trim_prefix("The ").to_upper()]


func _orders_left() -> int:
	return level.order_budget() - _orders.size()


## Gives or takes back the selected turret's one order.
func toggle_order() -> void:
	if focused < 0:
		return
	var key := Defs.order_for(guns[focused].type)
	if key == "":
		return
	if _orders.has(focused):
		_orders.erase(focused)
	elif _orders_left() > 0:
		_orders[focused] = key
	else:
		_toast_msg("No orders left this wave.", UiKit.THREAT)
		return
	var di := _dep_of_gun(focused)
	if di >= 0:
		deployment[di].order = _orders.get(focused, "")
	battlefield.show_deployment(deployment)
	_refresh()


func _sync_order_button() -> void:
	var key := Defs.order_for(guns[focused].type) if focused >= 0 and phase == Phase.DEPLOYMENT else ""
	var show := key != "" and level.order_budget() > 0 and _dep_of_gun(focused) >= 0
	_order_btn.visible = show
	_hint_box.visible = not show
	if show:
		UiKit.set_order_button(_order_btn, Defs.ORDERS[key].label, Defs.MONSTERS[Defs.ORDERS[key].target].model,
			_orders.has(focused), _orders_left(), level.order_budget())


## Marks the selected turret's tile and floats its X above it.
func _update_focus() -> void:
	var di := _dep_of_gun(focused) if focused >= 0 else -1
	var showing := di >= 0 and phase == Phase.DEPLOYMENT
	_remove_x.visible = showing
	if showing:
		battlefield.show_focus(deployment[di].cell)
		battlefield.show_focus_rings(deployment[di].cell, deployment[di].type)
		_remove_x.position = battlefield.gun_screen_pos(di, FOCUS_X_HEIGHT_M) - _remove_x.size * 0.5
	else:
		battlefield.clear_focus()
		battlefield.clear_focus_rings()


func _refresh_hud() -> void:
	if phase == Phase.COMBAT:
		_wave_sub.text = _subtitle()
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
		_turret_val.text = "%d/%d" % [_placed_count(), guns.size()]
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
		chip.visible = g.alive and g.max_ammo > 0
		if not chip.visible:
			continue
		UiKit.set_ammo_chip(chip, g.ammo, g.max_ammo)
		var s := chip.get_combined_minimum_size()
		chip.size = s
		var p := battlefield.gun_screen_pos(g.id, AMMO_CHIP_HEIGHT_M) - Vector2(s.x * 0.5, s.y)
		var w := _chips_layer.size.x
		chip.position = Vector2(clampf(p.x, UiKit.px(4), w - s.x - UiKit.px(4)), p.y)


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
	var scrim := ColorRect.new()  # reading screens sit on a dark wash, so the field never competes
	scrim.color = Color(UiKit.BG, 0.88)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.offset_top = UiKit.px(HEADER_PT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(scrim)
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
	# a sheet scrolls down, never sideways: content is held to the screen width and long lines wrap
	v.custom_minimum_size.x = get_viewport().get_visible_rect().size.x - UiKit.px(EDGE_PT * 2)
	scroll.resized.connect(func(): v.custom_minimum_size.x = scroll.size.x)
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
	s.add_child(UiKit.stepper(0))
	var p: Array = UiKit.panel(12, 7)
	s.add_child(p[0])
	var v: VBoxContainer = p[1]

	var head := UiKit.hbox(6)
	var title := UiKit.text(level.title, "title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	head.add_child(title)
	if level_index > 0:
		head.add_child(UiKit.icon_button("chevron_left", func(): start_level(level_index - 1), 30, 14))
	if level_index < unlocked:
		head.add_child(UiKit.icon_button("chevron", func(): start_level(level_index + 1), 30, 14))
	v.add_child(head)

	var gate := UiKit.hbox(8)
	gate.add_child(UiKit.text("Gate Integrity", "label"))
	gate.add_child(UiKit.spacer())
	gate.add_child(UiKit.text("%d / %d" % [level.gate_max_hp, level.gate_max_hp], "label"))
	v.add_child(gate)
	var bar := UiKit.vital_bar(4)
	bar.max_value = 1.0
	bar.value = 1.0
	v.add_child(bar)
	v.add_child(UiKit.text(_gate_tolerance(), "caption", UiKit.INK_MUTED))

	v.add_child(UiKit.section("Incoming · %d" % level.total_enemies()))
	for e in level.enemy_summary():
		var ui: Dictionary = MONSTER_UI[e.type]
		var noun: String = ui.one if e.count == 1 else ui.many
		var counters := []
		for c in ui.counter:
			if guns.any(func(g): return g.type == c):
				counters.append(GUN_UI[c].name)
		v.add_child(UiKit.enemy_row("%d %s" % [e.count, noun], ui.desc,
			_art(Defs.MONSTERS[e.type].model), counters))

	var turrets_head := UiKit.section("Your Turrets · %d" % guns.size(), UiKit.AMBER)
	if level.order_budget() > 0:
		turrets_head.add_child(UiKit.spacer())
		turrets_head.add_child(UiKit.text("Orders · %d" % level.order_budget(), "small", UiKit.AMBER))
	v.add_child(turrets_head)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", UiKit.px(6))
	grid.add_theme_constant_override("v_separation", UiKit.px(6))
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var counts := {}
	for g in guns:
		counts[g.type] = int(counts.get(g.type, 0)) + 1
	for type in counts:
		var g: Dictionary = guns.filter(func(x): return x.type == type)[0]
		var ui: Dictionary = GUN_UI[type]
		var name_line: String = ui.short if counts[type] == 1 else "%s ×%d" % [ui.short, counts[type]]
		var ammo_line: String = "No ammo" if g.ammo <= 0 else "%d %s" % [g.ammo, ui.ammo]
		grid.add_child(UiKit.defense_card(name_line, ammo_line, _gun_art(type)))
	v.add_child(grid)
	if level.note != "":
		var note := UiKit.text(level.note, "caption", UiKit.INK_MUTED)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(note)

	if phase == Phase.BRIEFING:
		s.add_child(UiKit.action("Next · Recon", _show_recon))
	else:
		s.add_child(UiKit.action("Back to Deployment", _close_overlay, "secondary", ""))


## How much punishment the gate takes, in the wave's own monsters.
func _gate_tolerance() -> String:
	var parts := []
	for e in level.enemy_summary():
		var hit: float = Defs.monster_stats(e.type, e.level).damage
		var n := int(ceil(level.gate_max_hp / hit))
		parts.append("%d %s %s" % [n, MONSTER_UI[e.type].one.to_lower(), "hit" if n == 1 else "hits"])
	return "Falls after %s." % " or ".join(parts)


## One line on how range works for the turrets in this wave.
func _range_rules() -> String:
	var types := {}
	for g in guns:
		types[g.type] = true
	var parts := []
	if types.has("mg"):
		parts.append("MG Turrets lose damage at long range.")
	var close := []
	for type in ["cannon", "sniper"]:
		if types.has(type):
			close.append(GUN_UI[type].name + "s")
	if close.size() > 0:
		parts.append("%s can't hit targets close to them." % " and ".join(close))
	if types.has("decoy") or types.has("rigged"):
		parts.append("Monsters stop to attack decoys.")
	if types.has("rigged"):
		parts.append("Rigged Decoys explode when destroyed.")
	return " ".join(parts)


## Every level as a small card. Waves past the first uncleared one are locked, like the
## briefing's next arrow (`unlock_all` opens them for testing).
func _show_levels(back: Callable) -> void:
	var s := _open_sheet()
	var p: Array = UiKit.panel(12, 8)
	s.add_child(p[0])
	var v: VBoxContainer = p[1]
	UiKit.titled(v, "Select Level", "%d of %d cleared" % [_cleared.size(), level_paths.size()])
	var grid := GridContainer.new()
	grid.columns = LEVEL_GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", UiKit.px(5))
	grid.add_theme_constant_override("v_separation", UiKit.px(5))
	v.add_child(grid)
	var titles := _titles_of_levels()
	for i in level_paths.size():
		grid.add_child(UiKit.level_card(i + 1, titles[i], _cleared.has(i), i == level_index, _play_level.bind(i),
			int(_stars.get(i, 0)), i > unlocked))
	s.add_child(UiKit.action("Back", back, "secondary", ""))


func _titles_of_levels() -> Array[String]:
	if _level_titles.is_empty():
		for path in level_paths:
			var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
			_level_titles.append(str(data.title))
	return _level_titles


func _play_level(i: int) -> void:
	paused = false
	battlefield.sim = null
	start_level(i)


func _show_radar() -> void:
	_show_recon()


## Step 2 of every wave: where they come from, the path they take, and when they arrive.
func _show_recon() -> void:
	var s := _open_sheet()
	var entering := phase == Phase.BRIEFING
	if entering:
		s.add_child(UiKit.stepper(1))
	var p: Array = UiKit.panel(12, 8)
	s.add_child(p[0])
	var v: VBoxContainer = p[1]
	v.add_child(UiKit.section("Spawn Map"))
	var radar := RadarView.new()
	radar.custom_minimum_size = Vector2(0, UiKit.px(300))
	radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radar.set_level(level, deployment)
	v.add_child(radar)

	var tp: Array = UiKit.panel(12, 6)
	s.add_child(tp[0])
	var tv: VBoxContainer = tp[1]
	tv.add_child(UiKit.section("Timeline"))
	var timeline := ReconTimeline.new()
	timeline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timeline.set_level(level, deployment)
	tv.add_child(timeline)

	var row := UiKit.hbox(8)
	if entering:
		var back := UiKit.action("Back", _show_briefing, "secondary", "")
		back.custom_minimum_size = Vector2(UiKit.px(100), UiKit.px(50))
		row.add_child(back)
		var go := UiKit.action("Deploy", begin_deployment)
		go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(go)
	else:
		var close := UiKit.action("Back to Deployment", _close_overlay, "secondary", "")
		close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(close)
	s.add_child(row)


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
	v.add_child(UiKit.action("All Levels", _show_levels.bind(_show_pause), "secondary", ""))
	v.add_child(UiKit.text("Restarts this wave with your placement saved.", "caption", UiKit.INK,
		HORIZONTAL_ALIGNMENT_CENTER))


func _show_result() -> void:
	if sim.state == BattleSim.State.VICTORY:
		_show_victory()
	else:
		_show_report()


func _show_victory() -> void:
	var s := sim.summary()
	var emblem := UiKit.image(load("res://assets/ui/glyphs/emblem_held.svg"), EMBLEM_PT, EMBLEM_PT)
	var v := _open_dialog(320, 200, emblem)
	v.add_child(UiKit.gap(EMBLEM_PT * 0.45))
	v.add_child(UiKit.text("Gate Held", "result", UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.text("Victory", "plate", UiKit.FRIENDLY, HORIZONTAL_ALIGNMENT_CENTER))
	var flags := _star_flags()
	var earned := flags.count(true)
	var row := UiKit.hbox(6)
	for k in 3:
		row.add_child(UiKit.star_tile(["Held", "Untouched", "20% Ammo"][k], flags[k]))
	v.add_child(row)
	var table := UiKit.inset(10, 4, UiKit.LINE)
	var rows := UiKit.vbox(3)
	table.add_child(rows)
	var total := 0
	for g in sim.guns:
		total += int(g.max_ammo)
	var data := [["Gate Integrity", "%d / %d" % [ceili(s.gate_hp), s.gate_max]],
		["Hostiles Eliminated", "%d / %d" % [s.kills, s.total_enemies]],
		["Ammunition Left", "%d%%" % (roundi(100.0 * s.ammo_left / maxf(total, 1)))]]
	for i in data.size():
		if i > 0:
			rows.add_child(UiKit.rule(UiKit.LINE_DIM))
		rows.add_child(UiKit.stat_row(data[i][0], data[i][1]))
	v.add_child(table)
	if _is_last_level():
		var total_stars := 0
		for k in _stars:
			total_stars += int(_stars[k])
		v.add_child(UiKit.text("Campaign complete · %d / %d stars" % [total_stars, level_paths.size() * 3],
			"label", UiKit.AMBER, HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(UiKit.action("All Levels", _show_levels.bind(_show_result)))
	else:
		v.add_child(UiKit.action("Next Wave", next_level))
	v.add_child(UiKit.action("Replay for 3 stars" if earned < 3 else "Replay Wave", retry, "secondary", ""))
	if not _is_last_level():
		v.add_child(UiKit.action("All Levels", _show_levels.bind(_show_result), "secondary", ""))


## The after-action report: what went wrong, the key moments, and how each turret did.
func _show_report() -> void:
	var s := _open_sheet()
	var p: Array = UiKit.panel(12, 8)
	s.add_child(p[0])
	var v: VBoxContainer = p[1]
	var head := UiKit.hbox(8)
	var title := UiKit.text("Gate Breached", "title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UiKit.text("Defeat · %s" % _clock(sim.time), "small", UiKit.THREAT))
	v.add_child(head)

	var cause := UiKit.inset(10, 7, UiKit.THREAT)
	var cv := UiKit.vbox(3)
	cause.add_child(cv)
	cv.add_child(UiKit.text("Cause", "small", UiKit.THREAT))
	var line := UiKit.text(_last_cause, "body")
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(line)
	var tip := _report_tip()
	if tip != "":
		var tip_label := UiKit.text(tip, "small", UiKit.FRIENDLY)
		tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(tip_label)
	v.add_child(cause)

	v.add_child(UiKit.section("Key Moments", UiKit.THREAT, "label_lg"))
	var moments := _key_moments(7)
	for m in moments:
		var r := UiKit.hbox(8)
		r.add_child(UiKit.text(_clock(m.t), "small", UiKit.INK_MUTED))
		var col: Color = {"brute": UiKit.AMBER, "lost": UiKit.THREAT, "empty": UiKit.AMBER}.get(m.kind, UiKit.INK)
		var moment := UiKit.text(m.text, "small", col)
		moment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		moment.clip_text = true
		r.add_child(moment)
		v.add_child(r)

	v.add_child(UiKit.section("Turrets", UiKit.AMBER, "label_lg"))
	var table := UiKit.inset(10, 4, UiKit.LINE)
	var rows := UiKit.vbox(2)
	table.add_child(rows)
	for g in sim.guns:
		if int(g.max_ammo) <= 0:
			continue
		var r := UiKit.hbox(8)
		var n := UiKit.text(_gun_name(g), "small")
		n.custom_minimum_size.x = UiKit.px(96)
		r.add_child(n)
		var used := UiKit.text("%d / %d" % [int(g.max_ammo) - int(g.ammo), int(g.max_ammo)], "small")
		used.custom_minimum_size.x = UiKit.px(70)
		r.add_child(used)
		var note := "Standing" if g.alive else "Lost"
		var ncol := UiKit.INK_MUTED if g.alive else UiKit.THREAT
		if g.alive and int(g.ammo) == 0:
			note = "Ran dry"
			ncol = UiKit.AMBER
		r.add_child(UiKit.text(note, "small", ncol))
		rows.add_child(r)
	v.add_child(table)

	var row := UiKit.hbox(8)
	var levels := UiKit.action("Waves", _show_levels.bind(_show_result), "secondary", "")
	levels.custom_minimum_size = Vector2(UiKit.px(100), UiKit.px(50))
	row.add_child(levels)
	var adjust := UiKit.action("Adjust Deployment", retry, "primary", "")
	adjust.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(adjust)
	s.add_child(row)


## Up to `n` moments, keeping losses and empty turrets over routine ones, in time order.
func _key_moments(n: int) -> Array:
	var rank := {"lost": 0, "empty": 1, "brute": 2, "info": 3}
	var picked := _log.duplicate()
	picked.sort_custom(func(a, b): return rank.get(a.kind, 3) < rank.get(b.kind, 3) or (rank.get(a.kind, 3) == rank.get(b.kind, 3) and a.t < b.t))
	picked = picked.slice(0, n)
	picked.sort_custom(func(a, b): return a.t < b.t)
	return picked


## A next step to try, only when the game can point at one.
func _report_tip() -> String:
	if _last_cause.begins_with("The Cannon") and level.order_budget() > 0:
		return "Try · Cannon order: Heavy only"
	for type in ["cannon", "sniper"]:
		if _last_cause.begins_with(GUN_UI[type].name) and "destroyed" in _last_cause:
			return "Try · move it back: it can't fire inside the hatched ring"
	if "destroyed" in _last_cause:
		return "Try · keep it out of the red lure rings"
	if "ran dry" in _last_cause:
		return "Try · move a turret back toward the gate"
	return ""


## Shown the moment a battle can no longer be won.
func _show_depleted() -> void:
	paused = true
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL, 6, UiKit.AMBER, 1.4))
	tile.custom_minimum_size = Vector2.ONE * UiKit.px(EMBLEM_PT * 0.8)
	var c := CenterContainer.new()
	var slashes := UiKit.hbox(4)
	slashes.add_child(UiKit.slash(UiKit.AMBER, 22))
	slashes.add_child(UiKit.slash(UiKit.AMBER, 22))
	c.add_child(slashes)
	tile.add_child(c)
	var v := _open_dialog(300, 170, tile)
	v.add_child(UiKit.gap(EMBLEM_PT * 0.4))
	v.add_child(UiKit.text("Defense Depleted", "title", UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.text("Decided at %s" % _clock(sim.time), "small", UiKit.THREAT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.text("All turrets are empty. %d remain." % sim.remaining_enemies(), "body", UiKit.INK,
		HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.action("See Report", skip_battle))
	v.add_child(UiKit.action("Watch to End", func():
		paused = false
		_close_overlay(), "secondary", ""))


## Drag anywhere on an open sheet to scroll it, with mouse or touch. Godot's ScrollContainer
## only drag-scrolls on touchscreens and not when the drag starts on a panel inside it.
func _input(event: InputEvent) -> void:
	if _handle_carry(event):
		return
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
		for i in d.get("cleared", []):
			_cleared[int(i)] = true
		var st = d.get("stars", {})
		if st is Dictionary:
			for k in st:
				_stars[int(k)] = int(st[k])
		var seen = d.get("tutorials", {})
		if seen is Dictionary:
			_tutorials_seen = seen


func _save_progress() -> void:
	var f := FileAccess.open(PROGRESS_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"unlocked": unlocked, "cleared": _cleared.keys(),
			"stars": _stars, "tutorials": _tutorials_seen}))


# ================================================================== automation (screenshots / CI)

func _apply_automation() -> void:
	if _args.has("unlock_all"):
		unlocked = level_paths.size() - 1
	var p := str(_args.get("phase", ""))
	if _args.has("weak"):  # one turret in a corner: lets monsters reach the gate (screenshots)
		place(0, level.view_rect.position + Vector2i(1, 1))
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
		"recon":
			_show_recon()
		"levels":
			begin_deployment()
			_show_levels(_close_overlay)
		"combat", "result", "pause":
			begin_deployment()
			defend()
			if p == "result":
				speed = 8.0
	for i in int(_args.get("hint", "0")):
		request_hint()
	if p == "pause":
		get_tree().create_timer(float(_args.get("shot_time", "3")) - 0.5).timeout.connect(toggle_pause)
	if _args.has("focus") and _placed_count() > 0:
		var pick: Dictionary = deployment[deployment.size() - 1]
		for d in deployment:
			if d.type == str(_args.focus):
				pick = d
		select_card(pick.gun)
		if _args.has("order"):
			toggle_order()
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
