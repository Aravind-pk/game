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
const GUN_SCALE := 1.15       # visual only; the simulation uses Defs radii
const MONSTER_SCALE := 1.3

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
	_build_environment()
	_build_ground()
	_build_wall()
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
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -40, 0)
	sun.light_energy = 0.95
	sun.light_color = Color(1.0, 0.94, 0.86)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#1b2430")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#8d9bb0")
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_bloom = 0.08
	e.glow_hdr_threshold = 1.1
	env.environment = e
	add_child(env)


func _build_camera() -> void:
	# angled perspective camera; horizontal FOV fixed so the play area fills the width
	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = 38.0
	var vr := level.view_rect
	var w := float(vr.size.x) * Defs.CELL
	var centre := Vector2(vr.position.x + vr.size.x * 0.5, vr.position.y + vr.size.y * 0.56) * Defs.CELL
	var target := to3(centre)
	var pitch := deg_to_rad(54.0)
	var dist := (w * 0.5 + 1.0) / tan(deg_to_rad(camera.fov * 0.5))
	camera.rotation = Vector3(-pitch, 0, 0)
	camera.position = target + Vector3(0, sin(pitch), cos(pitch)) * dist
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


func _build_ground() -> void:
	var ws := level.world_size()
	var plane := PlaneMesh.new()
	plane.size = ws + Vector2(80, 80)
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform vec3 grass : source_color = vec3(0.33, 0.42, 0.24);
uniform vec3 dry : source_color = vec3(0.47, 0.46, 0.34);
uniform vec3 dirt : source_color = vec3(0.36, 0.31, 0.25);
varying vec3 wp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; } return v; }
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float n = fbm(wp.xz * 0.06);
	float m = fbm(wp.xz * 0.23 + 7.0);
	float f = fbm(wp.xz * 1.7);
	vec3 c = mix(dirt, grass, smoothstep(0.38, 0.62, n));
	c = mix(c, dry, smoothstep(0.6, 0.85, m) * 0.45);
	c *= 0.86 + 0.24 * f;
	ALBEDO = c;
	ROUGHNESS = 0.97;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_mesh(plane, mat)


func _build_wall() -> void:
	var ws := level.world_size()
	var concrete := _mat(Color("#5d6672"), 0.85)
	var dark := _mat(Color("#2e3a48"), 0.7, 0.3)
	var steel := _mat(Color("#3b4552"), 0.5, 0.6)
	var stripe_y := _emissive(Color("#f5c56b"), 0.4)
	var lamp := _emissive(Color("#ffcf73"), 4.0)
	var cyan := _emissive(Color("#4fd6e0"), 3.0)
	var wall_z := to3(Vector2(0, level.wall_row * Defs.CELL + Defs.CELL * 0.5)).z
	var gx0 := level.gate_cols.x * Defs.CELL - ws.x * 0.5
	var gx1 := (level.gate_cols.y + 1) * Defs.CELL - ws.x * 0.5
	var x := -ws.x * 0.5 - 20.0
	var seg := 4.0
	var idx := 0
	while x < ws.x * 0.5 + 20.0:
		var x1 := x + seg
		if x1 <= gx0 - 1.0 or x >= gx1 + 1.0:
			var h := 3.6 + (0.4 if idx % 3 == 0 else 0.0)
			_box(Vector3(seg - 0.15, h, 1.6), concrete, Vector3(x + seg * 0.5, h * 0.5, wall_z))
			_box(Vector3(seg - 0.1, 0.25, 1.75), dark, Vector3(x + seg * 0.5, h + 0.12, wall_z))
			_box(Vector3(seg - 0.6, 0.18, 0.05), stripe_y, Vector3(x + seg * 0.5, 1.0, wall_z + 0.82))
			if idx % 2 == 0:
				_box(Vector3(0.7, h + 0.9, 2.0), dark, Vector3(x, (h + 0.9) * 0.5, wall_z))
				_box(Vector3(0.3, 0.2, 0.2), lamp, Vector3(x, h + 1.0, wall_z + 0.9))
		x = x1
		idx += 1
	# gate: towers, doors with hazard stripes, status lights
	for side in [gx0 - 1.4, gx1 + 1.4]:
		_box(Vector3(2.8, 7.0, 3.0), dark, Vector3(side, 3.5, wall_z))
		_box(Vector3(3.1, 0.5, 3.3), concrete, Vector3(side, 7.25, wall_z))
		_box(Vector3(0.5, 1.4, 0.1), cyan, Vector3(side, 4.6, wall_z + 1.52))
		_box(Vector3(0.5, 0.35, 0.35), lamp, Vector3(side, 7.7, wall_z + 1.1))
		_box(Vector3(2.4, 0.3, 0.06), stripe_y, Vector3(side, 2.0, wall_z + 1.52))
	var gw := gx1 - gx0
	var doors := Node3D.new()
	doors.name = "GateDoors"
	add_child(doors)
	_box(Vector3(gw, 5.2, 0.9), steel, Vector3((gx0 + gx1) * 0.5, 2.6, wall_z), doors)
	_box(Vector3(gw, 1.0, 0.06), _mat(Color("#1b222b")), Vector3((gx0 + gx1) * 0.5, 0.55, wall_z + 0.47), doors)
	for k in 9:
		var sx := gx0 + 0.5 + k * (gw - 1.0) / 8.0
		var s := _box(Vector3(0.38, 1.3, 0.05), _emissive(Color("#f5c56b"), 0.7), Vector3(sx, 0.55, wall_z + 0.5), doors)
		s.rotation.z = deg_to_rad(35)
	_box(Vector3(gw * 0.5, 0.7, 0.06), _emissive(Color("#4fd6e0"), 1.2), Vector3((gx0 + gx1) * 0.5, 4.3, wall_z + 0.48), doors)
	var sign := Label3D.new()
	sign.text = "G-01  NORTH GATE"
	sign.font_size = 64
	sign.pixel_size = 0.012
	sign.modulate = Color("#0f1722")
	sign.position = Vector3((gx0 + gx1) * 0.5, 4.3, wall_z + 0.53)
	doors.add_child(sign)
	_box(Vector3(0.08, 4.2, 0.06), dark, Vector3((gx0 + gx1) * 0.5, 2.2, wall_z + 0.47), doors)
	# settlement behind the wall
	for i in 14:
		var bx := -ws.x * 0.5 + 3.0 + i * (ws.x - 6.0) / 13.0
		var bh := 4.0 + _hash(i + 50) * 6.0
		_box(Vector3(3.2, bh, 3.0), _mat(Color("#3a4350").lerp(Color("#566170"), _hash(i)), 0.8),
			Vector3(bx, bh * 0.5, wall_z + 6.0 + _hash(i + 9) * 3.0))


func _build_obstacles() -> void:
	var concrete := _mat(Color("#7c8189"), 0.9)
	var rubble := _mat(Color("#62666c"), 0.95)
	var rust := _mat(Color("#7a4a33"), 0.8, 0.2)
	for i in level.obstacles.size():
		var r: Rect2i = level.obstacles[i]
		var centre := (Vector2(r.position) + Vector2(r.size) * 0.5) * Defs.CELL
		var size := Vector2(r.size) * Defs.CELL
		var p := to3(centre)
		var kind := i % 3
		if kind == 0:  # broken concrete ruin
			var h := 1.6 + _hash(i) * 1.6
			_box(Vector3(size.x * 0.9, h, size.y * 0.8), concrete, p + Vector3(0, h * 0.5, 0))
			_box(Vector3(size.x * 0.5, h * 0.6, 0.4), concrete, p + Vector3(-size.x * 0.2, h * 1.25, 0))
			var chunk := _box(Vector3(0.8, 0.5, 0.7), rubble, p + Vector3(size.x * 0.45, 0.25, size.y * 0.45))
			chunk.rotation.y = 0.6
		elif kind == 1:  # rock outcrop
			for k in 3:
				var s := SphereMesh.new()
				s.radius = 0.9 + _hash(i * 3 + k) * 0.5
				s.height = s.radius * 1.4
				s.radial_segments = 7
				s.rings = 4
				var mi := _mesh(s, rubble, p + Vector3((k - 1) * size.x * 0.28, 0.4, (_hash(k + i) - 0.5) * size.y * 0.5))
				mi.rotation = Vector3(_hash(k) * 2.0, _hash(k + 1) * 3.0, 0)
		else:  # abandoned container / vehicle
			_box(Vector3(size.x * 0.85, 1.5, size.y * 0.75), rust, p + Vector3(0, 0.75, 0))
			_box(Vector3(size.x * 0.86, 0.1, size.y * 0.76), _mat(Color("#5a3626")), p + Vector3(0, 1.52, 0))


func _build_scatter() -> void:
	var ws := level.world_size()
	var rock := _mat(Color("#6b6f73"), 0.95)
	var trunk := _mat(Color("#4a3b2e"), 0.9)
	var leaf := _mat(Color("#33452b"), 0.9)
	for i in 70:
		var p := Vector2(_hash(i * 2) * ws.x, _hash(i * 2 + 1) * (level.wall_row - 1) * Defs.CELL)
		var c := Vector2i(floori(p.x / Defs.CELL), floori(p.y / Defs.CELL))
		if level.view_rect.has_point(c) and _hash(i + 300) < 0.75:
			continue  # keep the playfield readable; mostly decorate the edges
		if i % 4 == 0:
			_box(Vector3(0.18, 1.8, 0.18), trunk, to3(p, 0.9))
			var s := SphereMesh.new()
			s.radius = 1.0
			s.height = 1.6
			_mesh(s, leaf, to3(p, 2.2))
		else:
			var s := SphereMesh.new()
			s.radius = 0.25 + _hash(i + 77) * 0.35
			s.height = s.radius * 1.2
			s.radial_segments = 6
			s.rings = 3
			_mesh(s, rock, to3(p, 0.1))


func _build_hotspots() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform float intensity = 0.25;
uniform vec3 glow : source_color = vec3(1.0, 0.32, 0.12);
vec2 h2(vec2 p) { p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3))); return fract(sin(p) * 43758.5453); }
float edge(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); float d1 = 8.0; float d2 = 8.0;
	for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
		vec2 g = vec2(float(x), float(y)); vec2 o = h2(i + g); float d = length(g + o - f);
		if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
	}
	return d2 - d1;
}
void fragment() {
	vec2 uv = UV - 0.5; float r = length(uv) * 2.0;
	float cracks = 1.0 - smoothstep(0.0, 0.09, edge(uv * 7.0));
	float fall = 1.0 - smoothstep(0.25, 1.0, r);
	float a = cracks * fall;
	ALBEDO = mix(vec3(0.08, 0.05, 0.04), glow * 2.5, intensity);
	EMISSION = glow * a * intensity * 6.0;
	ALPHA = clamp(a * (0.55 + intensity) + fall * 0.25 * intensity, 0.0, 1.0);
}
"""
	for h in level.hotspots:
		var plane := PlaneMesh.new()
		plane.size = Vector2(5.5, 5.5)
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("intensity", 0.22)
		var mi := _mesh(plane, mat, to3(level.hotspot_pos(h), 0.03))
		_hotspot_nodes.append(mi)


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
	for h in _hotspot_nodes:
		(h.material_override as ShaderMaterial).set_shader_parameter("intensity", 0.22)


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
	root.add_child(model)
	var head := _head_of(model)
	if head:
		head.rotation.y = PI  # face north, toward the threat
	var bar := _bar(1.6, Color("#5ee08a"))
	bar.name = "HP"
	bar.position.y = 3.6
	root.add_child(bar)
	var lab := Label3D.new()
	lab.name = "Ammo"
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.pixel_size = 0.012
	lab.font_size = 40
	lab.outline_size = 10
	lab.modulate = Color("#f5c56b")
	lab.text = str(d.ammo)
	lab.position.y = 4.1
	root.add_child(lab)
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
	for id in _gun_nodes:
		var lab := _gun_nodes[id].get_node("Ammo") as Label3D
		lab.text = str(sim.guns[id].ammo)


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
		(node.get_node("Ammo") as Label3D).text = str(g.ammo) if g.alive else ""
	var t := Time.get_ticks_msec() / 1000.0
	for m in sim.monsters:
		if m.state == "dead":
			continue
		var node: Node3D = _monster_nodes.get(m.id)
		if node == null:
			node = _spawn_monster_node(m)
		var p: Vector2 = m.prev_pos.lerp(m.pos, alpha)
		var y := 0.0
		if m.state == "emerging":
			var k: float = 1.0 - m.state_t / Defs.EMERGE_TIME
			y = lerpf(-1.8, 0.0, k)
		else:
			var moving: bool = m.prev_pos.distance_to(m.pos) > 0.001
			if moving:
				y = absf(sin(t * 10.0 + m.id)) * 0.08
		var body := node.get_child(0) as Node3D
		node.position = to3(p, y)
		node.rotation.y = lerp_angle(node.rotation.y, atan2(m.facing.x, m.facing.y), 0.25)
		body.position.z = (sin(t * 14.0) * 0.5 + 0.5) * 0.35 if m.attacking else 0.0
		var bar := node.get_node("HP") as Node3D
		bar.visible = m.hp < m.max_hp and m.state == "active"
		_set_bar(bar, m.hp / m.max_hp, 1.2)


func _spawn_monster_node(m: Dictionary) -> Node3D:
	var root := Node3D.new()
	var model := monster_model(m.type)
	model.scale = Vector3.ONE * float(Defs.MONSTERS[m.type].model_scale) * MONSTER_SCALE
	root.add_child(model)
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
	var mi: MeshInstance3D = _hotspot_nodes[hi]
	var mat := mi.material_override as ShaderMaterial
	var tw := create_tween()
	tw.tween_method(func(v): mat.set_shader_parameter("intensity", v), 0.22, 1.0, Defs.EMERGE_WARN)
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


func _fx_fire(e: Dictionary) -> void:
	var g: Dictionary = sim.guns[e.gun]
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
	tw.set_parallel(true)
	tw.tween_property(node, "rotation:z", 0.6, 0.4)
	tw.tween_property(node, "position:y", -1.6, 1.2).set_delay(0.3)
	tw.chain().tween_callback(node.queue_free)
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
	var doors := get_node_or_null("GateDoors") as Node3D
	if doors == null:
		return
	var tw := create_tween()
	tw.tween_property(doors, "position:x", 0.12, 0.04)
	tw.tween_property(doors, "position:x", -0.12, 0.04)
	tw.tween_property(doors, "position:x", 0.0, 0.04)
