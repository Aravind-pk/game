class_name LevelData
extends RefCounted
## A level loaded from res://levels/*.json. Grid coordinates: col (x) to the right,
## row (y) increasing toward the settlement gate at the bottom.

var id: String
var title: String
var cols: int
var rows: int
var view_rect: Rect2i            # cells visible to the normal camera (and deployable)
var gate_max_hp: float
var gate_cols: Vector2i          # first/last column of the gate opening
var wall_row: int                # row occupied by the settlement wall
var obstacles: Array[Rect2i] = []
var no_build: Array[Rect2i] = []  # unstable ground: monsters cross it, turrets can't be built on it
var fixed: Array = []            # [{type, level, ammo, cell}] holdout turrets already in place
var map_id: String               # which painted background this level uses
var note: String                 # one-line briefing note, usually introducing a mechanic
var orders := 0                  # turret orders the player may give this wave
var hotspots: Array = []         # [{name, cell: Vector2, delay, groups: [{type, level, count, interval}]}]
var guns: Array = []             # [{type, level, ammo, count}]
var intel: Array = []            # plain-language clues written by the level forge
var solutions: Array = []        # [{gate_left, ammo_left, guns: [{type, cell: Vector2i, zone: [Vector2i]}]}]


static func load_file(path: String) -> LevelData:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open level " + path)
		return null
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	return from_dict(d)


static func from_dict(d: Dictionary) -> LevelData:
	var L := LevelData.new()
	L.id = str(d.id)
	L.title = str(d.title)
	L.map_id = str(d.get("map", d.id))
	L.note = str(d.get("note", ""))
	L.orders = int(d.get("orders", -1))
	L.cols = int(d.cols)
	L.rows = int(d.rows)
	var v: Array = d.view
	L.view_rect = Rect2i(int(v[0]), int(v[1]), int(v[2]), int(v[3]))
	L.gate_max_hp = float(d.gate_hp)
	L.gate_cols = Vector2i(int(d.gate_cols[0]), int(d.gate_cols[1]))
	L.wall_row = L.rows - 1
	for o in d.get("obstacles", []):
		L.obstacles.append(Rect2i(int(o[0]), int(o[1]), int(o[2]), int(o[3])))
	for o in d.get("no_build", []):
		L.no_build.append(Rect2i(int(o[0]), int(o[1]), int(o[2]), int(o[3])))
	for g in d.get("fixed", []):
		L.fixed.append({"type": str(g.type), "level": int(g.level), "ammo": int(g.ammo),
			"cell": Vector2i(int(g.cell[0]), int(g.cell[1]))})
	for h in d.hotspots:
		var groups := []
		for g in h.groups:
			groups.append({"type": str(g.type), "level": int(g.level), "count": int(g.count),
				"interval": float(g.get("interval", 1.0))})
		L.hotspots.append({"name": str(h.name), "cell": Vector2(float(h.cell[0]), float(h.cell[1])),
			"delay": float(h.get("delay", 0.0)), "groups": groups})
	for g in d.guns:
		L.guns.append({"type": str(g.type), "level": int(g.level), "ammo": int(g.ammo),
			"count": int(g.get("count", 1))})
	for line in d.get("intel", []):
		L.intel.append(str(line))
	for s in d.get("solutions", []):
		var slots := []
		for g in s.guns:
			var zone := []
			for z in g.zone:
				zone.append(Vector2i(int(z[0]), int(z[1])))
			slots.append({"type": str(g.type), "cell": Vector2i(int(g.cell[0]), int(g.cell[1])), "zone": zone})
		L.solutions.append({"gate_left": int(s.gate_left), "ammo_left": int(s.ammo_left), "guns": slots})
	return L


func world_size() -> Vector2:
	return Vector2(cols, rows) * Defs.CELL


func cell_center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * Defs.CELL


func hotspot_pos(h: Dictionary) -> Vector2:
	return (h.cell + Vector2(0.5, 0.5)) * Defs.CELL


func is_obstacle(c: Vector2i) -> bool:
	for r in obstacles:
		if r.has_point(c):
			return true
	return false


func is_wall(c: Vector2i) -> bool:
	return c.y >= wall_row


## Can the player deploy a gun on this cell? (occupancy by other guns is checked separately)
func is_deployable(c: Vector2i) -> bool:
	if not view_rect.has_point(c) or is_wall(c) or is_obstacle(c):
		return false
	for r in no_build:
		if r.has_point(c):
			return false
	for g in fixed:
		if g.cell == c:
			return false
	for h in hotspots:
		if Vector2(c).distance_to(h.cell) < 1.5:
			return false  # can't build on a spawn fissure
	return true


## Enemy composition summary: [{type, level, count}] sorted by level.
func enemy_summary() -> Array:
	var acc := {}
	for h in hotspots:
		for g in h.groups:
			var key := "%s:%d" % [g.type, g.level]
			acc[key] = int(acc.get(key, 0)) + int(g.count)
	var out := []
	for key in acc:
		var p: PackedStringArray = key.split(":")
		out.append({"type": p[0], "level": int(p[1]), "count": acc[key]})
	out.sort_custom(func(a, b): return a.level < b.level)
	return out


func total_enemies() -> int:
	var n := 0
	for e in enemy_summary():
		n += int(e.count)
	return n


func hotspot_count(h: Dictionary) -> int:
	var n := 0
	for g in h.groups:
		n += int(g.count)
	return n


## Orders this wave: the level's own number, else one from wave 04 on when a turret can take one.
func order_budget() -> int:
	if orders >= 0:
		return orders
	if int(id) < 4:
		return 0
	for g in guns:
		if Defs.order_for(g.type) != "":
			return 1
	return 0
