class_name Battlefield
extends Node2D
## Draws the battle in 2D: a bare field, a wall that shows its damage, props placed from level
## data, sprites sorted by ground position, and effects.
## Reads BattleSim state and never changes it, so battles stay deterministic.

signal cell_tapped(cell: Vector2i)
signal drag_started(cell: Vector2i)
signal hover_changed(cell: Vector2i)

const PX_PER_M := UnitView.PX_PER_M
const DEPTH := UnitView.DEPTH
const RISE := UnitView.RISE
const DESIGN_WIDTH := 1080.0
const VIEW_NORTH_OFFSET_M := 2.94     # the screen centre sits this far south of the middle of the view; sets where the gate is on screen
const BACKGROUND := "res://assets/backgrounds/north_gate_field.jpg"
const APRON := "res://assets/backgrounds/apron.png"
const APRON_SCALE := 0.95
const WALL_DIR := "res://assets/sprites/wall/"
const RAIL_ABOVE_GATE_LINE := 51.5    # the wall's top rail, in pixels above the line monsters attack from
# Gate HP share at or below which each wall frame after the first takes over: cracks and dust,
# then sparks, then the collapse once the gate is nearly gone. The last frame is the breach.
const GATE_FRAME_AT_HP: Array[float] = [0.75, 0.65, 0.55, 0.45, 0.35, 0.25, 0.18, 0.12, 0.08, 0.04]
const FIRST_SPARK_FRAME := 4
const SPARKS_PER_HIT := 6
const DOOR_ABOVE_BASE_PX := 125.0
const PROPS_PATH := "res://assets/sprites/props/props"
const MONSTER_CLEARANCE_M := 0.6      # how far a monster's centre stays from a prop's footprint
const PROP_SCALE_MIN := 0.55
const PROP_SCALE_MAX := 1.15
const PROP_CHOICES := 4               # picks among this many of the best-fitting props
const SCATTER_DECOR := 42
const SCATTER_GROUND := 7
const SCATTER_CLEARANCE_PX := 34.0
const SCATTER_TOP_PX := -800.0

const MONSTER_KITS := {"burrower": "burrower"}   # monster types with a full sprite kit
const TURRET_KITS := {"kestrel": "kestrel"}      # turret models with a full sprite kit
const STAND_IN_ART := "res://assets/ui/art/%s.png"
const STAND_IN_WIDTH_M := {"stalker": 2.4, "brute": 3.8, "mule": 3.2, "needle": 2.8}
const MONSTER_BAR_HEIGHT_M := {"burrower": 2.7, "stalker": 2.7, "brute": 4.2}
const TURRET_BAR_HEIGHT_M := 3.6
const DEPLOY_DRAG_PX := 14.0
const GUN_TOUCH_HALF := Vector2(78.0, 100.0)  # the touch area around a turret, sized for a fingertip
const GUN_TOUCH_RISE_PX := 48.0              # its centre, above the turret's ground point
const CRATER_WIDTH_M := 6.5
const DECOY_TINT := Color(0.52, 0.57, 0.7)   # decoys wear dark steel so they never pass for a live turret
const GATE_HIT_TREMOR_PX := 7.0
const TURRET_HIT_TREMOR_PX := 3.5
const TREMOR_DECAY := 0.002       # share of the tremor left after one second
const TREMOR_MIN_PX := 0.15
const GATE_CLEARANCE_PX := -150.0   # where the foot of the wall sits against the bottom edge (negative: just past it)

var level: LevelData
var sim: BattleSim
var input_enabled := false
var pressed_gun := -1             # deployment index of the turret under the current press, or -1
var sim_speed := 1.0  # battle speed multiplier (animations follow it)

var _world: Node2D                # everything; scaled to fit the screen, moved for camera shake
var _entities: Node2D             # y-sorted units and obstacles
var _fx_root: Node2D
var _ground_root: Node2D
var _gate: Sprite2D
var _wall_base := 0.0             # the foot of the wall, from the screen centre
var _wall_data := {}
var _wall_frames: Array[Texture2D] = []
var _gate_frame := 0
var _props := {}                  # kind -> list of prop entries from props.json
var _props_texture: Texture2D
var _footprints: Array[Dictionary] = []   # ground polygons (metres) the monsters must walk around
var _grid: CellOverlay
var _hint: CellOverlay
var _hint_tween: Tween
var _focus_mark: CellOverlay
var _focus_tween: Tween
var _focus_cell := Vector2i(-1, -1)
var _ghost: Node2D
var _ghost_ring: RangeRing
var _routes: Node2D               # predicted monster paths, shown while deploying
var _focus_rings: Node2D          # range / lure / blind rings around the selected turret
var _last_plan: Node2D            # outlines of the last battle's layout, after a defeat
var _breach_route := -1           # hotspot whose route broke the gate last time
var _last_layout: Array = []
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
var _bottom_inset := 0.0          # screen pixels covered by the bottom controls
var _lift := 0.0                  # how far the field is raised so the gate clears those controls


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
	_routes = null
	_focus_rings = null
	_last_plan = null
	_focus_mark = null
	_focus_tween = null
	_focus_cell = Vector2i(-1, -1)
	_breaching = false
	_gate_frame = 0
	_footprints.clear()
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
	_ground_root = Node2D.new()
	_world.add_child(_ground_root)
	_build_hotspots()
	_build_unstable()
	_grid = _make_grid()
	_grid.visible = false
	_build_wall()
	_entities = Node2D.new()
	_entities.y_sort_enabled = true
	_world.add_child(_entities)
	_fx_root = Node2D.new()
	_world.add_child(_fx_root)
	_load_props()
	_build_obstacles()
	_build_craters()
	_build_scatter()
	_show_footprints_if_asked()
	_fit_to_screen()
	if not get_viewport().size_changed.is_connected(_fit_to_screen):
		get_viewport().size_changed.connect(_fit_to_screen)


func _fit_to_screen() -> void:
	if _world == null:
		return
	var view := get_viewport_rect().size
	_world.scale = Vector2.ONE * view.x / DESIGN_WIDTH
	# drop the field so the foot of the wall sits on the bottom edge: the gate shows through the
	# translucent tray and everything above it is open ground for turrets
	var foot := view.y * 0.5 + _wall_base * _world.scale.y
	_lift = clampf(foot + GATE_CLEARANCE_PX * _world.scale.y - view.y, 0.0, view.y * 0.25)
	_world.position = _base_position()


## The screen point the world layer is anchored to, before any tremor.
func _base_position() -> Vector2:
	return get_viewport_rect().size * 0.5 - Vector2(0.0, _lift)


## Tells the field how much of the bottom of the screen the controls cover.
func set_bottom_inset(px_value: float) -> void:
	if is_equal_approx(px_value, _bottom_inset):
		return
	_bottom_inset = px_value
	_fit_to_screen()


## Ground position in metres to a point in the world layer, optionally lifted off the ground.
func to_world(p: Vector2, height := 0.0) -> Vector2:
	return Vector2((p.x - _focus.x) * PX_PER_M, (p.y - _focus.y) * PX_PER_M * DEPTH - height * RISE * PX_PER_M)


func _cell_rect(c: Vector2i) -> Rect2:
	var top_left := to_world(Vector2(c) * Defs.CELL)
	return Rect2(top_left, Vector2(Defs.CELL * PX_PER_M, Defs.CELL * PX_PER_M * DEPTH))


func _load_props() -> void:
	if not _props.is_empty():
		return
	var file := FileAccess.open(PROPS_PATH + ".json", FileAccess.READ)
	for entry in (JSON.parse_string(file.get_as_text()) as Dictionary).props:
		if not _props.has(entry.kind):
			_props[entry.kind] = []
		_props[entry.kind].append(entry)
	_props_texture = load(PROPS_PATH + ".png")


func _level_rng(salt: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(level.title + salt)
	return rng


## Fills each blocked rectangle from the level data with props that fit it. The simulation
## blocks those cells; each prop's footprint then keeps monsters off the prop's real base.
func _build_obstacles() -> void:
	for i in level.obstacles.size():
		var r: Rect2i = level.obstacles[i]
		var rng := _level_rng("obstacle%d" % i)
		if r.size.x >= 2 and r.size.y >= 2:
			_fit_prop(r, ["solid"], rng)
		elif r.size.x >= 2:
			var c := r.position.x
			while c < r.end.x:
				var piece := mini(2, r.end.x - c)
				_fit_prop(Rect2i(c, r.position.y, piece, 1), ["thin"] if piece == 2 and rng.randf() < 0.75 else ["solid"], rng)
				c += piece
		elif r.size.y >= 2:
			for k in r.size.y:
				_fit_prop(Rect2i(r.position.x, r.position.y + k, 1, 1), ["solid"], rng)
		else:
			_fit_prop(r, ["tall"] if rng.randf() < 0.3 else ["solid"], rng)


## Picks a prop whose footprint suits the cells, at close to its natural size.
func _fit_prop(cells: Rect2i, kinds: Array, rng: RandomNumberGenerator) -> void:
	var room := Vector2(cells.size.x * Defs.CELL * PX_PER_M, cells.size.y * Defs.CELL * PX_PER_M * DEPTH)
	var options: Array = []
	for kind in kinds:
		for entry in _props.get(kind, []):
			var box := _footprint_size(entry)
			var fit := clampf(minf(room.x * 0.94 / box.x, room.y * 0.94 / box.y), PROP_SCALE_MIN, PROP_SCALE_MAX)
			if kind == "tall":
				fit = 1.0
			options.append({"entry": entry, "scale": fit, "score": absf(log(fit))})
	options.sort_custom(func(a, b): return a.score < b.score)
	var chosen: Dictionary = options[rng.randi_range(0, mini(PROP_CHOICES, options.size()) - 1)]
	var flip := rng.randf() < 0.5
	var centre := (Vector2(cells.position) + Vector2(cells.size) * 0.5) * Defs.CELL
	var at := to_world(centre)
	_entities.add_child(_prop_sprite(chosen.entry, at, chosen.scale, flip))
	_add_footprint(chosen.entry, at, chosen.scale, flip)


func _footprint_size(entry: Dictionary) -> Vector2:
	var lo := Vector2(INF, INF)
	var hi := -lo
	for q in entry.poly:
		lo = lo.min(Vector2(q[0], q[1]))
		hi = hi.max(Vector2(q[0], q[1]))
	return hi - lo


func _prop_sprite(entry: Dictionary, at: Vector2, size: float, flip: bool) -> Sprite2D:
	var rect: Array = entry.rect
	var sprite := Sprite2D.new()
	sprite.texture = _props_texture
	sprite.region_enabled = true
	sprite.region_rect = Rect2(rect[0], rect[1], rect[2], rect[3])
	sprite.centered = false
	sprite.flip_h = flip
	sprite.offset = Vector2(-(rect[2] - entry.anchor[0]) if flip else -entry.anchor[0], -entry.anchor[1])
	sprite.position = at
	sprite.scale = Vector2.ONE * size
	return sprite


## Tags the prop's picture with the patch of ground it stands on, in simulation metres.
func _add_footprint(entry: Dictionary, at: Vector2, size: float, flip: bool) -> void:
	var poly := PackedVector2Array()
	var box := Rect2()
	for q in entry.poly:
		var local := Vector2(-q[0] if flip else q[0], q[1]) * size + at
		var ground := Vector2(local.x / PX_PER_M + _focus.x, local.y / (PX_PER_M * DEPTH) + _focus.y)
		box = Rect2(ground, Vector2.ZERO) if poly.is_empty() else box.expand(ground)
		poly.append(ground)
	_footprints.append({"poly": poly, "box": box})


func _build_craters() -> void:
	var rng := _level_rng("craters")
	for h in level.hotspots:
		var options: Array = _props.get("crater", [])
		var entry: Dictionary = options[rng.randi_range(0, options.size() - 1)]
		var size: float = CRATER_WIDTH_M * PX_PER_M / float(entry.rect[2])
		_ground_root.add_child(_prop_sprite(entry, to_world(level.hotspot_pos(h)), size, rng.randf() < 0.5))


## Grass, scrub and dirt patches. Monsters walk through these, so they have no footprint.
func _build_scatter() -> void:
	var rng := _level_rng("scatter")
	var top := SCATTER_TOP_PX
	var bottom := _wall_rail_y() - 30.0
	for i in SCATTER_GROUND:
		var entry: Dictionary = _props.ground[rng.randi_range(0, _props.ground.size() - 1)]
		var at := Vector2(rng.randf_range(-520.0, 520.0), rng.randf_range(top, bottom))
		_ground_root.add_child(_prop_sprite(entry, at, rng.randf_range(0.8, 1.2), rng.randf() < 0.5))
	for i in SCATTER_DECOR:
		var at := Vector2(rng.randf_range(-530.0, 530.0), rng.randf_range(top, bottom))
		if _near_footprint(at):
			continue
		var entry: Dictionary = _props.decor[rng.randi_range(0, _props.decor.size() - 1)]
		# Monsters walk over these, so they always draw underneath.
		_ground_root.add_child(_prop_sprite(entry, at, rng.randf_range(0.75, 1.05), rng.randf() < 0.5))


func _near_footprint(at: Vector2) -> bool:
	var ground := Vector2(at.x / PX_PER_M + _focus.x, at.y / (PX_PER_M * DEPTH) + _focus.y)
	var margin := SCATTER_CLEARANCE_PX / PX_PER_M
	for footprint in _footprints:
		if (footprint.box as Rect2).grow(margin).has_point(ground):
			return true
	return false


## Keeps a point on open ground: if it is on, or too close to, a footprint it slides to the edge.
func _keep_clear(p: Vector2, clearance: float) -> Vector2:
	for footprint in _footprints:
		if not (footprint.box as Rect2).grow(clearance).has_point(p):
			continue
		var poly: PackedVector2Array = footprint.poly
		var inside := Geometry2D.is_point_in_polygon(p, poly)
		var nearest := p
		var best := INF
		for i in poly.size():
			var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
			var d := q.distance_to(p)
			if d < best:
				best = d
				nearest = q
		if inside or best < clearance:
			var away := (p - nearest).normalized()
			p = nearest + (-away if inside else away) * clearance
	return p


## Run the game with `-- footprints` to see every prop's ground polygon.
func _show_footprints_if_asked() -> void:
	if not OS.get_cmdline_user_args().has("footprints"):
		return
	for footprint in _footprints:
		var outline := Line2D.new()
		outline.width = 2.5
		outline.default_color = Color(0.2, 1.0, 1.0)
		outline.closed = true
		for q in footprint.poly:
			outline.add_point(to_world(q))
		outline.z_index = 30
		_world.add_child(outline)


## The wall and gate are one picture per damage stage, standing on the paved apron.
func _build_wall() -> void:
	if _wall_frames.is_empty():
		var file := FileAccess.open(WALL_DIR + "wall.json", FileAccess.READ)
		_wall_data = JSON.parse_string(file.get_as_text())
		for i in int(_wall_data.frames):
			_wall_frames.append(load(WALL_DIR + "wall_%02d.png" % i))
	_wall_base = _wall_rail_y() + float(_wall_data.rail_above_base)
	var apron := Sprite2D.new()
	apron.texture = load(APRON)
	apron.centered = false
	apron.scale = Vector2.ONE * APRON_SCALE
	apron.offset = Vector2(-apron.texture.get_width() * 0.5, 0)
	apron.position = Vector2(0, _wall_base - 34.0)
	_world.add_child(apron)
	_gate = Sprite2D.new()
	_gate.centered = false
	_world.add_child(_gate)
	_set_gate_frame(0)


func _wall_rail_y() -> float:
	return to_world(gate_ground()).y - RAIL_ABOVE_GATE_LINE


func _set_gate_frame(frame: int) -> void:
	_gate_frame = frame
	_gate.texture = _wall_frames[frame]
	_gate.position = Vector2(-DESIGN_WIDTH * 0.5, _wall_base - float(_wall_data.base_y[frame]))


func _door_ground() -> Vector2:
	var door_y := _wall_base - DOOR_ABOVE_BASE_PX
	return Vector2(gate_ground().x, door_y / (PX_PER_M * DEPTH) + _focus.y)


func gate_ground() -> Vector2:
	return Vector2((level.gate_cols.x + level.gate_cols.y + 1) * 0.5 * Defs.CELL, float(level.wall_row) * Defs.CELL)


func _build_hotspots() -> void:
	for h in level.hotspots:
		var at := to_world(level.hotspot_pos(h))
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

## Unstable ground is always shown, not only while a turret is held: the player plans around it.
func _build_unstable() -> void:
	if level.no_build.is_empty():
		return
	var ground := UnstableGround.new()
	for r in level.no_build:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var c := Vector2i(x, y)
				if level.view_rect.has_point(c):
					ground.add_cell(c, _cell_rect(c))
	_world.add_child(ground)


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
	_set_gate_frame(0)  # a retry starts with the gate repaired
	for i in deployment.size():
		_add_gun_node(i, deployment[i])
	_set_hotspot_intensity(0.35)
	show_routes(deployment)
	_draw_last_plan(deployment)


## Dashed lines from every fissure to the gate along the path the monsters will take with this
## layout. Brutes' paths are amber, everyone else red. Nothing written on the field.
func show_routes(deployment: Array) -> void:
	if is_instance_valid(_routes):
		_routes.queue_free()
	_routes = Node2D.new()
	_world.add_child(_routes)
	_world.move_child(_routes, _entities.get_index())
	var probe := BattleSim.new()
	probe.setup(level, deployment)
	for h in level.hotspots:
		var heavy := false
		var fast := false
		for g in h.groups:
			heavy = heavy or g.type == "brute"
			fast = fast or g.type == "stalker"
		var line := DashedPath.new()
		var pts := PackedVector2Array()
		for p in probe.route_from(level.hotspot_pos(h)):
			pts.append(to_world(p))
		var breach := level.hotspots.find(h) == _breach_route
		if breach:  # the route that broke the gate last time: solid and strong
			line.setup(_smooth(pts), Color("#f85936"), 9.0, false, true)
		else:
			var col := Color("#ffcb5e") if heavy else (Color("#ff9ad5") if fast else Color("#f2775a"))
			line.setup(_smooth(pts), col, 7.0 if heavy else 5.0, heavy, false, fast)
		_routes.add_child(line)


## Remembers the last battle's layout and the hotspot that broke the gate, for the retry.
func set_last_plan(last: Array, breach_hotspot: int) -> void:
	_last_layout = last.duplicate(true)
	_breach_route = breach_hotspot


## Dashed outlines where turrets stood last time (only those since moved).
func _draw_last_plan(now: Array) -> void:
	var last := _last_layout
	if is_instance_valid(_last_plan):
		_last_plan.queue_free()
	_last_plan = Node2D.new()
	_world.add_child(_last_plan)
	_world.move_child(_last_plan, _entities.get_index())
	var cells := {}
	for d in now:
		cells[d.cell] = true
	for d in last:
		if cells.has(d.cell):
			continue
		var mark := GhostTile.new()
		mark.rect = _cell_rect(d.cell)
		_last_plan.add_child(mark)


func hide_routes() -> void:
	if is_instance_valid(_routes):
		_routes.queue_free()
	_routes = null


## Rounds a cell-to-cell path into a curve (Chaikin), so it reads as a walk, not a grid.
func _smooth(pts: PackedVector2Array) -> PackedVector2Array:
	var cur := pts
	for _k in 3:
		if cur.size() < 3:
			break
		var nxt := PackedVector2Array([cur[0]])
		for i in cur.size() - 1:
			nxt.append(cur[i].lerp(cur[i + 1], 0.25))
			nxt.append(cur[i].lerp(cur[i + 1], 0.75))
		nxt.append(cur[cur.size() - 1])
		cur = nxt
	return cur


## The largest distance at which this wave's monsters notice a turret and leave their path.
func _lure_radius() -> float:
	var r := 0.0
	for h in level.hotspots:
		for g in h.groups:
			r = maxf(r, float(Defs.MONSTERS[g.type].detect))
	return r


## Range, full-damage, lure and blind rings for a turret type, as one node.
func _rings_for(type: String) -> Node2D:
	var n := Node2D.new()
	var gun: Dictionary = Defs.GUNS[type]
	if float(gun.damage) > 0.0:
		var range_ring := RangeRing.new()
		range_ring.setup(float(gun.range) * PX_PER_M, DEPTH, Color("#4fd6e0"))
		range_ring.name = "Range"
		n.add_child(range_ring)
		if float(gun.falloff_floor) < 1.0:  # full damage only up close
			var core := RangeRing.new()
			core.setup(float(gun.falloff_start) * PX_PER_M, DEPTH, Color("#4fd6e0"), "disc")
			n.add_child(core)
	var lure := RangeRing.new()
	lure.setup(_lure_radius() * PX_PER_M, DEPTH, Color("#f2775a"), "dashed")
	n.add_child(lure)
	if float(gun.min_range) > 0.0:
		var blind := RangeRing.new()
		blind.setup(float(gun.min_range) * PX_PER_M, DEPTH, Color("#f2775a"), "hatched")
		n.add_child(blind)
	return n


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
		turret.setup(TURRET_KITS[model], _soft_dot(), _additive)
		return turret
	var stand_in := StandInUnit.new()
	stand_in.setup(load(STAND_IN_ART % model), STAND_IN_WIDTH_M[model], Vector2.ZERO)
	return stand_in


func _add_gun_node(id: int, d: Dictionary) -> UnitView:
	var view := _make_gun_view(d.type)
	view.ground = level.cell_center(d.cell)
	view.position = to_world(view.ground)
	if Defs.GUNS[d.type].damage <= 0.0:  # decoys get dark steel and a coloured base so they read apart from real turrets
		view.tint(DECOY_TINT)
		var ring := RangeRing.new()
		ring.setup(1.4 * PX_PER_M, DEPTH, Color("#ff6b63") if Defs.GUNS[d.type].blast > 0.0 else Color("#f2b13a"))
		view.add_child(ring)
		view.move_child(ring, 0)
	if int(d.get("gun", 0)) < 0:  # holdout: dug in behind a ring of sandbags, so it reads as part of the map
		var bags := SandbagRing.new()
		view.add_child(bags)
		view.move_child(bags, 0)
	var order: String = d.get("order", "")
	if order != "":  # a small badge with the one monster type this turret will fire at
		var badge := Sprite2D.new()
		var tex: Texture2D = load(STAND_IN_ART % Defs.MONSTERS[Defs.ORDERS[order].target].model)
		badge.texture = tex
		badge.scale = Vector2.ONE * (54.0 / tex.get_width())
		badge.position = Vector2(-58.0, -120.0)
		var plate := OrderPlate.new()
		plate.position = badge.position
		view.add_child(plate)
		view.add_child(badge)
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
	var rings := _rings_for(type)
	_ghost.add_child(rings)
	_ghost_ring = rings.get_node_or_null("Range")
	_ghost.add_child(_make_gun_view(type))
	_ghost.visible = false
	_ghost.z_index = 5
	_world.add_child(_ghost)


func update_ghost(cell: Vector2i, valid: bool) -> void:
	if not _ghost:
		return
	_ghost.visible = level.view_rect.has_point(cell)
	_ghost.position = to_world(level.cell_center(cell))
	if _ghost_ring:
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


## Pulses the tile of the turret the player has selected.
func show_focus(cell: Vector2i) -> void:
	if _focus_cell == cell and is_instance_valid(_focus_mark):
		return
	clear_focus()
	_focus_cell = cell
	for d in _gun_nodes.values():
		if (d as UnitView).ground == level.cell_center(cell):
			pass
	_focus_mark = CellOverlay.new()
	_focus_mark.add_cell(_cell_rect(cell), Color(1.0, 0.72, 0.22, 0.45), Color(1.0, 0.82, 0.4, 1.0))
	_world.add_child(_focus_mark)
	_world.move_child(_focus_mark, _entities.get_index())
	_focus_tween = create_tween().set_loops()
	_focus_tween.tween_property(_focus_mark, "modulate:a", 0.5, 0.5)
	_focus_tween.tween_property(_focus_mark, "modulate:a", 1.0, 0.5)


## Rings around the selected placed turret.
func show_focus_rings(cell: Vector2i, type: String) -> void:
	clear_focus_rings()
	_focus_rings = _rings_for(type)
	_focus_rings.position = to_world(level.cell_center(cell))
	_world.add_child(_focus_rings)
	_world.move_child(_focus_rings, _entities.get_index())


func clear_focus_rings() -> void:
	if is_instance_valid(_focus_rings):
		_focus_rings.queue_free()
	_focus_rings = null


func clear_focus() -> void:
	if _focus_tween:
		_focus_tween.kill()
		_focus_tween = null
	if is_instance_valid(_focus_mark):
		_focus_mark.queue_free()
	_focus_mark = null
	_focus_cell = Vector2i(-1, -1)


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


## The foot of the wall, in the middle, on the UI canvas. Ignores the screen tremor.
func wall_foot_screen_pos() -> Vector2:
	return _base_position() + Vector2(0.0, _wall_base) * _world.scale


func screen_to_cell(screen_pos: Vector2) -> Vector2i:
	var local := _world.get_transform().affine_inverse() * screen_pos
	var p := Vector2(local.x / PX_PER_M + _focus.x, local.y / (PX_PER_M * DEPTH) + _focus.y)
	return Vector2i(floori(p.x / Defs.CELL), floori(p.y / Defs.CELL))


## Hands the current press over to a drag, so its release is not also read as a tap.
func cancel_press() -> void:
	_press_cell = Vector2i(-1, -1)
	pressed_gun = -1
	_dragging = false


## The deployed turret whose touch area contains this screen point, nearest first, or -1.
func gun_at(screen_pos: Vector2) -> int:
	var local := _world.get_transform().affine_inverse() * screen_pos
	var best := -1
	var best_distance := 1.0
	for id in _gun_nodes:
		var offset: Vector2 = local - (_gun_nodes[id] as UnitView).position + Vector2(0.0, GUN_TOUCH_RISE_PX)
		var distance := (offset / GUN_TOUCH_HALF).length()
		if distance < best_distance:
			best_distance = distance
			best = id
	return best


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or _world == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := screen_to_cell(event.position)
		if event.pressed:
			_press_cell = cell
			_press_pos = event.position
			pressed_gun = gun_at(event.position)
			_dragging = false
		elif _press_cell.x >= 0:
			cell_tapped.emit(cell)
			cancel_press()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var cell := screen_to_cell(event.position)
		if _press_cell.x >= 0 and not _dragging and event.position.distance_to(_press_pos) > DEPLOY_DRAG_PX:
			_dragging = true
			drag_started.emit(_press_cell)
		hover_changed.emit(cell)


# ================================================================== battle view

func begin_battle(s: BattleSim) -> void:
	sim = s
	set_held("")
	hide_routes()
	clear_focus_rings()


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
		turret.update_turret(g.alive and g.target >= 0, atan2(float(g.aim.y) * DEPTH, float(g.aim.x)), dt)
		turret.bar.visible = g.alive and g.hp < g.max_hp
		turret.bar.set_fraction(g.hp / g.max_hp)
	for m in sim.monsters:
		if m.state == "dead":
			continue
		var view: UnitView = _monster_nodes.get(m.id)
		if view == null:
			view = _spawn_monster_view(m)
		view.tick(m, m.prev_pos.lerp(m.pos, alpha), dt)
		if m.state == "active":
			view.ground = _keep_clear(view.ground, MONSTER_CLEARANCE_M)
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
	var gun: UnitView = _gun_nodes[e.gun]
	gun.fired()
	var from := gun.position + gun.muzzle_offset()
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


## Every hit shakes the screen. Falling HP moves the wall through its damage frames, and once
## they reach the sparking stage each hit also throws sparks off the doors.
func shake_gate() -> void:
	if sim == null or _breaching:
		return
	var hp := clampf(sim.gate_hp / level.gate_max_hp, 0.0, 1.0)
	var frame := 0
	for threshold in GATE_FRAME_AT_HP:
		if hp <= threshold:
			frame += 1
	if frame > _gate_frame:
		_set_gate_frame(frame)
	if _gate_frame >= FIRST_SPARK_FRAME:
		_fx_gate_sparks()
	if randi() % 3 == 0:  # visual only; the simulation stays deterministic
		_puff(to_world(gate_ground() + Vector2(randf_range(-3.0, 3.0), -0.8), 0.6), 0.9, Color(0.6, 0.55, 0.48, 0.5), 0.6, 1.8)


## Gate falls: chained explosions, destroyed art, debris and camera shake; then the
## surviving monsters charge through the breach (animate_breach).
func play_breach() -> void:
	if _breaching:
		return
	_breaching = true
	_breach_t = 0.0
	var door := _door_ground()
	var tween := create_tween()
	for k in 4:
		var off := Vector2((k - 1.5) * 1.8, -0.5 + (k % 2) * 0.4)
		tween.tween_callback(func():
			_fx_explosion(door + off, 2.2)
			_shake_screen(10.0))
		tween.tween_interval(0.16)
	for frame in range(_gate_frame + 1, _wall_frames.size()):
		tween.tween_callback(_set_gate_frame.bind(frame))
		tween.tween_interval(0.14)
	tween.tween_callback(func():
		_fx_explosion(door, 3.4)
		_shake_screen(22.0)
		for i in 14:
			_fx_debris(door + Vector2(randf_range(-3.0, 3.0), -0.4)))
	for i in 3:
		_puff(to_world(door + Vector2((i - 1) * 2.5, -1.0), 1.0), 1.2, Color(0.55, 0.5, 0.45, 0.55), 2.2, 3.8)


func _fx_gate_sparks() -> void:
	var door := to_world(_door_ground())
	for i in SPARKS_PER_HIT:
		var from := door + Vector2(randf_range(-130.0, 130.0), randf_range(-60.0, 60.0))
		var velocity := Vector2(randf_range(-170.0, 170.0), randf_range(-200.0, -40.0))
		_chip(from, velocity, Color("#ffd27a"), randf_range(2.5, 5.0), randf_range(0.25, 0.5))


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
	_world.position = _base_position() + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _tremor


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
	var _style := "ring"   # ring | disc (filled, no edge) | dashed (lure) | hatched (blind zone)

	func setup(radius_px: float, depth: float, color: Color, style := "ring") -> void:
		_radius = radius_px
		_depth = depth
		_color = color
		_style = style

	func set_color(color: Color) -> void:
		_color = color
		queue_redraw()

	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, _depth))
		match _style:
			"disc":
				draw_circle(Vector2.ZERO, _radius, Color(_color, 0.2))
			"dashed":
				draw_circle(Vector2.ZERO, _radius, Color(_color, 0.06))
				var dashes := 40
				for k in dashes:
					var a0 := TAU * float(k) / float(dashes)
					draw_arc(Vector2.ZERO, _radius, a0, a0 + TAU / float(dashes) * 0.55, 6, Color(_color, 0.95), 3.5, true)
			"hatched":
				draw_circle(Vector2.ZERO, _radius, Color(_color, 0.12))
				var step := 14.0
				var x := -_radius
				while x < _radius:
					var h := sqrt(maxf(_radius * _radius - x * x, 0.0))
					var x2 := minf(x + h * 2.0, _radius)
					var off := x2 - x
					draw_line(Vector2(x, h), Vector2(x + off, h - off), Color(_color, 0.55), 2.5, true)
					x += step
				draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 64, Color(_color, 0.9), 2.5, true)
			_:
				draw_circle(Vector2.ZERO, _radius, Color(_color, 0.1))
				draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 96, Color(_color, 0.95), 3.0, true)


## A dashed route line in world pixels; heavy units' routes use round dots.
class DashedPath extends Node2D:
	var _pts := PackedVector2Array()
	var _color := Color.WHITE
	var _width := 5.0
	var _dotted := false

	var _solid := false

	var _long := false

	func setup(pts: PackedVector2Array, color: Color, width: float, dotted: bool, solid := false, long := false) -> void:
		_pts = pts
		_color = color
		_width = width
		_dotted = dotted
		_solid = solid
		_long = long

	func _draw() -> void:
		if _solid:
			draw_polyline(_pts, Color(_color, 0.95), _width, true)
			return
		var on := 40.0 if _long else (22.0 if not _dotted else 4.0)
		var off := 10.0 if _long else (14.0 if not _dotted else 16.0)
		var carry := 0.0
		var drawing := true
		for i in _pts.size() - 1:
			var a := _pts[i]
			var b := _pts[i + 1]
			var seg := a.distance_to(b)
			var t := 0.0
			while t < seg:
				var left := (on if drawing else off) - carry
				var step := minf(left, seg - t)
				if drawing:
					var p0 := a.lerp(b, t / seg)
					var p1 := a.lerp(b, (t + step) / seg)
					if _dotted:
						draw_circle(p0, _width * 0.6, Color(_color, 0.95))
					else:
						draw_line(p0, p1, Color(_color, 0.9), _width, true)
				t += step
				carry += step
				if carry >= (on if drawing else off) - 0.001:
					carry = 0.0
					drawing = not drawing


## Cracked, rust-red tiles with a hazard-striped outer border, so it never reads as plain dirt.
class UnstableGround extends Node2D:
	const STRIPE_LENGTH := 12.0
	const STRIPE_WIDTH := 7.0
	var _cells := {}

	func add_cell(cell: Vector2i, rect: Rect2) -> void:
		_cells[cell] = rect
		queue_redraw()

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		for cell in _cells:
			var rect: Rect2 = _cells[cell]
			draw_rect(rect, Color(0.62, 0.2, 0.12, 0.42))
			rng.seed = hash(cell)
			for _k in 3:
				var at := rect.position + rect.size * Vector2(rng.randf(), rng.randf())
				var crack := PackedVector2Array([at])
				for _s in 3:
					at = (at + Vector2(rng.randf_range(-20.0, 20.0), rng.randf_range(-13.0, 13.0))).clamp(rect.position, rect.end)
					crack.append(at)
				draw_polyline(crack, Color(0.16, 0.06, 0.04, 0.85), 2.0)
		for cell in _cells:
			var rect: Rect2 = _cells[cell]
			if not _cells.has(cell + Vector2i.UP):
				_stripes(rect.position, Vector2.RIGHT, rect.size.x, Vector2.DOWN)
			if not _cells.has(cell + Vector2i.DOWN):
				_stripes(Vector2(rect.position.x, rect.end.y - STRIPE_WIDTH), Vector2.RIGHT, rect.size.x, Vector2.DOWN)
			if not _cells.has(cell + Vector2i.LEFT):
				_stripes(rect.position, Vector2.DOWN, rect.size.y, Vector2.RIGHT)
			if not _cells.has(cell + Vector2i.RIGHT):
				_stripes(Vector2(rect.end.x - STRIPE_WIDTH, rect.position.y), Vector2.DOWN, rect.size.y, Vector2.RIGHT)

	func _stripes(start: Vector2, along: Vector2, length: float, across: Vector2) -> void:
		var travelled := 0.0
		var hot := true
		while travelled < length:
			var piece := minf(STRIPE_LENGTH, length - travelled)
			var corner := start + along * travelled
			var size := along * piece + across * STRIPE_WIDTH
			draw_rect(Rect2(corner, size), Color(0.95, 0.3, 0.18, 0.9) if hot else Color(0.15, 0.05, 0.03, 0.9))
			travelled += piece
			hot = not hot


class SandbagRing extends Node2D:
	const BAGS := 12
	const RADIUS_PX := 66.0
	const BAG := Rect2(-17.0, -9.0, 34.0, 18.0)

	func _draw() -> void:
		for k in BAGS:
			var angle := TAU * float(k) / float(BAGS)
			var at := Vector2(cos(angle), sin(angle) * UnitView.DEPTH) * RADIUS_PX
			draw_set_transform(at, angle + PI * 0.5, Vector2(1.0, 0.8))
			draw_rect(BAG, Color("#c2a46a"))
			draw_rect(BAG, Color("#7d6638"), false, 2.0)


## Cyan plate behind a turret's order badge.
class OrderPlate extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(-32, -22, 64, 44), Color("#7af1eb"))
		draw_rect(Rect2(-32, -22, 64, 44), Color("#14171a"), false, 3.0)


## Dashed outline of a tile a turret stood on in the last battle.
class GhostTile extends Node2D:
	var rect := Rect2()

	func _draw() -> void:
		draw_rect(rect.grow(-4.0), Color(0.95, 0.89, 0.8, 0.12))
		var pts := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y), rect.position]
		for i in 4:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var n := 6
			for k in n:
				if k % 2 == 0:
					draw_line(a.lerp(b, float(k) / n), a.lerp(b, float(k + 1) / n), Color(0.95, 0.89, 0.8, 0.9), 3.0)
