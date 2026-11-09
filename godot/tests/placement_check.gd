extends SceneTree
## Drives the deployment controls with real pointer events on the real game screen.
##
##   godot --headless --path godot --script res://tests/placement_check.gd

var _failures := 0
var _game: Node


func _initialize() -> void:
	_game = load("res://scenes/main.tscn").instantiate()
	root.add_child(_game)
	_run.call_deferred()


func _run() -> void:
	_game.begin_deployment()
	await process_frame
	await process_frame
	var open := _open_tiles()
	var a: Vector2i = open[0]
	var b: Vector2i = open[open.size() - 1]
	_expect(a != b, "the level has open tiles to test with")

	_game.select_card(0)
	_game._on_cell_tapped(a)
	_expect(_placed(0) == a, "tap a card, then a tile, places the turret")
	_expect(_game.held == -1, "nothing stays held after placing")
	_expect(_game._cards.size() == _game.guns.size(), "every turret keeps its card after placing")

	_game.select_card(0)
	_expect(_game.focused == 0 and _game._remove_x.visible, "tapping a placed card selects it and shows the X")
	_expect(_game.battlefield._focus_cell == a, "its deployed tile is highlighted")
	_expect(_placed(0) == a, "selecting does not pick it up")
	_game.select_card(0)
	_expect(_game.focused == -1 and not _game._remove_x.visible, "tapping again deselects it")

	_game._on_cell_tapped(a)
	_expect(_game.focused == 0, "tapping the turret on the field selects it too")
	_game._on_cell_tapped(b)
	_expect(_game.focused == -1 and _placed(0) == a, "tapping open ground deselects without moving")

	_game.select_card(0)
	_game._remove_x.pressed.emit()
	_expect(_placed(0).x < 0 and _game.focused == -1, "the X removes the turret")

	var card: Button = _game._cards[0]
	_drag(card.get_global_rect().get_center(), _screen(a))
	_expect(_placed(0) == a, "dragging a card onto the field places the turret")
	_drag(card.get_global_rect().get_center(), _screen(b))
	_expect(_placed(0) == b, "dragging a placed turret's card moves it")

	var bf = _game.battlefield
	var body: Vector2 = _screen(b) - Vector2(0.0, bf.GUN_TOUCH_RISE_PX) * bf._world.scale
	_expect(bf.gun_at(body) == _game._dep_of_gun(0), "the turret's body is a touch target")
	_expect(bf.gun_at(body + Vector2(150.0, 0.0) * bf._world.scale) == -1, "a tap well clear of it misses")
	_field_drag(body, _screen(a))
	_expect(_placed(0) == a, "dragging the turret by its body moves it")
	_field_tap(_screen(a) - Vector2(30.0, 70.0) * bf._world.scale)
	_expect(_game.focused == 0, "tapping near the top of the turret selects it")
	_game.select_card(0)
	_field_drag(_screen(a) - Vector2(0.0, bf.GUN_TOUCH_RISE_PX) * bf._world.scale, _screen(b))
	_expect(_placed(0) == b, "it can be dragged back")

	_game._begin_carry(0)
	_game._drop_carry(Vector2i(-5, -5), false)
	_expect(_placed(0) == b, "dropping on a bad tile puts it back")
	_drag(card.get_global_rect().get_center(), _game._tray.get_global_rect().get_center())
	_expect(_placed(0).x < 0, "dragging it to the tray takes it off the field")
	_expect(_game.held == -1 and _game._carry_gun == -1, "no drag is left running")

	_game._show_levels(_game._close_overlay)
	_expect(_game._sheet_scroll != null, "the levels screen opens")
	var total: int = _game.level_paths.size()
	_game._play_level(total - 1)
	_expect(_game.level_index == total - 1, "choosing a card starts that level, even the last one")
	_expect(_game.phase == _game.Phase.BRIEFING, "it opens on that level's briefing")

	print("FAIL" if _failures else "PASS", " placement_check, failures: ", _failures)
	quit(1 if _failures else 0)


func _open_tiles() -> Array:
	var tiles := []
	var view: Rect2i = _game.level.view_rect
	for y in range(view.position.y + 2, view.end.y - 2):
		for x in range(view.position.x + 1, view.end.x - 1):
			var cell := Vector2i(x, y)
			# Tiles under the tray can't be reached with the pointer.
			if _game._valid_cell(cell) and not _game._tray.get_global_rect().has_point(_screen(cell)):
				tiles.append(cell)
	return tiles


func _placed(gi: int) -> Vector2i:
	var di: int = _game._dep_of_gun(gi)
	return Vector2i(-1, -1) if di < 0 else _game.deployment[di].cell


func _screen(cell: Vector2i) -> Vector2:
	var bf = _game.battlefield
	return bf._world.get_transform() * bf.to_world(_game.level.cell_center(cell))


func _drag(from: Vector2, to: Vector2) -> void:
	_mouse_button(from, true)
	_mouse_move((from + to) * 0.5)
	_mouse_move(to)
	_mouse_button(to, false)


## Sends pointer events the way the engine does: the game first, then the field if unclaimed.
func _field_event(e: InputEvent) -> void:
	if not _game._handle_carry(e):
		_game.battlefield._unhandled_input(e)


func _field_tap(at: Vector2) -> void:
	_field_event(_button_event(at, true))
	_field_event(_button_event(at, false))


func _field_drag(from: Vector2, to: Vector2) -> void:
	_field_event(_button_event(from, true))
	for k in [0.3, 0.7, 1.0]:
		var e := InputEventMouseMotion.new()
		e.position = from.lerp(to, k)
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
		_field_event(e)
	_field_event(_button_event(to, false))


func _button_event(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = at
	return e


func _mouse_button(at: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = at
	_game._input(e)


func _mouse_move(at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	_game._input(e)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("  failed: ", what)
