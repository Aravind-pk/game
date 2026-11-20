extends Node3D
## The 3D view of Fortress: low-poly, colourful, toon-lit. It owns no game state: every frame it
## reads the Game node (main.gd) and mirrors it, pooling one node per entity by its `uid`.
## Labels that sit over the world (costs, ammo, HP) are drawn on `ui`, a 2D canvas under the HUD.

const S := 1.0 / 40.0              # game pixels -> metres
const ITEM_H := 0.2                # height of one carried item
const PLAYER_SCALE := 1.55         # characters are drawn bigger than their hit circles so they read on a phone
const MONSTER_SCALE := 1.45

# palette (from the style references: deep teal grass, muted beige paths, lavender-grey rock,
# warm sand yard and pink stations). Values are albedo; the filmic tonemap deepens them further.
const C_GRASS := Color("#3a8c63")
const C_GRASS_DARK := Color("#317b58")
const C_GRASS_LIGHT := Color("#4c9d6c")
const C_PATH := Color("#d7bf8c")
const C_PATH_EDGE := Color("#b9a072")
const C_SAND := Color("#e5c487")
const C_YARD_GRASS := Color("#4fb36f")
const C_HEDGE := Color("#2c7f4f")
const C_ROCK := Color("#a9a6ba")
const C_CLIFF := Color("#b8b3c6")
const C_STONE := Color("#c4c2cf")
const C_STONE_DARK := Color("#8e8ca3")
const C_WOOD := Color("#a8693a")
const C_WOOD_DARK := Color("#6e4224")
const C_TREE := Color("#2b7a4b")
const C_TREE_LIGHT := Color("#3f9358")
const C_PINK := Color("#e57b8a")
const C_PINK_DARK := Color("#b4485e")
const C_TEAL := Color("#69c3d6")
const C_BLUE := Color("#3a6fd0")
const C_GOLD := Color("#ffc23a")
const C_AMMO := Color("#ffc940")
const C_OUTLINE := Color("#241d2c")
const C_WHITEWASH := Color("#efe8d8")
const C_REDCOAT := Color("#c8322f")
const C_REDCOAT_DARK := Color("#9a2522")
const C_NAVY := Color("#24304f")
const C_BRASS := Color("#d9a441")
const C_BRICK := Color("#a8503e")
const C_SKIN := Color("#ffd3a8")

var g: Node                         # the game (main.gd)
var cam: Camera3D
var sun: DirectionalLight3D
var ui: Node2D
var font: Font
var font_b: Font
var t := 0.0
var shake := 0.0
var cam_look := Vector3.ZERO
var cam_pitch := 56.0
var cam_dist := 34.0
var vignette: TextureRect

var mats := {}
var meshes := {}
var pools := {}                     # category -> {uid: Node3D}
var last := {}                      # uid -> last seen dictionary snapshot (pos, hp) for animation
var nodes3d: Array = []             # trees and rocks, by index of g.nodes
var node_stock: Array = []
var turrets3d: Array = []
var turret_keys: Array = []
var machine3d: Node3D
var gear: Node3D
var out_boxes: Array = []
var in_logs: Array = []
var pads3d := {}                    # pad id -> {root, fill, ghost}
var houses: Array = []
var house_root: Node3D
var player3d: Node3D
var player_parts := {}
var stack_root: Node3D
var stack_nodes: Array = []
var stack_kinds: Array = []
var player_prev := Vector2.ZERO
var player_speed := 0.0
var player_yaw := 0.0
var walk_phase := 0.0
var arrow: Node3D
var wall_mat: StandardMaterial3D
var was_down := false
var officer3d := {}
var officer_step := -1
var vault_shot_done := false
var launchers3d: Array = []
var bots3d: Array = []
var built_seen := {}
var was_state := "play"


func _ready() -> void:
	g = get_node("../Game")
	font = load("res://fonts/BarlowCondensed-ExtraBold.ttf")
	font_b = load("res://fonts/Barlow-Bold.ttf")
	ui = Node2D.new()
	ui.name = "WorldUI"
	add_child(ui)
	ui.draw.connect(_draw_ui)
	_build_environment()
	_build_ground()
	_build_cliffs_and_decor()
	_build_fence()
	_build_yard()
	_build_nodes()
	_build_turrets()
	_build_machine()
	_build_pads()
	_build_player()
	_build_arrow()
	if g.args.has("gallery"):
		_gallery.call_deferred()


# ================================================================== helpers

func w(p: Vector2, h: float = 0.0) -> Vector3:
	return Vector3((p.x - 600.0) * S, h, (p.y - 1100.0) * S)


func mat(col: Color, outline: bool = false, alpha: float = 1.0, unshaded: bool = false) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [col.to_html(), outline, alpha, unshaded]
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col, alpha)
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shadow_enabled = false
	if outline and false:  # inverted-hull outlines break on hard edges; the references use none
		var o := StandardMaterial3D.new()
		o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		o.albedo_color = C_OUTLINE
		o.cull_mode = BaseMaterial3D.CULL_FRONT
		o.grow = true
		o.grow_amount = 0.022
		m.next_pass = o
	mats[key] = m
	return m


## A unique, animatable copy of a material (for flashes and tints).
func own_mat(col: Color, outline: bool = false) -> StandardMaterial3D:
	var m: StandardMaterial3D = mat(col, outline).duplicate()
	return m


func box(sx: float, sy: float, sz: float) -> Mesh:
	var key := "box%.3f,%.3f,%.3f" % [sx, sy, sz]
	if not meshes.has(key):
		var b := BoxMesh.new()
		b.size = Vector3(sx, sy, sz)
		meshes[key] = b
	return meshes[key]


func cyl(top: float, bottom: float, h: float, seg: int = 8) -> Mesh:
	var key := "cyl%.3f,%.3f,%.3f,%d" % [top, bottom, h, seg]
	if not meshes.has(key):
		var c := CylinderMesh.new()
		c.top_radius = top
		c.bottom_radius = bottom
		c.height = h
		c.radial_segments = seg
		c.rings = 1
		meshes[key] = c
	return meshes[key]


func ball(r: float, seg: int = 12, rings: int = 6, hemi: bool = false) -> Mesh:
	var key := "ball%.3f,%d,%d,%s" % [r, seg, rings, hemi]
	if not meshes.has(key):
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * (1.0 if hemi else 2.0)
		s.radial_segments = seg
		s.rings = rings
		s.is_hemisphere = hemi
		meshes[key] = s
	return meshes[key]


func prism(sx: float, sy: float, sz: float) -> Mesh:
	var key := "prism%.3f,%.3f,%.3f" % [sx, sy, sz]
	if not meshes.has(key):
		var p := PrismMesh.new()
		p.size = Vector3(sx, sy, sz)
		meshes[key] = p
	return meshes[key]


## Flat-shaded, jittered copy of a mesh: the faceted low-poly look of rocks, cliffs and trees.
func faceted(src: Mesh, jitter: float, seed_v: int) -> Mesh:
	var key := "fac%d,%.3f,%d" % [src.get_instance_id(), jitter, seed_v]
	if meshes.has(key):
		return meshes[key]
	var arr := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for i in idx:
		var v: Vector3 = verts[i]
		var hv := hash(Vector3i(roundi(v.x * 100.0), roundi(v.y * 100.0), roundi(v.z * 100.0)) + Vector3i(seed_v, 0, 0))
		var j := Vector3(float(hv & 255) / 255.0 - 0.5, float((hv >> 8) & 255) / 255.0 - 0.5, float((hv >> 16) & 255) / 255.0 - 0.5)
		st.add_vertex(v + j * jitter)
	st.generate_normals()
	var m := st.commit()
	meshes[key] = m
	return m


func add(parent: Node, mesh: Mesh, m: Material, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO,
		scl: Vector3 = Vector3.ONE, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func node3(parent: Node, pos: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func pop_in(n: Node3D, delay: float = 0.0) -> void:
	var target := n.scale
	n.scale = target * 0.01
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(n, "scale", target, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func yaw_of(d: Vector2) -> float:
	return atan2(-d.x, -d.y)


# ================================================================== world building

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#9ccbe0")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#b9cfee")
	env.ambient_light_energy = float(g.args.get("amb", "0.3"))
	env.tonemap_mode = int(g.args.get("tm", "0"))
	env.tonemap_exposure = 1.0
	env.tonemap_white = float(g.args.get("white", "1.25"))
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
	env.adjustment_contrast = 1.06
	env.fog_enabled = true
	env.fog_light_color = Color("#a9cde0")
	env.fog_density = 0.0
	env.fog_height = 2.0
	env.fog_height_density = 0.0
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 48.0
	env.fog_depth_end = 95.0
	env.fog_depth_curve = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -40, 0)
	sun.light_energy = float(g.args.get("sun", "0.7"))
	sun.light_color = Color("#ffe9c9")
	sun.shadow_enabled = true
	sun.shadow_blur = 2.0
	sun.shadow_opacity = 0.8
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.35
	sun.directional_shadow_max_distance = 48.0
	add_child(sun)
	cam = Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	var a: Dictionary = g.args
	cam_pitch = float(a.get("pitch", "56"))
	cam.fov = float(a.get("fov", "30"))
	cam_dist = float(a.get("dist", "30"))
	cam.rotation_degrees = Vector3(-cam_pitch, 0, 0)
	cam.far = 200.0
	add_child(cam)
	cam.make_current()
	cam_look = _cam_target()
	_place_camera(Vector3.ZERO)
	# a soft vignette for depth
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var vig := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0.05, 0.03, 0.12, 0.42))
	grad.set_offset(0, 0.55)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.05, 1.05)
	vig.texture = tex
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.size = Vector2(720, 1280)
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(vig)
	vignette = vig



func _build_ground() -> void:
	var root := node3(self)
	add(root, box(120, 1, 120), mat(C_GRASS), Vector3(0, -0.5, -10), Vector3.ZERO, Vector3.ONE, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 70:  # darker and lighter patches break up the field
		var p := Vector3(rng.randf_range(-16, 16), 0.004 + i * 0.0001, rng.randf_range(-32, -1))
		add(root, cyl(rng.randf_range(0.8, 2.2), rng.randf_range(0.8, 2.2), 0.01, 7), mat(C_GRASS_DARK if i % 3 else C_GRASS_LIGHT), p,
			Vector3(0, rng.randf() * TAU, 0), Vector3(1, 1, rng.randf_range(0.5, 1.0)), false)
	# the winding monster paths: a ribbon with a darker edge, and pebbles along it
	for path in g.paths:
		var pts: PackedVector2Array = path.pts
		add(root, _ribbon(pts, 1.05, 0.012), mat(C_PATH_EDGE), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
		add(root, _ribbon(pts, 0.85, 0.02), mat(C_PATH), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
		for k in range(2, pts.size() - 2, 3):
			var d := (pts[k + 1] - pts[k - 1]).normalized()
			var side := Vector2(-d.y, d.x) * (1.0 if k % 2 == 0 else -1.0)
			var at := pts[k] + side * rng.randf_range(44.0, 52.0)
			add(root, faceted(ball(0.1, 5, 3), 0.05, k), mat(C_ROCK), w(at, 0.04), Vector3(0, k, 0), Vector3.ONE * rng.randf_range(0.6, 1.3),
				false)
	# grass tufts and flowers
	for i in 120:
		var p2 := Vector2(rng.randf_range(30, 1170), rng.randf_range(-200, 1080))
		if _near_path(p2, 50.0):
			continue
		var tuft := node3(root, w(p2))
		for k in 3:
			add(tuft, prism(0.08, 0.3, 0.04), mat(C_GRASS_LIGHT), Vector3((k - 1) * 0.07, 0.14, 0), Vector3(0, k * 0.9, (k - 1) * 0.35),
				Vector3.ONE, false)
		if i % 5 == 0:
			var fc := [Color("#ffd84a"), Color("#ff86a8"), Color("#f4f0ff")][i % 3] as Color
			add(tuft, ball(0.07, 6, 3), mat(fc), Vector3(0.12, 0.1, 0.05), Vector3.ZERO, Vector3.ONE, false)



func _near_path(p: Vector2, r: float) -> bool:
	for path in g.paths:
		for q in (path.pts as PackedVector2Array):
			if q.distance_to(p) < r:
				return true
	return false


## A flat strip along a polyline, `half` metres to each side.
func _ribbon(pts: PackedVector2Array, half: float, h: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in pts.size():
		var d := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := Vector3(-d.y, 0, d.x) * half
		var c := w(pts[i], h)
		var l := c - side
		var r := c + side
		if i > 0:
			st.add_vertex(prev_l)
			st.add_vertex(l)
			st.add_vertex(r)
			st.add_vertex(prev_l)
			st.add_vertex(r)
			st.add_vertex(prev_r)
		prev_l = l
		prev_r = r
	return st.commit()



func _build_cliffs_and_decor() -> void:
	var root := node3(self)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var k := 0
	# the far edge: a forest and rocky ridge the paths come out of
	var x := -18.0
	while x < 18.0:
		var on_path := false
		for path in g.paths:
			if absf(w((path.pts as PackedVector2Array)[0]).x - x) < 1.6:
				on_path = true
		if not on_path:
			var h := rng.randf_range(2.0, 4.0)
			add(root, faceted(ball(1.0, 6, 4), 0.35, k), mat(C_CLIFF if k % 3 else C_ROCK), Vector3(x, h * 0.3, rng.randf_range(-33.5, -31.0)),
				Vector3(0, rng.randf() * TAU, 0), Vector3(1.8, h, 1.6))
		for j in 2:
			var tp := Vector3(x + rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-30.5, -28.5) - j * 1.2)
			if not on_path:
				_cone_tree(root, tp, rng.randf_range(0.9, 1.3), k * 3 + j)
		x += rng.randf_range(1.2, 1.9)
		k += 1
	# the sides: ridges of rock with woods in front of them
	for side in [-1.0, 1.0]:
		var z := -32.0
		while z < 14.0:
			var hh := rng.randf_range(1.8, 3.8)
			add(root, faceted(ball(1.0, 6, 4), 0.35, k), mat(C_CLIFF if k % 3 else C_ROCK), Vector3(side * rng.randf_range(17.0, 18.5), hh * 0.3, z),
				Vector3(0, rng.randf() * TAU, 0), Vector3(1.9, hh, 1.7))
			if z < -0.5:
				_cone_tree(root, Vector3(side * rng.randf_range(15.4, 16.4), 0, z + rng.randf_range(-0.6, 0.6)), rng.randf_range(0.9, 1.3), 400 + k)
			z += rng.randf_range(1.3, 2.2)
			k += 1
	# scattered trees and boulders out in the field, away from the paths and the resource flanks
	for i in 26:
		var p := Vector2(rng.randf_range(80, 1120), rng.randf_range(-240, 560))
		if _near_path(p, 80.0):
			continue
		if i % 3 == 0:
			add(root, faceted(ball(0.5, 6, 4), 0.2, 600 + i), mat(C_ROCK), w(p, 0.25), Vector3(0, rng.randf() * TAU, 0), Vector3.ONE * rng.randf_range(0.7, 1.3))
		else:
			_cone_tree(root, w(p), rng.randf_range(0.8, 1.2), 700 + i)



func _cone_tree(parent: Node3D, p: Vector3, s: float, seed_v: int) -> Node3D:
	var tree := node3(parent, p)
	tree.scale = Vector3.ONE * s
	add(tree, cyl(0.08, 0.11, 0.5, 6), mat(C_WOOD_DARK), Vector3(0, 0.25, 0))
	add(tree, cyl(0.0, 0.66, 0.95, 12), mat(C_TREE), Vector3(0, 0.8, 0))
	add(tree, cyl(0.0, 0.52, 0.85, 12), mat(C_TREE.lerp(C_TREE_LIGHT, 0.5)), Vector3(0, 1.22, 0))
	add(tree, cyl(0.0, 0.36, 0.7, 12), mat(C_TREE_LIGHT), Vector3(0, 1.62, 0))
	return tree


func _build_fence() -> void:
	var root := node3(self)
	wall_mat = own_mat(C_WHITEWASH)
	var coping := mat(C_REDCOAT_DARK)
	var z: float = (g.FENCE_H * 0.5) * S
	var cuts := []
	for lx in g.LANES:
		cuts.append((lx - 600.0) * S)
	var a := -15.0
	for i in cuts.size() + 1:
		var b: float = (cuts[i] - 0.6) if i < cuts.size() else 15.0
		add(root, box(b - a, 0.62, 0.26), wall_mat, Vector3((a + b) * 0.5, 0.31, z))                 # a thin whitewashed wall
		add(root, box(b - a, 0.1, 0.24), mat(C_STONE_DARK), Vector3((a + b) * 0.5, 0.05, z))          # its stone footing
		add(root, box(b - a, 0.06, 0.32), coping, Vector3((a + b) * 0.5, 0.65, z))                    # red coping
		var mx := a + 0.22
		while mx < b - 0.12:  # small crenellations
			add(root, box(0.22, 0.18, 0.26), wall_mat, Vector3(mx, 0.77, z))
			add(root, box(0.24, 0.03, 0.28), coping, Vector3(mx, 0.875, z))
			mx += 0.5
		var post := a + 1.4
		while post < b - 0.4:  # slim pilasters
			add(root, box(0.16, 0.66, 0.34), mat(C_WHITEWASH.darkened(0.06)), Vector3(post, 0.33, z))
			post += 2.8
		a = (cuts[i] + 0.6) if i < cuts.size() else 15.0



func _build_yard() -> void:
	var root := node3(self)
	var z0: float = g.FENCE_H * S
	var depth: float = (g.H - g.FENCE_Y - g.FENCE_H) * S
	add(root, box(30.0, 0.04, depth + 0.4), mat(C_SAND), Vector3(0, 0.02, z0 + depth * 0.5 + 0.2), Vector3.ZERO, Vector3.ONE, false)
	add(root, box(34.0, 0.03, 6.0), mat(C_GRASS), Vector3(0, 0.015, z0 + depth + 3.2), Vector3.ZERO, Vector3.ONE, false)
	add(root, box(30.0, 0.03, 0.45), mat(C_SAND.darkened(0.08)), Vector3(0, 0.035, z0 + 0.22), Vector3.ZERO, Vector3.ONE, false)
	# hedges along the yard's sides, bright lawn beyond
	for side in [-1.0, 1.0]:
		add(root, box(4.0, 0.05, depth + 2.0), mat(C_YARD_GRASS), Vector3(side * 17.0, 0.02, z0 + depth * 0.5), Vector3.ZERO, Vector3.ONE, false)
		add(root, box(0.45, 0.7, depth), mat(C_HEDGE), Vector3(side * 15.1, 0.35, z0 + depth * 0.5))
	add(root, box(31.0, 0.7, 0.45), mat(C_HEDGE), Vector3(0, 0.35, z0 + depth + 0.2))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 60:  # sand speckles and little stones
		add(root, cyl(0.05, 0.05, 0.01, 5), mat(C_SAND.darkened(0.12)), Vector3(rng.randf_range(-14.5, 14.5), 0.045,
			rng.randf_range(z0 + 0.6, z0 + depth - 0.3)), Vector3.ZERO, Vector3.ONE, false)
	for i in 8:  # little crates and barrels by the wall, for life
		var p := Vector3(rng.randf_range(-14, 14), 0, z0 + rng.randf_range(0.6, 1.0))
		var near_tower := false
		for lx in g.LANES:
			if absf(p.x - (lx - 600.0) * S) < 2.4:
				near_tower = true
		if near_tower:
			continue
		if i % 2 == 0:
			add(root, box(0.4, 0.4, 0.4), mat(C_WOOD), p + Vector3(0, 0.2, 0), Vector3(0, rng.randf(), 0))
		else:
			add(root, cyl(0.18, 0.18, 0.45, 8), mat(C_WOOD_DARK), p + Vector3(0, 0.22, 0))
	house_root = node3(root)



## The fort's buildings, one more for every pad you finish: verandah bungalows, red-brick Georgian
## houses, a long barracks and the governor's house with its portico.
func _house(i: int) -> Node3D:
	var slots := [Vector2(150, 1585), Vector2(1050, 1585), Vector2(300, 1592), Vector2(900, 1592), Vector2(450, 1598),
		Vector2(750, 1598), Vector2(85, 1480), Vector2(1115, 1480), Vector2(100, 1370), Vector2(1100, 1370)]
	var at: Vector2 = slots[i % slots.size()]
	var h := node3(house_root, w(at))
	h.rotation.y = [0.05, -0.06, 0.0, 0.08, -0.03][i % 5]
	match ["bungalow", "brick", "barracks", "bungalow", "governor", "brick", "bungalow", "barracks", "brick", "bungalow"][i % 10]:
		"bungalow":
			_bungalow(h, i)
		"brick":
			_brick_house(h, i)
		"barracks":
			_barracks_block(h)
		"governor":
			_governor(h)
	return h



func _build_nodes() -> void:
	for i in g.nodes.size():
		var n: Dictionary = g.nodes[i]
		var root := node3(self, w(n.pos))
		var full := node3(root)
		var empty := node3(root)
		if n.kind == "wood":
			_cone_tree(full, Vector3.ZERO, 1.25, 200 + i)
			add(empty, cyl(0.16, 0.2, 0.22, 7), mat(C_WOOD), Vector3(0, 0.11, 0))
			add(empty, cyl(0.12, 0.12, 0.01, 7), mat(Color("#e9c48a")), Vector3(0, 0.225, 0), Vector3.ZERO, Vector3.ONE, false)
		else:
			add(full, faceted(ball(0.55, 6, 4), 0.22, 300 + i), mat(C_ROCK), Vector3(0, 0.38, 0), Vector3(0, i, 0), Vector3(1.1, 0.85, 1.0))
			add(full, faceted(ball(0.3, 6, 3), 0.12, 320 + i), mat(C_ROCK.lightened(0.1)), Vector3(0.45, 0.2, 0.2))
			add(empty, faceted(ball(0.16, 5, 3), 0.06, 340 + i), mat(C_ROCK), Vector3(-0.15, 0.1, 0.1))
			add(empty, faceted(ball(0.12, 5, 3), 0.05, 360 + i), mat(C_ROCK), Vector3(0.2, 0.08, -0.05))
		nodes3d.append({"root": root, "full": full, "empty": empty})
		node_stock.append(n.stock)


func _build_turrets() -> void:
	for i in g.turrets.size():
		var tr: Dictionary = g.turrets[i]
		var root := node3(self, w(tr.pos))
		root.scale = Vector3.ONE * 1.2
		var tm := _tower_model(root)
		turrets3d.append({"root": root, "found": tm.found, "tower": tm.tower, "head": tm.head, "gun": null, "recoil": 0.0, "yaw": 0.0,
			"aura": tm.aura, "flag": tm.flag})
		turret_keys.append("")


func _tower_model(root: Node3D) -> Dictionary:
	var found := node3(root)  # foundation shown before it is built
	add(found, cyl(0.6, 0.66, 0.24, 20), mat(C_STONE_DARK), Vector3(0, 0.12, 0))
	var tower := node3(root)
	add(tower, cyl(0.56, 0.64, 1.2, 24), wall_mat, Vector3(0, 0.6, 0))                             # round bastion
	add(tower, cyl(0.62, 0.66, 0.14, 24), mat(C_STONE_DARK), Vector3(0, 0.07, 0))
	add(tower, cyl(0.6, 0.6, 0.12, 24), mat(C_REDCOAT), Vector3(0, 0.9, 0))                         # red band
	add(tower, cyl(0.68, 0.68, 0.1, 24), mat(C_REDCOAT_DARK), Vector3(0, 1.24, 0))                  # parapet ledge
	for k in 8:
		var a := TAU * k / 8.0
		add(tower, box(0.2, 0.2, 0.14), wall_mat, Vector3(cos(a) * 0.6, 1.38, sin(a) * 0.6), Vector3(0, -a, 0))
	add(tower, box(0.18, 0.28, 0.04), mat(Color("#3a2a20")), Vector3(0, 0.55, 0.62))                # arrow slit / door
	# a pennant on a pole at the back, waving
	var pole := node3(tower, Vector3(0.45, 1.3, 0.35))
	add(pole, cyl(0.02, 0.025, 1.1, 8), mat(C_WOOD_DARK), Vector3(0, 0.55, 0))
	add(pole, ball(0.04, 8, 4), mat(C_GOLD), Vector3(0, 1.12, 0))
	var flag := node3(pole, Vector3(0, 0.95, 0))
	add(flag, box(0.42, 0.09, 0.02), mat(C_REDCOAT), Vector3(0.21, 0.08, 0), Vector3.ZERO, Vector3.ONE, false)
	add(flag, box(0.42, 0.07, 0.02), mat(Color("#f4f0e6")), Vector3(0.21, 0.0, 0), Vector3.ZERO, Vector3.ONE, false)
	add(flag, box(0.42, 0.09, 0.02), mat(Color("#25407a")), Vector3(0.21, -0.08, 0), Vector3.ZERO, Vector3.ONE, false)
	var aura := add(tower, cyl(0.95, 0.95, 0.02, 24), mat(Color("#7af1eb"), false, 0.45, true), Vector3(0, 1.31, 0), Vector3.ZERO,
		Vector3.ONE, false)
	aura.visible = false
	var head := node3(tower, Vector3(0, 1.35, 0))
	return {"found": found, "tower": tower, "head": head, "aura": aura, "flag": flag}

func _turret_gun(i: int) -> void:
	var td: Dictionary = turrets3d[i]
	var tr: Dictionary = g.turrets[i]
	if td.gun != null:
		td.gun.queue_free()
	td.gun = _gun_model(td.head, int(tr.level), tr.evo)
	pop_in(td.gun)


func _gun_model(head: Node3D, level: int, evo: String) -> Node3D:
	var gun := node3(head)
	var brass := mat(C_BRASS)
	var iron := mat(Color("#33343c"))
	var carriage := mat(C_REDCOAT_DARK if evo == "cannon" else C_WOOD)
	add(gun, box(0.5, 0.18, 0.62), carriage, Vector3(0, 0.08, 0.05))                                  # carriage
	for sx in [-0.29, 0.29]:  # wheels
		add(gun, cyl(0.2, 0.2, 0.06, 16), mat(C_WOOD_DARK), Vector3(sx, 0.1, 0.12), Vector3(0, 0, PI * 0.5))
		add(gun, cyl(0.06, 0.06, 0.08, 10), brass, Vector3(sx, 0.1, 0.12), Vector3(0, 0, PI * 0.5))
	var tip := -0.85
	match evo:
		"gatling":
			var spin := node3(gun, Vector3(0, 0.3, -0.2))
			spin.name = "Spin"
			for k in 6:
				var a := TAU * k / 6.0
				add(spin, cyl(0.03, 0.03, 0.72, 8), brass, Vector3(cos(a) * 0.08, sin(a) * 0.08, -0.3), Vector3(PI * 0.5, 0, 0))
			add(spin, cyl(0.13, 0.13, 0.06, 12), brass, Vector3(0, 0, -0.6), Vector3(PI * 0.5, 0, 0))
			add(gun, box(0.22, 0.2, 0.3), brass, Vector3(0, 0.3, 0.12))                                  # breech
			add(gun, box(0.1, 0.18, 0.12), mat(C_WOOD_DARK), Vector3(0, 0.46, 0.1))                    # magazine
			tip = -0.95
		"cannon":
			add(gun, cyl(0.14, 0.2, 0.85, 16), iron, Vector3(0, 0.3, -0.3), Vector3(PI * 0.5, 0, 0))
			add(gun, cyl(0.2, 0.2, 0.06, 16), iron, Vector3(0, 0.3, -0.72), Vector3(PI * 0.5, 0, 0))
			add(gun, ball(0.12, 12, 6), iron, Vector3(0, 0.3, 0.16))
			tip = -0.95
		"frost":
			add(gun, cyl(0.07, 0.1, 0.62, 12), mat(Color("#9fb7c8")), Vector3(0, 0.28, -0.3), Vector3(PI * 0.5, 0, 0))
			add(gun, faceted(ball(0.16, 6, 3), 0.0, 1), mat(Color("#c9f1ff")), Vector3(0, 0.28, -0.66), Vector3.ZERO, Vector3(1, 1, 1.4))
			add(gun, faceted(cyl(0.0, 0.12, 0.35, 5), 0.0, 2), mat(Color("#c9f1ff")), Vector3(0, 0.45, 0.1))
			tip = -0.8
		_:
			add(gun, cyl(0.06, 0.09, 0.7, 14), brass, Vector3(0, 0.27, -0.25), Vector3(PI * 0.5, 0, 0))
			add(gun, ball(0.1, 12, 6), brass, Vector3(0, 0.27, 0.12))
	if level >= 2:  # gold band on the carriage for level 2+
		add(gun, box(0.52, 0.04, 0.1), mat(C_GOLD), Vector3(0, 0.18, 0.32), Vector3.ZERO, Vector3.ONE, false)
	var flash := add(gun, ball(0.16, 8, 4), mat(Color("#fff2b0"), false, 1.0, true), Vector3(0, 0.28, tip), Vector3.ZERO,
		Vector3.ONE, false)
	flash.visible = false
	flash.name = "Flash"
	return gun


func _build_machine() -> void:
	machine3d = node3(self, w(g.MACHINE_POS))
	var m := machine3d
	add(m, box(1.7, 0.85, 1.3), mat(C_BRICK), Vector3(0, 0.43, 0))                                      # the powder works
	for k in 4:  # brick courses
		add(m, box(1.71, 0.02, 1.31), mat(C_BRICK.darkened(0.15)), Vector3(0, 0.2 + k * 0.2, 0), Vector3.ZERO, Vector3.ONE, false)
	add(m, box(1.82, 0.12, 1.42), mat(C_WOOD_DARK), Vector3(0, 0.9, 0))
	add(m, prism(1.3, 0.45, 1.86), mat(Color("#3f5a7a")), Vector3(0, 1.18, 0.05), Vector3(0, PI * 0.5, 0))   # slate roof
	add(m, cyl(0.3, 0.22, 0.45, 14), mat(C_BRASS), Vector3(-0.55, 1.2, -0.2))                           # copper hopper
	add(m, box(0.26, 0.9, 0.26), mat(C_BRICK.darkened(0.1)), Vector3(0.55, 1.35, -0.25))               # chimney
	add(m, box(0.32, 0.06, 0.32), mat(C_STONE_DARK), Vector3(0.55, 1.82, -0.25))
	machine3d.set_meta("stack_top", Vector3(0.55, 1.9, -0.25))
	add(m, box(0.42, 0.55, 0.05), mat(C_WOOD_DARK), Vector3(-0.4, 0.3, 0.66))                          # door
	gear = node3(m, Vector3(0.45, 0.5, 0.67))
	add(gear, cyl(0.28, 0.28, 0.06, 16), mat(C_BRASS), Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
	for k in 4:
		add(gear, box(0.66, 0.08, 0.08), mat(C_BRASS.darkened(0.2)), Vector3(0, 0, 0.03), Vector3(0, 0, k * PI * 0.25))
	add(m, box(0.5, 0.1, 0.9), mat(C_WOOD), Vector3(-0.35, 0.72, -0.9), Vector3(0.5, 0, 0))            # chute to the pile
	for k in 8:  # the input pile of logs beside it
		var lg := add(m, item_mesh("wood"), item_mat("wood"), Vector3(1.15 + (k % 2) * 0.22, 0.08 + (k / 2) * 0.17, 0.2),
			Vector3(0, PI * 0.5, PI * 0.5))
		in_logs.append(lg)
	var out := node3(self, w(g.OUTPUT_POS))  # a wooden trestle for the crates
	add(out, box(1.7, 0.08, 1.0), mat(C_WOOD), Vector3(0, 0.42, 0))
	for sx in [-0.7, 0.7]:
		for sz in [-0.4, 0.4]:
			add(out, box(0.08, 0.42, 0.08), mat(C_WOOD_DARK), Vector3(sx, 0.21, sz))
	for i in g.MACHINE_OUT_MAX:
		var col: int = i % 4
		var row: int = (i / 4) % 2
		var lay: int = i / 8
		var b := item_node(out, "ammo")
		b.position = Vector3(-0.54 + col * 0.36, 0.56 + lay * 0.2, -0.18 + row * 0.36)
		b.visible = false
		out_boxes.append(b)
	machine3d.set_meta("out", out)
	machine3d.visible = false
	out.visible = false



func item_mesh(kind: String) -> Mesh:
	match kind:
		"wood":
			return cyl(0.09, 0.09, 0.42, 7)
		"stone":
			return faceted(ball(0.15, 6, 3), 0.05, 7)
		"coin":
			return cyl(0.15, 0.15, 0.05, 10)
		_:
			return box(0.32, 0.18, 0.26)


func item_mat(kind: String) -> Material:
	match kind:
		"wood":
			return mat(C_WOOD, true)
		"stone":
			return mat(C_ROCK, true)
		"coin":
			return mat(C_GOLD, true)
		_:
			return mat(C_AMMO, true)


## One item as it is held: logs lie sideways, ammo is a red cartridge box with a brass band.
func item_node(parent: Node, kind: String) -> Node3D:
	var n := node3(parent)
	if kind == "wood":
		add(n, item_mesh(kind), item_mat(kind), Vector3.ZERO, Vector3(0, 0, PI * 0.5))
		add(n, cyl(0.07, 0.07, 0.43, 10), mat(Color("#e9c48a")), Vector3.ZERO, Vector3(0, 0, PI * 0.5), Vector3.ONE, false)
	elif kind == "ammo":
		add(n, box(0.32, 0.19, 0.26), mat(C_REDCOAT))
		add(n, box(0.33, 0.05, 0.27), mat(C_BRASS), Vector3(0, 0.03, 0), Vector3.ZERO, Vector3.ONE, false)
	elif kind == "coin":
		add(n, item_mesh(kind), item_mat(kind))
	else:
		add(n, item_mesh(kind), item_mat(kind), Vector3(0, 0.02, 0), Vector3(0, 0, 0), Vector3(1.2, 0.8, 1.0))
	return n



func _build_pads() -> void:
	for pad in g.pads:
		var root := node3(self, w(pad.pos))
		var size := 1.55
		add(root, box(size, 0.05, size), mat(Color.WHITE, false, 0.28), Vector3(0, 0.05, 0), Vector3.ZERO, Vector3.ONE, false)
		for k in 4:  # dashed border
			for d in 4:
				var off := -size * 0.5 + size * (d + 0.25) / 4.0 + size * 0.0625
				var along := Vector3(off, 0.08, -size * 0.5) if k == 0 else (Vector3(off, 0.08, size * 0.5) if k == 1 else
					(Vector3(-size * 0.5, 0.08, off) if k == 2 else Vector3(size * 0.5, 0.08, off)))
				var sz := Vector3(size / 8.0, 0.03, 0.07) if k < 2 else Vector3(0.07, 0.03, size / 8.0)
				add(root, box(sz.x, sz.y, sz.z), mat(Color.WHITE), along, Vector3.ZERO, Vector3.ONE, false)
		var fill := add(root, box(size - 0.16, 0.06, size - 0.16), mat(Color("#7ee8c8"), false, 0.55), Vector3(0, 0.07, 0),
			Vector3.ZERO, Vector3.ONE, false)
		var ghost := node3(root)
		_ghost_model(ghost, pad.id)
		pads3d[pad.id] = {"root": root, "fill": fill, "ghost": ghost, "shown": false}
		root.visible = false


## A see-through preview of what the pad will build.
func _ghost_model(n: Node3D, id: String) -> void:
	var gm := mat(Color("#ffffff"), false, 0.35)
	match id:
		"machine":
			add(n, box(1.3, 0.7, 1.0), gm, Vector3(0, 0.4, 0), Vector3.ZERO, Vector3.ONE, false)
			add(n, cyl(0.35, 0.25, 0.4, 8), gm, Vector3(-0.3, 0.95, 0), Vector3.ZERO, Vector3.ONE, false)
		"turret_l", "turret_r":
			pass  # the tower's foundation already shows it
		"launcher_l", "launcher_r":
			add(n, box(0.9, 0.4, 0.9), gm, Vector3(0, 0.25, 0), Vector3.ZERO, Vector3.ONE, false)
			add(n, box(0.12, 0.12, 1.0), gm, Vector3(0, 0.6, 0), Vector3(0.6, 0, 0), Vector3.ONE, false)
		"fence":
			for k in 3:
				add(n, box(0.35, 0.6, 0.35), gm, Vector3(-0.45 + k * 0.45, 0.35, 0), Vector3.ZERO, Vector3.ONE, false)
		"backpack":
			add(n, box(0.6, 0.7, 0.4), gm, Vector3(0, 0.4, 0), Vector3.ZERO, Vector3.ONE, false)
		"cutter":
			add(n, ball(0.25, 8, 4), gm, Vector3(0, 0.85, 0), Vector3.ZERO, Vector3.ONE, false)
			add(n, cyl(0.16, 0.2, 0.45, 8), gm, Vector3(0, 0.4, 0), Vector3.ZERO, Vector3.ONE, false)


func _launcher(pos: Vector2) -> Node3D:
	var root := node3(self, w(pos))
	add(root, box(1.0, 0.36, 1.0), mat(C_WOOD), Vector3(0, 0.18, 0))
	add(root, box(1.06, 0.07, 1.06), mat(C_REDCOAT_DARK), Vector3(0, 0.38, 0))
	for sx in [-0.35, 0.35]:
		add(root, box(0.1, 0.5, 0.1), mat(C_WOOD_DARK), Vector3(sx, 0.65, 0))
	add(root, cyl(0.04, 0.04, 0.8, 8), mat(C_BRASS), Vector3(0, 0.85, 0), Vector3(0, 0, PI * 0.5))
	var arm := node3(root, Vector3(0, 0.75, 0))
	add(arm, box(0.12, 0.1, 1.1), mat(C_WOOD), Vector3(0, 0, 0.3))
	add(arm, cyl(0.2, 0.14, 0.14, 12), mat(C_WOOD_DARK), Vector3(0, 0.07, 0.85))
	root.set_meta("arm", arm)
	pop_in(root)
	return root


## A chibi redcoat: big head, small body, red coat with white cross-belts and brass buttons.
## `soldier` is the hero (white pith helmet, musket); otherwise a pioneer (forage cap, leather apron,
## axe), the woodcutter.
func _worker(parent: Node, suit: Color, hat: Color, axe: bool = false, soldier: bool = false, officer: bool = false) -> Dictionary:
	var root := node3(parent)
	var body := node3(root)
	var parts := {"root": root, "body": body}
	var coat := mat(C_REDCOAT)
	var white := mat(Color("#f4f0e6"))
	for sx in [-0.1, 0.1]:
		var hip := node3(body, Vector3(sx, 0.3, 0))
		add(hip, cyl(0.075, 0.068, 0.24, 12), mat(C_NAVY), Vector3(0, -0.12, 0))
		add(hip, box(0.02, 0.22, 0.02), mat(C_REDCOAT), Vector3(sx * 0.7, -0.12, 0), Vector3.ZERO, Vector3.ONE, false)  # trouser stripe
		add(hip, box(0.14, 0.11, 0.21), mat(Color("#1f1c22")), Vector3(0, -0.26, -0.03))
		parts["leg%s" % ("l" if sx < 0 else "r")] = hip
	add(body, cyl(0.17, 0.22, 0.4, 16), coat, Vector3(0, 0.48, 0))
	add(body, cyl(0.23, 0.25, 0.1, 16), coat, Vector3(0, 0.3, 0))                                      # coat skirt
	add(body, cyl(0.218, 0.218, 0.05, 16), white, Vector3(0, 0.36, 0))                                 # white belt
	for sgn in [-1.0, 1.0]:  # cross-belts
		add(body, box(0.05, 0.42, 0.02), white, Vector3(0, 0.5, -0.2), Vector3(0.1, 0, sgn * 0.62), Vector3.ONE, false)
		add(body, box(0.05, 0.42, 0.02), white, Vector3(0, 0.5, 0.2), Vector3(-0.1, 0, sgn * 0.62), Vector3.ONE, false)
	for k in 3:  # brass buttons
		add(body, ball(0.02, 6, 3), mat(C_BRASS), Vector3(0.08, 0.42 + k * 0.08, -0.205), Vector3.ZERO, Vector3.ONE, false)
	add(body, box(0.24, 0.07, 0.16), mat(C_NAVY), Vector3(0, 0.66, 0))                                  # collar
	if officer:  # crimson sash and a sword
		add(body, box(0.06, 0.5, 0.02), mat(Color("#8a1a2e")), Vector3(0, 0.5, -0.215), Vector3(0, 0, 0.7), Vector3.ONE, false)
		add(body, box(0.06, 0.5, 0.02), mat(Color("#8a1a2e")), Vector3(0, 0.5, 0.215), Vector3(0, 0, -0.7), Vector3.ONE, false)
		add(body, cyl(0.012, 0.012, 0.5, 6), mat(Color("#d9dde4")), Vector3(-0.24, 0.2, 0.05), Vector3(0.3, 0, 0.25))
		add(body, box(0.08, 0.03, 0.05), mat(C_GOLD), Vector3(-0.2, 0.4, 0.0))
	elif not soldier:  # pioneer's leather apron
		add(body, box(0.3, 0.34, 0.03), mat(Color("#9a6a3e")), Vector3(0, 0.4, -0.22), Vector3(0.1, 0, 0))
	for sx in [-0.24, 0.24]:
		var sh := node3(body, Vector3(sx, 0.6, 0))
		add(sh, ball(0.075, 10, 5), mat(C_GOLD if officer else (C_BRASS if soldier else C_REDCOAT)), Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1.2, 0.6, 1.2))  # epaulette
		add(sh, cyl(0.06, 0.055, 0.24, 12), coat, Vector3(0, -0.11, 0))
		add(sh, cyl(0.062, 0.062, 0.05, 12), white, Vector3(0, -0.21, 0))                              # cuff
		add(sh, ball(0.06, 10, 5), mat(C_SKIN), Vector3(0, -0.26, 0))
		parts["arm%s" % ("l" if sx < 0 else "r")] = sh
	var head := node3(body, Vector3(0, 0.92, 0))
	parts["head"] = head
	add(head, ball(0.27, 20, 10), mat(C_SKIN))
	for sx in [-0.1, 0.1]:
		add(head, ball(0.05, 10, 5), mat(Color("#1d1a24")), Vector3(sx, 0.0, -0.245), Vector3.ZERO, Vector3(1, 1.3, 0.6), false)
		add(head, ball(0.016, 6, 3), mat(Color.WHITE, false, 1.0, true), Vector3(sx + 0.015, 0.025, -0.275), Vector3.ZERO, Vector3.ONE, false)
		add(head, ball(0.045, 8, 4), mat(Color("#ff9e9e")), Vector3(sx * 1.6, -0.08, -0.215), Vector3.ZERO, Vector3(1, 0.6, 0.4), false)
		add(head, box(0.1, 0.025, 0.03), mat(Color("#5a3a24")), Vector3(sx, 0.085, -0.25), Vector3(0, 0, -sx * 2.5), Vector3.ONE, false)
		add(head, box(0.09, 0.035, 0.04), mat(Color("#6a4428")), Vector3(sx * 0.6, -0.09, -0.255), Vector3(0, 0, sx * 2.0), Vector3.ONE, false)  # moustache
	if officer:  # black bicorne worn side to side, gold trim and a red cockade; white whiskers
		add(head, prism(0.72, 0.3, 0.2), mat(Color("#1d1a24")), Vector3(0, 0.3, 0.0))
		add(head, box(0.7, 0.03, 0.21), mat(C_GOLD), Vector3(0, 0.16, 0.0), Vector3.ZERO, Vector3.ONE, false)
		add(head, cyl(0.05, 0.05, 0.02, 12), mat(C_REDCOAT), Vector3(0.12, 0.26, -0.11), Vector3(PI * 0.5, 0, 0), Vector3.ONE, false)
		add(head, ball(0.255, 18, 9, true), mat(Color("#cfc8c0")), Vector3(0, 0.0, 0.04), Vector3.ZERO, Vector3(1, 0.5, 1))
		for sx in [-0.1, 0.1]:
			add(head, box(0.14, 0.05, 0.05), mat(Color("#f4f0e6")), Vector3(sx * 0.8, -0.09, -0.26), Vector3(0, 0, sx * 3.0), Vector3.ONE, false)
	elif soldier:  # white pith helmet with a brass spike
		add(head, ball(0.25, 20, 10, true), white, Vector3(0, 0.1, 0.01), Vector3.ZERO, Vector3(1.0, 1.15, 1.08))
		add(head, cyl(0.29, 0.29, 0.025, 24), white, Vector3(0, 0.11, 0.01), Vector3.ZERO, Vector3(1.0, 1.0, 1.12))
		add(head, cyl(0.26, 0.26, 0.05, 20), mat(Color("#d9cfb5")), Vector3(0, 0.15, 0.01), Vector3.ZERO, Vector3(1.0, 1.0, 1.08))  # puggaree band
		add(head, cyl(0.0, 0.035, 0.1, 8), mat(C_BRASS), Vector3(0, 0.42, 0.01))
		add(head, ball(0.255, 18, 9, true), mat(Color("#5a3a24")), Vector3(0, 0.0, 0.04), Vector3.ZERO, Vector3(1, 0.45, 1))  # hair under it
	elif not officer:  # navy forage cap with a red band
		add(head, cyl(0.24, 0.24, 0.14, 18), mat(C_NAVY), Vector3(0, 0.27, 0.0), Vector3(-0.15, 0, 0.2))
		add(head, cyl(0.245, 0.245, 0.04, 18), mat(C_REDCOAT), Vector3(0, 0.22, 0.0), Vector3(-0.15, 0, 0.2))
		add(head, ball(0.255, 18, 9, true), mat(Color("#5a3a24")), Vector3(0, 0.04, 0.03), Vector3.ZERO, Vector3(1, 0.5, 1))  # hair
	if axe:
		var handle := node3(parts.armr, Vector3(0, -0.24, -0.05))
		add(handle, cyl(0.025, 0.025, 0.5, 8), mat(C_WOOD_DARK), Vector3(0, 0.12, -0.1), Vector3(-0.6, 0, 0))
		add(handle, box(0.05, 0.16, 0.16), mat(Color("#c9d2e0")), Vector3(0, 0.3, -0.24))
		parts["axe"] = handle
	return parts



func _build_player() -> void:
	player_parts = _worker(self, C_REDCOAT, Color.WHITE, false, true)
	player3d = player_parts.root
	player3d.scale = Vector3.ONE * PLAYER_SCALE
	# the musket: held ready when his hands are free, slung on the back while carrying
	var rifle := node3(player_parts.body, Vector3(0.1, 0.42, -0.24))
	add(rifle, box(0.06, 0.08, 0.5), mat(C_WOOD), Vector3(0, 0, 0.05))                                 # stock
	add(rifle, cyl(0.022, 0.022, 0.5, 8), mat(Color("#4a4d58")), Vector3(0, 0.04, -0.3), Vector3(PI * 0.5, 0, 0))
	add(rifle, cyl(0.006, 0.014, 0.18, 6), mat(Color("#d9dde4")), Vector3(0, 0.04, -0.63), Vector3(PI * 0.5, 0, 0))  # bayonet
	add(rifle, box(0.065, 0.03, 0.08), mat(C_BRASS), Vector3(0, -0.03, 0.22), Vector3.ZERO, Vector3.ONE, false)
	var fl := add(rifle, ball(0.08, 8, 4), mat(Color("#fff2b0"), false, 1.0, true), Vector3(0, 0.04, -0.58), Vector3.ZERO, Vector3.ONE, false)
	fl.visible = false
	player_parts["flash"] = fl
	player_parts["rifle"] = rifle
	stack_root = node3(player_parts.body, Vector3(0, 0.56, -0.36))  # the carried stack rises from his arms
	var aura := add(player3d, cyl(0.62, 0.62, 0.02, 28), mat(Color.WHITE, false, 0.4, true), Vector3(0, 0.03, 0), Vector3.ZERO,
		Vector3.ONE, false)
	aura.visible = false
	player_parts["aura"] = aura
	var stars := node3(player3d, Vector3(0, 1.35, 0))
	for k in 3:
		var a := TAU * k / 3.0
		add(stars, prism(0.12, 0.12, 0.04), mat(C_GOLD, false, 1.0, true), Vector3(cos(a) * 0.3, 0, sin(a) * 0.3), Vector3.ZERO, Vector3.ONE, false)
	stars.visible = false
	player_parts["stars"] = stars
	player_prev = g.player.pos



func _build_arrow() -> void:
	arrow = node3(self)
	var am := mat(Color.WHITE, false, 0.85, true)
	add(arrow, prism(0.5, 0.42, 0.05), am, Vector3(0, 0.06, -1.25), Vector3(-PI * 0.5, 0, 0), Vector3.ONE, false)


func _monster(type: String, r: float) -> Node3D:
	var root := node3(self)
	var body := node3(root)
	body.name = "Body"
	var s := r * S
	var col: Color = g.MONSTERS[type].color
	var m := own_mat(col.lightened(0.05), true)
	root.set_meta("mat", m)
	var eye_w := mat(Color.WHITE, true)
	var pupil := mat(Color("#1d1a24"))
	match type:
		"grunt":
			add(body, ball(1.0, 18, 9), m, Vector3(0, 1.0, 0), Vector3.ZERO, Vector3(1.0, 0.92, 1.0))
			for sx in [-0.35, 0.35]:
				add(body, ball(0.26, 8, 4), eye_w, Vector3(sx, 1.25, -0.8))
				add(body, ball(0.13, 6, 3), pupil, Vector3(sx, 1.25, -1.02), Vector3.ZERO, Vector3.ONE, false)
				add(body, faceted(cyl(0.0, 0.18, 0.5, 5), 0.0, 0), mat(Color("#fff0d0"), true), Vector3(sx * 1.4, 1.95, -0.1),
					Vector3(0, 0, -sx * 1.0))
				add(body, ball(0.28, 6, 3), m, Vector3(sx * 1.3, 0.2, -0.1), Vector3.ZERO, Vector3(1, 0.6, 1.3))
		"runner":
			add(body, cyl(0.45, 0.9, 1.7, 16), m, Vector3(0, 1.05, 0))
			add(body, ball(0.45, 16, 8, true), m, Vector3(0, 1.9, 0))
			add(body, ball(0.36, 8, 4), eye_w, Vector3(0, 1.35, -0.62))
			add(body, ball(0.18, 6, 3), pupil, Vector3(0, 1.35, -0.92), Vector3.ZERO, Vector3.ONE, false)
			for sx in [-0.35, 0.35]:
				add(body, faceted(cyl(0.0, 0.2, 0.7, 4), 0.0, 0), m, Vector3(sx, 2.1, 0), Vector3(0, 0, -sx * 0.9))
				add(body, cyl(0.12, 0.1, 0.4, 5), mat(col.darkened(0.35), true), Vector3(sx, 0.2, 0))
		"brute":
			add(body, faceted(box(1.8, 1.6, 1.5), 0.0, 0), m, Vector3(0, 1.0, 0))
			add(body, box(1.2, 0.18, 0.2), mat(col.darkened(0.5)), Vector3(0, 1.45, -0.78), Vector3(0, 0, 0))
			for sx in [-0.4, 0.4]:
				add(body, ball(0.2, 8, 4), mat(Color("#ffe066"), true), Vector3(sx, 1.2, -0.75))
				add(body, faceted(cyl(0.0, 0.22, 0.8, 5), 0.0, 0), mat(Color("#fff0d0"), true), Vector3(sx * 2.0, 2.0, 0),
					Vector3(0, 0, -sx * 1.4))
				add(body, faceted(cyl(0.0, 0.1, 0.3, 4), 0.0, 0), mat(Color("#fff0d0")), Vector3(sx * 0.7, 0.55, -0.8),
					Vector3(PI, 0, 0))
				add(body, box(0.5, 0.5, 0.6), mat(col.darkened(0.3), true), Vector3(sx * 1.4, 0.25, 0))
	root.scale = Vector3.ONE * s * MONSTER_SCALE
	return root


# ================================================================== per frame

func _process(delta: float) -> void:
	t += delta
	if g.state == "play" and was_state != "play":
		_on_reset()
	was_state = g.state
	_update_nodes()
	_update_turrets(delta)
	_update_machine(delta)
	_update_pads()
	_update_houses()
	_update_launchers()
	_update_bots(delta)
	_update_player(delta)
	_update_officer(delta)
	_sync_monsters(delta)
	_sync_pickups()
	_sync_lobs()
	_sync_shots()
	_sync_fx()
	_sync_upgrades()
	_update_fence()
	_update_arrow()
	_update_camera(delta)
	ui.queue_redraw()
	if g.args.has("vault_shot") and not vault_shot_done:  # screenshots: catch the climb mid-air
		var vd: Dictionary = g.player.get("vault", {})
		if not vd.is_empty() and float(vd.t) > g.VAULT_TIME * 0.5:
			vault_shot_done = true
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(str(g.args.vault_shot))
			get_tree().quit()


func _on_reset() -> void:
	for td in turrets3d:
		if td.gun != null:
			td.gun.queue_free()
			td.gun = null
	for i in turret_keys.size():
		turret_keys[i] = ""
	for l in launchers3d:
		l.queue_free()
	launchers3d.clear()
	for b in bots3d:
		b.root.queue_free()
	bots3d.clear()
	for h in houses:
		h.queue_free()
	houses.clear()
	built_seen.clear()
	for pid in pads3d:
		pads3d[pid].shown = false
		pads3d[pid].root.visible = false


func _update_nodes() -> void:
	for i in g.nodes.size():
		var n: Dictionary = g.nodes[i]
		var nd: Dictionary = nodes3d[i]
		var has := int(n.stock) > 0
		if has and not nd.full.visible:
			pop_in(nd.full)
		nd.full.visible = has
		nd.empty.visible = not has
		if int(n.stock) < int(node_stock[i]) and has:  # chopped or mined: a quick wobble
			var tw := create_tween()
			nd.full.rotation.z = 0.12
			tw.tween_property(nd.full, "rotation:z", 0.0, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		node_stock[i] = n.stock
		var k := 0.7 + 0.3 * float(n.stock) / float(g.NODE_STOCK)
		nd.full.scale = nd.full.scale.lerp(Vector3.ONE * k, 0.2)


func _update_turrets(delta: float) -> void:
	for i in g.turrets.size():
		var tr: Dictionary = g.turrets[i]
		var td: Dictionary = turrets3d[i]
		var was_built: bool = td.tower.visible
		td.tower.visible = tr.built
		td.found.visible = not tr.built
		if tr.built and not was_built:
			pop_in(td.tower)
		if not tr.built:
			continue
		var key := "%d|%s" % [tr.level, tr.evo]
		if key != turret_keys[i]:
			turret_keys[i] = key
			_turret_gun(i)
		td.aura.visible = g.power_t > 0.0
		if td.aura.visible:
			td.aura.scale = Vector3.ONE * (1.0 + 0.1 * sin(t * 12.0))
		var target_yaw := yaw_of(tr.aim)
		td.yaw = lerp_angle(td.yaw, target_yaw, minf(1.0, delta * 12.0))
		td.flag.rotation.y = sin(t * 3.0 + i) * 0.35  # the pennant waves
		td.flag.scale.x = 1.0 + 0.08 * sin(t * 6.0 + i)
		td.head.rotation.y = td.yaw
		if tr.flash > 0.0:
			td.recoil = 1.0
		td.recoil = maxf(td.recoil - delta * 6.0, 0.0)
		if td.gun != null:
			td.gun.position.z = 0.12 * td.recoil
			var spin: Node3D = td.gun.get_node_or_null("Spin")
			if spin and tr.flash > 0.0:
				spin.rotation.z += delta * 30.0
			var f: Node3D = td.gun.get_node_or_null("Flash")
			if f:
				f.visible = tr.flash > 0.0
				f.scale = Vector3.ONE * (0.7 + randf() * 0.6)


func _update_machine(delta: float) -> void:
	var built: bool = g.machine.built
	var out: Node3D = machine3d.get_meta("out")
	if built and not machine3d.visible:
		machine3d.visible = true
		out.visible = true
		pop_in(machine3d)
		pop_in(out, 0.1)
	if not built:
		machine3d.visible = false
		out.visible = false
		return
	var working: bool = int(g.machine.input) > 0 and int(g.machine.out) < g.MACHINE_OUT_MAX
	if working and fmod(t, 0.35) < delta:  # chimney smoke
		var sp_at: Vector3 = machine3d.position + machine3d.get_meta("stack_top")
		var puff := add(self, ball(0.14, 8, 4), mat(Color("#dfe3e8"), false, 0.7), sp_at, Vector3.ZERO, Vector3.ONE, false)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(puff, "position", sp_at + Vector3(0.3, 1.0, -0.2), 1.0)
		tw.tween_property(puff, "scale", Vector3.ONE * 2.2, 1.0)
		tw.chain().tween_callback(puff.queue_free)
	if working:
		gear.rotation.z -= delta * 5.0
		machine3d.scale = Vector3(1.0 + 0.03 * sin(t * 18.0), 1.0 - 0.03 * sin(t * 18.0), 1.0)
	else:
		machine3d.scale = machine3d.scale.lerp(Vector3.ONE, 0.2)
	for i in out_boxes.size():
		var b: Node3D = out_boxes[i]
		var show := i < int(g.machine.out)
		if show and not b.visible:
			b.visible = true
			pop_in(b)
		b.visible = show
	for i in in_logs.size():
		in_logs[i].visible = i < int(g.machine.input)


func _update_pads() -> void:
	var vis := {}
	for pad in g._visible_pads():
		vis[pad.id] = pad
	for pad in g.pads:
		var pd: Dictionary = pads3d[pad.id]
		var show := vis.has(pad.id)
		if show and not pd.shown:
			pd.root.visible = true
			pd.root.scale = Vector3.ONE
			pop_in(pd.root)
		elif not show and pd.shown:
			pd.root.visible = false
		pd.shown = show
		if not show:
			continue
		var total := 0
		var paid := 0
		for kind in pad.cost:
			total += int(pad.cost[kind])
			paid += int(pad.paid.get(kind, 0))
		var f := float(paid) / float(total)
		pd.fill.scale = pd.fill.scale.lerp(Vector3(maxf(f, 0.001), 1, maxf(f, 0.001)), 0.25)
		pd.ghost.position.y = 0.05 * sin(t * 2.5)


func _update_houses() -> void:
	var want: int = 2 + int(g.built_count)
	while houses.size() < want:
		var h := _house(houses.size())
		houses.append(h)
		pop_in(h, 0.15 * (houses.size() % 2))


func _update_launchers() -> void:
	while launchers3d.size() < g.launchers.size():
		launchers3d.append(_launcher(g.launchers[launchers3d.size()].pos))
	for i in launchers3d.size():
		var arm: Node3D = launchers3d[i].get_meta("arm")
		var c: float = g.launchers[i].cool / g.LAUNCH_TIME
		# flings forward when it fires, then winds back
		arm.rotation.x = lerpf(-0.25, 1.1, c * c) if c > 0.0 else -0.25


func _update_bots(delta: float) -> void:
	while bots3d.size() < g.bots.size():
		var parts := _worker(self, Color("#3d5a8a"), Color("#ffcf2e"), true)
		parts["prev"] = g.bots[bots3d.size()].pos
		parts["logs"] = []
		parts["yaw"] = 0.0
		pop_in(parts.root)
		bots3d.append(parts)
	for i in bots3d.size():
		var b: Dictionary = g.bots[i]
		var p: Dictionary = bots3d[i]
		var pos: Vector2 = b.pos
		var v: Vector2 = (pos - (p.prev as Vector2)) / maxf(delta, 0.001)
		p.prev = pos
		p.root.position = w(pos)
		p.root.scale = Vector3.ONE * 1.25
		var vault: Dictionary = b.get("vault", {})
		if not vault.is_empty():
			v = ((vault.to as Vector2) - (vault.from as Vector2)).normalized() * 200.0
		var carrying: bool = int(b.carry) > 0
		_animate_worker(p, v, delta, carrying)
		_vault_pose(p, vault, carrying)
		var chopping: bool = float(b.t) > 0.0
		if chopping:  # chainsaw into the trunk, buzzing
			p.armr.rotation.x = 1.3 + sin(t * 40.0) * 0.06
			p.body.position.x = sin(t * 50.0) * 0.01
		var logs: Array = p.logs
		while logs.size() < int(b.carry):
			var it := item_node(p.body, "wood")
			it.position = Vector3(0, 0.56 + logs.size() * ITEM_H, -0.36)
			logs.append(it)
			pop_in(it)
		while logs.size() > int(b.carry):
			logs.pop_back().queue_free()



func _animate_worker(p: Dictionary, v: Vector2, delta: float, carrying: bool) -> void:
	var speed := v.length()
	if speed > 5.0:
		p.yaw = lerp_angle(float(p.get("yaw", 0.0)), yaw_of(v), minf(1.0, delta * 14.0))
	p.root.rotation.y = p.get("yaw", 0.0)
	var k := clampf(speed / 200.0, 0.0, 1.0)
	var ph: float = p.get("phase", 0.0) + delta * (6.0 + 10.0 * k) * (1.0 if k > 0.05 else 0.0)
	p.phase = ph
	var swing := sin(ph * 2.0) * 0.8 * k
	p.legl.rotation.x = swing
	p.legr.rotation.x = -swing
	if carrying:  # hugging the stack in front
		p.arml.rotation.x = lerp_angle(p.arml.rotation.x, 1.25, 0.3)
		p.armr.rotation.x = lerp_angle(p.armr.rotation.x, 1.25, 0.3)
		p.arml.rotation.z = lerp_angle(p.arml.rotation.z, -0.35, 0.3)
		p.armr.rotation.z = lerp_angle(p.armr.rotation.z, 0.35, 0.3)
	elif p.has("rifle"):  # rifle held ready
		p.arml.rotation.x = lerp_angle(p.arml.rotation.x, 1.05 + swing * 0.1, 0.3)
		p.armr.rotation.x = lerp_angle(p.armr.rotation.x, 0.85 + swing * 0.1, 0.3)
		p.arml.rotation.z = lerp_angle(p.arml.rotation.z, -0.55, 0.3)
		p.armr.rotation.z = lerp_angle(p.armr.rotation.z, 0.1, 0.3)
	else:
		p.arml.rotation.x = -swing * 0.8
		p.armr.rotation.x = swing * 0.8
	var bob := absf(sin(ph * 2.0)) * 0.07 * k
	p.body.position.y = bob
	var idle := sin(t * 3.0) * 0.02 * (1.0 - k)
	p.body.scale = Vector3(1.0 - idle, 1.0 + idle + bob * 0.5, 1.0 - idle)


func _update_player(delta: float) -> void:
	var pos: Vector2 = g.player.pos
	var v := (pos - player_prev) / maxf(delta, 0.001)
	player_prev = pos
	player_speed = lerpf(player_speed, v.length(), 0.3)
	player3d.position = w(pos)
	var down: bool = g.down_t > 0.0
	var stars: Node3D = player_parts.stars
	if down:  # knocked out: flat on his back, stars circling
		if not was_down:
			was_down = true
			_poof(player3d.position, 8, Color("#ff6b5e"))
		player_parts.body.rotation.x = lerpf(player_parts.body.rotation.x, PI * 0.5, 0.2)
		player_parts.body.position.y = lerpf(player_parts.body.position.y, 0.12, 0.2)
		stars.visible = true
		stars.rotation.y += delta * 5.0
		player3d.visible = g.down_t > 1.0 or fmod(g.down_t, 0.2) < 0.12
		player_parts.aura.visible = false
		_clear_stack()
		return
	stars.visible = false
	if was_down:  # back: dropped in from above with a bounce
		was_down = false
		player_parts.body.rotation.x = 0.0
		player_parts.body.position.y = 0.0
		player3d.position.y = 6.0
		var tw := create_tween()
		tw.tween_property(player3d, "position:y", 0.0, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func() -> void: _dust(player3d.position))
	var carrying: bool = g.stack.size() > 0
	if v.length() < 5.0 and g.state == "play":
		v = Vector2.ZERO
	var vault: Dictionary = g.player.get("vault", {})
	if not vault.is_empty():
		v = ((vault.to as Vector2) - (vault.from as Vector2)).normalized() * 300.0
	_animate_worker(player_parts, v, delta, carrying)
	_vault_pose(player_parts, vault, carrying)
	# hit: flinch back and blink
	if g.hurt_t > g.HURT_GRACE - 0.15 and g.hearts < g.HEARTS:
		player_parts.body.rotation.x = 0.35
	var blink: bool = g.hurt_t > 0.0 and fmod(g.hurt_t, 0.16) < 0.08
	player3d.visible = not blink
	# power auras: sprint (yellow), fury (red)
	var aura: MeshInstance3D = player_parts.aura
	aura.visible = g.sprint_t > 0.0 or g.fury_t > 0.0
	if aura.visible:
		aura.material_override = mat(Color("#ff5a4e") if g.fury_t > 0.0 else Color("#ffe066"), false, 0.45, true)
		aura.scale = Vector3.ONE * (1.0 + 0.12 * sin(t * 10.0))
		if g.sprint_t > 0.0 and player_speed > 60.0 and fmod(t, 0.12) < delta:
			_dust(player3d.position)
	var shooting := false
	for s in g.shots:
		if s.player and s.t > 0.05:
			shooting = true
	player_parts.flash.visible = shooting
	var rifle: Node3D = player_parts.rifle
	if carrying:
		rifle.position = rifle.position.lerp(Vector3(0.0, 0.6, 0.24), 0.3)
		rifle.rotation = Vector3(0, 0, 0.9)
	else:
		rifle.position = rifle.position.lerp(Vector3(0.1, 0.42, -0.24), 0.3)
		rifle.rotation = Vector3(-0.05 if not shooting else -0.12, 0, 0)
		if shooting:
			player_parts.body.position.z = 0.03  # recoil
	# the carried tower: rebuild the changed part, then sway it with the walk
	var kinds: Array = g.stack
	var same := 0
	while same < mini(kinds.size(), stack_kinds.size()) and kinds[same] == stack_kinds[same]:
		same += 1
	while stack_nodes.size() > same:
		stack_nodes.pop_back().queue_free()
	for i in range(same, kinds.size()):
		var it := item_node(stack_root, kinds[i])
		it.position = Vector3(0, i * ITEM_H, 0)
		it.rotation.y = (i % 3 - 1) * 0.12
		stack_nodes.append(it)
		pop_in(it)
	stack_kinds = kinds.duplicate()
	var lean := clampf(player_speed / 240.0, 0.0, 1.0)
	for i in stack_nodes.size():
		var n: Node3D = stack_nodes[i]
		var lag := sin(t * 7.0 - i * 0.35) * 0.012 * i * (0.3 + lean)
		n.position = Vector3(lag, i * ITEM_H, lean * 0.02 * i)



func _sync(cat: String, items: Array, make: Callable, update: Callable, gone: Callable = Callable()) -> void:
	if not pools.has(cat):
		pools[cat] = {}
	var pool: Dictionary = pools[cat]
	var seen := {}
	for it in items:
		var id: int = it.uid
		seen[id] = true
		if not pool.has(id):
			pool[id] = make.call(it)
		update.call(pool[id], it)
	for id in pool.keys():
		if not seen.has(id):
			if gone.is_valid():
				gone.call(pool[id], id)
			pool[id].queue_free()
			pool.erase(id)
			last.erase(id)


func _sync_monsters(delta: float) -> void:
	_sync("mon", g.monsters, func(m: Dictionary) -> Node3D:
		var n := _monster(m.type, m.r)
		n.position = w(m.pos)
		last[m.uid] = {"pos": m.pos, "hp": m.hp, "flash": 0.0, "yaw": PI, "ph": randf() * TAU}
		var target := n.scale
		n.scale = target * 0.3
		create_tween().tween_property(n, "scale", target, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		return n,
	func(n: Node3D, m: Dictionary) -> void:
		var l: Dictionary = last[m.uid]
		var pos: Vector2 = m.pos
		var v: Vector2 = (pos - (l.pos as Vector2)) / maxf(delta, 0.001)
		l.pos = pos
		n.position = w(pos)
		var body: Node3D = n.get_node("Body")
		var moving := v.length() > 3.0
		if moving:
			l.yaw = lerp_angle(l.yaw, yaw_of(v), minf(1.0, delta * 10.0))
		elif m.waiting:
			l.yaw = lerp_angle(l.yaw, PI, delta * 4.0)  # face the fence (towards +Z)
		n.rotation.y = l.yaw
		var hop_rate: float = 9.0 if m.type == "runner" else (5.0 if m.type == "brute" else 7.0)
		l.ph += delta * hop_rate * (1.0 if moving else 0.35)
		var hop := absf(sin(l.ph))
		body.position.y = hop * (0.35 if moving else 0.08)
		var sq := 1.0 + (0.12 if moving else 0.05) * (hop - 0.5)
		body.scale = Vector3(1.0 / sqrt(sq), sq, 1.0 / sqrt(sq))
		if m.waiting:  # banging on the fence
			body.rotation.x = -absf(sin(t * 6.0 + l.ph)) * 0.25
		else:
			body.rotation.x = 0.0
		var atk: float = float(m.get("atk", 0.0))
		if atk > 0.0:  # the lunge when it hits you
			var a := sin((1.0 - atk / 0.3) * PI)
			body.position.z = -a * 0.9
			body.rotation.x = -a * 0.5
			body.scale = Vector3(1.0 + 0.15 * a, 1.0 - 0.1 * a, 1.0 + 0.25 * a)
		else:
			body.position.z = 0.0
		if float(m.hp) < float(l.hp):
			l.flash = 0.1
		l.hp = m.hp
		l.flash = maxf(l.flash - delta, 0.0)
		var mm: StandardMaterial3D = n.get_meta("mat")
		var base: Color = (g.MONSTERS[m.type].color as Color).lightened(0.05)
		if m.slow_t > 0.0 or g.freeze_t > 0.0:
			base = base.lerp(Color("#9fd8ff"), 0.6)
		mm.albedo_color = Color.WHITE if l.flash > 0.0 else base
		if l.flash > 0.0:
			body.scale *= 1.12,
	func(n: Node3D, id: int) -> void:
		if g.state == "play":
			_poof(n.position, 10, (n.get_meta("mat") as StandardMaterial3D).albedo_color))


func _poof(at: Vector3, count: int, col: Color) -> void:
	for k in count:
		var p := add(self, ball(0.12, 6, 3), mat(col if k % 2 else Color.WHITE), at + Vector3(0, 0.4, 0), Vector3.ZERO, Vector3.ONE,
			false)
		var dir := Vector3(randf_range(-1, 1), randf_range(0.6, 1.4), randf_range(-1, 1)).normalized()
		var tw := create_tween().set_parallel(true)
		tw.tween_property(p, "position", p.position + dir * randf_range(0.6, 1.1), 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(p, "scale", Vector3.ONE * 0.01, 0.35).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(p.queue_free)


func _dust(at: Vector3) -> void:
	for k in 7:
		var a := TAU * k / 7.0
		var p := add(self, ball(0.14, 6, 3), mat(Color("#f4ead6"), false, 0.8), at + Vector3(0, 0.1, 0), Vector3.ZERO, Vector3.ONE, false)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(p, "position", at + Vector3(cos(a) * 0.7, 0.25, sin(a) * 0.7), 0.4).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "scale", Vector3.ONE * 0.05, 0.4).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(p.queue_free)


func _sync_pickups() -> void:
	_sync("coin", g.pickups, func(k: Dictionary) -> Node3D:
		var n := item_node(self, "coin")
		n.scale = Vector3.ONE * 1.6
		n.position = w(k.pos, 0.2)
		var tw := create_tween()
		n.position.y = 0.9
		tw.tween_property(n, "position:y", 0.22, 0.4).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		return n,
	func(n: Node3D, k: Dictionary) -> void:
		n.rotation = Vector3(PI * 0.5 * 0.6, t * 3.0 + float(k.uid), 0)
		n.visible = float(k.life) > 6.0 or fmod(float(k.life), 0.5) > 0.2)


func _arc(from: Vector2, to: Vector2, k: float, h0: float, h1: float, peak: float) -> Vector3:
	var p := w(from.lerp(to, k))
	p.y = lerpf(h0, h1, k) + sin(k * PI) * peak
	return p


func _sync_lobs() -> void:
	_sync("lob", g.lobs, func(b: Dictionary) -> Node3D:
		return item_node(self, "ammo"),
	func(n: Node3D, b: Dictionary) -> void:
		var k := clampf(float(b.t) / float(b.dur), 0.0, 1.0)
		n.position = _arc(b.from, b.to, k, 1.1, 1.6, 3.0)
		n.rotation = Vector3(k * TAU, k * PI, 0))


func _sync_shots() -> void:
	_sync("shot", g.shots, func(s: Dictionary) -> Node3D:
		var col := (Color("#ff7b5e") if s.get("fury", false) else Color("#bff8ff")) if s.player else Color("#fff0a0")
		if s.get("evo", "") == "frost":
			col = Color("#a8e4ff")
		elif s.get("evo", "") == "cannon":
			col = Color("#ffb070")
		var a: Vector3 = w(s.a, 0.9 if s.player else 2.1)
		var b: Vector3 = w(s.b, 0.45)
		var n := node3(self, (a + b) * 0.5)
		var len := a.distance_to(b)
		var thick := 0.11 if s.get("evo", "") == "cannon" else 0.06
		add(n, box(thick, thick, len), mat(col, false, 1.0, true), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
		if a.distance_to(b) > 0.01:
			n.look_at_from_position((a + b) * 0.5, b, Vector3.UP)
		return n,
	func(n: Node3D, s: Dictionary) -> void:
		var k := clampf(float(s.t) / 0.08, 0.0, 1.0)
		n.scale = Vector3(k, k, 1.0))


func _sync_fx() -> void:
	_sync("fx", g.fx, func(f: Dictionary) -> Node3D:
		var n: Node3D
		match f.kind:
			"blast":
				n = node3(self, w(f.from, 0.3))
				add(n, ball(1.0, 10, 5), mat(Color("#ffb066"), false, 0.5, true), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
			"spark":
				n = node3(self)
				add(n, ball(0.1, 6, 3), mat(Color("#ffd36b"), false, 1.0, true), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
			"hurt":
				n = node3(self)
				add(n, ball(0.09, 6, 3), mat(Color("#ff5e5e"), false, 1.0, true), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
			"heal":
				n = node3(self)
				add(n, box(0.08, 0.26, 0.08), mat(Color("#6cf08a"), false, 1.0, true), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
				add(n, box(0.26, 0.08, 0.08), mat(Color("#6cf08a"), false, 1.0, true), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
			_:
				n = item_node(self, f.kind)
		return n,
	func(n: Node3D, f: Dictionary) -> void:
		var k := clampf(float(f.t) / float(f.dur), 0.0, 1.0)
		if f.kind == "blast":
			var r: float = float(f.get("r", 40.0)) * S * (0.4 + 0.6 * k)
			n.scale = Vector3(r, r * 0.5, r)
			return
		var to: Vector2 = f.to
		var h1 := 0.4
		if to == g.POWER_BTN:  # coins fly up to the meter: rise and vanish
			n.position = w(f.from, 0.3 + k * 2.5)
			n.scale = Vector3.ONE * (1.0 - k * 0.8)
			return
		n.position = _arc(f.from, to, k, 1.2 if f.kind in ["wood", "stone", "ammo"] else 0.4, h1, 1.0)
		if f.kind == "heal":
			n.position = w((f.from as Vector2).lerp(f.to, k), 0.6 + k * 1.6)
		if f.kind in ["spark", "hurt", "heal"]:
			n.scale = Vector3.ONE * (1.0 - k))


func _sync_upgrades() -> void:
	var ups: Array = g._upgrade_pads()
	var items := []
	for u in ups:
		items.append({"uid": hash(u.key), "u": u})
	_sync("up", items, func(it: Dictionary) -> Node3D:
		var u: Dictionary = it.u
		var n := node3(self, w(u.pos))
		var col := Color("#fff3dc") if u.choice == "lv2" else (g.EVOLUTIONS[u.choice].color as Color).lightened(0.25)
		add(n, cyl(0.5, 0.52, 0.08, 16), mat(col, true), Vector3(0, 0.05, 0))
		add(n, cyl(0.38, 0.38, 0.02, 16), mat(col.lightened(0.4)), Vector3(0, 0.1, 0), Vector3.ZERO, Vector3.ONE, false)
		var icon := item_node(n, "coin")
		icon.position = Vector3(0, 0.5, 0)
		n.set_meta("icon", icon)
		pop_in(n)
		return n,
	func(n: Node3D, it: Dictionary) -> void:
		var icon: Node3D = n.get_meta("icon")
		icon.rotation = Vector3(PI * 0.5, t * 2.0, 0)
		icon.position.y = 0.55 + 0.08 * sin(t * 3.0)
		icon.visible = g.wallet >= int(it.u.cost))


func _update_fence() -> void:
	var strain: float = float(g._waiting()) / float(g.fence_max)
	var pulse := 0.5 + 0.5 * sin(t * 6.0)
	wall_mat.albedo_color = C_STONE.lerp(Color("#ff7a6e"), clampf(strain * (0.5 + 0.3 * pulse), 0.0, 0.8))


func _update_arrow() -> void:
	if g.state != "play" or g.autoplay:
		arrow.visible = false
		return
	var target: Vector2 = g._route(g.player.pos, g._advice())
	var d: Vector2 = target - g.player.pos
	arrow.visible = d.length() > 90.0
	arrow.position = w(g.player.pos, 0.02)
	arrow.rotation.y = lerp_angle(arrow.rotation.y, yaw_of(d), 0.25)
	arrow.scale = Vector3.ONE * (1.0 + 0.08 * sin(t * 6.0))


func _update_camera(delta: float) -> void:
	shake = maxf(shake - delta * 2.5, 0.0)
	if g.hurt_t > g.HURT_GRACE - 0.05:
		shake = 0.35
	cam_look = cam_look.lerp(_cam_target(), minf(1.0, delta * 3.0))
	_place_camera(Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.25)


## Where the camera looks: ahead of you, kept inside the map.
func _cam_target() -> Vector3:
	var p := w(g.player.pos)
	if g.args.get("look_at", "") == "player":
		return Vector3(p.x, 0, p.z)
	if g.args.get("look_at", "") == "bot" and g.bots.size() > 0:
		var bp := w(g.bots[0].pos)
		return Vector3(bp.x, 0, bp.z)
	if g.args.has("look_at"):  # screenshots: aim at a design-pixel spot
		var xy: PackedStringArray = str(g.args.look_at).split(",")
		var q := w(Vector2(float(xy[0]), float(xy[1])))
		return Vector3(q.x, 0, q.z)
	var half_w := tan(deg_to_rad(cam.fov * 0.5)) * cam_dist
	var lim := maxf(15.0 - half_w + 0.6, 0.0)
	# keep the screen's bottom edge on the yard and its top edge short of the map's far edge
	var vs := get_viewport().get_visible_rect().size
	var tan_v := tan(deg_to_rad(cam.fov * 0.5)) * vs.y / maxf(vs.x, 1.0)
	var v := atan(tan_v)
	var pr := deg_to_rad(cam_pitch)
	var base_z := cam_dist * cos(pr)
	var bottom_off := base_z - cam_dist * sin(pr) / tan(pr + v)
	var top_off := base_z - cam_dist * sin(pr) / tan(maxf(pr - v, 0.15))
	var max_z := 13.9 - bottom_off
	var min_z := -30.0 - top_off
	return Vector3(clampf(p.x, -lim, lim), 0, clampf(p.z - 2.0, minf(min_z, max_z), max_z))


func _place_camera(jolt: Vector3) -> void:
	cam.position = cam_look + Vector3(0, sin(deg_to_rad(cam_pitch)), cos(deg_to_rad(cam_pitch))) * cam_dist + jolt


# ================================================================== labels over the world

func sp(p: Vector3) -> Vector2:
	return cam.unproject_position(p)


func _pill(c: Vector2, size: Vector2, bg: Color, border: Color = Color(0, 0, 0, 0)) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(size.y * 0.5))
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(3)
	ui.draw_style_box(sb, Rect2(c - size * 0.5, size))


func _txt(s: String, c: Vector2, fs: int, col: Color, outline: bool = true, f: Font = null) -> void:
	var fnt := f if f else font
	var tw := fnt.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := c + Vector2(-tw * 0.5, fs * 0.36)
	if outline:
		ui.draw_string_outline(fnt, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, C_OUTLINE)
	ui.draw_string(fnt, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _icon(kind: String, c: Vector2, s: float) -> void:
	match kind:
		"wood":
			ui.draw_rect(Rect2(c - Vector2(s, s * 0.5), Vector2(s * 2, s)), C_WOOD)
			ui.draw_circle(c + Vector2(s, 0), s * 0.5, Color("#e9c48a"))
		"stone":
			ui.draw_colored_polygon(PackedVector2Array([c + Vector2(-s, s * 0.6), c + Vector2(-s * 0.6, -s * 0.7), c + Vector2(s * 0.4, -s * 0.8),
				c + Vector2(s, 0), c + Vector2(s * 0.7, s * 0.7)]), C_ROCK.darkened(0.1))
		"coin":
			ui.draw_circle(c, s, C_GOLD)
			ui.draw_circle(c, s * 0.55, C_GOLD.lightened(0.35))
		_:
			ui.draw_rect(Rect2(c - Vector2(s, s * 0.7), Vector2(s * 2, s * 1.4)), C_AMMO)
			ui.draw_rect(Rect2(c - Vector2(s, s * 0.15), Vector2(s * 2, s * 0.3)), Color("#e8584f"))


func _world_circle(center: Vector2, r: float, col: Color, width: float, a0: float = 0.0, a1: float = TAU, h: float = 0.05) -> void:
	var pts := PackedVector2Array()
	var n := 48
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		pts.append(sp(w(center + Vector2(cos(a), sin(a)) * r, h)))
	ui.draw_polyline(pts, col, width, true)


func _draw_ui() -> void:
	if g == null:
		return
	var near_dist := 130.0
	# ranges: the turret you stand by, and your own gun while outside
	for tr in g.turrets:
		if tr.built and g._near(g.player.pos, tr.pos, 120.0):
			_world_circle(tr.pos, g.TURRET_RANGE, Color(1, 1, 1, 0.45), 3.0, PI, TAU)
	if not g._inside(g.player.pos) and g.bag > 0:
		_world_circle(g.player.pos, g.GUN_RANGE, Color(0.75, 1.0, 1.0, 0.35), 2.5)
	for pad in g._visible_pads():
		if str(pad.id).begins_with("launcher"):
			_world_circle(pad.pos, g.LAUNCH_RANGE, Color(1.0, 0.85, 0.4, 0.5), 2.5, PI, TAU)
	# build pads: what they still need
	for pad in g._visible_pads():
		var c := sp(w(pad.pos, 0.1)) + Vector2(0, -6)
		var kinds := []
		for kind in pad.cost:
			if g._remaining(pad, kind) > 0:
				kinds.append(kind)
		var y0 := c.y - (kinds.size() - 1) * 17.0
		for i in kinds.size():
			var kind: String = kinds[i]
			var cc := Vector2(c.x, y0 + i * 34.0)
			var label := "%d/%d" % [int(pad.paid.get(kind, 0)), int(pad.cost[kind])]
			_pill(cc, Vector2(92, 30), Color(1, 1, 1, 0.94))
			_icon(kind, cc + Vector2(-26, 0), 9)
			_txt(label, cc + Vector2(10, 0), 22, C_OUTLINE, false)
		_txt(pad.label, c + Vector2(0, -kinds.size() * 17.0 - 22), 19, Color.WHITE)
	# turrets: ammo, level stars, empty warning
	for i in g.turrets.size():
		var tr: Dictionary = g.turrets[i]
		if not tr.built:
			continue
		var c2 := sp(w(tr.pos, 2.9))
		var frac := float(tr.ammo) / float(g.TURRET_BOXES * g.SHOTS_PER_BOX)
		_pill(c2, Vector2(64, 14), Color(0.1, 0.08, 0.15, 0.75))
		if frac > 0.0:
			var sb := StyleBoxFlat.new()
			sb.bg_color = C_AMMO
			sb.set_corner_radius_all(5)
			ui.draw_style_box(sb, Rect2(c2 - Vector2(29, 4), Vector2(58.0 * frac, 8)))
		for k in int(tr.level) - 1:
			_star(c2 + Vector2(-8 + k * 16 - (int(tr.level) - 2) * 0.0, -18), 7.0)
		if int(tr.ammo) <= 0:
			var pulse := 0.5 + 0.5 * sin(t * 8.0)
			_pill(c2 + Vector2(0, -22 - pulse * 4), Vector2(34, 34), Color("#ff5a4e"), Color.WHITE)
			_txt("!", c2 + Vector2(0, -22 - pulse * 4), 26, Color.WHITE, false)
	# upgrade pads: cost, and their names when you are close
	for u in g._upgrade_pads():
		var c3 := sp(w(u.pos, 0.1))
		var afford: bool = g.wallet >= int(u.cost)
		_pill(c3 + Vector2(0, 2), Vector2(58, 24), Color(1, 1, 1, 0.92 if afford else 0.55))
		_icon("coin", c3 + Vector2(-14, 2), 7)
		_txt("%d" % u.cost, c3 + Vector2(8, 2), 19, C_OUTLINE, false)
		if g._near(g.player.pos, u.pos, near_dist):
			var col := Color.WHITE if u.choice == "lv2" else (g.EVOLUTIONS[u.choice].color as Color).lightened(0.35)
			_txt(u.label, c3 + Vector2(62, 2), 18, col)
		if u.key == g.dwell_key and g.dwell_t > 0.0:
			_world_circle(u.pos, g.UPGRADE_R + 6.0, C_GOLD, 5.0, -PI * 0.5, -PI * 0.5 + TAU * g.dwell_t / g.UPGRADE_DWELL, 0.12)
	# machine: logs waiting
	if g.machine.built and int(g.machine.input) > 0:
		var c4 := sp(w(g.MACHINE_POS + Vector2(48, 0), 1.6))
		_pill(c4, Vector2(62, 26), Color(1, 1, 1, 0.92))
		_icon("wood", c4 + Vector2(-14, 0), 7)
		_txt("%d" % g.machine.input, c4 + Vector2(12, 0), 19, C_OUTLINE, false)
	# monsters: hp when hurt, a red "!" when chasing you
	for m in g.monsters:
		var top: float = float(m.r) * S * 2.6 * MONSTER_SCALE
		var c5 := sp(w(m.pos, top))
		if float(m.hp) < float(m.max):
			var wdt: float = 18.0 + float(m.r) * 1.6
			ui.draw_rect(Rect2(c5 + Vector2(-wdt * 0.5 - 2, -8), Vector2(wdt + 4, 8)), C_OUTLINE)
			ui.draw_rect(Rect2(c5 + Vector2(-wdt * 0.5, -6), Vector2(wdt * float(m.hp) / float(m.max), 4)), Color("#ff6b5e"))
		if m.chase:
			_pill(c5 + Vector2(0, -24), Vector2(24, 24), Color.WHITE, Color("#ff5a4e"))
			_txt("!", c5 + Vector2(0, -24), 20, Color("#ff5a4e"), false)
	if g.tutorial:  # a speech bubble over the sergeant major ties him to the orders panel
		var oc := sp(w(g.OFFICER_POS, 2.6))
		var bob := sin(t * 4.0) * 4.0
		_pill(oc + Vector2(0, bob), Vector2(46, 34), Color.WHITE, C_REDCOAT_DARK)
		ui.draw_colored_polygon(PackedVector2Array([oc + Vector2(-6, 15 + bob), oc + Vector2(6, 15 + bob), oc + Vector2(0, 26 + bob)]), Color.WHITE)
		_txt("...", oc + Vector2(0, bob - 4), 24, C_REDCOAT_DARK, false)
	# monsters still off screen: red markers on the edge they will come from
	var vr := Rect2(Vector2(14, g.HUD_H + 18), Vector2(720 - 28, 1280 - g.HUD_H - 32))
	for m in g.monsters:
		var q := sp(w(m.pos, 0.5))
		if vr.has_point(q):
			continue
		var e := Vector2(clampf(q.x, vr.position.x, vr.end.x), clampf(q.y, vr.position.y, vr.end.y))
		var dir := (q - e).normalized() if q.distance_to(e) > 0.1 else Vector2.UP
		var side := Vector2(-dir.y, dir.x)
		var big: float = 11.0 if m.type == "brute" else 8.0
		ui.draw_colored_polygon(PackedVector2Array([e + dir * big, e - dir * big * 0.6 + side * big, e - dir * big * 0.6 - side * big]),
			Color("#ff5a4e"))
	# player: bag under the feet, FULL over the stack
	var pc := sp(w(g.player.pos, 0.0))
	var bf := float(g.bag) / float(g.BAG_MAX)
	_pill(pc + Vector2(0, 18), Vector2(52, 12), Color(0.1, 0.08, 0.15, 0.6))
	if bf > 0.0:
		ui.draw_rect(Rect2(pc + Vector2(-24, 15), Vector2(48.0 * bf, 6)), Color("#7af1eb"))
	var head_h: float = maxf(1.35, 0.56 + g.stack.size() * ITEM_H) * PLAYER_SCALE
	if g.down_t <= 0.0 and (not g._inside(g.player.pos) or g.hearts < g.HEARTS):  # your health, over your head
		var hc := sp(w(g.player.pos, head_h + 0.35))
		var seg := 11.0
		var total: float = g.HEARTS * seg
		ui.draw_rect(Rect2(hc + Vector2(-total * 0.5 - 3, -5), Vector2(total + 6, 12)), C_OUTLINE)
		for k in g.HEARTS:
			var on: bool = k < g.hearts
			ui.draw_rect(Rect2(hc + Vector2(-total * 0.5 + k * seg + 1, -3), Vector2(seg - 2, 8)),
				Color("#6cf08a") if on and g.hearts > 2 else (Color("#ff5a4e") if on else Color(0.3, 0.25, 0.35)))
	if g.stack.size() >= g.capacity:
		var top2 := sp(w(g.player.pos, head_h + 0.9))
		_pill(top2, Vector2(64, 26), Color("#ff9a3c"), Color.WHITE)
		_txt("FULL", top2, 19, Color.WHITE, false)


func _star(c: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI * 0.5 + PI * k / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if k % 2 == 0 else r * 0.45))
	ui.draw_colored_polygon(pts, C_GOLD)
	pts.append(pts[0])
	ui.draw_polyline(pts, C_OUTLINE, 1.5)


## The climb over the wall: a crouch, a hop with knees tucked and hands on the wall, then down.
## Returns true while it runs.
func _vault_pose(p: Dictionary, vault: Dictionary, carrying: bool) -> bool:
	if vault.is_empty():
		p.body.rotation.x = lerpf(p.body.rotation.x, 0.0, 0.3)
		if p.get("vaulting", false):  # landing: squash and a puff of dust
			p.vaulting = false
			p.body.scale = Vector3(1.2, 0.78, 1.2)
			create_tween().tween_property(p.body, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_dust(p.root.position)
		return false
	p.vaulting = true
	var k := clampf(float(vault.t) / g.VAULT_TIME, 0.0, 1.0)
	if k < 0.18:  # crouch
		var c := k / 0.18
		p.body.position.y = -0.08 * c
		p.body.scale = Vector3(1.0 + 0.12 * c, 1.0 - 0.15 * c, 1.0 + 0.12 * c)
		p.legl.rotation.x = 0.4 * c
		p.legr.rotation.x = 0.4 * c
		return true
	var j := (k - 0.18) / 0.82
	var arc := sin(j * PI)
	p.body.position.y = arc * 1.3
	p.body.rotation.x = -sin(j * TAU) * 0.3
	p.legl.rotation.x = -1.4 * arc
	p.legr.rotation.x = -1.2 * arc
	if not carrying:  # hands reach down to the wall at the top
		p.arml.rotation.x = 0.9 + 0.8 * arc
		p.armr.rotation.x = 0.9 + 0.8 * arc
	p.body.scale = Vector3(1.0 - 0.06 * arc, 1.0 + 0.1 * arc, 1.0 - 0.06 * arc)
	return true


func _clear_stack() -> void:
	for n in stack_nodes:
		n.queue_free()
	stack_nodes.clear()
	stack_kinds.clear()


## A hipped roof: slopes on all four sides, ridge along X. `a`, `b`: half length and half depth.
func _hip_mesh(a: float, b: float, h: float) -> Mesh:
	var key := "hip%.3f,%.3f,%.3f" % [a, b, h]
	if meshes.has(key):
		return meshes[key]
	var r := maxf(a - b, 0.02)
	var fl := Vector3(-a, 0, b)
	var fr := Vector3(a, 0, b)
	var bl := Vector3(-a, 0, -b)
	var br := Vector3(a, 0, -b)
	var rl := Vector3(-r, h, 0)
	var rr := Vector3(r, h, 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for v in [fl, rl, rr, fl, rr, fr, br, rr, rl, br, rl, bl, fr, rr, br, bl, rl, fl]:
		st.add_vertex(v)
	st.generate_normals()
	var m := st.commit()
	meshes[key] = m
	return m


func _shuttered_window(h: Node3D, at: Vector3, sz: Vector2, shutters: bool = true) -> void:
	add(h, box(sz.x + 0.06, sz.y + 0.06, 0.03), mat(Color("#f7f3ea")), at, Vector3.ZERO, Vector3.ONE, false)   # white frame
	add(h, box(sz.x, sz.y, 0.03), mat(Color("#3d5a6e")), at + Vector3(0, 0, 0.01), Vector3.ZERO, Vector3.ONE, false)
	add(h, box(0.02, sz.y, 0.03), mat(Color("#f7f3ea")), at + Vector3(0, 0, 0.02), Vector3.ZERO, Vector3.ONE, false)  # glazing bar
	if shutters:
		for sx in [-1.0, 1.0]:
			add(h, box(sz.x * 0.45, sz.y + 0.04, 0.03), mat(Color("#2f6a4a")), at + Vector3(sx * (sz.x * 0.5 + sz.x * 0.25 + 0.04), 0, 0),
				Vector3.ZERO, Vector3.ONE, false)


## Whitewashed bungalow with a verandah on white posts under a terracotta hipped roof.
func _bungalow(h: Node3D, i: int) -> void:
	var wall := mat(C_WHITEWASH)
	add(h, box(1.7, 0.14, 1.5), mat(C_STONE_DARK), Vector3(0, 0.07, 0.1))                          # plinth
	add(h, box(1.5, 0.7, 1.0), wall, Vector3(0, 0.49, -0.1))
	add(h, box(1.6, 0.04, 0.42), mat(C_WOOD), Vector3(0, 0.16, 0.6))                              # verandah boards
	for k in 4:
		add(h, cyl(0.035, 0.035, 0.7, 10), mat(Color("#f7f3ea")), Vector3(-0.72 + k * 0.48, 0.52, 0.76))
	add(h, box(1.56, 0.06, 0.04), mat(Color("#f7f3ea")), Vector3(0, 0.36, 0.77))                    # rail
	add(h, box(0.32, 0.5, 0.03), mat(Color("#2f6a4a")), Vector3(0, 0.4, 0.41))                       # green door
	add(h, box(0.38, 0.06, 0.03), mat(Color("#f7f3ea")), Vector3(0, 0.68, 0.41), Vector3.ZERO, Vector3.ONE, false)
	for wx in [-0.5, 0.5]:
		_shuttered_window(h, Vector3(wx, 0.52, 0.41), Vector2(0.2, 0.28))
	var roof_col: Color = [Color("#b8553a"), Color("#a84a34"), Color("#c26340")][i % 3]
	add(h, _hip_mesh(0.92, 0.82, 0.62), mat(roof_col), Vector3(0, 0.86, 0.08))
	add(h, box(1.86, 0.04, 1.66), mat(roof_col.darkened(0.25)), Vector3(0, 0.86, 0.08), Vector3.ZERO, Vector3.ONE, false)   # eaves
	add(h, box(0.18, 0.4, 0.18), mat(C_WHITEWASH.darkened(0.08)), Vector3(0.45, 1.25, -0.3))          # chimney
	add(h, box(0.22, 0.05, 0.22), mat(C_BRICK), Vector3(0.45, 1.46, -0.3))
	if i % 3 == 0:  # a potted palm by the steps
		add(h, cyl(0.08, 0.06, 0.14, 10), mat(C_BRICK), Vector3(0.95, 0.07, 0.75))
		for k in 5:
			add(h, box(0.04, 0.02, 0.28), mat(C_TREE_LIGHT), Vector3(0.95, 0.2, 0.75), Vector3(0.5, TAU * k / 5.0, 0))


## Red-brick Georgian house: white sash windows in two rows, a white door case, slate roof, chimneys.
func _brick_house(h: Node3D, i: int) -> void:
	var brick := mat(C_BRICK)
	add(h, box(1.3, 1.25, 1.0), brick, Vector3(0, 0.625, 0))
	for k in 5:
		add(h, box(1.31, 0.015, 1.01), mat(C_BRICK.darkened(0.15)), Vector3(0, 0.18 + k * 0.22, 0), Vector3.ZERO, Vector3.ONE, false)
	add(h, box(1.36, 0.06, 1.06), mat(Color("#f7f3ea")), Vector3(0, 1.25, 0))                       # cornice
	add(h, box(1.34, 0.05, 1.04), mat(Color("#f7f3ea")), Vector3(0, 0.66, 0), Vector3.ZERO, Vector3.ONE, false)   # string course
	for wx in [-0.38, 0.38]:
		_shuttered_window(h, Vector3(wx, 0.95, 0.5), Vector2(0.2, 0.3), false)
	_shuttered_window(h, Vector3(-0.38, 0.4, 0.5), Vector2(0.2, 0.3), false)
	_shuttered_window(h, Vector3(0.38, 0.4, 0.5), Vector2(0.2, 0.3), false)
	add(h, box(0.26, 0.48, 0.04), mat(Color("#1f2a44")), Vector3(0, 0.24, 0.51))                    # navy door
	add(h, prism(0.42, 0.14, 0.06), mat(Color("#f7f3ea")), Vector3(0, 0.56, 0.52))                   # pediment
	add(h, box(0.5, 0.06, 0.2), mat(C_STONE), Vector3(0, 0.03, 0.6))                                 # step
	add(h, prism(1.1, 0.55, 1.4), mat(Color("#4a5566")), Vector3(0, 1.55, 0), Vector3(0, PI * 0.5, 0))   # slate roof
	for cx in [-0.55, 0.55]:
		add(h, box(0.22, 0.55, 0.3), brick, Vector3(cx, 1.6, 0))
		add(h, box(0.26, 0.05, 0.34), mat(Color("#f7f3ea")), Vector3(cx, 1.88, 0))
		add(h, cyl(0.04, 0.04, 0.08, 8), mat(C_BRICK.darkened(0.3)), Vector3(cx, 1.94, 0))


## A long whitewashed barracks with a verandah along its front and a red tiled roof.
func _barracks_block(h: Node3D) -> void:
	add(h, box(2.5, 0.12, 1.4), mat(C_STONE_DARK), Vector3(0, 0.06, 0.05))
	add(h, box(2.3, 0.72, 0.9), mat(C_WHITEWASH), Vector3(0, 0.48, -0.1))
	add(h, box(2.4, 0.04, 0.38), mat(C_WOOD), Vector3(0, 0.14, 0.55))
	for k in 6:
		add(h, cyl(0.032, 0.032, 0.7, 10), mat(Color("#f7f3ea")), Vector3(-1.1 + k * 0.44, 0.5, 0.7))
	for k in 4:
		_shuttered_window(h, Vector3(-0.85 + k * 0.57, 0.52, 0.36), Vector2(0.18, 0.26))
	add(h, box(0.26, 0.48, 0.03), mat(Color("#2f6a4a")), Vector3(-0.28, 0.4, 0.36))
	add(h, _hip_mesh(1.33, 0.78, 0.55), mat(Color("#b8553a")), Vector3(0, 0.84, 0.05))
	add(h, box(2.68, 0.04, 1.58), mat(Color("#8a3a26")), Vector3(0, 0.84, 0.05), Vector3.ZERO, Vector3.ONE, false)
	add(h, cyl(0.02, 0.02, 0.9, 6), mat(C_WOOD_DARK), Vector3(1.0, 1.5, -0.2))                        # small flag
	add(h, box(0.3, 0.07, 0.02), mat(C_REDCOAT), Vector3(1.15, 1.88, -0.2), Vector3.ZERO, Vector3.ONE, false)
	add(h, box(0.3, 0.07, 0.02), mat(Color("#25407a")), Vector3(1.15, 1.81, -0.2), Vector3.ZERO, Vector3.ONE, false)


## The governor's house: ochre stucco, a white portico with columns and a pediment, slate hipped roof.
func _governor(h: Node3D) -> void:
	var stucco := mat(Color("#e2b86a"))
	var white := mat(Color("#f7f3ea"))
	add(h, box(1.9, 0.16, 1.4), mat(C_STONE), Vector3(0, 0.08, 0.05))
	add(h, box(1.7, 1.0, 1.0), stucco, Vector3(0, 0.66, -0.1))
	add(h, box(1.76, 0.07, 1.06), white, Vector3(0, 1.19, -0.1))
	for wx in [-0.6, -0.32, 0.32, 0.6]:
		_shuttered_window(h, Vector3(wx, 0.92, 0.41), Vector2(0.16, 0.26), false)
		_shuttered_window(h, Vector3(wx, 0.48, 0.41), Vector2(0.16, 0.26), false)
	for k in 4:  # portico
		add(h, cyl(0.045, 0.05, 0.9, 12), white, Vector3(-0.27 + k * 0.18, 0.61, 0.62))
	add(h, box(0.7, 0.08, 0.36), white, Vector3(0, 1.08, 0.55))
	add(h, prism(0.74, 0.24, 0.36), white, Vector3(0, 1.24, 0.55))
	add(h, box(0.24, 0.5, 0.03), mat(Color("#1f2a44")), Vector3(0, 0.41, 0.41))
	add(h, _hip_mesh(0.95, 0.6, 0.45), mat(Color("#4a5566")), Vector3(0, 1.22, -0.1))
	add(h, cyl(0.025, 0.025, 1.0, 8), mat(C_WOOD_DARK), Vector3(0, 2.0, -0.1))                         # flagstaff
	add(h, box(0.42, 0.08, 0.02), mat(C_REDCOAT), Vector3(0.21, 2.38, -0.1), Vector3.ZERO, Vector3.ONE, false)
	add(h, box(0.42, 0.07, 0.02), mat(Color("#f4f0e6")), Vector3(0.21, 2.31, -0.1), Vector3.ZERO, Vector3.ONE, false)
	add(h, box(0.42, 0.08, 0.02), mat(Color("#25407a")), Vector3(0.21, 2.24, -0.1), Vector3.ZERO, Vector3.ONE, false)


## The sergeant major who runs the training: bicorne, crimson sash, sword, white moustache.
func _officer() -> Dictionary:
	var parts := _worker(self, C_REDCOAT, Color.WHITE, false, false, true)
	parts.root.scale = Vector3.ONE * PLAYER_SCALE * 1.05
	parts.root.position = w(g.OFFICER_POS)
	return parts


## The sergeant major during the training: faces you, points the way, hops at each new order.
func _update_officer(delta: float) -> void:
	if officer3d.is_empty():
		if not g.tutorial:
			return
		officer3d = _officer()
		pop_in(officer3d.root)
	var p: Dictionary = officer3d
	p.root.visible = g.tutorial
	if not g.tutorial:
		return
	var to_player: Vector2 = g.player.pos - g.OFFICER_POS
	var target: Vector2 = g._tut_target()
	var point := to_player.length() < 260.0 and target.distance_to(g.OFFICER_POS) > 120.0
	var look: Vector2 = (target - g.OFFICER_POS) if point else to_player
	p.yaw = lerp_angle(float(p.get("yaw", 0.0)), yaw_of(look), minf(1.0, delta * 6.0))
	p.root.rotation.y = p.yaw
	_animate_worker(p, Vector2.ZERO, delta, false)
	p.armr.rotation.x = lerp_angle(p.armr.rotation.x, 1.6 if point else 0.15, 0.15)   # arm out at the objective
	p.arml.rotation.x = lerp_angle(p.arml.rotation.x, -0.1, 0.15)
	p.arml.rotation.z = lerp_angle(p.arml.rotation.z, -0.6, 0.15)                     # hand on hip
	if g.tut_step != officer_step:  # a new order: a little hop
		officer_step = g.tut_step
		var tw := create_tween()
		tw.tween_property(p.body, "position:y", 0.35, 0.15).set_ease(Tween.EASE_OUT)
		tw.tween_property(p.body, "position:y", 0.0, 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


# ================================================================== asset gallery
# `-- gallery=/dir` renders every asset on its own, from three-quarters above, one PNG each, and
# writes /dir/assets.json (number, file, name, group). Used for the asset review page.

func _gallery() -> void:
	set_process(false)
	g.visible = false
	g.set_process(false)
	ui.visible = false
	vignette.visible = false
	var out_dir := str(g.args.gallery)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var env: Environment = (get_children().filter(func(c): return c is WorldEnvironment)[0] as WorldEnvironment).environment
	env.background_color = Color("#e8e2d4")
	env.fog_enabled = false
	var list := []  # [name, group, size, ground colour, builder]
	list.append(["Hero: redcoat with musket", "Characters", 1.35, C_SAND, func(h: Node3D) -> void:
		_build_player()
		player3d.reparent(h, false)
		player3d.position = Vector3.ZERO
		player3d.rotation.y = PI - 0.5])
	list.append(["Hero carrying a load", "Characters", 1.55, C_SAND, func(h: Node3D) -> void:
		var p := _worker(h, C_REDCOAT, Color.WHITE, false, true)
		p.root.scale = Vector3.ONE * PLAYER_SCALE
		p.root.rotation.y = PI - 0.5
		for a in [p.arml, p.armr]:
			a.rotation.x = 1.25
		p.arml.rotation.z = -0.35
		p.armr.rotation.z = 0.35
		var st := node3(p.body, Vector3(0, 0.56, -0.36))
		for k in 6:
			var it := item_node(st, ["wood", "wood", "stone", "stone", "ammo", "ammo"][k])
			it.position = Vector3(0, k * ITEM_H, 0)])
	list.append(["Woodcutter: redcoat pioneer", "Characters", 1.35, C_GRASS, func(h: Node3D) -> void:
		var p := _worker(h, C_REDCOAT, Color.WHITE, true)
		p.root.scale = Vector3.ONE * 1.25 * 1.2
		p.root.rotation.y = PI - 0.5
		p.armr.rotation.x = 1.3])
	list.append(["Sergeant major (training)", "Characters", 1.4, C_SAND, func(h: Node3D) -> void:
		var p := _worker(h, C_REDCOAT, Color.WHITE, false, false, true)
		p.root.scale = Vector3.ONE * PLAYER_SCALE
		p.root.rotation.y = PI - 0.5
		p.arml.rotation.z = -0.6])
	for m in [["grunt", "Grunt"], ["runner", "Runner"], ["brute", "Brute"]]:
		list.append(["Monster: " + m[1], "Monsters", 0.9 if m[0] != "brute" else 1.2, C_GRASS, func(h: Node3D) -> void:
			var n := _monster(m[0], g.MONSTERS[m[0]].r)
			n.reparent(h, false)
			n.position = Vector3.ZERO
			n.rotation.y = PI - 0.6])
	list.append(["Wall section", "Fort", 1.8, C_GRASS, func(h: Node3D) -> void:
		var root := node3(h)
		add(root, box(3.6, 0.62, 0.26), wall_mat, Vector3(0, 0.31, 0))
		add(root, box(3.6, 0.1, 0.24), mat(C_STONE_DARK), Vector3(0, 0.05, 0))
		add(root, box(3.6, 0.06, 0.32), mat(C_REDCOAT_DARK), Vector3(0, 0.65, 0))
		for k in 8:
			add(root, box(0.22, 0.18, 0.26), wall_mat, Vector3(-1.58 + k * 0.45, 0.77, 0))
			add(root, box(0.24, 0.03, 0.28), mat(C_REDCOAT_DARK), Vector3(-1.58 + k * 0.45, 0.875, 0))
		add(root, box(0.16, 0.66, 0.34), mat(C_WHITEWASH.darkened(0.06)), Vector3(0.4, 0.33, 0))
		root.rotation.y = 0.35])
	list.append(["Tower: empty foundation", "Fort", 1.0, C_GRASS, func(h: Node3D) -> void:
		var r := node3(h)
		r.scale = Vector3.ONE * 1.2
		var tm := _tower_model(r)
		tm.tower.visible = false])
	for v in [["Tower: brass swivel gun", 1, ""], ["Tower: level 2", 2, ""], ["Tower: Gatling (evolution)", 3, "gatling"],
			["Tower: iron cannon (evolution)", 3, "cannon"], ["Tower: frost gun (evolution)", 3, "frost"]]:
		list.append([v[0], "Fort", 1.3, C_GRASS, func(h: Node3D) -> void:
			var r := node3(h)
			r.scale = Vector3.ONE * 1.2
			var tm := _tower_model(r)
			tm.found.visible = false
			_gun_model(tm.head, v[1], v[2])
			tm.head.rotation.y = PI - 0.7])
	list.append(["Powder works (ammo machine) and crate table", "Buildings you build", 1.6, C_SAND, func(h: Node3D) -> void:
		machine3d.visible = true
		var o: Node3D = machine3d.get_meta("out")
		o.visible = true
		machine3d.reparent(h, false)
		machine3d.position = Vector3(0, 0, 0.9)
		o.reparent(h, false)
		o.position = Vector3(0, 0, -1.2)
		for k in out_boxes.size():
			out_boxes[k].visible = k < 10
		for k in in_logs.size():
			in_logs[k].visible = k < 6])
	list.append(["Catapult (launcher)", "Buildings you build", 0.9, C_SAND, func(h: Node3D) -> void:
		var l := _launcher(Vector2.ZERO)
		l.reparent(h, false)
		l.position = Vector3.ZERO
		l.scale = Vector3.ONE
		(l.get_meta("arm") as Node3D).rotation.x = -0.25])
	list.append(["Build pad (with ghost preview)", "Buildings you build", 0.9, C_SAND, func(h: Node3D) -> void:
		var pd: Dictionary = pads3d["machine"]
		pd.root.visible = true
		pd.root.reparent(h, false)
		pd.root.position = Vector3.ZERO
		pd.fill.scale = Vector3(0.5, 1, 0.5)])
	list.append(["Upgrade pads: level 2, Gatling, cannon, frost", "Buildings you build", 1.4, C_SAND, func(h: Node3D) -> void:
		var cols := [Color("#fff3dc"), (g.EVOLUTIONS.gatling.color as Color).lightened(0.25), (g.EVOLUTIONS.cannon.color as Color).lightened(0.25),
			(g.EVOLUTIONS.frost.color as Color).lightened(0.25)]
		for k in 4:
			var n := node3(h, Vector3(-1.35 + k * 0.9, 0, 0))
			add(n, cyl(0.5, 0.52, 0.08, 16), mat(cols[k]), Vector3(0, 0.05, 0))
			add(n, cyl(0.38, 0.38, 0.02, 16), mat((cols[k] as Color).lightened(0.4)), Vector3(0, 0.1, 0), Vector3.ZERO, Vector3.ONE, false)
			var icon := item_node(n, "coin")
			icon.position = Vector3(0, 0.55, 0)
			icon.rotation = Vector3(PI * 0.5 * 0.7, 0, 0)])
	for b in [["House: verandah bungalow", 0], ["House: red-brick Georgian", 1], ["House: barracks", 2], ["House: governor's house", 4]]:
		list.append([b[0], "Fort houses", 1.5 if b[1] != 2 else 1.7, C_SAND, func(h: Node3D) -> void:
			var n := node3(h)
			n.rotation.y = 0.4
			if b[1] == 0:
				_bungalow(n, 0)
			elif b[1] == 1:
				_brick_house(n, 1)
			elif b[1] == 2:
				_barracks_block(n)
			else:
				_governor(n)])
	list.append(["Tree (wood source) and its stump", "Nature", 1.2, C_GRASS, func(h: Node3D) -> void:
		var nd: Dictionary = nodes3d[0]
		nd.full.reparent(h, false)
		nd.full.position = Vector3(-0.5, 0, 0)
		nd.full.visible = true
		nd.empty.reparent(h, false)
		nd.empty.position = Vector3(0.9, 0, 0.3)
		nd.empty.visible = true])
	list.append(["Rock (stone source) and its rubble", "Nature", 1.1, C_GRASS, func(h: Node3D) -> void:
		var nd: Dictionary = nodes3d[1]
		nd.full.reparent(h, false)
		nd.full.position = Vector3(-0.4, 0, 0)
		nd.full.visible = true
		nd.empty.reparent(h, false)
		nd.empty.position = Vector3(0.9, 0, 0.3)
		nd.empty.visible = true])
	list.append(["Decor: cone trees, boulder, grass and flowers", "Nature", 1.6, C_GRASS, func(h: Node3D) -> void:
		_cone_tree(h, Vector3(-0.9, 0, -0.3), 1.0, 1)
		_cone_tree(h, Vector3(-0.2, 0, -0.8), 0.8, 2)
		add(h, faceted(ball(0.5, 6, 4), 0.2, 600), mat(C_ROCK), Vector3(0.9, 0.25, -0.2))
		for k in 5:
			var tuft := node3(h, Vector3(-0.6 + k * 0.4, 0, 0.7))
			for j in 3:
				add(tuft, prism(0.08, 0.3, 0.04), mat(C_GRASS_LIGHT), Vector3((j - 1) * 0.07, 0.14, 0), Vector3(0, j * 0.9, (j - 1) * 0.35))
			add(tuft, ball(0.07, 6, 3), mat([Color("#ffd84a"), Color("#ff86a8"), Color("#f4f0ff")][k % 3]), Vector3(0.12, 0.1, 0.05))])
	list.append(["Items: log, stone, cartridge box, coin", "Items", 1.1, C_SAND, func(h: Node3D) -> void:
		for k in 4:
			var it := item_node(h, ["wood", "stone", "ammo", "coin"][k])
			it.position = Vector3(-1.05 + k * 0.7, 0.2, 0)
			it.scale = Vector3.ONE * 1.5
			if k == 3:
				it.rotation = Vector3(PI * 0.35, 0, 0)])
	var manifest := []
	for i in list.size():
		var e: Array = list[i]
		var holder := node3(self, Vector3(i * 14.0, 0, 70.0))
		add(holder, cyl(float(e[2]) * 1.9, float(e[2]) * 1.9, 0.04, 40), mat(e[3]), Vector3(0, 0.0, 0), Vector3.ZERO, Vector3.ONE, false)
		(e[4] as Callable).call(holder)
		var size: float = e[2]
		cam.fov = 30.0
		cam.rotation_degrees = Vector3(-34, 0, 0)
		var look := holder.position + Vector3(0, size * 0.6, 0)
		cam.position = look + Vector3(0, sin(deg_to_rad(34.0)), cos(deg_to_rad(34.0))) * size * 5.2
		for f in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var file := "asset_%02d.png" % (i + 1)
		get_viewport().get_texture().get_image().save_png(out_dir.path_join(file))
		manifest.append({"n": i + 1, "file": file, "name": e[0], "group": e[1]})
		holder.visible = false
	var fa := FileAccess.open(out_dir.path_join("assets.json"), FileAccess.WRITE)
	fa.store_string(JSON.stringify(manifest, "  "))
	fa.close()
	print("[gallery] ", manifest.size(), " assets")
	get_tree().quit()
