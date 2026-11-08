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
	_check_wheel(sprite)
	_check_emerge_to_walk(sprite)
	_check_full_circle(sprite)
	_check_attack(sprite)
	sprite.die(1.0)
	_expect(sprite._state == "dead", "death starts")
	print("FAIL" if _failures else "PASS", " monster_sprite_check, failures: ", _failures)
	quit(1 if _failures else 0)


func _monster(state: String) -> Dictionary:
	return {"state": state, "state_t": 0.0, "attacking": false, "facing": Vector2(0, 1), "attack_rate": 1.0, "cooldown": 1.0}


func _check_turret() -> void:
	var turret := TurretSprite.new()
	root.add_child(turret)
	turret.setup("kestrel")
	_expect(turret._anims.aim.frames.size() == 14 and turret._anims.fire.frames.size() == 14, "turret has 14 aim and fire frames")
	_expect(turret._anims.destroy.frames.size() == 12, "turret has 12 destruction frames")
	var last := turret._aim
	for i in 200:
		turret.update_turret(true, PI * 0.5, DT)
		var moved := mini(posmod(turret._aim - last, 14), posmod(last - turret._aim, 14))
		_expect(moved <= 1, "barrel swung %d steps in one frame" % moved)
		last = turret._aim
	_expect(turret._aim == 0, "barrel reaches the south aim frame (got %d)" % turret._aim)
	turret.destroyed()
	for i in 120:
		turret.update_turret(false, 0.0, DT)
	_expect(turret._destroy_ms > 1000.0, "destruction plays out")


func _check_wheel(sprite: MonsterSprite) -> void:
	_expect(sprite._wheel.size() == 26, "turntable has 26 poses (got %d)" % sprite._wheel.size())
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
