extends SceneTree
## Replays battles from tools/level_engine/parity_cases.mjs in the real simulation and reports
## any difference, so the fast Node search tool can be trusted to match BattleSim.
##   godot --headless --path godot --script res://tests/port_parity.gd -- cases=/path/cases.json


func _init() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("cases="):
			path = a.trim_prefix("cases=")
	var cases: Array = JSON.parse_string(FileAccess.get_file_as_string(path))
	var levels := {}
	var bad := 0
	var slowest := 0
	var t0 := Time.get_ticks_msec()
	for c in cases:
		if not levels.has(c.file):
			levels[c.file] = LevelData.load_file("res://levels/" + c.file)
		var dep := []
		for d in c.deployment:
			dep.append({"type": d.type, "level": int(d.level), "ammo": int(d.ammo),
				"cell": Vector2i(int(d.cell[0]), int(d.cell[1])), "order": str(d.get("order", ""))})
		var sim := BattleSim.new()
		sim.setup(levels[c.file], BattleSim.canonical_order(dep))
		var t1 := Time.get_ticks_msec()
		sim.run_to_end()
		slowest = maxi(slowest, Time.get_ticks_msec() - t1)
		var s := sim.summary()
		var steps := roundi(sim.time * 30.0)
		var win: bool = sim.state == BattleSim.State.VICTORY
		var same: bool = win == c.win and steps == int(c.steps) and int(s.kills) == int(c.kills) \
			and int(s.guns_survived) == int(c.guns_left) and int(s.ammo_left) == int(c.ammo_left) \
			and absf(sim.gate_hp - float(c.gate_hp)) < 0.001
		if not same:
			bad += 1
			if bad <= 10:
				print("DIFF %s godot[win=%s steps=%d gate=%.2f kills=%d guns=%d ammo=%d] node[win=%s steps=%d gate=%.2f kills=%d guns=%d ammo=%d]" % [
					c.file, win, steps, sim.gate_hp, s.kills, s.guns_survived, s.ammo_left,
					c.win, c.steps, c.gate_hp, c.kills, c.guns_left, c.ammo_left])
	print("PARITY: %d/%d battles identical (%.2fs total, slowest %dms)" % [cases.size() - bad, cases.size(),
		(Time.get_ticks_msec() - t0) / 1000.0, slowest])
	quit(1 if bad > 0 else 0)
