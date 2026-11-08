class_name Battlefield
extends Node3D
## 3D presentation of a level: terrain, ruins, settlement wall + gate, spawn fissures,
## turrets, monsters and combat effects. Reads BattleSim state; never changes it.
## Also handles tap/drag placement during deployment.

signal cell_tapped(cell: Vector2i)
signal cell_dragged(from_cell: Vector2i, to_cell: Vector2i)
signal hover_changed(cell: Vector2i)

const TURRET_PALETTE := "polar_ceramic"
const MONSTER_PALETTE := "basalt_ember"
const GUN_SCALE := 1.45       # visual only; the simulation uses Defs radii
const MONSTER_SCALE := 1.45

var level: LevelData
var camera: Camera3D
var sim: BattleSim

var _gun_nodes := {}        # deployment index / sim gun id -> Node3D
var _monster_nodes := {}    # monster id -> Node3D
var _hotspot_nodes := []    # fissure meshes
var _grid: MeshInstance3D
var _ghost: Node3D
var _ghost_ring: MeshInstance3D
var _ghost_type := ""
var _ghost_valid := false
var _scene_cache := {}
var _fx_root: Node3D
var _dynamic_root: Node3D
var _press_cell := Vector2i(-1, -1)
var _press_pos := Vector2.ZERO
var _dragging := false
var _wreck_mat: StandardMaterial3D
var _interp := 1.0
var _env_root: Node3D


# ================================================================== setup

func build(lv: LevelData) -> void:
	level = lv
	for c in get_children():
		c.queue_free()
	_gun_nodes.clear()
	_monster_nodes.clear()
	_hotspot_nodes.clear()
	_dynamic_root = Node3D.new()
	add_child(_dynamic_root)
	_fx_root = Node3D.new()
	add_child(_fx_root)
	_wreck_mat = StandardMaterial3D.new()
	_wreck_mat.albedo_color = Color(0.13, 0.12, 0.12)
	_wreck_mat.roughness = 1.0
	_env_root = Node3D.new()
	add_child(_env_root)
	_load_cam()
	_build_environment()
	_build_ground()
	_build_wall()
	_build_gate()
	_build_obstacles()
	_build_scatter()
	_build_hotspots()
	_build_grid()
	_build_camera()


func to3(p: Vector2, h := 0.0) -> Vector3:
	var ws := level.world_size()
	return Vector3(p.x - ws.x * 0.5, h, p.y - ws.y * 0.5)


func cell3(c: Vector2i, h := 0.0) -> Vector3:
	return to3(level.cell_center(c), h)


func _build_environment() -> void:
	# lighting matches the pre-rendered background (camera.json sun); units are the only lit objects
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-float(_cam.sun_pitch_deg), float(_cam.sun_yaw_deg), 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.9, 0.78)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#2c333b")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#a9b8cc")
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR  # keep the painted background's colours exact
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_hdr_threshold = 1.05
	env.environment = e
	add_child(env)


func _cam_target() -> Vector3:
	var vr := level.view_rect
	var tx := (vr.position.x + vr.size.x * 0.5) * Defs.CELL
	var ty := (vr.position.y * Defs.CELL + level.wall_row * Defs.CELL) * 0.5 + float(_cam.target_y_offset_m)
	return to3(Vector2(tx, ty))


func _build_camera() -> void:
	# identical to the camera render_backgrounds.py uses, so units sit on the painted ground
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = float(_cam.width_m)
	var pitch := deg_to_rad(float(_cam.pitch_deg))
	camera.rotation = Vector3(-pitch, 0, 0)
	camera.position = _cam_target() + Vector3(0, sin(pitch), cos(pitch)) * 120.0
	camera.near = 1.0
	camera.far = 300.0
	add_child(camera)
	camera.make_current()


func _mat(color: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


func _emissive(color: Color, energy := 3.0, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color, alpha)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _mesh(mesh: Mesh, mat: Material, pos := Vector3.ZERO, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	(parent if parent else self).add_child(mi)
	return mi


func _box(size: Vector3, mat: Material, pos: Vector3, parent: Node = null) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mesh(b, mat, pos, parent)


# deterministic pseudo-random for decoration (never used by the simulation)
func _hash(i: int) -> float:
	var x := sin(float(i) * 12.9898 + 78.233) * 43758.5453
	return x - floor(x)


## Painted background projected in screen space onto the ground plane and onto simple
## occluder boxes (wall, ruins): units sit on the painting, take real shadows on it, and walk
## behind the wall and ruins. Everything static lives in the image.
const BG_SHADER := """
shader_type spatial;
render_mode ambient_light_disabled, specular_disabled, cull_back%s;
uniform sampler2D bg : source_color, filter_linear;
uniform float v_scale = 1.0;
uniform float shadow_floor = 0.6;
void fragment() {
	vec2 uv = vec2(SCREEN_UV.x, 0.5 + (SCREEN_UV.y - 0.5) * v_scale);
	ALBEDO = texture(bg, uv).rgb;
}
void light() {
	DIFFUSE_LIGHT += vec3(mix(shadow_floor, 1.0, ATTENUATION));
}
"""

var _bg_mat: ShaderMaterial      # occluders (writes depth)
var _ground_mat: ShaderMaterial  # ground (no depth write, so sprite cards can sink below it)
var _cam: Dictionary = {}
var _sprites: Dictionary = {}
var _gate: Sprite3D
var _gate_state := "intact"
var _gate_pos := Vector3.ZERO
var _breaching := false
var _breach_t := 0.0


func _load_cam() -> void:
	var f := FileAccess.open("res://levels/camera.json", FileAccess.READ)
	_cam = JSON.parse_string(f.get_as_text())


func _projector(depth_mode: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = BG_SHADER % depth_mode
	var m := ShaderMaterial.new()
	m.shader = sh
	var p := "res://assets/backgrounds/level_%s.jpg" % level.id
	m.set_shader_parameter("bg", load(p) if ResourceLoader.exists(p) else null)
	return m


func _build_ground() -> void:
	_bg_mat = _projector("")
	_ground_mat = _projector(", depth_draw_never")
	_ground_mat.render_priority = -128  # depth_draw_never puts it in the alpha pass: draw it first
	_update_bg_scale()
	if not get_viewport().size_changed.is_connected(_update_bg_scale):
		get_viewport().size_changed.connect(_update_bg_scale)
	var ws := level.world_size()
	var plane := PlaneMesh.new()
	plane.size = ws + Vector2(160, 160)
	var g := _mesh(plane, _ground_mat)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _update_bg_scale() -> void:
	if _bg_mat == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var img_aspect := float(_cam.image_h) / float(_cam.image_w)
	for m in [_bg_mat, _ground_mat]:
		m.set_shader_parameter("v_scale", (vs.y / vs.x) / img_aspect)


func _occluder(size: Vector3, pos: Vector3) -> void:
	var m := _box(size, _bg_mat, pos + Vector3(0, size.y * 0.5, 0), _env_root)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The settlement wall is part of the painted background and deliberately does NOT occlude:
## monsters attacking the gate stand just north of it and must stay visible (the concept art
## cheats the same way), so they always draw over the wall.
func _build_wall() -> void:
	pass


## Gameplay obstacles are 2D sprites rendered from the game camera (render_prop_sprites.py).
## Each is a camera-facing card centred on its ground point at the background's pixel density;
## because the card's depth equals its ground point's depth, units north of it are hidden behind
## it and units south of it draw over it.
func _load_sprites() -> void:
	if not _sprites.is_empty():
		return
	var f := FileAccess.open("res://assets/sprites/props/props.json", FileAccess.READ)
	if f:
		_sprites = JSON.parse_string(f.get_as_text())


func _prop_sprite(name: String, ground: Vector2, scale := 1.0) -> void:
	var path := "res://assets/sprites/props/%s.png" % name
	if not ResourceLoader.exists(path):
		push_warning("missing sprite " + path)
		return
	var spr := Sprite3D.new()
	spr.texture = load(path)
	spr.pixel_size = 1.0 / float(_sprites.get("px_per_m", 40.0))
	spr.shaded = false
	spr.transparent = true
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spr.rotation = Vector3(-deg_to_rad(float(_cam.pitch_deg)), 0, 0)
	spr.position = to3(ground)
	spr.scale = Vector3.ONE * scale
	_env_root.add_child(spr)


func _build_obstacles() -> void:
	_load_sprites()
	for i in level.obstacles.size():
		var r: Rect2i = level.obstacles[i]
		var span := maxi(r.size.x, r.size.y)
		var vertical := r.size.y > r.size.x
		var ab := "a" if i % 2 == 0 else "b"
		var dir := "90" if vertical else "0"
		var name := ""
		var sc := 1.0
		if r.size.x >= 2 and r.size.y >= 2:
			name = ("ruin_corner_" if i % 2 == 0 else "block_pile_") + ab
		elif span >= 3:
			name = "container_" + dir
			sc = span * Defs.CELL / 6.2
		elif span == 2:
			name = ["ruin_wall_", "car_", "barrier_"][i % 3] + dir
		else:
			name = ["ruin_pillar_", "rocks_", "block_pile_"][i % 3] + ab
			sc = 0.6 if i % 3 == 2 else 0.8
		var centre := (Vector2(r.position) + Vector2(r.size) * 0.5) * Defs.CELL
		_prop_sprite(name, centre, sc)


## The gate is a sprite (intact / damaged / destroyed) at the doors' ground point, pushed back
## along the camera's view direction: same place on screen, but deeper than the monsters
## attacking it, so they always draw in front of the doors.
func _build_gate() -> void:
	_load_sprites()
	var front := float(level.wall_row) * Defs.CELL
	var gx := (level.gate_cols.x + level.gate_cols.y + 1) * 0.5 * Defs.CELL
	var ground := Vector2(gx, front + 0.9 * 0.8 + 1.9)  # measured against the painted towers
	var pitch := deg_to_rad(float(_cam.pitch_deg))
	var forward := Vector3(0, -sin(pitch), -cos(pitch))
	_gate = Sprite3D.new()
	_gate.pixel_size = 1.0 / float(_sprites.get("px_per_m", 40.0))
	_gate.shaded = false
	_gate.transparent = true
	_gate.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	_gate.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_gate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gate.rotation = Vector3(-pitch, 0, 0)
	_gate_pos = to3(ground) + forward * 14.0
	_gate.position = _gate_pos
	_env_root.add_child(_gate)
	_set_gate_state("intact")


func _set_gate_state(state: String) -> void:
	_gate_state = state
	var path := "res://assets/sprites/props/gate_%s.png" % state
	if ResourceLoader.exists(path):
		_gate.texture = load(path)


func gate_ground() -> Vector2:
	var gx := (level.gate_cols.x + level.gate_cols.y + 1) * 0.5 * Defs.CELL
	return Vector2(gx, float(level.wall_row) * Defs.CELL)


func _build_scatter() -> void:
	pass  # set dressing is part of the painted background


func _build_hotspots() -> void:
	for h in level.hotspots:
		var p := to3(level.hotspot_pos(h))
		var q := QuadMesh.new()
		q.size = Vector2(6.0, 6.0)
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.albedo_texture = _soft_dot()
		gm.albedo_color = Color(1.0, 0.42, 0.15, 0.0)
		gm.no_depth_test = false
		var glow := _mesh(q, gm, p + Vector3(0, 0.08, 0), _env_root)
		glow.rotation.x = -PI * 0.5
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var smoke := CPUParticles3D.new()
		smoke.amount = 8
		smoke.lifetime = 4.0
		smoke.preprocess = 4.0
		smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		smoke.emission_sphere_radius = 0.7
		smoke.direction = Vector3(0.2, 1, 0)
		smoke.spread = 12.0
		smoke.initial_velocity_min = 0.5
		smoke.initial_velocity_max = 0.9
		smoke.gravity = Vector3(0.15, 0.08, 0)
		smoke.scale_amount_min = 0.8
		smoke.scale_amount_max = 1.6
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0.4))
		curve.add_point(Vector2(1, 1.5))
		smoke.scale_amount_curve = curve
		var grad := Gradient.new()
		grad.set_color(0, Color(0.5, 0.46, 0.44, 0.0))
		grad.add_point(0.2, Color(0.5, 0.46, 0.44, 0.32))
		grad.set_color(grad.get_point_count() - 1, Color(0.55, 0.53, 0.53, 0.0))
		smoke.color_ramp = grad
		var sq := QuadMesh.new()
		sq.size = Vector2(1.4, 1.4)
		var sm := StandardMaterial3D.new()
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		sm.vertex_color_use_as_albedo = true
		sm.albedo_texture = _soft_dot()
		sq.material = sm
		smoke.mesh = sq
		smoke.position = p + Vector3(0, 0.3, 0)
		_env_root.add_child(smoke)
		_hotspot_nodes.append({"glow": gm})
	_set_hotspot_intensity(0.0)


func _set_hotspot_intensity(v: float) -> void:
	for h in _hotspot_nodes:
		(h.glow as StandardMaterial3D).albedo_color.a = 0.15 + v * 0.85


var _dot_tex: Texture2D


func _soft_dot() -> Texture2D:
	if _dot_tex:
		return _dot_tex
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 32.0
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 1.8))
	_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex


func _build_grid() -> void:
	var vr := level.view_rect
	var img := Image.create(vr.size.x, vr.size.y, false, Image.FORMAT_L8)
	for y in vr.size.y:
		for x in vr.size.x:
			var ok := level.is_deployable(Vector2i(vr.position.x + x, vr.position.y + y))
			img.set_pixel(x, y, Color.WHITE if ok else Color.BLACK)
	var tex := ImageTexture.create_from_image(img)
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform sampler2D mask : filter_nearest;
uniform vec2 cells;
uniform float alpha = 0.6;
void fragment() {
	vec2 f = fract(UV * cells);
	float line = 1.0 - smoothstep(0.0, 0.05, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
	float ok = texture(mask, UV).r;
	vec3 col = mix(vec3(1.0, 0.35, 0.3), vec3(0.55, 1.0, 0.9), ok);
	ALBEDO = col;
	ALPHA = (line * 0.75 + (ok > 0.5 ? 0.06 : 0.16)) * alpha;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("mask", tex)
	mat.set_shader_parameter("cells", Vector2(vr.size))
	var plane := PlaneMesh.new()
	plane.size = Vector2(vr.size) * Defs.CELL
	var centre := (Vector2(vr.position) + Vector2(vr.size) * 0.5) * Defs.CELL
	_grid = _mesh(plane, mat, to3(centre, 0.05))
	_grid.visible = false


# ================================================================== models

func _load_model(path: String) -> Node3D:
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path)
	var ps: PackedScene = _scene_cache[path]
	if ps == null:
		var fallback := Node3D.new()
		_box(Vector3(1, 1, 1), _mat(Color.MAGENTA), Vector3(0, 0.5, 0), fallback)
		return fallback
	return ps.instantiate()


func gun_model(type: String) -> Node3D:
	return _load_model("res://assets/models/turrets/%s_%s.glb" % [Defs.GUNS[type].model, TURRET_PALETTE])


func monster_model(type: String) -> Node3D:
	return _load_model("res://assets/models/monsters/%s_%s.glb" % [Defs.MONSTERS[type].model, MONSTER_PALETTE])


func _head_of(n: Node) -> Node3D:
	return n.find_child("*_Head", true, false) as Node3D


func _ring(radius: float, color: Color) -> MeshInstance3D:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform vec4 color : source_color;
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float ring = smoothstep(0.955, 0.975, d) - smoothstep(0.99, 1.0, d);
	float fill = d < 1.0 ? 0.10 : 0.0;
	ALBEDO = color.rgb;
	ALPHA = (ring * 0.95 + fill) * color.a;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("color", color)
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius, radius) * 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position.y = 0.08
	return mi


func _bar(width: float, color: Color) -> Node3D:
	var root := Node3D.new()
	for k in 2:
		var q := QuadMesh.new()
		q.size = Vector2(width, 0.16 if k == 0 else 0.11)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.no_depth_test = true
		m.render_priority = 10 + k
		m.albedo_color = Color(0.05, 0.06, 0.08, 0.85) if k == 0 else color
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.name = "bg" if k == 0 else "fg"
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


func _set_bar(bar: Node3D, frac: float, width: float) -> void:
	var fg := bar.get_node("fg") as MeshInstance3D
	frac = clampf(frac, 0.0, 1.0)
	fg.scale.x = maxf(frac, 0.001)
	fg.position.x = -width * 0.5 * (1.0 - frac)


# ================================================================== deployment view

func show_deployment(deployment: Array) -> void:
	_clear_dynamic()
	for i in deployment.size():
		_add_gun_node(i, deployment[i])
	_set_hotspot_intensity(0.35)


func _clear_dynamic() -> void:
	for c in _dynamic_root.get_children():
		c.queue_free()
	for c in _fx_root.get_children():
		c.queue_free()
	_gun_nodes.clear()
	_monster_nodes.clear()


func _add_gun_node(id: int, d: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.position = cell3(d.cell)
	var model := gun_model(d.type)
	model.scale = Vector3.ONE * GUN_SCALE
	Stylize.apply(model, 0.025)
	root.add_child(model)
	var head := _head_of(model)
	if head:
		head.rotation.y = PI  # face north, toward the threat
	var bar := _bar(1.6, Color("#5ee08a"))
	bar.name = "HP"
	bar.position.y = 3.6
	root.add_child(bar)
	_dynamic_root.add_child(root)
	_gun_nodes[id] = root
	return root


func set_held(type: String) -> void:
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	_ghost_type = type
	_grid.visible = type != ""
	if type == "":
		return
	_ghost = Node3D.new()
	var model := gun_model(type)
	model.scale = Vector3.ONE * GUN_SCALE
	Stylize.apply(model, 0.025)
	_ghost.add_child(model)
	var head := _head_of(model)
	if head:
		head.rotation.y = PI
	_ghost_ring = _ring(Defs.GUNS[type].range, Color("#4fd6e0"))
	_ghost.add_child(_ghost_ring)
	_ghost.visible = false
	_dynamic_root.add_child(_ghost)


func update_ghost(cell: Vector2i, valid: bool) -> void:
	if not _ghost:
		return
	_ghost.visible = level.view_rect.has_point(cell)
	_ghost.position = cell3(cell)
	_ghost_valid = valid
	var col := Color("#4fd6e0") if valid else Color("#ff6b63")
	(_ghost_ring.material_override as ShaderMaterial).set_shader_parameter("color", col)


## Where a point `height` metres above a gun / the gate appears on the UI canvas.
func gun_screen_pos(id: int, height: float) -> Vector2:
	return camera.unproject_position((_gun_nodes[id] as Node3D).position + Vector3.UP * height)


func gate_screen_pos(height: float) -> Vector2:
	return camera.unproject_position(to3(gate_ground(), height))


func screen_to_cell(screen_pos: Vector2) -> Vector2i:
	var o := camera.project_ray_origin(screen_pos)
	var n := camera.project_ray_normal(screen_pos)
	if absf(n.y) < 0.0001:
		return Vector2i(-1, -1)
	var t := -o.y / n.y
	var hit := o + n * t
	var ws := level.world_size()
	var p := Vector2(hit.x + ws.x * 0.5, hit.z + ws.y * 0.5)
	return Vector2i(floori(p.x / Defs.CELL), floori(p.y / Defs.CELL))


var input_enabled := false
var sim_speed := 1.0  # battle speed multiplier (animations follow it)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or camera == null:
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
		if _press_cell.x >= 0 and event.position.distance_to(_press_pos) > 14.0:
			_dragging = true
		hover_changed.emit(cell)


# ================================================================== battle view

func begin_battle(s: BattleSim) -> void:
	sim = s
	set_held("")


func sync(alpha: float) -> void:
	if sim == null:
		return
	_interp = alpha
	for g in sim.guns:
		var node: Node3D = _gun_nodes.get(g.id)
		if node == null:
			continue
		if g.alive:
			var head := _head_of(node)
			if head and g.target >= 0:
				var want := atan2(g.aim.x, g.aim.y)
				head.rotation.y = lerp_angle(head.rotation.y, want, 0.35)
		_set_bar(node.get_node("HP"), g.hp / g.max_hp, 1.6)
	var t := Time.get_ticks_msec() / 1000.0
	for m in sim.monsters:
		if m.state == "dead":
			continue
		var node: Node3D = _monster_nodes.get(m.id)
		if node == null:
			node = _spawn_monster_node(m)
		var p: Vector2 = m.prev_pos.lerp(m.pos, alpha)
		var y := 0.0
		var moving: bool = m.prev_pos.distance_to(m.pos) > 0.001
		if m.state == "emerging":
			var k: float = 1.0 - m.state_t / Defs.EMERGE_TIME
			y = lerpf(-1.8, 0.0, k)
		node.position = to3(p, y)
		node.rotation.y = lerp_angle(node.rotation.y, atan2(m.facing.x, m.facing.y), 0.25)
		var ap := node.get_meta("anim", null) as AnimationPlayer
		if ap:
			var want := "emerge"
			var spd := 1.0
			if m.state == "active":
				if m.attacking:
					want = "attack"
					# one swing per simulated attack
					spd = ap.get_animation("attack").length * float(m.attack_rate)
				elif moving:
					want = "walk"
					spd = float(m.speed) / float(Defs.MONSTERS[m.type].speed)
				else:
					want = "idle"
			if ap.current_animation != want:
				ap.play(want, 0.15)
			ap.speed_scale = spd * (sim_speed if sim_speed > 0.0 else 1.0)
		else:
			var body := node.get_child(0) as Node3D
			if moving:
				node.position.y += absf(sin(t * 10.0 + m.id)) * 0.08
			body.position.z = (sin(t * 14.0) * 0.5 + 0.5) * 0.35 if m.attacking else 0.0
		var bar := node.get_node("HP") as Node3D
		bar.visible = m.hp < m.max_hp and m.state == "active"
		_set_bar(bar, m.hp / m.max_hp, 1.2)


func _spawn_monster_node(m: Dictionary) -> Node3D:
	var root := Node3D.new()
	var model := monster_model(m.type)
	model.scale = Vector3.ONE * float(Defs.MONSTERS[m.type].model_scale) * MONSTER_SCALE
	Stylize.apply(model, 0.025)
	root.add_child(model)
	var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap:
		for loop_name in ["idle", "walk", "attack"]:
			if ap.has_animation(loop_name):
				ap.get_animation(loop_name).loop_mode = Animation.LOOP_LINEAR
		ap.play("emerge")
		root.set_meta("anim", ap)
	var bar := _bar(1.2, Color("#ff6b63"))
	bar.name = "HP"
	bar.position.y = 2.6 if m.type != "brute" else 3.8
	bar.visible = false
	root.add_child(bar)
	root.position = to3(m.pos, -2.0)
	_dynamic_root.add_child(root)
	_monster_nodes[m.id] = root
	return root


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
			"gate_hit":
				var m: Dictionary = sim.monsters[e.monster]
				_fx_spark(m.pos + Vector2(0, 0.9), Color("#ff6b63"))


# ================================================================== effects

func _fade_free(node: Node3D, time: float, grow := 1.0) -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	if grow != 1.0:
		tw.tween_property(node, "scale", node.scale * grow, time)
	var mi := node as MeshInstance3D
	if mi and mi.material_override is StandardMaterial3D:
		var m := mi.material_override as StandardMaterial3D
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tw.tween_property(m, "albedo_color:a", 0.0, time)
	tw.chain().tween_callback(node.queue_free)


func _fx_warning(hi: int) -> void:
	var h: Dictionary = _hotspot_nodes[hi]
	var tw := create_tween()
	tw.tween_method(func(v: float): (h.glow as StandardMaterial3D).albedo_color.a = 0.15 + v * 0.85,
		0.0, 1.0, Defs.EMERGE_WARN)
	tw.tween_method(func(v: float): (h.glow as StandardMaterial3D).albedo_color.a = 0.15 + v * 0.85,
		1.0, 0.25, 2.5)
	# dust puffs while the ground shakes
	for k in 5:
		var p := level.hotspot_pos(level.hotspots[hi]) + Vector2(cos(k * 1.3), sin(k * 1.3)) * 1.4
		var s := SphereMesh.new()
		s.radius = 0.5
		s.height = 0.7
		var d := _mesh(s, _emissive(Color(0.55, 0.5, 0.42), 0.2, 0.55), to3(p, 0.3), _fx_root)
		d.scale = Vector3.ONE * 0.3
		var t2 := create_tween()
		t2.tween_interval(k * 0.25)
		t2.tween_property(d, "scale", Vector3.ONE * 1.6, 1.0)
		t2.parallel().tween_property(d, "position:y", 1.2, 1.0)
		t2.tween_callback(d.queue_free)


func _fx_emerge(p: Vector2) -> void:
	for k in 6:
		var b := BoxMesh.new()
		b.size = Vector3(0.35, 0.3, 0.3)
		var r := _mesh(b, _mat(Color("#5a4a3e")), to3(p, 0.2), _fx_root)
		var dir := Vector3(cos(k * 1.05), 0, sin(k * 1.05))
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(r, "position", r.position + dir * (1.2 + _hash(k) * 0.8) + Vector3(0, 1.2, 0), 0.25)
		tw.tween_property(r, "rotation", Vector3(3, 2, 1), 0.6)
		tw.chain().tween_property(r, "position:y", 0.1, 0.35)
		tw.chain().tween_callback(r.queue_free).set_delay(0.6)
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 1.2
	var dust := _mesh(s, _emissive(Color(0.6, 0.52, 0.42), 0.15, 0.6), to3(p, 0.5), _fx_root)
	_fade_free(dust, 0.8, 2.2)


func _recoil(gun_id: int, amount: float) -> void:
	var node: Node3D = _gun_nodes.get(gun_id)
	if node == null:
		return
	var head := _head_of(node)
	if head == null:
		return
	if not head.has_meta("rest"):
		head.set_meta("rest", head.position)
	var rest: Vector3 = head.get_meta("rest")
	var back := head.basis.z.normalized() * -amount
	var tw := create_tween()
	tw.tween_property(head, "position", rest + back, 0.04)
	tw.tween_property(head, "position", rest, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _fx_fire(e: Dictionary) -> void:
	var g: Dictionary = sim.guns[e.gun]
	_recoil(e.gun, {"mg": 0.05, "cannon": 0.35, "sniper": 0.2}.get(g.type, 0.1))
	var from := to3(g.pos, 1.2)
	var to := to3(e.to, 0.7)
	var col := Color("#ffd27a")
	var w := 0.06
	var life := 0.05
	if g.type == "sniper":
		col = Color("#5ff3ff")
		w = 0.1
		life = 0.18
	if e.get("shell", false):
		_fx_shell(from, to, g)
		return
	var dist := from.distance_to(to)
	if dist < 0.01:
		return
	var tr := _box(Vector3(w, w, dist), _emissive(col, 5.0), (from + to) * 0.5, _fx_root)
	tr.look_at_from_position((from + to) * 0.5, to, Vector3.UP)
	_fade_free(tr, life)
	var s := SphereMesh.new()
	s.radius = 0.22
	s.height = 0.44
	var fl := _mesh(s, _emissive(col, 6.0), from + (to - from).normalized() * 0.9, _fx_root)
	_fade_free(fl, 0.06)
	_fx_spark(e.to, col)


func _fx_shell(from: Vector3, to: Vector3, g: Dictionary) -> void:
	var s := SphereMesh.new()
	s.radius = 0.2
	s.height = 0.4
	var shell := _mesh(s, _emissive(Color("#ffb347"), 4.0), from, _fx_root)
	var flight: float = from.distance_to(to) / g.projectile_speed
	var arc := func(k: float) -> void:
		var p := from.lerp(to, k)
		p.y += sin(k * PI) * 2.5
		shell.position = p
	var tw := create_tween()
	tw.tween_method(arc, 0.0, 1.0, flight)
	tw.tween_callback(shell.queue_free)
	var fl := _mesh(SphereMesh.new(), _emissive(Color("#ffcf73"), 6.0), from, _fx_root)
	fl.scale = Vector3.ONE * 0.8
	_fade_free(fl, 0.08)


func _fx_explosion(p: Vector2, radius: float) -> void:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	var core := _mesh(s, _emissive(Color("#ff8a3d"), 5.0, 0.9), to3(p, 0.6), _fx_root)
	core.scale = Vector3.ONE * 0.4
	_fade_free(core, 0.35, radius * 2.2)
	var smoke := _mesh(s, _emissive(Color(0.25, 0.22, 0.2), 0.1, 0.7), to3(p, 0.8), _fx_root)
	smoke.scale = Vector3.ONE * 0.6
	_fade_free(smoke, 0.9, radius * 1.6)
	var ring := _ring(radius, Color("#ffb347"))
	ring.position = to3(p, 0.1)
	_fx_root.add_child(ring)
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_callback(ring.queue_free)


func _fx_spark(p: Vector2, col: Color) -> void:
	var s := SphereMesh.new()
	s.radius = 0.18
	s.height = 0.36
	var sp := _mesh(s, _emissive(col, 5.0), to3(p, 0.8), _fx_root)
	_fade_free(sp, 0.12, 2.0)


func _fx_monster_death(id: int) -> void:
	if not _monster_nodes.has(id):
		return
	var node: Node3D = _monster_nodes[id]
	_monster_nodes.erase(id)
	node.get_node("HP").visible = false
	var tw := create_tween()
	var ap := node.get_meta("anim", null) as AnimationPlayer
	if ap and ap.has_animation("death"):
		ap.speed_scale = maxf(sim_speed, 1.0)
		ap.play("death", 0.1)
		tw.tween_interval(1.6 / maxf(sim_speed, 1.0))
		tw.tween_property(node, "position:y", -1.6, 1.0)
	else:
		tw.set_parallel(true)
		tw.tween_property(node, "rotation:z", 0.6, 0.4)
		tw.tween_property(node, "position:y", -1.6, 1.2).set_delay(0.3)
		tw.chain()
	tw.tween_callback(node.queue_free)
	var s := SphereMesh.new()
	var puff := _mesh(s, _emissive(Color("#ff6b40"), 3.0, 0.8), node.position + Vector3(0, 0.6, 0), _fx_root)
	_fade_free(puff, 0.3, 2.5)


func _fx_gun_destroyed(id: int) -> void:
	var node: Node3D = _gun_nodes.get(id)
	if node == null:
		return
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		if mi.get_parent().name != "HP":
			(mi as MeshInstance3D).material_override = _wreck_mat
	var head := _head_of(node)
	if head:
		var tw := create_tween()
		tw.tween_property(head, "rotation:x", 0.5, 0.3)
	node.get_node("HP").visible = false
	var s := SphereMesh.new()
	var boom := _mesh(s, _emissive(Color("#ff9a3d"), 5.0, 0.9), node.position + Vector3(0, 1.2, 0), _fx_root)
	_fade_free(boom, 0.4, 3.0)
	var smoke := _mesh(s, _emissive(Color(0.2, 0.2, 0.2), 0.1, 0.6), node.position + Vector3(0, 1.8, 0), _fx_root)
	_fade_free(smoke, 1.6, 4.0)


func shake_gate() -> void:
	if _gate == null or _gate_state == "destroyed":
		return
	if sim and _gate_state == "intact" and sim.gate_hp <= level.gate_max_hp * 0.5:
		_set_gate_state("damaged")
		_fx_explosion(gate_ground() + Vector2(-1.5, -0.6), 1.4)
	var tw := create_tween()
	_gate.modulate = Color(1.0, 0.55, 0.5)
	tw.tween_property(_gate, "position:x", _gate_pos.x + 0.12, 0.04)
	tw.tween_property(_gate, "position:x", _gate_pos.x - 0.12, 0.04)
	tw.tween_property(_gate, "position:x", _gate_pos.x, 0.04)
	tw.parallel().tween_property(_gate, "modulate", Color.WHITE, 0.25)
	if randi() % 3 == 0:  # visual only; the simulation stays deterministic
		var s := SphereMesh.new()
		var p := gate_ground() + Vector2(randf_range(-3.0, 3.0), -0.8)
		var d := _mesh(s, _emissive(Color(0.6, 0.55, 0.48), 0.2, 0.5), to3(p, 0.6), _fx_root)
		_fade_free(d, 0.6, 1.8)


## Gate falls: chained explosions, destroyed sprite, debris, dust and camera shake; then the
## surviving monsters charge through the breach (animate_breach).
func play_breach() -> void:
	if _gate == null or _breaching:
		return
	_breaching = true
	_breach_t = 0.0
	var g := gate_ground()
	var tw := create_tween()
	for k in 4:
		var off := Vector2((k - 1.5) * 1.8, -0.5 + (k % 2) * 0.4)
		tw.tween_callback(func(): _fx_explosion(g + off, 2.2); _shake_camera(0.35))
		tw.tween_interval(0.16)
	tw.tween_callback(func():
		_set_gate_state("destroyed")
		_fx_explosion(g, 3.4)
		_shake_camera(0.8)
		for i in 14:
			_fx_debris(g + Vector2(randf_range(-3.0, 3.0), -0.4)))
	for i in 3:
		var dust := _mesh(SphereMesh.new(), _emissive(Color(0.55, 0.5, 0.45), 0.15, 0.55),
			to3(g + Vector2((i - 1) * 2.5, -1.0), 1.0), _fx_root)
		dust.scale = Vector3.ONE * 1.2
		var t2 := create_tween()
		t2.tween_interval(0.7)
		t2.tween_property(dust, "scale", Vector3.ONE * 4.5, 1.6)
		t2.parallel().tween_property(dust.material_override, "albedo_color:a", 0.0, 1.6)
		t2.tween_callback(dust.queue_free)


func _fx_debris(p: Vector2) -> void:
	var b := BoxMesh.new()
	b.size = Vector3(0.35, 0.2, 0.3) * randf_range(0.6, 1.4)
	var r := _mesh(b, _mat(Color("#3e4752").lerp(Color("#8e9196"), randf()), 0.8, 0.3), to3(p, 1.0), _fx_root)
	var dir := Vector3(randf_range(-1, 1), 0, randf_range(-0.3, 1.0)).normalized()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(r, "position", r.position + dir * randf_range(2.0, 5.0) + Vector3(0, 2.5, 0), 0.35)
	tw.tween_property(r, "rotation", Vector3(randf() * 6, randf() * 6, randf() * 6), 1.0)
	tw.chain().tween_property(r, "position:y", 0.1, 0.4)
	tw.chain().tween_interval(1.2)
	tw.chain().tween_callback(r.queue_free)


func _shake_camera(strength: float) -> void:
	var tw := create_tween()
	for i in 6:
		tw.tween_property(camera, "h_offset", randf_range(-strength, strength), 0.04)
		tw.parallel().tween_property(camera, "v_offset", randf_range(-strength, strength), 0.04)
	tw.tween_property(camera, "h_offset", 0.0, 0.06)
	tw.parallel().tween_property(camera, "v_offset", 0.0, 0.06)


## After the breach: surviving monsters run through the gate into the settlement.
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
		var node: Node3D = _monster_nodes[m.id]
		var cur := Vector2(node.position.x, node.position.z) + level.world_size() * 0.5
		var target := Vector2(clampf(cur.x, g.x - 3.0, g.x + 3.0), g.y + 14.0)
		if cur.y < g.y - 0.5:
			target = Vector2(clampf(cur.x, g.x - 2.5, g.x + 2.5), g.y + 1.0)
		var dir := (target - cur).normalized()
		var nxt := cur + dir * float(m.speed) * 1.4 * delta
		node.position = to3(nxt)
		node.rotation.y = lerp_angle(node.rotation.y, atan2(dir.x, dir.y), 0.2)
		var ap := node.get_meta("anim", null) as AnimationPlayer
		if ap and ap.current_animation != "walk":
			ap.play("walk", 0.15)
			ap.speed_scale = 1.6
