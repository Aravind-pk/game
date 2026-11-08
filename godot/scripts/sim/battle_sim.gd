class_name BattleSim
extends RefCounted
## Deterministic battle simulation. No nodes, no randomness, fixed time step:
## the same LevelData + deployment always produces the same battle.
##
## World coordinates are metres on the ground plane: x to the right, y toward the gate.
## The presentation layer reads `guns`, `monsters`, `shells` and drains `events`.

enum State { RUNNING, VICTORY, DEFEAT }

const INF := 1 << 30
const NEIGHBOURS := [Vector2i(0, 1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(-1, 0),
	Vector2i(1, 0), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(0, -1)]

var level: LevelData
var time := 0.0
var state := State.RUNNING
var gate_hp := 0.0
var guns: Array = []        # Dictionaries, index == id
var monsters: Array = []    # Dictionaries, index == id (dead ones stay, state == "dead")
var shells: Array = []
var events: Array = []      # drained by the view each frame
var kills := 0

var _schedule: Array = []   # [{t, hotspot, type, level, seq}] sorted by t
var _warnings: Array = []   # [{t, hotspot}]
var _blocked := PackedByteArray()
var _flow := PackedInt32Array()
var _flow_dirty := true
var _alive_monsters := 0


func setup(lv: LevelData, deployment: Array) -> void:
	level = lv
	gate_hp = lv.gate_max_hp
	for i in deployment.size():
		var d: Dictionary = deployment[i]
		var s := Defs.gun_stats(d.type, d.level)
		guns.append({
			"id": i, "type": d.type, "level": d.level, "cell": d.cell,
			"pos": lv.cell_center(d.cell), "hp": s.hp, "max_hp": s.hp, "damage": s.damage,
			"fire_rate": s.fire_rate, "range": s.range, "splash": s.splash,
			"projectile_speed": s.projectile_speed, "radius": s.radius, "ammo": int(d.ammo),
			"max_ammo": int(d.ammo), "cooldown": 0.0, "alive": true, "aim": Vector2(0, -1),
			"target": -1,
		})
	# spawn schedule: each hotspot runs its groups in order after its delay
	for hi in lv.hotspots.size():
		var h: Dictionary = lv.hotspots[hi]
		_warnings.append({"t": h.delay, "hotspot": hi})
		var t: float = h.delay + Defs.EMERGE_WARN
		var seq := 0
		for g in h.groups:
			for k in int(g.count):
				_schedule.append({"t": t, "hotspot": hi, "type": g.type, "level": g.level, "seq": seq})
				t += float(g.interval)
				seq += 1
	_schedule.sort_custom(func(a, b):
		if a.t != b.t:
			return a.t < b.t
		if a.hotspot != b.hotspot:
			return a.hotspot < b.hotspot
		return a.seq < b.seq)
	_warnings.sort_custom(func(a, b): return a.t < b.t or (a.t == b.t and a.hotspot < b.hotspot))
	_rebuild_blocked()


func step() -> void:
	if state != State.RUNNING:
		return
	time += Defs.SIM_DT
	_process_spawns()
	for m in monsters:
		m.prev_pos = m.pos
	_update_monsters()
	_separate_monsters()
	_update_guns()
	_update_shells()
	_collect_dead()
	if _flow_dirty:
		_rebuild_blocked()
	if gate_hp <= 0.0:
		gate_hp = 0.0
		state = State.DEFEAT
		events.append({"type": "defeat"})
	elif _schedule.is_empty() and _alive_monsters == 0:
		state = State.VICTORY
		events.append({"type": "victory"})
	elif time > Defs.MAX_BATTLE_TIME:
		state = State.DEFEAT
		events.append({"type": "defeat"})


## Run to completion (used by tests / level validation).
func run_to_end() -> int:
	while state == State.RUNNING:
		step()
		events.clear()
	return state


func summary() -> Dictionary:
	var survived := 0
	var ammo_left := 0
	for g in guns:
		if g.alive:
			survived += 1
		ammo_left += int(g.ammo)
	return {"state": state, "time": snappedf(time, 0.001), "gate_hp": snappedf(gate_hp, 0.01),
		"gate_max": level.gate_max_hp, "guns_survived": survived, "guns_total": guns.size(),
		"kills": kills, "total_enemies": level.total_enemies(), "ammo_left": ammo_left}


func fingerprint() -> String:
	var parts := [str(summary())]
	for m in monsters:
		parts.append("%d:%.3f,%.3f:%.2f" % [m.id, m.pos.x, m.pos.y, m.hp])
	return "|".join(parts)


func remaining_enemies() -> int:
	return _schedule.size() + _alive_monsters


# ------------------------------------------------------------------ spawning

func _process_spawns() -> void:
	while not _warnings.is_empty() and _warnings[0].t <= time:
		var w: Dictionary = _warnings.pop_front()
		events.append({"type": "hotspot_warning", "hotspot": w.hotspot})
	while not _schedule.is_empty() and _schedule[0].t <= time:
		var s: Dictionary = _schedule.pop_front()
		_spawn_monster(s)


func _spawn_monster(s: Dictionary) -> void:
	var st := Defs.monster_stats(s.type, s.level)
	var h: Dictionary = level.hotspots[s.hotspot]
	# deterministic scatter around the fissure (golden-angle spiral)
	var k: int = s.seq % 9
	var ang := float(s.seq) * 2.39996
	var off := Vector2(cos(ang), sin(ang)) * 0.75 * sqrt(float(k))
	var pos := level.hotspot_pos(h) + off
	if _is_blocked_pos(pos):
		pos = level.hotspot_pos(h)
	var m := {
		"id": monsters.size(), "type": s.type, "level": s.level, "pos": pos, "prev_pos": pos,
		"hp": st.hp, "max_hp": st.hp, "speed": st.speed, "damage": st.damage,
		"attack_rate": st.attack_rate, "detect": st.detect, "attack_range": st.attack_range,
		"radius": st.radius, "state": "emerging", "state_t": Defs.EMERGE_TIME, "target": -1,
		"cooldown": 0.5, "retarget": 0.0, "facing": Vector2(0, 1), "hotspot": s.hotspot,
		"attacking": false,
	}
	monsters.append(m)
	_alive_monsters += 1
	events.append({"type": "emerge", "monster": m.id, "hotspot": s.hotspot})


# ------------------------------------------------------------------ monsters

func _update_monsters() -> void:
	var gate_y := float(level.wall_row) * Defs.CELL
	var gate_x0 := float(level.gate_cols.x) * Defs.CELL
	var gate_x1 := float(level.gate_cols.y + 1) * Defs.CELL
	for m in monsters:
		if m.state == "dead":
			continue
		if m.state == "emerging":
			m.state_t -= Defs.SIM_DT
			if m.state_t <= 0.0:
				m.state = "active"
			continue
		m.attacking = false
		# --- target selection
		if m.target >= 0 and not guns[m.target].alive:
			m.target = -1
		m.retarget -= Defs.SIM_DT
		if m.target < 0 and m.retarget <= 0.0:
			m.retarget = Defs.RETARGET_INTERVAL
			m.target = _closest_gun(m.pos, m.detect)
		# --- act
		if m.target >= 0:
			var g: Dictionary = guns[m.target]
			var to: Vector2 = g.pos - m.pos
			var gap: float = to.length() - g.radius - m.radius
			m.facing = to.normalized()
			if gap > m.attack_range:
				_move(m, m.facing, minf(m.speed * Defs.SIM_DT, gap - m.attack_range * 0.5))
			else:
				_attack(m, func():
					g.hp -= m.damage
					events.append({"type": "monster_attack", "monster": m.id, "gun": g.id})
					if g.hp <= 0.0 and g.alive:
						g.hp = 0.0
						g.alive = false
						_flow_dirty = true
						events.append({"type": "gun_destroyed", "gun": g.id}))
		else:
			var at_gate: bool = m.pos.y >= gate_y - m.radius - m.attack_range - 0.2 \
				and m.pos.x > gate_x0 and m.pos.x < gate_x1
			if at_gate:
				m.facing = Vector2(0, 1)
				_attack(m, func():
					gate_hp -= m.damage
					events.append({"type": "gate_hit", "monster": m.id, "damage": m.damage}))
			else:
				var dir := _flow_dir(m.pos, gate_x0, gate_x1, gate_y)
				# fixed per-monster lane offset so groups spread instead of marching single file
				var lane := float((m.id * 37) % 7 - 3) * 0.14
				dir = (dir + Vector2(-dir.y, dir.x) * lane).normalized()
				m.facing = dir
				_move(m, dir, m.speed * Defs.SIM_DT)


func _attack(m: Dictionary, hit: Callable) -> void:
	m.attacking = true
	m.cooldown -= Defs.SIM_DT
	if m.cooldown <= 0.0:
		m.cooldown += 1.0 / m.attack_rate
		hit.call()


func _move(m: Dictionary, dir: Vector2, dist: float) -> void:
	if dist <= 0.0:
		return
	var p: Vector2 = m.pos + dir * dist
	if not _is_blocked_pos(p):
		m.pos = p
		return
	# slide along whichever axis is free
	var px := Vector2(p.x, m.pos.y)
	var py := Vector2(m.pos.x, p.y)
	if absf(dir.x) >= absf(dir.y):
		if not _is_blocked_pos(px):
			m.pos = px
		elif not _is_blocked_pos(py):
			m.pos = py
	else:
		if not _is_blocked_pos(py):
			m.pos = py
		elif not _is_blocked_pos(px):
			m.pos = px


func _closest_gun(pos: Vector2, radius: float) -> int:
	var best := -1
	var best_d := INF * 1.0
	for g in guns:
		if not g.alive:
			continue
		var d: float = pos.distance_to(g.pos) - g.radius
		if d <= radius and d < best_d:
			best_d = d
			best = g.id
	return best


func _separate_monsters() -> void:
	var n := monsters.size()
	for i in n:
		var a: Dictionary = monsters[i]
		if a.state != "active":
			continue
		for j in range(i + 1, n):
			var b: Dictionary = monsters[j]
			if b.state != "active":
				continue
			var d: Vector2 = b.pos - a.pos
			var min_d: float = a.radius + b.radius
			var len2 := d.length_squared()
			if len2 >= min_d * min_d:
				continue
			var l := sqrt(len2)
			var nrm := d / l if l > 0.0001 else Vector2(cos(float(i * 7 + j)), sin(float(i * 7 + j)))
			var push := (min_d - l) * 0.5
			var pa: Vector2 = a.pos - nrm * push
			var pb: Vector2 = b.pos + nrm * push
			if not _is_blocked_pos(pa):
				a.pos = pa
			if not _is_blocked_pos(pb):
				b.pos = pb


func _collect_dead() -> void:
	for m in monsters:
		if m.state != "dead" and m.hp <= 0.0:
			m.state = "dead"
			m.hp = 0.0
			_alive_monsters -= 1
			kills += 1
			events.append({"type": "monster_died", "monster": m.id})


# ------------------------------------------------------------------ guns

func _update_guns() -> void:
	for g in guns:
		if not g.alive:
			continue
		g.cooldown = maxf(g.cooldown - Defs.SIM_DT, -Defs.SIM_DT)
		var t := _closest_monster(g.pos, g.range)
		g.target = t
		if t < 0:
			continue
		var m: Dictionary = monsters[t]
		g.aim = (m.pos - g.pos).normalized()
		if g.ammo <= 0 or g.cooldown > 0.0:
			continue
		g.ammo -= 1
		g.cooldown += 1.0 / g.fire_rate
		if g.projectile_speed > 0.0:
			var dist: float = g.pos.distance_to(m.pos)
			shells.append({"from": g.pos, "to": m.pos, "t": dist / g.projectile_speed,
				"flight": dist / g.projectile_speed, "damage": g.damage, "splash": g.splash,
				"gun": g.id})
			events.append({"type": "fire", "gun": g.id, "to": m.pos, "shell": true})
		else:
			m.hp -= g.damage
			events.append({"type": "fire", "gun": g.id, "to": m.pos, "monster": m.id})


func _closest_monster(pos: Vector2, rng: float) -> int:
	var best := -1
	var best_d := INF * 1.0
	for m in monsters:
		if m.state != "active" or m.hp <= 0.0:
			continue
		var d: float = pos.distance_to(m.pos) - m.radius
		if d <= rng and d < best_d:
			best_d = d
			best = m.id
	return best


func _update_shells() -> void:
	var i := 0
	while i < shells.size():
		var s: Dictionary = shells[i]
		s.t -= Defs.SIM_DT
		if s.t > 0.0:
			i += 1
			continue
		for m in monsters:
			if m.state == "active" and m.hp > 0.0 and m.pos.distance_to(s.to) <= s.splash + m.radius:
				m.hp -= s.damage
		events.append({"type": "explode", "pos": s.to, "radius": s.splash, "gun": s.gun})
		shells.remove_at(i)


# ------------------------------------------------------------------ navigation

func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / Defs.CELL), floori(p.y / Defs.CELL))


func _in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < level.cols and c.y < level.rows


func _is_blocked_cell(c: Vector2i) -> bool:
	if not _in_grid(c):
		return true
	return _blocked[c.y * level.cols + c.x] != 0


func _is_blocked_pos(p: Vector2) -> bool:
	return _is_blocked_cell(_cell_of(p))


func _rebuild_blocked() -> void:
	var n := level.cols * level.rows
	_blocked.resize(n)
	for y in level.rows:
		for x in level.cols:
			var c := Vector2i(x, y)
			_blocked[y * level.cols + x] = 1 if (level.is_wall(c) or level.is_obstacle(c)) else 0
	for g in guns:
		if g.alive:
			_blocked[g.cell.y * level.cols + g.cell.x] = 1
	_build_flow()
	_flow_dirty = false


## Dijkstra distance field (10 straight / 14 diagonal) toward the cells in front of the gate.
func _build_flow() -> void:
	var n := level.cols * level.rows
	_flow.resize(n)
	_flow.fill(INF)
	var frontier: Array = []
	var gy := level.wall_row - 1
	for x in range(level.gate_cols.x, level.gate_cols.y + 1):
		var c := Vector2i(x, gy)
		if not _is_blocked_cell(c):
			_flow[gy * level.cols + x] = 0
			frontier.append(c)
	# simple bucketed Dijkstra (costs are small integers)
	while not frontier.is_empty():
		var best_i := 0
		var best_v := INF
		for i in frontier.size():
			var v := _flow[frontier[i].y * level.cols + frontier[i].x]
			if v < best_v:
				best_v = v
				best_i = i
		var c: Vector2i = frontier[best_i]
		frontier.remove_at(best_i)
		for d in NEIGHBOURS:
			var nc: Vector2i = c + d
			if _is_blocked_cell(nc):
				continue
			if d.x != 0 and d.y != 0 and (_is_blocked_cell(Vector2i(c.x + d.x, c.y)) \
					or _is_blocked_cell(Vector2i(c.x, c.y + d.y))):
				continue  # no corner cutting
			var cost := best_v + (14 if (d.x != 0 and d.y != 0) else 10)
			var idx := nc.y * level.cols + nc.x
			if cost < _flow[idx]:
				if _flow[idx] == INF:
					frontier.append(nc)
				_flow[idx] = cost


func _flow_dir(pos: Vector2, gx0: float, gx1: float, gy: float) -> Vector2:
	var c := _cell_of(pos)
	var here := INF
	if _in_grid(c) and not _is_blocked_cell(c):
		here = _flow[c.y * level.cols + c.x]
	if here == 0:
		return (Vector2(clampf(pos.x, gx0 + 0.5, gx1 - 0.5), gy) - pos).normalized()
	if here == INF:
		return (Vector2((gx0 + gx1) * 0.5, gy) - pos).normalized()
	var best := here
	var best_c := c
	for d in NEIGHBOURS:
		var nc: Vector2i = c + d
		if _is_blocked_cell(nc):
			continue
		if d.x != 0 and d.y != 0 and (_is_blocked_cell(Vector2i(c.x + d.x, c.y)) \
				or _is_blocked_cell(Vector2i(c.x, c.y + d.y))):
			continue
		var v := _flow[nc.y * level.cols + nc.x]
		if v < best:
			best = v
			best_c = nc
	return (level.cell_center(best_c) - pos).normalized()
