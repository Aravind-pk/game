extends SceneTree
## Render the normal game scene at 540x960 despite desktop window size constraints.
## godot --path godot --script /abs/tools/sprites/record_combat.gd --fixed-fps 10
##   --quit-after 420 -- level=04 phase=combat capture=/abs/output

var _stage: SubViewport
var _output := ""
var _frame := 0

func _initialize() -> void:
	call_deferred("_start_game")


func _start_game() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("capture="):
			_output = argument.trim_prefix("capture=")
	assert(not _output.is_empty(), "Pass capture=/abs/output")
	DirAccess.make_dir_recursive_absolute(_output)
	_stage = SubViewport.new()
	# Match project.godot's 1080x1920 design canvas and its 0.5 display scale.
	_stage.size = Vector2i(1080, 1920)
	_stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_stage)
	var scene := load("res://scenes/main.tscn") as PackedScene
	_stage.add_child(scene.instantiate())
	RenderingServer.frame_post_draw.connect(_capture)


func _capture() -> void:
	var image := _stage.get_texture().get_image()
	image.resize(540, 960, Image.INTERPOLATE_LANCZOS)
	image.save_png(_output.path_join("f%08d.png" % _frame))
	_frame += 1
