class_name Battlefield
extends Node2D
## Draws the battle in 2D: a painted field, sprites sorted by ground position, and effects.
## Reads BattleSim state and never changes it, so battles stay deterministic.

signal cell_tapped(cell: Vector2i)
signal cell_dragged(from: Vector2i, to: Vector2i)
signal hover_changed(cell: Vector2i)

const PX_PER_M := UnitView.PX_PER_M
const DEPTH := UnitView.DEPTH
const RISE := UnitView.RISE
const DESIGN_WIDTH := 1080.0
const VIEW_NORTH_OFFSET_M := 8.0      # the screen centre sits this far south of the middle of the view
const BACKGROUND := "res://assets/backgrounds/north_gate_field.jpg"
const PAINTED_DOORS_CENTRE := Vector2(0, 448)   # the doors in the painting, from the screen centre
const PAINTED_DOORS_SIZE := Vector2(300, 166)

const MONSTER_KITS := {"burrower": "burrower"}   # monster types with a full sprite kit
const TURRET_KITS := {"kestrel": "kestrel"}      # turret models with a full sprite kit
const STAND_IN_ART := "res://assets/ui/art/%s.png"
const STAND_IN_WIDTH_M := {"stalker": 2.4, "brute": 3.8, "mule": 3.2, "needle": 2.8}
const MONSTER_BAR_HEIGHT_M := {"burrower": 2.7, "stalker": 2.7, "brute": 4.2}
const TURRET_BAR_HEIGHT_M := 3.6
const DEPLOY_DRAG_PX := 14.0
const CRATER_WIDTH_M := 6.5
const GATE_HIT_TREMOR_PX := 7.0
const TURRET_HIT_TREMOR_PX := 3.5
const TREMOR_DECAY := 0.002       # share of the tremor left after one second
const TREMOR_MIN_PX := 0.15

var level: LevelData
var sim: BattleSim
var input_enabled := false
var sim_speed := 1.0  # battle speed multiplier (animations follow it)

var _world: Node2D                # everything; scaled to fit the screen, moved for camera shake
var _entities: Node2D             # y-sorted units and obstacles
var _fx_root: Node2D
var _gate: Node2D
var _gate_cracks: Node2D
var _gate_hole: Polygon2D
var _gate_flash: ColorRect
var _gate_state := "intact"
var _grid: CellOverlay
var _hint: CellOverlay
var _hint_tween: Tween
var _ghost: Node2D
var _ghost_ring: RangeRing
var _gun_nodes := {}              # deployment index / sim gun id -> UnitView
var _monster_nodes := {}          # monster id -> UnitView
var _hotspot_glows: Array[Sprite2D] = []
var _focus := Vector2.ZERO        # simulation point at the centre of the screen
var _additive: CanvasItemMaterial
var _dot: Texture2D
var _press_cell := Vector2i(-1, -1)
var _press_pos := Vector2.ZERO
var _dragging := false
var _breaching := false
var _breach_t := 0.0
var _tremor := 0.0                # current screen shake strength, in pixels


# ================================================================== setup

func build(lv: LevelData) -> void:
	level = lv
	for c in get_children():
		c.queue_free()
	_gun_nodes.clear()
	_monster_nodes.clear()
	_hotspot_glows.clear()
	_ghost = null
	_hint = null
	_breaching = false
	_gate_state = "intact"
	var vr := level.view_rect
	_focus = Vector2((vr.position.x + vr.size.x * 0.5) * Defs.CELL,
		(vr.position.y * Defs.CELL + level.wall_row * Defs.CELL) * 0.5 + VIEW_NORTH_OFFSET_M)
	_additive = CanvasItemMaterial.new()
	_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_world = Node2D.new()
	add_child(_world)
	var painting := Sprite2D.new()
	painting.texture = load(BACKGROUND)
	_world.add_child(painting)
	_build_hotspots()
	_grid = _make_grid()
	_grid.visible = false
	_build_gate()
	_entities = Node2D.new()
	_entities.y_sort_enabled = true
	_world.add_child(_entities)
	_fx_root = Node2D.new()
	_world.add_child(_fx_root)
	_build_obstacles()
	_fit_to_screen()
	if not get_viewport().size_changed.is_connected(_fit_to_screen):
		get_viewport().size_changed.connect(_fit_to_screen)


func _fit_to_screen() -> void:
	if _world == null:
		return
	var view := get_viewport_rect().size
	_world.position = view * 0.5
	_world.scale = Vector2.ONE * view.x / DESIGN_WIDTH


## Ground position in metres to a point in the world layer, optionally lifted off the ground.
func to_world(p: Vector2, height := 0.0) -> Vector2:
	return Vector2((p.x - _focus.x) * PX_PER_M, (p.y - _focus.y) * PX_PER_M * DEPTH - height * RISE * PX_PER_M)


func _cell_rect(c: Vector2i) -> Rect2:
	var top_left := to_world(Vector2(c) * Defs.CELL)
	return Rect2(top_left, Vector2(Defs.CELL * PX_PER_M, Defs.CELL * PX_PER_M * DEPTH))


## Fills each blocked rectangle with painted props: long runs of barriers and broken wall
## side to side, rubble down the columns, and a large piece on the square blocks.
func _build_obstacles() -> void:
	for i in level.obstacles.size():
		var r: Rect2i = level.obstacles[i]
		if r.size.x >= 2 and r.size.y >= 2:
			_place_prop("rocks" if i % 2 == 0 else "rubble", r, 1.15)
		elif r.size.x >= 2:
			var c := r.position.x
			while c < r.end.x:
				var piece := mini(2, r.end.x - c)
				var art := "rubble" if piece == 1 else ("barrier" if (c + i) % 2 == 0 else "broken_wall")
				_place_prop(art, Rect2i(c, r.position.y, piece, 1), 1.05)
				c += piece
		elif r.size.y >= 2:
			for k in r.size.y:
				_place_prop("rubble" if (k + i) % 2 == 0 else "rocks", Rect2i(r.position.x, r.position.y + k, 1, 1), 1.2)
		else:
			_place_prop(["cabinet", "rocks", "rubble"][i % 3], r, 0.8 if i % 3 == 0 else 1.15)


## Stands a prop on the front edge of its cells, so it sorts correctly against units.
func _place_prop(art: String, cells: Rect2i, width_share: float) -> void:
	var texture: Texture2D = load("res://assets/sprites/props/%s.png" % art)
	var prop := Sprite2D.new()
	prop.texture = texture
	prop.centered = false
	var size := texture.get_size()
	prop.offset = Vector2(-size.x * 0.5, -size.y)
	prop.scale = Vector2.ONE * cells.size.x * Defs.CELL * PX_PER_M * width_share / size.x
	var front := Vector2((cells.position.x + cells.size.x * 0.5) * Defs.CELL, (cells.position.y + cells.size.y) * Defs.CELL)
	prop.position = to_world(front)
	_entities.add_child(prop)


## The gate itself is part of the painting. Damage is drawn on top of its doors.
func _build_gate() -> void:
	_gate = Node2D.new()
	_gate.position = PAINTED_DOORS_CENTRE
	_world.add_child(_gate)
	var half := PAINTED_DOORS_SIZE * 0.5
	_gate_cracks = Node2D.new()
	for line in [[Vector2(-0.8, -1), Vector2(-0.45, -0.3), Vector2(-0.6, 0.25), Vector2(-0.25, 1)],
			[Vector2(0.7, -1), Vector2(0.35, -0.2), Vector2(0.55, 0.4), Vector2(0.2, 1)],
			[Vector2(-0.45, -0.3), Vector2(0.0, -0.1), Vector2(0.35, -0.2)]]:
		var crack := Line2D.new()
		crack.width = 3.5
		crack.default_color = Color(0.05, 0.04, 0.03, 0.9)
		for p in line:
			crack.add_point(p * half)
		_gate_cracks.add_child(crack)
	_gate.add_child(_gate_cracks)
	_gate_hole = Polygon2D.new()
	_gate_hole.color = Color(0.03, 0.025, 0.02)
	_gate_hole.polygon = PackedVector2Array([
		Vector2(-1, 1) * half, Vector2(-0.96, -0.55) * half, Vector2(-0.62, -0.92) * half, Vector2(-0.25, -0.7) * half,
		Vector2(0.12, -1) * half, Vector2(0.55, -0.72) * half, Vector2(0.97, -0.9) * half, Vector2(1, 1) * half,
	])
	_gate.add_child(_gate_hole)
	_gate_flash = ColorRect.new()
	_gate_flash.color = Color(1.0, 0.3, 0.2, 0.0)
	_gate_flash.position = -half
	_gate_flash.size = PAINTED_DOORS_SIZE
	_gate.add_child(_gate_flash)
	_set_gate_state("intact")


func _set_gate_state(state: String) -> void:
	_gate_state = state
	_gate_cracks.visible = state == "damaged"
	_gate_hole.visible = state == "destroyed"


func gate_ground() -> Vector2:
	return Vector2((level.gate_cols.x + level.gate_cols.y + 1) * 0.5 * Defs.CELL, float(level.wall_row) * Defs.CELL)


func _build_hotspots() -> void:
	for h in level.hotspots:
		var at := to_world(level.hotspot_pos(h))
		var crater := Sprite2D.new()
		crater.texture = load("res://assets/sprites/props/crater.png")
		crater.position = at
		crater.scale = Vector2.ONE * CRATER_WIDTH_M * PX_PER_M / crater.texture.get_width()
		_world.add_child(crater)
		var glow := Sprite2D.new()
		glow.texture = _soft_dot()
		glow.material = _additive
		glow.modulate = Color(1.0, 0.42, 0.15, 0.0)
		glow.position = at
		glow.scale = Vector2(240.0, 240.0 * DEPTH) / 64.0
		_world.add_child(glow)
		_hotspot_glows.append(glow)
		var smoke := CPUParticles2D.new()
		smoke.texture = _soft_dot()
		smoke.amount = 8
		smoke.lifetime = 4.0
		smoke.preprocess = 4.0
		smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		smoke.emission_sphere_radius = 26.0
		smoke.direction = Vector2(0.15, -1.0)
		smoke.spread = 12.0
		smoke.gravity = Vector2(5.0, -3.0)
		smoke.initial_velocity_min = 18.0
		smoke.initial_velocity_max = 32.0
		smoke.scale_amount_min = 0.9
		smoke.scale_amount_max = 1.7
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.5, 0.46, 0.44, 0.0))
		ramp.add_point(0.2, Color(0.5, 0.46, 0.44, 0.32))
		ramp.set_color(ramp.get_point_count() - 1, Color(0.55, 0.53, 0.53, 0.0))
		smoke.color_ramp = ramp
		smoke.position = at
		_world.add_child(smoke)
	_set_hotspot_intensity(0.0)


func _set_hotspot_intensity(v: float) -> void:
	for glow in _hotspot_glows:
		glow.modulate.a = 0.15 + v * 0.85


func _soft_dot() -> Texture2D:
	if _dot == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var d := Vector2(x - 31.5, y - 31.5).length() / 32.0
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 1.8))
		_dot = ImageTexture.create_from_image(img)
	return _dot


# ================================================================== deployment view

func _make_grid() -> CellOverlay:
	var overlay := CellOverlay.new()
	var vr := level.view_rect
	for y in vr.size.y:
		for x in vr.size.x:
			var c := vr.position + Vector2i(x, y)
			var ok := level.is_deployable(c)
			var tint := Color(0.55, 1.0, 0.9) if ok else Color(1.0, 0.35, 0.3)
			overlay.add_cell(_cell_rect(c), Color(tint, 0.05 if ok else 0.12), Color(tint, 0.26))
	_world.add_child(overlay)
	return overlay


func show_deployment(deployment: Array) -> void:
	_clear_dynamic()
	_breaching = false
	_set_gate_state("intact")  # a retry starts with the gate repaired
	for i in deployment.size():
		_add_gun_node(i, deployment[i])
	_set_hotspot_intensity(0.35)


func _clear_dynamic() -> void:
	for table in [_gun_nodes, _monster_nodes]:
		for view in table.values():
			view.queue_free()
		table.clear()
	for c in _fx_root.get_children():
		c.queue_free()


func _make_gun_view(type: String) -> UnitView:
	var model: String = Defs.GUNS[type].model
	if TURRET_KITS.has(model):
		var turret := TurretSprite.new()
		turret.setup(TURRET_KITS[model])
		return turret
	var stand_in := StandInUnit.new()
	stand_in.setup(load(STAND_IN_ART % model), STAND_IN_WIDTH_M[model], Vector2.ZERO)
	return stand_in


func _add_gun_node(id: int, d: Dictionary) -> UnitView:
	var view := _make_gun_view(d.type)
	view.ground = level.cell_center(d.cell)
	view.position = to_world(view.ground)
	if Defs.GUNS[d.type].damage <= 0.0:  # decoys get a coloured base so they read apart from real turrets
		var ring := RangeRing.new()
		ring.setup(1.4 * PX_PER_M, DEPTH, Color("#ff6b63") if Defs.GUNS[d.type].blast > 0.0 else Color("#f2b13a"))
		ring.z_index = -1
		view.add_child(ring)
	view.add_bar(1.6, TURRET_BAR_HEIGHT_M, Color("#5ee08a"))
	_entities.add_child(view)
	_gun_nodes[id] = view
	return view


func set_held(type: String) -> void:
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	_grid.visible = type != ""
	if type == "":
		return
	_ghost = Node2D.new()
	_ghost.add_child(_make_gun_view(type))
	_ghost_ring = RangeRing.new()
	_ghost_ring.setup(float(Defs.GUNS[type].range) * PX_PER_M, DEPTH, Color("#4fd6e0"))
	_ghost.add_child(_ghost_ring)
	var min_range: float = Defs.GUNS[type].min_range
	if min_range > 0.0:  # the blind zone around the turret
		var blind := RangeRing.new()
		blind.setup(min_range * PX_PER_M, DEPTH, Color("#ff6b63"))
		_ghost.add_child(blind)
	_ghost.visible = false
	_ghost.z_index = 5
	_world.add_child(_ghost)


func update_ghost(cell: Vector2i, valid: bool) -> void:
	if not _ghost:
		return
	_ghost.visible = level.view_rect.has_point(cell)
	_ghost.position = to_world(level.cell_center(cell))
	_ghost_ring.set_color(Color("#4fd6e0") if valid else Color("#ff6b63"))


## Pulsing amber tiles on the field: an area, or a single tile for the most direct hint.
func show_hint(cells: Array, exact: bool) -> void:
	clear_hint()
	_hint = CellOverlay.new()
	for c in cells:
		_hint.add_cell(_cell_rect(c), Color(1.0, 0.72, 0.22, 0.55 if exact else 0.28), Color(1.0, 0.72, 0.22, 0.9))
	_world.add_child(_hint)
	_world.move_child(_hint, _entities.get_index())
	_hint_tween = create_tween().set_loops()
	_hint_tween.tween_property(_hint, "modulate:a", 0.45, 0.8)
	_hint_tween.tween_property(_hint, "modulate:a", 1.0, 0.8)


func clear_hint() -> void:
	if _hint_tween:
		_hint_tween.kill()
		_hint_tween = null
	if is_instance_valid(_hint):
		_hint.queue_free()
	_hint = null


## Where a point `height` metres above a gun / the gate appears on the UI canvas.
func gun_screen_pos(id: int, height: float) -> Vector2:
	return _world.get_transform() * to_world((_gun_nodes[id] as UnitView).ground, height)


func gate_screen_pos(height: float) -> Vector2:
	return _world.get_transform() * to_world(gate_ground(), height)


func screen_to_cell(screen_pos: Vector2) -> Vector2i:
	var local := _world.get_transform().affine_inverse() * screen_pos
	var p := Vector2(local.x / PX_PER_M + _focus.x, local.y / (PX_PER_M * DEPTH) + _focus.y)
	return Vector2i(floori(p.x / Defs.CELL), floori(p.y / Defs.CELL))


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or _world == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := screen_to_cell(event.position)
		if event.pressed:
			_press_cell = cell
			_press_pos = event.position
			_dragging = false
		else:
			if _dragging and cell != _press_cell:
				cell_dragged.emit(_press_cell, cell)
			else:
				cell_tapped.emit(cell)
			_dragging = false
			_press_cell = Vector2i(-1, -1)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var cell := screen_to_cell(event.position)
		if _press_cell.x >= 0 and event.position.distance_to(_press_pos) > DEPLOY_DRAG_PX:
			_dragging = true
		hover_changed.emit(cell)


# ================================================================== battle view

func begin_battle(s: BattleSim) -> void:
	sim = s
	set_held("")


func _view_dt() -> float:
	return get_process_delta_time() * maxf(sim_speed, 1.0)


func sync(alpha: float) -> void:
	if sim == null:
		return
	var dt := _view_dt()
	for g in sim.guns:
		var turret: UnitView = _gun_nodes.get(g.id)
		if turret == null:
			continue
		turret.update_turret(g.alive and g.target >= 0, atan2(float(g.aim.y), float(g.aim.x)), dt)
		turret.bar.visible = g.alive and g.hp < g.max_hp
		turret.bar.set_fraction(g.hp / g.max_hp)
	for m in sim.monsters:
		if m.state == "dead":
			continue
		var view: UnitView = _monster_nodes.get(m.id)
		if view == null:
			view = _spawn_monster_view(m)
		view.tick(m, m.prev_pos.lerp(m.pos, alpha), dt)
		view.position = to_world(view.ground)
		view.bar.visible = m.hp < m.max_hp and m.state == "active"
		view.bar.set_fraction(m.hp / m.max_hp)


func _spawn_monster_view(m: Dictionary) -> UnitView:
	var view: UnitView
	if MONSTER_KITS.has(m.type):
		var sprite := MonsterSprite.new()
		sprite.setup(MONSTER_KITS[m.type], m.pos)
		view = sprite
	else:
		var stand_in := StandInUnit.new()
		stand_in.setup(load(STAND_IN_ART % Defs.MONSTERS[m.type].model), STAND_IN_WIDTH_M[m.type], m.pos)
		view = stand_in
	view.add_bar(1.2, MONSTER_BAR_HEIGHT_M[m.type], Color("#ff6b63"))
	view.position = to_world(m.pos)
	_entities.add_child(view)
	_monster_nodes[m.id] = view
	return view


func handle_events(events: Array) -> void:
	for e in events:
		match e.type:
			"hotspot_warning":
				_fx_warning(e.hotspot)
			"emerge":
				_fx_emerge(level.hotspot_pos(level.hotspots[e.hotspot]))
			"fire":
				_fx_fire(e)
			"explode":
				_fx_explosion(e.pos, e.radius)
			"monster_died":
				_fx_monster_death(e.monster)
			"gun_destroyed":
				_fx_gun_destroyed(e.gun)
			"monster_attack":
				_fx_spark(sim.guns[e.gun].pos, Color("#ffb070"))
				_shake_screen(TURRET_HIT_TREMOR_PX)
			"gate_hit":
				var m: Dictionary = sim.monsters[e.monster]
				_fx_spark(m.pos + Vector2(0, 0.9), Color("#ff6b63"))
				_shake_screen(GATE_HIT_TREMOR_PX)


# ================================================================== effects

func _puff(at: Vector2, radius_m: float, color: Color, time: float, grow := 1.0, glow := false) -> void:
	var puff := Sprite2D.new()
	puff.texture = _soft_dot()
	puff.modulate = color
	if glow:
		puff.material = _additive
	puff.position = at
	var start := Vector2(1.0, 0.8) * radius_m * PX_PER_M / 32.0
	puff.scale = start
	_fx_root.add_child(puff)
	var tween := create_tween().set_parallel(true)
	if grow != 1.0:
		tween.tween_property(puff, "scale", start * grow, time)
	tween.tween_property(puff, "modulate:a", 0.0, time)
	tween.chain().tween_callback(puff.queue_free)


func _chip(at: Vector2, velocity: Vector2, color: Color, size_px: float, time: float) -> void:
	var chip := ColorRect.new()
	chip.color = color
	chip.size = Vector2.ONE * size_px
	chip.position = at
	_fx_root.add_child(chip)
	var drop := at + velocity * time + Vector2(0, 260.0 * time * time)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(chip, "position", drop, time)
	tween.tween_property(chip, "modulate:a", 0.0, time * 0.4).set_delay(time * 0.6)
	tween.chain().tween_callback(chip.queue_free)


func _fx_warning(hi: int) -> void:
	var glow := _hotspot_glows[hi]
	var tween := create_tween()
	tween.tween_property(glow, "modulate:a", 1.0, Defs.EMERGE_WARN)
	tween.tween_property(glow, "modulate:a", 0.4, 2.5)
	for k in 5:  # dust while the ground shakes
		var p := level.hotspot_pos(level.hotspots[hi]) + Vector2(cos(k * 1.3), sin(k * 1.3)) * 1.4
		get_tree().create_timer(k * 0.25).timeout.connect(func():
			if _fx_root and is_instance_valid(_fx_root):
				_puff(to_world(p, 0.3), 0.5, Color(0.55, 0.5, 0.42, 0.55), 1.0, 3.0))


func _fx_emerge(p: Vector2) -> void:
	var at := to_world(p, 0.2)
	for k in 8:
		var a := k * 0.8
		_chip(at, Vector2(cos(a) * 70.0, sin(a) * 30.0 - 60.0), Color("#5a4a3e"), 6.0, 0.55)
	_puff(to_world(p, 0.5), 1.0, Color(0.6, 0.52, 0.42, 0.6), 0.8, 2.2)


func _fx_fire(e: Dictionary) -> void:
	var g: Dictionary = sim.guns[e.gun]
	(_gun_nodes[e.gun] as UnitView).fired()
	var from := to_world(g.pos, 1.8)
	var to := to_world(e.to, 0.7)
	if e.get("shell", false):
		_fx_shell(from, to, g)
		return
	var sniper: bool = g.type == "sniper"
	var color := Color("#5ff3ff") if sniper else Color("#ffd27a")
	var tracer := Line2D.new()
	tracer.points = PackedVector2Array([from, to])
	tracer.width = 4.0 if sniper else 2.5
	tracer.default_color = color
	tracer.material = _additive
	_fx_root.add_child(tracer)
	var tween := create_tween()
	tween.tween_property(tracer, "modulate:a", 0.0, 0.18 if sniper else 0.06)
	tween.tween_callback(tracer.queue_free)
	_fx_spark(e.to, color)


func _fx_shell(from: Vector2, to: Vector2, g: Dictionary) -> void:
	var shell := Sprite2D.new()
	shell.texture = _soft_dot()
	shell.material = _additive
	shell.modulate = Color("#ffb347")
	shell.scale = Vector2.ONE * 0.45
	_fx_root.add_child(shell)
	var flight: float = from.distance_to(to) / (float(g.projectile_speed) * PX_PER_M)
	var arc := func(k: float) -> void:
		shell.position = from.lerp(to, k) - Vector2(0, sin(k * PI) * 2.5 * RISE * PX_PER_M)
	var tween := create_tween()
	tween.tween_method(arc, 0.0, 1.0, flight)
	tween.tween_callback(shell.queue_free)


func _fx_explosion(p: Vector2, radius: float) -> void:
	var at := to_world(p, 0.4)
	_puff(at, radius * 0.6, Color("#ff9a3d"), 0.35, 1.8, true)
	_puff(at, radius * 0.35, Color("#ffe2a0"), 0.18, 1.6, true)
	_puff(to_world(p, 1.0), radius * 0.5, Color(0.25, 0.23, 0.22, 0.6), 1.1, 2.4)


func _fx_spark(p: Vector2, color: Color) -> void:
	_puff(to_world(p, 0.7), 0.3, color, 0.14, 1.8, true)


func _fx_monster_death(id: int) -> void:
	if not _monster_nodes.has(id):
		return
	var view: UnitView = _monster_nodes[id]
	_monster_nodes.erase(id)
	view.bar.visible = false
	view.die(sim_speed)


func _fx_gun_destroyed(id: int) -> void:
	var view: UnitView = _gun_nodes.get(id)
	if view == null:
		return
	view.destroyed()
	_puff(to_world(view.ground, 1.2), 1.0, Color("#ff9a3d"), 0.4, 3.0, true)
	_puff(to_world(view.ground, 1.8), 1.0, Color(0.2, 0.2, 0.2, 0.6), 1.6, 3.0)


func shake_gate() -> void:
	if _gate_state == "destroyed":
		return
	if sim and _gate_state == "intact" and sim.gate_hp <= level.gate_max_hp * 0.5:
		_set_gate_state("damaged")
		_fx_explosion(gate_ground() + Vector2(-1.5, -0.6), 1.4)
	_gate_flash.color.a = 0.5
	create_tween().tween_property(_gate_flash, "color:a", 0.0, 0.25)
	if randi() % 3 == 0:  # visual only; the simulation stays deterministic
		_puff(to_world(gate_ground() + Vector2(randf_range(-3.0, 3.0), -0.8), 0.6), 0.9, Color(0.6, 0.55, 0.48, 0.5), 0.6, 1.8)


## Gate falls: chained explosions, destroyed art, debris and camera shake; then the
## surviving monsters charge through the breach (animate_breach).
func play_breach() -> void:
	if _breaching:
		return
	_breaching = true
	_breach_t = 0.0
	var g := gate_ground()
	var tween := create_tween()
	for k in 4:
		var off := Vector2((k - 1.5) * 1.8, -0.5 + (k % 2) * 0.4)
		tween.tween_callback(func():
			_fx_explosion(g + off, 2.2)
			_shake_screen(10.0))
		tween.tween_interval(0.16)
	tween.tween_callback(func():
		_set_gate_state("destroyed")
		_fx_explosion(g, 3.4)
		_shake_screen(22.0)
		for i in 14:
			_fx_debris(g + Vector2(randf_range(-3.0, 3.0), -0.4)))
	for i in 3:
		_puff(to_world(g + Vector2((i - 1) * 2.5, -1.0), 1.0), 1.2, Color(0.55, 0.5, 0.45, 0.55), 2.2, 3.8)


func _fx_debris(p: Vector2) -> void:
	var velocity := Vector2(randf_range(-150.0, 150.0), randf_range(-240.0, -90.0))
	_chip(to_world(p, 0.4), velocity, Color("#4a4f55"), randf_range(5.0, 11.0), randf_range(0.7, 1.2))


func _shake_screen(strength_px: float) -> void:
	_tremor = maxf(_tremor, strength_px)


## A small full-screen tremor that dies away quickly. Visual only.
func _process(delta: float) -> void:
	if _world == null or _tremor <= 0.0:
		return
	_tremor *= pow(TREMOR_DECAY, delta)
	if _tremor < TREMOR_MIN_PX:
		_tremor = 0.0
		_fit_to_screen()
		return
	_world.position = get_viewport_rect().size * 0.5 + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _tremor


## After the breach: surviving monsters run through the gate.
func animate_breach(delta: float) -> void:
	if not _breaching or sim == null:
		return
	_breach_t += delta
	if _breach_t < 0.9:
		return
	var g := gate_ground()
	for m in sim.monsters:
		if m.state == "dead" or not _monster_nodes.has(m.id):
			continue
		var view: UnitView = _monster_nodes[m.id]
		var cur := view.ground
		var target := Vector2(clampf(cur.x, g.x - 3.0, g.x + 3.0), g.y + 14.0)
		if cur.y < g.y - 0.5:
			target = Vector2(clampf(cur.x, g.x - 2.5, g.x + 2.5), g.y + 1.0)
		view.move_by((target - cur).normalized() * float(m.speed) * 1.4 * delta, delta)
		view.position = to_world(view.ground)


class CellOverlay extends Node2D:
	var _cells: Array = []

	func add_cell(rect: Rect2, fill: Color, line: Color) -> void:
		_cells.append({"rect": rect, "fill": fill, "line": line})
		queue_redraw()

	func _draw() -> void:
		for c in _cells:
			draw_rect(c.rect, c.fill)
			draw_rect(c.rect, c.line, false, 2.5)


class RangeRing extends Node2D:
	var _radius := 0.0
	var _depth := 1.0
	var _color := Color.WHITE

	func setup(radius_px: float, depth: float, color: Color) -> void:
		_radius = radius_px
		_depth = depth
		_color = color

	func set_color(color: Color) -> void:
		_color = color
		queue_redraw()

	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, _depth))
		draw_circle(Vector2.ZERO, _radius, Color(_color, 0.1))
		draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 96, Color(_color, 0.95), 3.0, true)
