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
	# golden-hour key light: low, warm, long soft shadows
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34, -38, 0)
	sun.light_energy = 1.45
	sun.light_color = Color(1.0, 0.9, 0.76)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 110.0
	add_child(sun)
	# cool fill from the opposite side keeps shadows blue-violet instead of black
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-50, 140, 0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.55, 0.65, 0.95)
	add_child(fill)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#3a4a72")
	sky_mat.sky_horizon_color = Color("#d9b49a")
	sky_mat.ground_horizon_color = Color("#7f8a7a")
	sky_mat.ground_bottom_color = Color("#2a2a30")
	sky_mat.sun_angle_max = 30.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.1
	e.ambient_light_sky_contribution = 0.85
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	e.tonemap_white = 6.0
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_strength = 1.1
	e.glow_bloom = 0.06
	e.glow_hdr_threshold = 1.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.fog_enabled = true
	e.fog_light_color = Color("#b8b4a8")
	e.fog_light_energy = 0.9
	e.fog_density = 0.0016
	e.fog_sky_affect = 0.3
	e.fog_height = 6.0
	e.fog_height_density = 0.0
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.08
	e.adjustment_saturation = 1.18
	e.adjustment_brightness = 1.0
	env.environment = e
	add_child(env)


func _build_camera() -> void:
	# angled perspective camera; horizontal FOV fixed so the play area fills the width
	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = 38.0
	var vr := level.view_rect
	var w := float(vr.size.x) * Defs.CELL
	var centre := Vector2(vr.position.x + vr.size.x * 0.5, vr.position.y + vr.size.y * 0.6) * Defs.CELL
	var target := to3(centre)
	var pitch := deg_to_rad(47.0)
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


func _prop(name: String, pos: Vector3, yaw := 0.0, scale := 1.0, outline := 0.035) -> Node3D:
	var n := _load_model("res://assets/models/props/%s.glb" % name)
	n.position = pos
	n.rotation.y = yaw
	n.scale = Vector3.ONE * scale
	Stylize.apply(n, outline)
	_env_root.add_child(n)
	return n


func _build_ground() -> void:
	var ws := level.world_size()
	var plane := PlaneMesh.new()
	plane.size = ws + Vector2(120, 120)
	plane.subdivide_width = 1
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode diffuse_toon, specular_disabled;
uniform vec3 grass_a : source_color = vec3(0.30, 0.42, 0.22);
uniform vec3 grass_b : source_color = vec3(0.42, 0.50, 0.26);
uniform vec3 dry : source_color = vec3(0.58, 0.52, 0.34);
uniform vec3 dirt : source_color = vec3(0.42, 0.34, 0.25);
uniform vec3 scorch : source_color = vec3(0.16, 0.13, 0.12);
uniform vec4 hotspots[8];
uniform int hotspot_count = 0;
varying vec3 wp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.07; a *= 0.5; } return v; }
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wp.xz;
	float n = fbm(p * 0.045);
	float m = fbm(p * 0.13 + 11.0);
	float tuft = fbm(p * 0.9 + 3.0);
	float fine = noise(p * 6.0);
	vec3 g = mix(grass_a, grass_b, smoothstep(0.3, 0.75, m));
	vec3 c = mix(dirt, g, smoothstep(0.26, 0.46, n));
	c = mix(c, dry, smoothstep(0.66, 0.86, fbm(p * 0.07 + 5.0)) * 0.4);
	c *= 0.82 + 0.28 * tuft;
	c *= 0.94 + 0.08 * fine;
	for (int i = 0; i < hotspot_count; i++) {
		float d = distance(p, hotspots[i].xy);
		c = mix(c, scorch, (1.0 - smoothstep(1.5, 4.5 + 1.5 * fbm(p * 0.6), d)) * 0.85);
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var hs := []
	for h in level.hotspots:
		var p3 := to3(level.hotspot_pos(h))
		hs.append(Vector4(p3.x, p3.z, 0, 0))
	while hs.size() < 8:
		hs.append(Vector4(9999, 9999, 0, 0))
	mat.set_shader_parameter("hotspots", hs)
	mat.set_shader_parameter("hotspot_count", mini(level.hotspots.size(), 8))
	_mesh(plane, mat)
	_build_grass()


func _build_grass() -> void:
	# stylised grass tufts: three crossed blades per instance, swaying in the wind
	var blade := ArrayMesh.new()
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for k in 3:
		var a := k * PI / 3.0
		var d := Vector3(cos(a), 0, sin(a)) * 0.13
		verts.append_array([-d, d, Vector3(0, 0.34, 0) + d * 0.3])
		uvs.append_array([Vector2(0, 1), Vector2(1, 1), Vector2(0.5, 0)])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	blade.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_disabled;
uniform vec3 base : source_color = vec3(0.24, 0.36, 0.18);
uniform vec3 tip : source_color = vec3(0.50, 0.60, 0.30);
void vertex() {
	float h = 1.0 - UV.y;
	vec3 wpos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	VERTEX.x += sin(TIME * 1.7 + wpos.x * 0.4 + wpos.z * 0.3) * 0.08 * h;
	NORMAL = vec3(0.0, 1.0, 0.0);
}
void fragment() {
	ALBEDO = mix(base, tip, 1.0 - UV.y);
	ROUGHNESS = 1.0;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	blade.surface_set_material(0, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = blade
	var ws := level.world_size()
	var pts := []
	var i := 0
	while pts.size() < 9000 and i < 30000:
		i += 1
		var p := Vector2(_hash(i * 3 + 1000) * ws.x, _hash(i * 3 + 1001) * (level.wall_row * Defs.CELL - 1.0))
		# clumpy distribution
		if _hash(floori(p.x / 3.0) * 97 + floori(p.y / 3.0) * 13) < 0.35:
			continue
		var c := Vector2i(floori(p.x / Defs.CELL), floori(p.y / Defs.CELL))
		if level.is_obstacle(c):
			continue
		pts.append(p)
	mm.instance_count = pts.size()
	for k in pts.size():
		var s := 0.7 + _hash(k + 7000) * 0.9
		var t := Transform3D(Basis(Vector3.UP, _hash(k + 9000) * TAU).scaled(Vector3(s, s * (0.8 + _hash(k) * 0.6), s)),
			to3(pts[k]))
		mm.set_instance_transform(k, t)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _build_wall() -> void:
	var ws := level.world_size()
	_env_root = _env_root if _env_root else Node3D.new()
	var wall_z := to3(Vector2(0, level.wall_row * Defs.CELL + Defs.CELL * 0.5)).z
	var gx0 := level.gate_cols.x * Defs.CELL - ws.x * 0.5
	var gx1 := (level.gate_cols.y + 1) * Defs.CELL - ws.x * 0.5
	var gcx := (gx0 + gx1) * 0.5
	var doors := _prop("gate_doors", Vector3(gcx, 0, wall_z), 0.0, (gx1 - gx0) / 8.0)
	doors.name = "GateDoors"
	_prop("gate_tower", Vector3(gx0 - 1.6, 0, wall_z), 0.0)
	_prop("gate_tower", Vector3(gx1 + 1.6, 0, wall_z), 0.0)
	# modular wall sections outward from the towers
	var idx := 0
	var x := gx1 + 3.1 + 2.0
	while x < ws.x * 0.5 + 24.0:
		_prop("logo_wall" if idx == 1 else "wall_segment", Vector3(x, 0, wall_z), 0.0)
		x += 4.0
		idx += 1
	idx = 0
	x = gx0 - 3.1 - 2.0
	while x > -ws.x * 0.5 - 24.0:
		_prop("wall_segment", Vector3(x, 0, wall_z), 0.0)
		x -= 4.0
		idx += 1
	# lamp posts in front of the wall, warm pools of light
	for lx in [gx0 - 6.0, gx1 + 6.0, -ws.x * 0.5 + 5.0, ws.x * 0.5 - 5.0]:
		var lp := _prop("lamp_post", Vector3(lx, 0, wall_z - 2.6), PI * 0.5 if lx < 0 else -PI * 0.5)
		var light := OmniLight3D.new()
		light.light_color = Color("#ffc070")
		light.light_energy = 2.0
		light.omni_range = 9.0
		light.position = Vector3(lx, 4.6, wall_z - 2.6)
		_env_root.add_child(light)
	# settlement silhouettes behind the wall
	for i in 12:
		var bx := -ws.x * 0.5 - 6.0 + i * (ws.x + 12.0) / 11.0
		var bh := 6.0 + _hash(i + 50) * 9.0
		var b := _box(Vector3(5.0, bh, 4.0), _mat(Color("#3b4350").lerp(Color("#59606a"), _hash(i)), 0.9),
			Vector3(bx, bh * 0.5, wall_z + 7.0 + _hash(i + 9) * 4.0), _env_root)
		Stylize.apply(b, 0.0)


## Obstacle rectangles (cells) -> ruins / containers / wrecks that fill the footprint.
func _build_obstacles() -> void:
	for i in level.obstacles.size():
		var r: Rect2i = level.obstacles[i]
		var centre := (Vector2(r.position) + Vector2(r.size) * 0.5) * Defs.CELL
		var p := to3(centre)
		var long_x := r.size.x >= r.size.y
		var yaw := 0.0 if long_x else PI * 0.5
		var span := maxi(r.size.x, r.size.y)
		var flip := PI if _hash(i + 3) > 0.5 else 0.0
		if r.size.x >= 2 and r.size.y >= 2:
			_prop("ruin_corner" if i % 2 == 0 else "block_pile", p, _hash(i) * TAU, 1.0)
		elif span >= 3:
			_prop("container", p, yaw + flip, float(span) * Defs.CELL / 6.2)
		elif span == 2:
			_prop(["ruin_wall", "car", "barrier"][i % 3], p, yaw + flip, 1.0)
		else:
			_prop(["ruin_pillar", "rocks", "block_pile"][i % 3], p, _hash(i) * TAU, 0.6 if i % 3 == 2 else 0.8)


## Set dressing: dense ruins and pine woods around the edges, sparse low clutter in the field.
func _build_scatter() -> void:
	var ws := level.world_size()
	var vr := level.view_rect
	var field := Rect2(Vector2(vr.position) * Defs.CELL, Vector2(vr.size) * Defs.CELL).grow(-0.5)
	var big := ["pine", "pine", "pine", "ruin_wall", "ruin_pillar", "block_pile", "container", "car", "ruin_corner"]
	var placed := []
	var tries := 0
	while placed.size() < 70 and tries < 900:
		tries += 1
		var p := Vector2(_hash(tries * 5) * (ws.x + 20.0) - 10.0, _hash(tries * 5 + 1) * (level.wall_row * Defs.CELL - 4.0))
		if field.has_point(p):
			continue
		var near := false
		for h in level.hotspots:
			if p.distance_to(level.hotspot_pos(h)) < 4.5:
				near = true
		for q in placed:
			if p.distance_to(q) < 3.2:
				near = true
		if near:
			continue
		placed.append(p)
		var kind: String = big[int(_hash(tries * 5 + 2) * big.size()) % big.size()]
		var s := 0.8 + _hash(tries * 5 + 3) * 0.5
		_prop(kind, to3(p), _hash(tries * 5 + 4) * TAU, s)
	# inside the field: only low clutter that doesn't read as an obstacle
	for k in 26:
		var p := Vector2(field.position.x + _hash(k * 7 + 500) * field.size.x,
			field.position.y + _hash(k * 7 + 501) * (field.size.y - 4.0))
		var c := Vector2i(floori(p.x / Defs.CELL), floori(p.y / Defs.CELL))
		if level.is_obstacle(c):
			continue
		_prop("bush" if k % 3 else "rocks", to3(p), _hash(k + 40) * TAU, 0.45 + _hash(k + 41) * 0.35, 0.02)


func _build_hotspots() -> void:
	for h in level.hotspots:
		var p := to3(level.hotspot_pos(h))
		var crater := _prop("crater", p, _hash(int(p.x * 10.0)) * TAU, 1.0, 0.02)
		var mats := []
		for mi in crater.find_children("*", "MeshInstance3D", true, false):
			for s in (mi as MeshInstance3D).mesh.get_surface_count():
				var m := (mi as MeshInstance3D).get_active_material(s) as StandardMaterial3D
				if m and m.emission_enabled:
					m = m.duplicate()
					(mi as MeshInstance3D).set_surface_override_material(s, m)
					mats.append(m)
		var light := OmniLight3D.new()
		light.light_color = Color("#ff6a2a")
		light.light_energy = 1.2
		light.omni_range = 7.0
		light.position = p + Vector3(0, 1.0, 0)
		_env_root.add_child(light)
		var smoke := CPUParticles3D.new()
		smoke.amount = 14
		smoke.lifetime = 4.0
		smoke.preprocess = 4.0
		smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		smoke.emission_sphere_radius = 1.0
		smoke.direction = Vector3(0.2, 1, 0)
		smoke.spread = 15.0
		smoke.initial_velocity_min = 0.6
		smoke.initial_velocity_max = 1.1
		smoke.gravity = Vector3(0.15, 0.1, 0)
		smoke.scale_amount_min = 1.0
		smoke.scale_amount_max = 2.2
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0.4))
		curve.add_point(Vector2(1, 1.6))
		smoke.scale_amount_curve = curve
		var grad := Gradient.new()
		grad.set_color(0, Color(0.45, 0.4, 0.38, 0.0))
		grad.add_point(0.15, Color(0.42, 0.38, 0.36, 0.45))
		grad.set_color(grad.get_point_count() - 1, Color(0.5, 0.48, 0.48, 0.0))
		smoke.color_ramp = grad
		var q := QuadMesh.new()
		q.size = Vector2(1.6, 1.6)
		var sm := StandardMaterial3D.new()
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		sm.vertex_color_use_as_albedo = true
		sm.albedo_texture = _soft_dot()
		q.material = sm
		smoke.mesh = q
		smoke.position = p + Vector3(0, 0.4, 0)
		_env_root.add_child(smoke)
		var embers := CPUParticles3D.new()
		embers.amount = 10
		embers.lifetime = 1.6
		embers.preprocess = 2.0
		embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		embers.emission_sphere_radius = 0.9
		embers.direction = Vector3(0, 1, 0)
		embers.spread = 25.0
		embers.initial_velocity_min = 1.0
		embers.initial_velocity_max = 2.2
		embers.gravity = Vector3(0, -0.5, 0)
		var eq := QuadMesh.new()
		eq.size = Vector2(0.12, 0.12)
		eq.material = _emissive(Color("#ff8a3a"), 6.0)
		(eq.material as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		embers.mesh = eq
		embers.position = p + Vector3(0, 0.2, 0)
		_env_root.add_child(embers)
		_hotspot_nodes.append({"mats": mats, "light": light})
	_set_hotspot_intensity(0.35)


func _set_hotspot_intensity(v: float) -> void:
	for h in _hotspot_nodes:
		for m in h.mats:
			(m as StandardMaterial3D).emission_energy_multiplier = 1.5 + v * 6.0
		(h.light as OmniLight3D).light_energy = 0.6 + v * 2.5


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
	Stylize.apply(model, 0.025)
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
	var h: Dictionary = _hotspot_nodes[hi]
	var tw := create_tween()
	tw.tween_method(func(v: float):
		for m in h.mats:
			(m as StandardMaterial3D).emission_energy_multiplier = 1.5 + v * 6.0
		(h.light as OmniLight3D).light_energy = 0.6 + v * 2.5, 0.35, 1.0, Defs.EMERGE_WARN)
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
	var doors := find_child("GateDoors", true, false) as Node3D
	if doors == null:
		return
	if not doors.has_meta("x0"):
		doors.set_meta("x0", doors.position.x)
	var x0: float = doors.get_meta("x0")
	var tw := create_tween()
	tw.tween_property(doors, "position:x", x0 + 0.12, 0.04)
	tw.tween_property(doors, "position:x", x0 - 0.12, 0.04)
	tw.tween_property(doors, "position:x", x0, 0.04)
