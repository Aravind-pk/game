class_name SpriteKits
extends RefCounted
## Loaded sprite kits, shared by every unit that uses them.
## Keep this cache here: holding it in static variables on the unit scripts crashed Godot 4.5.1 on exit.

static var _cache := {}


## Returns {"texture", "anims"} for res://assets/sprites/<folder>/<kit_name>.png and .json.
static func get_kit(folder: String, kit_name: String) -> Dictionary:
	var base := "res://assets/sprites/%s/%s" % [folder, kit_name]
	if not _cache.has(base):
		var file := FileAccess.open(base + ".json", FileAccess.READ)
		_cache[base] = {"texture": load(base + ".png"), "anims": (JSON.parse_string(file.get_as_text()) as Dictionary).anims}
	return _cache[base]
