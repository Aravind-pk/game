extends SceneTree
## Headless simulation checks + balance probe.
##   godot --headless --path godot --script res://tests/sim_check.gd [-- trials=150 level=03]
## For each level: no-defence must lose, identical runs must match exactly, and a seeded
## random search over deployments reports how winnable the level is.

var _failures := 0
var _search_iters := 0


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var trials := int(args.get("trials", "150"))
	_search_iters = int(args.get("search", "0"))
	var only := str(args.get("level", ""))
	var dir := DirAccess.open("res://levels")
	var files := Array(dir.get_files()).filter(func(f): return f.begins_with("level_") and f.ends_with(".json"))
	files.sort()
	if only != "":  # open only the requested file, so a level being rewritten elsewhere can't break the run
		files = files.filter(func(f): return f == "level_%s.json" % only)
	for f in files:
		var lv := LevelData.load_file("res://levels/" + f)
		if lv == null:
			_failures += 1
			continue
		_check_level(lv, trials)
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("  FAIL: " + msg)


func _run(lv: LevelData, dep: Array) -> BattleSim:
	var sim := BattleSim.new()
	sim.setup(lv, BattleSim.canonical_order(dep + lv.fixed))
	sim.run_to_end()
	return sim


func _gun_list(lv: LevelData) -> Array:
	var out := []
	for g in lv.guns:
		for i in int(g.count):
			out.append({"type": g.type, "level": g.level, "ammo": g.ammo})
	return out


func _random_deployment(lv: LevelData, rng: RandomNumberGenerator) -> Array:
	var cells := []
	for y in range(lv.view_rect.position.y, lv.view_rect.end.y):
		for x in range(lv.view_rect.position.x, lv.view_rect.end.x):
			if lv.is_deployable(Vector2i(x, y)):
				cells.append(Vector2i(x, y))
	var dep := []
	var used := {}
	for g in _gun_list(lv):
		var c: Vector2i = cells[rng.randi() % cells.size()]
		while used.has(c):
			c = cells[rng.randi() % cells.size()]
		used[c] = true
		var d: Dictionary = g.duplicate()
		d.cell = c
		dep.append(d)
	return dep


func _score(sm: Dictionary) -> float:
	return sm.gate_hp + 1000.0 * float(sm.kills) / float(sm.total_enemies) + 50.0 * sm.guns_survived


func _hill_climb(lv: LevelData, dep: Array, score: float, rng: RandomNumberGenerator) -> Dictionary:
	var cells := []
	for y in range(lv.view_rect.position.y, lv.view_rect.end.y):
		for x in range(lv.view_rect.position.x, lv.view_rect.end.x):
			if lv.is_deployable(Vector2i(x, y)):
				cells.append(Vector2i(x, y))
	var cur := dep.duplicate(true)
	var cur_sm := _run(lv, cur).summary()
	var cur_score := _score(cur_sm)
	for it in _search_iters:
		var cand := cur.duplicate(true)
		var gi := rng.randi() % cand.size()
		var c: Vector2i
		if rng.randf() < 0.6:  # small nudge
			c = cand[gi].cell + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2))
		else:
			c = cells[rng.randi() % cells.size()]
		if not lv.is_deployable(c) or cand.any(func(g): return g.cell == c):
			continue
		cand[gi].cell = c
		var sm := _run(lv, cand).summary()
		var sc := _score(sm)
		if sc >= cur_score:
			cur = cand
			cur_sm = sm
			cur_score = sc
	return {"dep": cur, "summary": cur_sm}


func _solution_deployment(lv: LevelData, sol: Dictionary) -> Array:
	var dep := []
	var ammo := {}
	var gun_level := {}
	for g in lv.guns:
		ammo[g.type] = g.ammo
		gun_level[g.type] = g.level
	for slot in sol.guns:
		dep.append({"type": slot.type, "level": gun_level[slot.type], "ammo": ammo[slot.type], "cell": slot.cell})
	return dep


## Hints promise that solutions win, so every baked solution and zone tile is replayed here.
func _check_solutions(lv: LevelData) -> void:
	_expect(not lv.solutions.is_empty(), "level has no baked solutions")
	_expect(not lv.intel.is_empty(), "level has no intel lines")
	var roster := {}
	for g in lv.guns:
		roster[g.type] = int(g.count)
	var zone_runs := 0
	for si in lv.solutions.size():
		var sol: Dictionary = lv.solutions[si]
		var dep := _solution_deployment(lv, sol)
		var counts := {}
		for slot in sol.guns:
			_expect(lv.is_deployable(slot.cell), "solution %d uses an unbuildable tile" % si)
			counts[slot.type] = int(counts.get(slot.type, 0)) + 1
		_expect(counts == roster, "solution %d does not use the level's turrets" % si)
		var sim := _run(lv, dep)
		_expect(sim.state == BattleSim.State.VICTORY, "solution %d must win" % si)
		for gi in dep.size():
			if dep[gi].ammo <= 0:
				var without := dep.duplicate(true)
				without.remove_at(gi)
				_expect(_run(lv, without).state != BattleSim.State.VICTORY, "solution %d must need its decoy" % si)
		print("  solution %d: %s, gate %.0f/%.0f, ammo left %d" % [si,
			"win" if sim.state == BattleSim.State.VICTORY else "LOSS", sim.gate_hp, lv.gate_max_hp, sim.summary().ammo_left])
		for gi in dep.size():
			for z in sol.guns[gi].zone:
				var cand := dep.duplicate(true)
				cand[gi].cell = z
				zone_runs += 1
				_expect(_run(lv, cand).state == BattleSim.State.VICTORY, "zone tile %s of gun %d must win" % [z, gi])
	print("  zone tiles replayed: %d" % zone_runs)
	_expect(not LevelHints.next_step(lv, []).get("solved", true), "an empty field must not count as solved")
	_expect(LevelHints.next_step(lv, _solution_deployment(lv, lv.solutions[0])).get("solved", false),
		"a full solution must count as solved")


func _check_level(lv: LevelData, trials: int) -> void:
	var t0 := Time.get_ticks_msec()
	print("Level %s — %s  (%d enemies)" % [lv.id, lv.title, lv.total_enemies()])
	_check_solutions(lv)
	var empty := _run(lv, [])
	_expect(empty.state == BattleSim.State.DEFEAT, "undefended gate should fall")
	print("  no defence: %s at t=%.1fs" % ["defeat" if empty.state == BattleSim.State.DEFEAT else "VICTORY?", empty.time])

	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var dep := _random_deployment(lv, rng)
	var a := _run(lv, dep)
	var b := _run(lv, dep)
	_expect(a.fingerprint() == b.fingerprint(), "identical deployments must give identical battles")

	var wins := 0
	var best: Dictionary = {}
	var best_dep := []
	for i in trials:
		var d := _random_deployment(lv, rng)
		var s := _run(lv, d)
		var sm := s.summary()
		if s.state == BattleSim.State.VICTORY:
			wins += 1
		var score: float = sm.gate_hp + 1000.0 * float(sm.kills) / float(sm.total_enemies)
		if best.is_empty() or score > best.score:
			best = sm.duplicate()
			best.score = score
			best_dep = d
	print("  random deployments won: %d / %d  (%.0f%%)" % [wins, trials, 100.0 * wins / max(trials, 1)])
	print("  best: gate %.0f/%.0f, kills %d/%d, guns left %d/%d" % [best.gate_hp, best.gate_max,
		best.kills, best.total_enemies, best.guns_survived, best.guns_total])
	if _search_iters > 0:
		var res := _hill_climb(lv, best_dep, best.score, rng)
		best_dep = res.dep
		best = res.summary
		print("  hill-climb best: %s gate %.0f/%.0f, kills %d/%d, guns left %d/%d" % [
			"WIN" if best.state == BattleSim.State.VICTORY else "loss", best.gate_hp, best.gate_max,
			best.kills, best.total_enemies, best.guns_survived, best.guns_total])
	var cells := []
	for g in best_dep:
		cells.append("%s@%d,%d" % [g.type, g.cell.x, g.cell.y])
	print("  best deployment: " + ", ".join(cells))
	print("  (%.1fs)" % ((Time.get_ticks_msec() - t0) / 1000.0))
