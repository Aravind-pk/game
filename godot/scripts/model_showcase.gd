extends Node3D
## Lays out every exported North Gate model in a grid (rows = palettes) so the
## art can be checked in-engine. Models face +Z (Godot MODEL_FRONT).

const TURRETS := ["kestrel", "mule", "needle"]
const TURRET_PALETTES := ["frontier_olive", "polar_ceramic", "midnight_steel"]
const MONSTERS := ["shale_digger", "rift_runner", "faultbreaker"]
const MONSTER_PALETTES := ["basalt_ember", "clayfire", "abyss_violet"]
const SPACING := 4.5

var _pivot: Node3D


func _ready() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	_place_family("turrets", TURRETS, TURRET_PALETTES, -8.0)
	_place_family("monsters", MONSTERS, MONSTER_PALETTES, 8.0)
	_setup_environment()


func _place_family(folder: String, models: Array, palettes: Array, z_offset: float) -> void:
	for col in models.size():
		for row in palettes.size():
			var path := "res://assets/models/%s/%s_%s.glb" % [folder, models[col], palettes[row]]
			var scene := load(path) as PackedScene
			if scene == null:
				push_warning("Missing model: " + path)
				continue
			var inst := scene.instantiate() as Node3D
			inst.position = Vector3((col - 1) * SPACING, 0.0, z_offset + (row - 1) * SPACING)
			_pivot.add_child(inst)


func _setup_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#2e3a48")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#9aa7b5")
	env.environment.glow_enabled = true  # makes the cyan / ember emissives bloom
	add_child(env)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#6b7a52")
	ground.material_override = mat
	add_child(ground)

	# Angled top-down camera like the battlefield view
	var cam := Camera3D.new()
	cam.position = Vector3(0, 30, 22)
	cam.rotation_degrees = Vector3(-55, 0, 0)
	cam.fov = 45
	add_child(cam)

