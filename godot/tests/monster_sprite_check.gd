extends SceneTree
## Drives a sprite monster and turret through a battle's states without a renderer and checks that
## the 2D view behaves: no skipped turn poses, full turn coverage, and a clean death.
##
##   godot --headless --path godot --script res://tests/monster_sprite_check.gd

const DT := 1.0 / 60.0

var _failures := 0


func _init() -> void:
	var sprite := MonsterSprite.new()
	root.add_child(sprite)
	sprite.setup("burrower", Vector2.ZERO)
	_check_turret()
	_check_pending_turrets()
	_check_pending_monsters()
	_check_footprint_avoidance()
	_check_wheel(sprite)
	_check_emerge_to_walk(sprite)
	_check_full_circle(sprite)
	_check_attack(sprite)
	sprite.die(1.0)
	_expect(sprite._state == "dead", "death starts")
	call_deferred("_finish_checks")


func _finish_checks() -> void:
	_check_wall()
	print("FAIL" if _failures else "PASS", " monster_sprite_check, failures: ", _failures)
	quit(1 if _failures else 0)


func _monster(state: String) -> Dictionary:
	return {"state": state, "state_t": 0.0, "attacking": false, "facing": Vector2(0, 1), "attack_rate": 1.0, "cooldown": 1.0}


func _check_wall() -> void:
	var timelines := []
	for start_stage in [0, 4]:
		var field := Battlefield.new()
		root.add_child(field)
		var level := LevelData.load_file("res://levels/level_05.json")
		field.build(level)
		field.sim = BattleSim.new()
		field.sim.setup(level, [])
		var foot := field.wall_foot_screen_pos()
		var attack_line := field.gate_ground()
		var position := field._gate.position
		_expect(is_equal_approx(position.y + 80.0, field._wall_base - 312.6), "wall padding preserves its original physical registration")
		for stage in 5:
			field._set_gate_frame(stage)
			_expect(field._gate.position == position, "damage stages share one registration")
		field._set_gate_frame(start_stage)
		field.play_breach()
		var seen := {0: true}
		var timeline := []
		for step in 72:
			field.animate_breach(0.05)
			timeline.append(field._breach_frame)
			seen[field._breach_frame] = true
			_expect(field._gate.position == position, "breach registration stays fixed")
			_expect(field.wall_foot_screen_pos() == foot, "gate HP plate anchor stays fixed")
			_expect(field.gate_ground() == attack_line, "monster attack line stays fixed")
		_expect(seen.size() == 14, "all fourteen breach frames are reached")
		_expect(field._breach_frame == 13, "last breach frame holds")
		_expect(float(field._wall_data.breach_frame_ms) * 14.0 < 3600.0, "breach fits the defeat timer")
		timelines.append(timeline)
		field._breaching = false
		field.play_breach()
		for index in range(1, 14):
			field.animate_breach(0.1)
			_expect(field._breach_frame == index, "10 fps reaches breach frame %d without rounding skips" % index)
		field.free()
	_expect(timelines[0] == timelines[1], "breach clock is independent of prior damage stage")


func _check_pending_turrets() -> void:
	for kit_name in Battlefield.TURRET_KITS.values():
		if kit_name == "kestrel":
			continue
		var turret := TurretSprite.new()
		root.add_child(turret)
		turret.setup(kit_name, null, null)
		_expect(turret._anims.aim.frames.size() == 14, "%s has 14 aim frames" % kit_name)
		_expect(turret._muzzle_px.size() == turret._aim_degrees.size(), "%s muzzle coverage" % kit_name)
		for angle in turret._aim_degrees:
			turret.update_turret(true, deg_to_rad(float(angle)), 1.0)
			_expect(turret._base_sprite.position == Vector2.ZERO, "%s base stays fixed" % kit_name)
			turret.fired()
			turret.update_turret(true, deg_to_rad(float(angle)), 0.2)
			_expect(turret._sprite.position.is_zero_approx(), "%s recoil recovers" % kit_name)
		turret.destroyed()
		for i in 120:
			turret.update_turret(false, 0.0, DT)
		_expect(not turret._base_sprite.visible, "%s wreck includes its own base" % kit_name)
		turret.queue_free()


func _check_pending_monsters() -> void:
	for kit_name in Battlefield.MONSTER_KITS.values():
		if kit_name == "burrower":
			continue
		var sprite := MonsterSprite.new()
		root.add_child(sprite)
		sprite.setup(kit_name, Vector2.ZERO)
		for heading in ["S", "SW", "E", "NE", "N"]:
			_expect(sprite._anims["walk_" + heading].frames.size() == 8, "%s walk %s coverage" % [kit_name, heading])
		for heading in ["S", "SW", "E"]:
			_expect(sprite._anims["attack_" + heading].frames.size() == 6, "%s attack %s coverage" % [kit_name, heading])
		_expect(sprite._anims.death_S.frames.size() == 10 and sprite._anims.death_E.frames.size() == 10, "%s death coverage" % kit_name)
		_expect(sprite._anims.emerge.frames.size() == 12, "%s emerge coverage" % kit_name)
		_expect(sprite._wheel.size() == 8, "%s uses eight authored turn holds" % kit_name)
		_check_emerge_to_walk(sprite)
		_check_full_circle(sprite)
		_check_attack(sprite)
		for heading in [0.0, PI * 0.5, PI, PI * 1.5]:
			sprite._dir = sprite.DIR_ORDER[sprite._nearest_dir(heading)]
			sprite.die(1.0)
			for i in 90:
				sprite._process(DT)
			_expect(sprite._state == "dead", "%s death plays for facing %s" % [kit_name, heading])
		sprite.queue_free()


func _check_turret() -> void:
	var turret := TurretSprite.new()
	root.add_child(turret)
	turret.setup("kestrel", null, null)
	_expect(turret._anims.aim.frames.size() == 16, "turret has 16 aim frames")
	_expect(turret.MUZZLE_PX.size() == 16 and turret.AIM_DEGREES.size() == 16, "every aim frame has a muzzle and an angle")
	_expect(turret._anims.destroy.frames.size() == 8, "Kestrel has eight v3 destruction frames")
	var baseline_path := ProjectSettings.globalize_path("res://../art/sprites/kestrel_v3/")
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(baseline_path + "kestrel-atlas-v3.json"))
	var current := Image.load_from_file(ProjectSettings.globalize_path("res://assets/sprites/turrets/kestrel.png"))
	var previous := Image.load_from_file(baseline_path + "kestrel-atlas-v3.png")
	for name in ["aim", "base"]:
		_expect(turret._anims[name] == baseline.anims[name], "Kestrel %s JSON is preserved" % name)
		for frame in baseline.anims[name].frames:
			var rect := Rect2i(frame.x, frame.y, frame.w, frame.h)
			_expect(current.get_region(rect).get_data() == previous.get_region(rect).get_data(), "Kestrel %s pixels are preserved" % name)
	var last := turret._aim
	for i in 200:
		turret.update_turret(true, PI * 0.5, DT)
		var moved := mini(posmod(turret._aim - last, 16), posmod(last - turret._aim, 16))
		_expect(moved <= 1, "barrel swung %d steps in one frame" % moved)
		last = turret._aim
	_expect(turret._aim == 0, "barrel reaches the south aim frame (got %d)" % turret._aim)
	turret.fired()
	turret.update_turret(true, PI * 0.5, DT)
	_expect(turret._flash.visible, "firing shows a flash")
	_expect(turret.muzzle_offset().is_equal_approx(turret.MUZZLE_PX[0] * turret._art_scale() + turret._sprite.position), "shots leave from the south muzzle")
	_expect(turret._base_sprite.position == Vector2.ZERO and turret._sprite.position.length() > 0.0, "only the head recoils")
	turret._flash.visible = false
	turret.fired()
	_expect(turret._flash.visible, "flash appears on firing frame")
	turret._aim_angle = deg_to_rad(170.0)
	turret._pan_toward(deg_to_rad(-170.0), DT)
	_expect(is_equal_approx(rad_to_deg(turret._aim_angle), 176.0), "aim takes short angular path across wrap")
	turret._aim_angle = 0.0
	turret._pan_toward(PI * 0.5, 0.25)
	_expect(is_equal_approx(turret._aim_angle, PI * 0.5), "aim speed is independent of frame spacing")

	turret.update_turret(false, 0.0, 0.0)
	var entry_rect := turret._sprite.region_rect
	var entry_offset := turret._sprite.offset
	var pedestal_rect := turret._base_sprite.region_rect
	var pedestal_offset := turret._base_sprite.offset
	turret.destroyed()
	turret.update_turret(false, 0.0, 0.0)
	_expect(turret._sprite.region_rect == entry_rect and turret._sprite.offset == entry_offset, "Kestrel destruction starts on the current aim image")
	_expect(turret._base_sprite.visible, "Kestrel keeps its approved pedestal during destruction")
	for i in 120:
		turret.update_turret(false, 0.0, DT)
		_expect(turret._base_sprite.visible and turret._base_sprite.position == Vector2.ZERO, "Kestrel pedestal stays planted")
		_expect(turret._base_sprite.region_rect == pedestal_rect and turret._base_sprite.offset == pedestal_offset, "Kestrel pedestal art and anchor stay unchanged")
	_expect(turret._destroy_ms > 1000.0, "destruction plays out")


func _check_footprint_avoidance() -> void:
	var field := Battlefield.new()
	var square := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 2), Vector2(0, 2)])
	field._footprints.append({"poly": square, "box": Rect2(0, 0, 4, 2)})
	var from_inside := field._keep_clear(Vector2(2, 0.5), 0.45)
	_expect(not Geometry2D.is_point_in_polygon(from_inside, square), "a monster inside a footprint is moved out")
	_expect(is_equal_approx(from_inside.y, -0.45), "it moves out by the nearest edge (got %s)" % from_inside)
	var near := field._keep_clear(Vector2(2, 2.2), 0.45)
	_expect(is_equal_approx(near.y, 2.45), "a monster too close is eased away (got %s)" % near)
	_expect(field._keep_clear(Vector2(9, 9), 0.45) == Vector2(9, 9), "open ground is left alone")
	field.free()


func _check_wheel(sprite: MonsterSprite) -> void:
	_expect(sprite._wheel.size() == 16, "turntable has 16 poses (got %d)" % sprite._wheel.size())
	var largest := 0.0
	for i in sprite._wheel.size():
		var next: Dictionary = sprite._wheel[(i + 1) % sprite._wheel.size()]
		largest = maxf(largest, absf(angle_difference(sprite._wheel[i].a, next.a)))
	_expect(rad_to_deg(largest) < 25.0, "no gap between turn poses over 25 degrees (got %.1f)" % rad_to_deg(largest))


func _check_emerge_to_walk(sprite: MonsterSprite) -> void:
	var m := _monster("emerging")
	m.state_t = Defs.EMERGE_TIME
	while m.state_t > 0.0:
		m.state_t -= DT
		sprite.tick(m, Vector2.ZERO, DT)
	m.state = "active"
	sprite.tick(m, Vector2.ZERO, DT)
	_expect(sprite._state == "walk", "emerge hands over to walking")


## Walks a full circle and checks the facing only ever moves to a neighbouring one.
func _check_full_circle(sprite: MonsterSprite) -> void:
	var m := _monster("active")
	var seen := {}
	var last := sprite.DIR_ORDER.find(sprite._dir)
	var angle := PI / 2.0
	var pos := sprite.ground
	for _i in 4000:
		angle += 0.004
		pos += Vector2(cos(angle), sin(angle)) * 0.04
		sprite.tick(m, pos, DT)
		if sprite._state == "turn":
			continue
		var now := sprite.DIR_ORDER.find(sprite._dir)
		seen[sprite._dir] = true
		var apart := mini((now - last + 16) % 16, (last - now + 16) % 16)
		_expect(apart <= 2, "facing jumped %d steps without turning" % apart)
		last = now
	_expect(seen.size() == 16, "walked through all 16 facings (saw %d)" % seen.size())


func _check_attack(sprite: MonsterSprite) -> void:
	var m := _monster("active")
	m.attacking = true
	for i in 120:
		m.cooldown -= DT
		if m.cooldown <= 0.0:
			m.cooldown += 1.0
		sprite.tick(m, sprite.ground, DT)
	_expect(sprite._state == "attack", "reaches the attack state after turning")
	_expect(sprite._attack_anim == "attack_S", "attacks straight ahead when facing the gate")


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("  failed: ", what)

