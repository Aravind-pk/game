class_name Defs
extends RefCounted
## Static game data: gun and monster stats. `name` is the on-screen (concept sheet) name;
## the dictionary keys are the spec names used in level data. All distances in metres, times in seconds.
## Balance numbers are first-pass values meant to be tuned through playtesting.

const SIM_DT := 1.0 / 30.0          # fixed simulation step
const CELL := 2.0                   # placement grid cell size (m)
const EMERGE_WARN := 1.6            # ground shakes / cracks before a monster breaks out
const EMERGE_TIME := 0.9            # monster climbing out (not targetable yet)
const RETARGET_INTERVAL := 0.25     # how often monsters look for guns
const MAX_BATTLE_TIME := 600.0

# ---------------------------------------------------------------- orders
# One order, from a small per-wave budget: a Cannon set to Heavy only saves its shells for brutes
# and fires at nothing else. MG Turrets, Snipers and decoys take no orders.
const ORDERS := {
	"heavy": {"label": "Heavy only", "target": "brute", "gun": "cannon"},
}


## The order a turret type can take, or "".
static func order_for(gun_type: String) -> String:
	for k in ORDERS:
		if ORDERS[k].gun == gun_type:
			return k
	return ""

# ---------------------------------------------------------------- guns
# min_range: targets closer than this can't be hit. Damage fades linearly from full at
# falloff_start to damage * falloff_floor at max range.
const GUNS := {
	"mg": {
		"name": "Kestrel", "model": "kestrel", "desc": "High Fire Rate",
		"hp": 120.0, "damage": 7.0, "fire_rate": 6.0, "range": 9.0,
		"splash": 0.0, "projectile_speed": 0.0, "radius": 0.8,
		"min_range": 0.0, "falloff_start": 4.0, "falloff_floor": 0.5, "blast": 0.0, "blast_radius": 0.0,
	},
	"cannon": {
		"name": "Mule", "model": "mule", "desc": "AoE Damage",
		"hp": 200.0, "damage": 110.0, "fire_rate": 0.35, "range": 12.0,
		"splash": 2.6, "projectile_speed": 16.0, "radius": 1.0,
		"min_range": 4.0, "falloff_start": 11.0, "falloff_floor": 1.0, "blast": 0.0, "blast_radius": 0.0,
	},
	"sniper": {
		"name": "Needle", "model": "needle", "desc": "Long Range",
		"hp": 90.0, "damage": 75.0, "fire_rate": 0.45, "range": 20.0,
		"splash": 0.0, "projectile_speed": 0.0, "radius": 0.7,
		"min_range": 3.0, "falloff_start": 20.0, "falloff_floor": 1.0, "blast": 0.0, "blast_radius": 0.0,
	},
	# No ammo, so they never fire: monsters stop to attack them, buying the other turrets time.
	"decoy": {
		"name": "Decoy", "model": "kestrel", "desc": "Draws Attacks",
		"hp": 220.0, "damage": 0.0, "fire_rate": 1.0, "range": 6.0,
		"splash": 0.0, "projectile_speed": 0.0, "radius": 0.9,
		"min_range": 0.0, "falloff_start": 6.0, "falloff_floor": 1.0, "blast": 0.0, "blast_radius": 0.0,
	},
	"rigged": {
		"name": "Rigged Decoy", "model": "kestrel", "desc": "Explodes When Destroyed",
		"hp": 90.0, "damage": 0.0, "fire_rate": 1.0, "range": 6.0,
		"splash": 0.0, "projectile_speed": 0.0, "radius": 0.9,
		"min_range": 0.0, "falloff_start": 6.0, "falloff_floor": 1.0, "blast": 110.0, "blast_radius": 4.5,
	},
}

# ---------------------------------------------------------------- monsters
const MONSTERS := {
	"burrower": {
		"name": "Shale Digger", "model": "shale_digger", "base_level": 1, "desc": "Swarm", "armor": 0.0,
		"hp": 32.0, "speed": 2.3, "damage": 7.0, "attack_rate": 1.0,
		"detect": 6.0, "attack_range": 1.0, "radius": 0.55,
	},
	"stalker": {
		"name": "Rift Runner", "model": "rift_runner", "base_level": 2, "desc": "Fast", "armor": 0.0,
		"hp": 48.0, "speed": 4.4, "damage": 9.0, "attack_rate": 1.2,
		"detect": 7.0, "attack_range": 1.0, "radius": 0.55,
	},
	"brute": {
		"name": "Faultbreaker", "model": "faultbreaker", "base_level": 3, "desc": "Tank", "armor": 8.0,
		"hp": 300.0, "speed": 1.25, "damage": 18.0, "attack_rate": 0.5,
		"detect": 5.0, "attack_range": 1.6, "radius": 1.15,
	},
}


## Armour takes a flat amount off every hit, but at least a tenth of the hit always gets through.
static func hit_after_armor(raw: float, armor: float) -> float:
	return maxf(raw - armor, raw * 0.1)


## A shell's blast is full strength at the impact and half at the edge of its splash.
static func splash_factor(d: float, splash: float) -> float:
	return 1.0 - 0.5 * clampf(d / maxf(splash, 0.001), 0.0, 1.0)


static func gun_stats(type: String, level: int) -> Dictionary:
	var s: Dictionary = GUNS[type].duplicate()
	var k := 1.0 + 0.25 * float(level - 1)
	s.hp *= k
	s.damage *= k
	return s


static func monster_stats(type: String, level: int) -> Dictionary:
	var s: Dictionary = MONSTERS[type].duplicate()
	var k := 1.0 + 0.3 * float(level - int(s.base_level))
	s.hp *= k
	s.damage *= k
	return s
