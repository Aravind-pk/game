class_name UnitView
extends Node2D
## Base for anything standing on the battlefield. The view is pure 2D: the game looks down
## at the ground at a fixed angle, so a ground distance north-south is drawn shorter.

const PX_PER_M := 40.0
const DEPTH := 0.643    # screen pixels per ground pixel, north-south
const RISE := 0.766     # screen pixels per metre of height

var ground := Vector2.ZERO  # where the unit is drawn, in simulation metres
var bar: HealthBar


func add_bar(width_m: float, height_m: float, color: Color) -> void:
	bar = HealthBar.new()
	bar.setup(width_m * PX_PER_M, color)
	bar.position.y = -height_m * RISE * PX_PER_M
	bar.visible = false
	add_child(bar)


## Monsters: called once per rendered frame while the simulation has this one alive.
func tick(_m: Dictionary, _sim_pos: Vector2, _dt: float) -> void:
	pass


func die(_speed: float) -> void:
	queue_free()


func move_by(step: Vector2, _dt: float) -> void:
	ground += step


## Turrets: called once per rendered frame while the battle runs.
func update_turret(_has_target: bool, _aim_angle: float, _dt: float) -> void:
	pass


func fired() -> void:
	pass


func destroyed() -> void:
	pass
