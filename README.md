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
  The same deployment always gives the same battle.
- Monsters follow a flow field to the gate, attack turrets within their detection radius, then
  carry on to the gate. Turrets have limited ammo.
- Levels are data in `godot/levels/*.json`. `tools/level_engine/` generates and checks the campaign.

## Tests

```bash
godot --headless --path godot --import          # once, registers classes
godot --headless --path godot --script res://tests/sim_check.gd -- trials=40 search=150
godot --headless --path godot --script res://tests/monster_sprite_check.gd
```

Screenshots: `godot --path godot -- level=05 phase=combat shot=out.png shot_time=20`
(phases: briefing, deploy, radar, combat, result, pause).

## Web build

```bash
godot --headless --path godot --export-release "Web" ../build/web/index.html   # needs 4.5.1 export templates
python tools/web/package_web.py build/web build/web_split                       # 9 MB chunks + loader shim
```

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
tools/
  sprites/           Art pipeline
  level_engine/      Campaign generation
  web/               Web packaging
```
