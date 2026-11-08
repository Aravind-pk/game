# North Gate

Tactical defense / strategy-puzzle game for Android & iOS (portrait), built in **Godot 4**.
Players study an incoming wave of underground monsters, deploy a fixed set of unmanned turrets
anywhere on the battlefield, then watch a deterministic, fully automatic battle play out.

> Plan → Deploy → Simulate → Win or Lose

## Running

Open `godot/` in **Godot 4.5** and press Play (main scene: `scenes/main.tscn`).
The game is portrait 1080×1920 and uses the Compatibility renderer.

**Flow:** Briefing (enemy list, gate HP, spawn radar) → Plan & Deploy (pick a turret card, tap the
field; tap a placed turret to pick it up, drag to move) → **DEFEND** (fully automatic, 1×/2× speed)
→ Result. **Retry** keeps your deployment so you can adjust it.

## Graphics

The game is entirely 2D. `scripts/game/battlefield.gd` draws a painted field, sprites sorted by
ground position, and effects. It reads the simulation and never changes it.

- **Monsters with a sprite kit** (`monster_sprite.gd`): 16 facings, a 26-pose turntable for large
  turns, emerge, attack and death. The simulation's sharp grid paths are rounded into curves in the
  view only.
- **Turrets with a sprite kit** (`turret_sprite.gd`): 14 aim directions, firing, recoil, destruction.
- **Units without a kit** (`stand_in_unit.gd`) use a single piece of artwork until they get one.
  Currently: Mule, Needle, Rift Runner and Faultbreaker.

### Adding art

Run these from the repo root. Each needs Python with Pillow and NumPy.

| Art | Source | Command |
|---|---|---|
| Monster kit | `art/sprites/<kit>/` six 256px sheets | `python tools/sprites/extract_kit.py <kit>` |
| Turret kit | `art/sprites/<kit>/sheet.png` | `PYTHONPATH=tools/sprites python tools/sprites/extract_turret.py <kit>` |
| Obstacles and craters | `art/sprites/props/` | `python tools/sprites/extract_props.py` |
| Battlefield | `art/backgrounds/north_gate_field.webp` | `python tools/sprites/fit_background.py` |
| Card portraits | the atlases above | `python tools/sprites/make_portraits.py` |

Generated sheets often mislabel their rows, so check `art/previews/<kit>_contact.png` after
extracting. To use a new kit in the game, add it to `MONSTER_KITS` or `TURRET_KITS` in
`battlefield.gd`.

## Simulation

- Deterministic fixed-step simulation (`scripts/sim/battle_sim.gd`), fully separate from visuals.
  The same deployment always gives the same battle; a test checks this exactly.
- Free placement on a grid anywhere in the visible field, with a range ring and valid/invalid cell
  colours. Ruins, the wall and spawn fissures can't be built on.
- Underground spawning: the fissure glows and the ground throws up dust, then the monster
  climbs out. Hotspots off-screen are simulated like any other.
- Monsters follow a flow field to the gate with no predefined roads. They go for turrets
  within their detection radius, destroy them, then carry on to the gate and attack it.
- Turrets target the closest monster automatically and have limited ammo. Cannon shells fly and
  splash, sniper beams have long range. Destroyed turrets become wrecks that no longer block movement.
- Spawn radar (full map, hotspots + counts), briefing panel, victory/defeat, retry, next level,
  saved progress.
- 50 levels in `godot/levels/*.json` in five chapters, each made and tuned by the level forge
  (see below). All of it is data-driven.
- Three-stage hints: two written clues worked out from a winning plan, then the area where the next
  turret works, then the exact tile.

### Mechanics

Every level gives a fixed roster, and **every turret has to pull its weight**: the forge only accepts
plans where each live turret deals at least 10% of the damage, so there is no "spare" turret to park.

| Chapter | Levels | New idea |
|---|---|---|
| 1 | 1–10 | MG Turrets, Cannons (splash, minimum range) and Snipers (long range) against swarms, runners and brutes, on one to three fronts. |
| 2 | 11–20 | **Decoys**: no ammo and never fire, but monsters stop to attack them. Each decoy in a solution is needed: take it away and the plan loses. Dark steel finish, amber ring and tray card. |
| 3 | 21–30 | **Unstable ground**: cracked red tiles with a hazard border. Monsters cross them, turrets can't be built on them, so the easy spots are gone. |
| 4 | 31–40 | **Rigged Decoys**: weaker decoys that explode when destroyed, damaging every monster within 4.5 tiles. Red ring and tray card. |
| 5 | 41–50 | **Holdouts**: turrets already dug in behind sandbags, with their own small ammo supply. They can't be moved or cleared; the plan is built around them. |

## Web build

```bash
godot --headless --path godot --export-release "Web" ../build/web/index.html   # needs 4.5.1 export templates
python tools/web/package_web.py build/web build/web_split                       # 9 MB chunks + loader shim
```

The Web preset (`godot/export_presets.cfg`) is single-threaded and uses the Compatibility renderer
(the only one Godot supports on the web).
`package_web.py` splits the engine (`.wasm`) and data pack (`.pck`) into chunks for hosts with
a per-file size limit and adds a small fetch shim that reassembles them. It writes both a standalone
`index.html` and `artifact.html`, a fragment for hosts that supply their own page skeleton.

### Tests & balance

```bash
godot --headless --path godot --import                                               # once, registers classes
godot --headless --path godot --script res://tests/sim_check.gd -- level=07 trials=3
godot --headless --path godot --script res://tests/monster_sprite_check.gd
```

`sim_check.gd` replays every stored solution and every hint-zone tile in the real simulation and
checks that each must win, that no defence loses, that identical runs match bit-for-bit, and that
every decoy in a solution is needed. Leave out `level=` to check them all.

Screenshots (`level=` is the position in the level list, phases: briefing,
deploy, radar, combat, result; `hint=N` presses Hint N times, `hold` picks up the first card):
`godot --path godot --resolution 540x960 -- level=05 phase=combat shot=out.png shot_time=20`

## Level forge (`tools/level_engine`)

A Node port of the battle simulation that makes and tunes levels. It needs Node 22+ and nothing else.

```bash
node tools/level_engine/forge.mjs 03 04            # re-tune hand-written specs (specs/level_NN.json)
node tools/level_engine/forge.mjs --campaign       # generate missing levels 6-50 (existing files are skipped)
node tools/level_engine/forge.mjs --campaign 12    # one level; delete its file first to remake it
node tools/level_engine/baseline.mjs 2000          # random-deployment win rate of every level
node tools/level_engine/parity_cases.mjs cases.json 8
godot --headless --path godot --script res://tests/port_parity.gd -- cases=$PWD/cases.json
```

For each level the forge searches for the most efficient winning deployment, cuts ammo and gate HP
down to what it needs plus a little slack, then raises enemy pressure until the share of random
deployments that win is close to the level's target. A level is accepted when that share is within
2x of the target either way; if none of five layouts gets there, the closest is kept. It writes up
to three distinct solutions, the hint zone around each turret and the written clues into the level
file. `campaign.mjs` defines the chapters, their difficulty targets and the layout generator.
`FORGE_WORKERS` sets the worker count (default: cores - 1) and `FORGE_VARIANT_OFFSET` tries fresh
layouts when remaking a level. A level takes 2-10 minutes on four cores.

**Keep `sim.mjs` in step with the game.** Whenever `scripts/sim/battle_sim.gd`, `defs.gd` or
`level_data.gd` changes, make the same change in `sim.mjs` and run the parity check above: it replays
battles from the Node port in Godot and must report every battle identical.

### Difficulty curve

The share of uniformly random deployments that win (12,000 samples per level; the hand-made
levels 1-5 use 40,000). A thoughtful player does far better than random, so this is a guide for
ordering levels, not a measure of how hard they feel; it still needs playtesting.

<!-- curve:start -->
| Level | Name | Chapter | Random win | Target |
|---:|---|---|---:|---:|
| 1 | First Contact | Basics | 27.02% | 26% |
| 2 | Two Fronts | Basics | 12.73% | 12% |
| 3 | Fast Movers | Basics | 3.3% | 2% |
| 4 | Heavy Footsteps | Basics | 0.74% | 1% |
| 5 | The Eastern Breach | Basics | 0.63% | 0.5% |
| 6 | Dust Line | Basics | 9.76% | 6% |
| 7 | The Long Ditch | Basics | 3.34% | 4.01% |
| 8 | Night Shift | Basics | 1.92% | 2.68% |
| 9 | Broken Causeway | Basics | 1.13% | 1.79% |
| 10 | Last Light | Basics | 1.92% | 1.2% |
| 11 | False Colours | Decoys | 8.82% | 12% |
| 12 | Bait and Hold | Decoys | 6.77% | 9.1% |
| 13 | The Scarecrow Line | Decoys | 8.45% | 6.91% |
| 14 | Empty Barrels | Decoys | 9.37% | 5.24% |
| 15 | Drawn Fire | Decoys | 5.54% | 3.98% |
| 16 | Sacrifice Play | Decoys | 2.14% | 3.02% |
| 17 | Hollow Guard | Decoys | 3.02% | 2.29% |
| 18 | The Lure | Decoys | 0.92% | 1.74% |
| 19 | Dead Reckoning | Decoys | 0.95% | 1.32% |
| 20 | Red Herring | Decoys | 1.58% | 1% |
| 21 | Soft Ground | Unstable ground | 16.83% | 9% |
| 22 | Sinkhole Row | Unstable ground | 6.87% | 6.66% |
| 23 | The Crumbling Mile | Unstable ground | 2.74% | 4.93% |
| 24 | Fault Lines | Unstable ground | 7.44% | 3.65% |
| 25 | Shifting Sands | Unstable ground | 1.83% | 2.7% |
| 26 | No Footing | Unstable ground | 0.82% | 2% |
| 27 | Undermined | Unstable ground | 1.5% | 1.48% |
| 28 | Collapse Point | Unstable ground | 0.64% | 1.1% |
| 29 | Thin Crust | Unstable ground | 1.36% | 0.81% |
| 30 | The Pit Road | Unstable ground | 0.93% | 0.6% |
| 31 | Short Fuse | Rigged decoys | 14.76% | 8% |
| 32 | Powder Keg | Rigged decoys | 8.38% | 5.88% |
| 33 | Tripwire | Rigged decoys | 5.05% | 4.32% |
| 34 | Blast Radius | Rigged decoys | 5.08% | 3.17% |
| 35 | Chain Reaction | Rigged decoys | 2.8% | 2.33% |
| 36 | Killing Ground | Rigged decoys | 1.52% | 1.71% |
| 37 | Deadfall | Rigged decoys | 0.6% | 1.26% |
| 38 | Slow Burn | Rigged decoys | 0.99% | 0.93% |
| 39 | Detonation Alley | Rigged decoys | 0.69% | 0.68% |
| 40 | The Big Bang | Rigged decoys | 0.51% | 0.5% |
| 41 | Dug In | Holdouts | 6.92% | 5% |
| 42 | Old Guard | Holdouts | 6.63% | 3.66% |
| 43 | Stand Fast | Holdouts | 1.9% | 2.68% |
| 44 | The Forgotten Post | Holdouts | 3.93% | 1.96% |
| 45 | Iron Will | Holdouts | 2.55% | 1.43% |
| 46 | Holdout Ridge | Holdouts | 1.88% | 1.05% |
| 47 | No Retreat | Holdouts | 0.61% | 0.77% |
| 48 | Siege of Embers | Holdouts | 1.03% | 0.56% |
| 49 | The Final Watch | Holdouts | 0.48% | 0.41% |
| 50 | North Gate Stands | Holdouts | 0.18% | 0.3% |
<!-- curve:end -->

## Repository layout

```
godot/
  levels/            Level data (JSON)
  scripts/sim/       Stats, level loading and the deterministic battle core
  scripts/game/      main.gd (flow + UI), battlefield.gd (2D view), unit views, radar
  tests/             Determinism, balance and sprite checks
  assets/            Background, sprite atlases, props, UI
art/
  backgrounds/       Source battlefield painting
  sprites/           Source sprite sheets and props
  concepts/          Concept sheets
  blender/           Procedural model scripts (source of truth): units (build_all.py), props (build_props.py)
  previews/          Renders, colour-study sheets, TripoSR comparison
tools/level_engine/  Level forge: Node port of the simulation, level generator, specs
tools/triposr/       CPU TripoSR runner used for the comparison
```
