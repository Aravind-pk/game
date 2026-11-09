class_name LevelHints
extends RefCounted
## Works out the next placement to suggest, from the solutions tools/level_engine/forge.mjs baked
## into the level. Only reads data, so asking for a hint costs nothing on a phone.


## Returns {} if the level has no solutions, otherwise:
##   solved:  every turret is on the tile of one complete solution
##   slot:    {type, cell, zone} the turret to deal with next (absent when solved)
##   move:    true if no spare turret of that type is left, so a placed one has to move
##   solution: index of the solution followed
## `stick_to` keeps later hints on one solution once the player has started following it, so the
## marked tile does not jump to a different plan after every move.
static func next_step(level: LevelData, deployment: Array, stick_to := -1) -> Dictionary:
	if stick_to >= 0 and stick_to < level.solutions.size():
		var kept := _match(level.solutions[stick_to], deployment)
		kept.solution = stick_to
		return kept
	var best := {}
	var best_score := -1
	for i in level.solutions.size():
		var m := _match(level.solutions[i], deployment)
		if m.score > best_score:
			best_score = m.score
			best = m
			best.solution = i
	return best


## Lines up the player's turrets with a solution: exact tiles first, then tiles in a slot's zone.
static func _match(sol: Dictionary, deployment: Array) -> Dictionary:
	var slots: Array = sol.guns
	var status := []
	status.resize(slots.size())
	status.fill("open")
	var taken := {}
	for pass_name in ["exact", "zone"]:
		for si in slots.size():
			if status[si] != "open":
				continue
			var s: Dictionary = slots[si]
			for di in deployment.size():
				var d: Dictionary = deployment[di]
				if taken.has(di) or d.type != s.type or d.get("gun", 0) < 0:
					continue
				var fits: bool = d.cell == s.cell if pass_name == "exact" else s.zone.has(d.cell)
				if fits:
					status[si] = pass_name
					taken[di] = true
					break
	var score := 0
	var open_i := -1
	var zone_i := -1
	for si in slots.size():
		score += 3 if status[si] == "exact" else (1 if status[si] == "zone" else 0)
		if status[si] == "open" and open_i < 0:
			open_i = si
		elif status[si] == "zone" and zone_i < 0:
			zone_i = si
	var target := open_i if open_i >= 0 else zone_i
	if target < 0:
		return {"score": score, "solved": true}
	var spare_placed := false
	for di in deployment.size():
		if not taken.has(di) and deployment[di].type == slots[target].type and deployment[di].get("gun", 0) >= 0:
			spare_placed = true
	return {"score": score, "solved": false, "slot": slots[target],
		"move": spare_placed or status[target] == "zone"}
