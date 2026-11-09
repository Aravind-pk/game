extends SceneTree
## Render the normal game scene at 540x960 despite desktop window size constraints.
## godot --path godot --script /abs/tools/sprites/record_combat.gd --fixed-fps 10
##   --quit-after 420 -- level=04 phase=combat capture=/abs/output

var _stage: SubViewport
var _output := ""
var _frame := 0
var _first_frame := 0
var _last_frame := -1
var _main: Node
var _trace: FileAccess
var _probe_cell := Vector2i(-1, -1)
var _watch_to_end := false

func _initialize() -> void:
	call_deferred("_start_game")


func _start_game() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("capture="):
			_output = argument.trim_prefix("capture=")
		elif argument.begins_with("capture_from="):
			_first_frame = roundi(float(argument.trim_prefix("capture_from=")) * 10.0)
		elif argument.begins_with("capture_to="):
			_last_frame = roundi(float(argument.trim_prefix("capture_to=")) * 10.0)
		elif argument.begins_with("capture_mg="):
			var coordinates := argument.trim_prefix("capture_mg=").split(",")
			_probe_cell = Vector2i(int(coordinates[0]), int(coordinates[1]))
		elif argument == "capture_watch":
			_watch_to_end = true
	assert(not _output.is_empty(), "Pass capture=/abs/output")
	DirAccess.make_dir_recursive_absolute(_output)
	_trace = FileAccess.open(_output.path_join("trace.jsonl"), FileAccess.WRITE)
	_stage = SubViewport.new()
	# Match project.godot's 1080x1920 design canvas and its 0.5 display scale.
	_stage.size = Vector2i(1080, 1920)
	_stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_stage)
	var scene := load("res://scenes/main.tscn") as PackedScene
	_main = scene.instantiate()
	_stage.add_child(_main)
	if _probe_cell.x >= 0:
		call_deferred("_deploy_probe")
	RenderingServer.frame_post_draw.connect(_capture)


func _deploy_probe() -> void:
	# Use the same placement/defend entry points as the UI, on a deployment-phase run.
	assert(_main.get("deployment").is_empty(), "Use phase=deploy for capture_mg")
	assert(_main.place(0, _probe_cell), "The probe cell must be a legal MG placement")
	_main.defend()


func _capture() -> void:
	if _frame >= _first_frame and (_last_frame < 0 or _frame <= _last_frame):
		var image := _stage.get_texture().get_image()
		image.resize(540, 960, Image.INTERPOLATE_LANCZOS)
		image.save_png(_output.path_join("f%08d.png" % _frame))
	_frame += 1


func _process(_delta: float) -> bool:
	if not is_instance_valid(_main):
		return false
	if _watch_to_end and bool(_main.get("paused")):
		for label in _main.find_children("*", "Label", true, false):
			if label.text.to_lower() == "watch to end":
				var button := label.get_parent()
				while button != null and not button is Button:
					button = button.get_parent()
				if button is Button:
					button.pressed.emit()
				break
	var battle := _main.get("sim") as BattleSim
	var field := _main.get("battlefield") as Battlefield
	if battle != null and is_instance_valid(field) and is_instance_valid(field._gate):
		var guns := []
		for gun in battle.guns:
			guns.append({"id": gun.id, "type": gun.type, "alive": gun.alive, "hp": gun.hp})
		_trace.store_line(JSON.stringify({"frame": _frame, "time": battle.time,
			"gate_hp": battle.gate_hp, "damage": field._gate_frame,
			"breach": field.get("_breach_frame"), "wall_base": field._wall_base,
			"gate_position": [field._gate.position.x, field._gate.position.y], "guns": guns}))
		_trace.flush()
	return false
