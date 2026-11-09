# North Gate: handoff plan

Written 2026-11-10 for a model picking this work up with no prior context. Read it top to bottom
once; each workstream is then self-contained.

## 1. Where things stand

- **Repo:** `Aravind-pk/game`, cloned at `/home/aravind/code/northgate`. The game is not on `main`.
  Work from branch `ccr-fb8db459-dfc415`.
- **Committed on that branch (2026-11-10):** four bug fixes (star tiles lit per condition, campaign
  ends at level 50, level grid locks waves past the first uncleared one, stale README paths removed)
  and animated sprite kits for the Mule, Needle, Faultbreaker and Rift Runner, merged from
  `sprites/pending-kits`. Every unit now has a kit. Tests pass. Nothing is pushed.
- **Sprite work in progress:** Codex is working in the worktree `.worktrees/sprites` (branch
  `sprites/pending-kits`) on two things: a new destruction sequence for the Kestrel MG turret (its
  atlas still shows the old orange design when it dies) and a dedicated gate breach animation with
  monotonic damage stages. Its report is `docs/sprite-kits-report.md` on that branch. Treat the
  report as a claim: check in the game before merging (section 5, W0). Review pages and recordings
  are git-ignored and exist only in that worktree.
- **Known art compromises in the merged kits:** monsters turn by stepping between eight held views;
  the Faultbreaker has a low swipe instead of an overhead slam and its death was never seen in a
  recorded battle; the Rift Runner is only 24-35 px wide head-on.
- **Tools on this machine:** `godot` 4.5.1 (`~/.local/bin/godot`), Node 24, Python with Pillow and
  NumPy at `~/.local/opt/northgate-venv/bin/python`. No ffmpeg.
- **Running the game from the command line** writes the real save file
  (`~/.local/share/godot/app_userdata/North Gate/progress.json`). Delete it after automated runs.

Read `README.md` first. It documents the flow, the simulation, the level forge and every test command.

## 2. Rules that must not be broken

1. **The simulation exists twice.** `godot/scripts/sim/battle_sim.gd` + `defs.gd` + `level_data.gd`
   and the Node port `tools/level_engine/sim.mjs`. Any change to one must be made in the other, then
   `parity_cases.mjs` + `tests/port_parity.gd` must report every battle identical (commands in the README).
2. **Any change to combat numbers or sim behaviour invalidates all 50 levels.** They are tuned by the
   forge to exact ammo. Re-tuning takes 2-10 minutes per level on four cores. Prefer view-only changes.
   Workstreams below are marked **[view]**, **[data]** (level files or forge only) or **[sim]**.
3. **The view never changes the simulation.** `battlefield.gd` reads `sim` and drains `sim.events`.
4. After any change run:
   `godot --headless --path godot --script res://tests/placement_check.gd`,
   `res://tests/monster_sprite_check.gd`, and for sim or level changes `res://tests/sim_check.gd`.
5. Do not commit `build/` output or anything under `.scratch/` or `.worktrees/`.

## 3. What the evidence says

Measured on 2026-11-10 by replaying each level's first stored solution in the Node sim. The scripts
are in `.scratch/analysis/` (`probe.mjs`, `orders.mjs`, `three_star.mjs`, `stats.mjs`; `sim_probe.mjs`
is `sim.mjs` with counters and two switches added). Run them as `node .scratch/analysis/probe.mjs $PWD`.

| Question | Result | What it means |
|---|---|---|
| Do solutions still win if monsters ignore turrets (no luring)? | 8 of 50 | **Luring is the game.** Monsters stopping to attack a turret is what gives the others time to shoot. |
| Do solutions still win if turrets do not block tiles (no route bending)? | 46 of 50 | Route bending almost never matters, yet it is the first thing the tutorial teaches. |
| Does any stored solution use the Cannon's "Heavy only" order? | 0 of 50 | The forge never searches orders. The order rescues 6% of losing random layouts (564 of 9,580), so it is a real but minor tool. |
| If one turret is moved one tile, does the solution still win? | 82% of nudges on average | Placement is forgiving. Exceptions: level 05 (36%) and level 30 (45%). |
| How do Cannon shells perform? | 174 shells, 2 hit nothing, 50 killed two or more, 1.06 kills per shell | Shells rarely miss, but the "splash" turret mostly kills one thing. Best single shell: 10 kills (level 02). |
| How much Sniper damage is overkill? | 30% (MG: 7%) | The Sniper shoots the closest target, often a 32 HP burrower with a 75 damage round. It appears in only 9 of 50 levels. |
| Are 3 stars reachable everywhere? | Yes, on all 50 | No fix needed. |
| How long is a battle, and when is the first shot? | 15-85 s; first shot 2.5-11 s in | Up to 11 s of walking before anything happens at 1x. |
| How long does a full battle take to simulate in GDScript? | 270-430 ms on this desktop | Fast enough to re-run a battle in the background after an edit. Expect several times slower on a phone. |
| How varied are the levels? | One grid size (20x34), one painted field, 5 obstacle layouts, 3 monsters, 1-3 spawn points | 50 levels look like one place. Level names such as "Night Shift" are not reflected on screen. |
| Is there any audio? | No audio files, no audio calls | |
| How much reading before the first touch? | Briefing sheet, Recon sheet, then a text card on the field | Three taps and three blocks of text before level 1 lets the player place anything. |

Two earlier claims are withdrawn: the Cannon "cannot hit runners" (true in theory, 2 of 174 shells in
practice) and "3 stars unreachable on 8 levels" (all reachable).

## 4. The design direction

**The aha moment is: "My turrets are bait. The fight happens where I put them."**

The player's first instinct is that turrets are guns and position is about range. The evidence shows
the winning idea is formation: which turret gets attacked first, whether it can survive that, and
whether the others can shoot while it does. Decoys (chapter 2) are this idea made explicit, but it
already decides levels from level 02 on and nothing in the game shows it. The route preview ignores
it, the tutorial teaches route bending instead, and a clever formation looks the same as a lucky one.

Everything in section 5 serves one of three things:

- **Show it:** the deploy screen tells the truth about who gets attacked (W2, W3).
- **Let the player find it:** an early level where the obvious layout fails and the formation wins (W4).
- **Reward it and make retrying instant:** payoff effects, sound, and a retry that jumps to the moment that changed (W1, W5, W6).

Rejected, so nobody re-proposes them:

- **Tap abilities during combat.** Timed input breaks the determinism the forge, hints and tests rely on.
- **A win/lose forecast while placing.** It turns the puzzle into dragging until the light goes green.
- **Stat upgrades bought with stars.** Levels are tuned to exact ammo.
- **Making the Cannon lead its target.** [sim] cost for a 1% effect.

## 5. Workstreams, in order

Each has a goal, where to work, what done looks like, and how to check it.

### W0. Land what exists

- Done: fixes committed, four sprite kits merged.
- Remaining: review Codex's Kestrel destruction and gate breach in the game before merging them.
  Record a lost battle (`level=05 phase=combat` loses at about 0:34 with the automatic layout; the
  recorder is `tools/sprites/record_combat.gd`), step through the frames, and merge only what keeps
  registration: the pedestal must not move when an MG turret dies, the gate must never look less
  damaged than a moment before, and the gate HP plate must stay put.
- Regenerate card portraits (`tools/sprites/make_portraits.py`) if a kit's look changed.
- Push the branch when the owner asks; nothing has been pushed.

### W1. Sound and haptics **[view]**

- **Goal:** every event the player causes or fears makes a sound.
- **Where:** `Battlefield.handle_events` (`godot/scripts/game/battlefield.gd:852`) already receives
  `hotspot_warning`, `emerge`, `fire`, `explode`, `monster_died`, `gun_destroyed`, `monster_attack`,
  `gate_hit`; `main.gd` handles victory, defeat, placement, invalid tile and button taps. Add one
  small audio manager with a pool of `AudioStreamPlayer`s, per-sound rate limiting (an MG fires 6
  times a second) and pitch variation. `Input.vibrate_handheld` on gate hits, turret loss and breach.
- **Assets:** none exist. Use CC0 packs (for example Kenney) or generated sounds, and record the
  licence of each file in `godot/assets/audio/CREDITS.md`. **Ask the owner before downloading.**
- **Also:** a mute toggle in the pause dialog, saved in `progress.json`.
- **Done when:** a level played with eyes closed tells you when shooting starts, when a turret dies,
  when the gate is hit and how the battle ended; 4x speed does not turn into noise.

### W2. Truthful deploy preview: "first contact" **[view]**

- **Goal:** while deploying, the field shows which turret each group will attack first.
- **Why:** `show_routes` (`battlefield.gd:491`) draws `BattleSim.route_from`, the path through the
  flow field only. A monster that comes within its detect radius of a turret leaves that path, so the
  drawn route runs straight past turrets the monsters will in fact stop at.
- **How:** `show_routes` already builds a throwaway `BattleSim` for the current layout. Step that
  probe until the first monster from each hotspot either acquires a target or reaches the gate (cap
  the simulated time, about 30 s), recording that monster's positions. Draw that recorded path
  instead of `route_from`: it ends at the turret it attacks. Put a small "attacked first" bracket on
  that turret. Do this only when the layout changes, not per frame; if it costs more than a frame on
  a phone, run it in a `Thread` and draw when ready.
- **Limit:** show first contact only. No kill counts, no outcome.
- **Done when:** on level 02, dragging an MG toward a route makes the dashed line snap to it and the
  bracket appear; `placement_check.gd` still passes; the preview matches what the battle then does.

### W3. Teach the real mechanic **[view]**

- **Where:** `TUTORIALS` in `main.gd:198`, the idle hint strings in `_refresh`, `MONSTER_UI` descriptions.
- **Change:** wave 01's three cards become one idea each, shown as the player does the thing, not
  before: (1) "Monsters attack the first turret they notice." (2) "While they chew on it, your other
  turrets shoot. Put the tough one in front." (3) range ring. Drop "Turrets bend them" from the first
  card; mention it where it matters (chapter 3, unstable ground).
- **Onboarding flow:** on waves 01-03 open directly on the field with the first turret already in
  hand; Briefing and Recon stay reachable from the tray's radar button. From wave 04 on, merge
  Briefing and Recon into one sheet with one button. Today it is two sheets every wave
  (`_show_briefing`, `_show_recon`).
- **Done when:** from launch, the first turret is placed with at most one tap and no sheet in between.

### W4. The discovery level **[data]**

- **Goal:** by the end of wave 02 the player has found the formation idea themselves.
- **Where:** hand-written specs `tools/level_engine/specs/level_01.json` to `level_05.json`, tuned
  with `node tools/level_engine/forge.mjs 02 03 04 05`. Keep 50 levels: re-sequence 02-05, do not
  insert (progress is saved by level index).
- **New opening sequence:**
  - 01: one front, cannot really be lost (already true: 51% of random layouts win).
  - 02 "the shield": one tough turret (MG) and one fragile strong one (Sniper), one front. Layouts
    with the Sniper in front or both turrets side by side at the gate must lose; MG forward with the
    Sniper behind it must win with room to spare.
  - 03 "the clump": MG as bait with a Cannon behind it, so one shell lands on the pile. Target: the
    solution's best shell kills 6 or more (measure with `probe.mjs`, column `bestShell`).
  - 04: two fronts. 05: brutes and the Heavy-only order.
- **Write the acceptance as a script**, next to `baseline.mjs`: for 02, enumerate every layout, and
  assert that the "obvious" families lose and the formation family wins. Random-win targets for 02-05
  should fall no lower than about 3% (today 04 and 05 sit at 0.74% and 0.63%, as hard as levels
  37-40), and the one-tile nudge survival of each solution should be above 60% (level 05 is 36%).
- **Done when:** forge output accepted, `sim_check.gd` passes for 01-05, README difficulty table updated.

### W5. Payoff and pacing **[view]**

- **Multi-kill callout:** count `monster_died` events that share a step with an `explode`; at 3 or
  more show "x5" at the blast with a short hit-stop. Rigged decoys count too.
- **Director speed:** when no turret has a target and no monster is attacking, run at 3x; drop to the
  chosen speed at first contact. Removes the 2.5-11 s of walking before the first shot.
- **Last stand:** when the gate is under 25% and holds, or the last monster dies, 0.5 s of slow motion.
- **Turret under attack reads as a tank:** a shield flash on the attacked turret and its HP bar always
  visible while it is being hit, so the "bait" role is legible.
- **Where:** `battlefield.gd` (`handle_events`, `sync`), speed handling in `main.gd` `_process`
  and `_set_speed`. Slow motion and director speed scale the view's time accumulation, never the
  sim step.
- **Done when:** recorded footage of level 02 shows the callout and no stretch longer than 3 s at
  real time with nothing happening.

### W6. Retry that skips to the change **[view]**

- **Goal:** after a loss, moving one turret and pressing Defend shows the consequence within seconds
  instead of replaying a minute.
- **How:** while a battle runs, store `sim.fingerprint()` once per simulated second. On Defend after a
  retry, first run the new layout in a background sim, comparing fingerprints with the stored run, to
  find the first second at which they differ. Start playback about 2 s before that point: step the
  visible sim there without playing effects (the same loop as `skip_battle` in `main.gd:369`, but
  stopping at a time), then resume normally. Show one line: "Same as last time until 0:19".
  If the two runs never differ, say "Nothing changed" and play from the start.
- **Needs:** `Battlefield` to pick up a sim that is already mid-battle. `begin_battle`
  (`battlefield.gd:799`) assumes time zero; unit views for monsters already alive or dead must be
  created from sim state. Check this path first: it is the only risk in this workstream.
- **Later, same foundation:** a scrub bar on the defeat report that replays any moment of the lost battle.
- **Done when:** on level 05, lose, move one turret, press Defend, and playback starts at the
  divergence; a second identical Defend reports no change; the sim and its tests are untouched.

### W7. Stars that mean something **[view] + [data]**

- Third star becomes **"beat the engineer"**: ammo left at or above the forge's best stored solution
  for that level (`solutions[].ammo_left` is already in every level file), shown as "Par 24 rounds
  left, you 31". Keep it achievable: use 80% of the forge's best as the bar.
- **Hints cost:** written clues stay free; asking for the exact tile caps that attempt at 2 stars.
  `_hints_used` in `main.gd` is already counted and never read.
- **Investigate before building:** whether levels can be won with one turret left in the tray. Search
  with the Node sim (drop each roster turret, random-search the rest). If it works on at least a third
  of levels, add it as a per-level badge, not a star.

### W8. Make 50 levels look like more than one place **[view]**, then **[sim]**

- **Cheap:** a colour grade and time of day per chapter and per named level (`CanvasModulate`, a
  vignette, muzzle-flash light at night). "Night Shift" should be at night. One background painting
  serves all 50 levels today.
- **Expensive, later:** one new monster per chapter. Each is a [sim] change (both sims, parity,
  re-tune of that chapter) plus a sprite kit. Do not start before W1-W6 are in and played.

### W10. Combat visuals: smoothness and readability **[view]**

From a frame-by-frame review of levels 3 and 5 recorded at 30 fps (2026-11-10) and
`.scratch/analysis/atlas_metrics.py`. The strips looked at are in `.scratch/review/keep/`.
All of this is view code; none of it touches the simulation. In rough order of value:

1. **Effects land where the sprite is not.** `MonsterSprite` trails the simulation by `FOLLOW_TIME`
   (0.28 s): about 0.6 m for a burrower, 1.2 m for a runner. Tracers and hit sparks are drawn at the
   simulated position (`_fx_fire` uses `e.to`), so shots visibly land beside runners. Aim effects at
   the monster's view position when the event names a monster, and make the trail a distance
   (about 0.4 m) rather than a time.
2. **Crowds are one grey blob.** Sprites are about 2.2x wider than the collision circle (burrower art
   2.4 m against 1.1 m), and every monster of a type shows the same walk frame at the same moment
   (`_walk_frame` starts at 0). Give each monster a phase offset from its id, 5% scale and
   brightness variation, a view-only personal-space nudge, and try the art at 85% size.
3. **One stride length for every monster.** `STRIDE_M = 1.25` makes the runner cycle 3.5 times a second
   (28 animation frames a second, which strobes) and the Faultbreaker shuffle. Put `stride_m` in
   each kit's JSON; start with runner 2.6, Faultbreaker 2.0.
4. **The Burrower floats.** Its anchor is at its lowest claw, so the shadow, centred on the anchor,
   sits half below the feet. The new kits anchor at the body centre and look grounded. Add a
   per-kit shadow offset or re-anchor the Burrower.
5. **Gunfire is nearly invisible.** MG tracers are 2.5 px wide and live 0.06 s; the muzzle flash is a
   small dot. Make the tracer a moving streak, enlarge the flash, add ground dust at the impact and a
   60 ms white flash on the monster hit (today monsters flash only when they die).
6. **Turrets fire before they face the target.** The view pans at one turn a second while the
   simulation fires at once, so tracers leave at an angle to the barrel. Snap to the target pose in
   `fired()`.
7. **Explosions and destruction are soft dots.** Shell blasts, turret deaths and emergence are two or
   three blurred circles and square chips. Draw a proper explosion strip, a shock ring, flying
   debris, a shell shadow and trail, and leave scorch marks, craters and corpses on the ground for
   the rest of the battle. A destroyed turret also swaps to a different facing on its first
   destruction frame.
8. **The ammo chip is bigger than the turret.** "83" and "EMPTY" plates float over the kill zone and
   hide it. Replace with a thin arc or pips at the base; show a number only when it is low.
9. **Health bars cross the turret's face** (`TURRET_BAR_HEIGHT_M` is one constant; the Mule is
   taller). Take bar height from each kit.
10. **Attackers hide behind the turret they attack**, since they arrive from the north and sort
    behind it. Shake and flash the turret itself on each hit, and drop the full-screen tremor on
    turret hits (it fires on every bite and never rests while a turret is under attack).
11. **Turns pop and views differ in size.** The new monster kits turn through 8 held views; the
    runner snaps from a low, long side view to a taller front view that reads as a bigger animal.
    Needs in-between art and one body scale across views, or a quick squash across the swap.
12. **A north-aiming Mule shows no barrel**, and north is the rest direction. Rest it at an angle, or
    redraw the rear views with the barrel raised.
13. **Emergence happens off screen** on most levels, with up to 11 s of empty field first. Show an
    edge marker for off-screen fissures, and see W5 (director speed).
14. **Monsters walk over scattered rocks** and over turret wrecks. Keep scatter flat, and keep wrecks
    low enough to step over or fade them.
15. **Low contrast.** Monsters, especially runners, are grey-brown on brown. Add a rim light or a
    one-pixel dark outline, and let the Burrower's orange seams show at game size.
16. **No mipmaps.** Atlases are drawn at 0.33-0.84x with plain bilinear filtering, which shimmers in
    motion on the 540 px web build. Turn mipmaps on in the atlas import settings.

Done when: a 30 fps recording of level 5 shows shots ending on the monsters, no two neighbouring
monsters in the same pose, and the area around a turret under attack stays readable.

### W9. Smaller items

- Sniper targeting: prefer a target the shot will not overkill by more than half. [sim], affects 9
  levels. Low priority.
- Home screen with a chapter map and star totals; the game boots into a briefing.
- Daily challenge: pre-generate puzzles with the forge and ship them in the build; share the result as
  text. Only after the core loop above is fun.
- Housekeeping: move the game to its own repo or to `main`, add CI running the three Godot tests and
  the parity check, remove `build/web_split` from git.

## 6. Order and dependencies

1. W0 (land fixes and sprites)
2. W2 + W3 (show and teach the mechanic) - independent of each other
3. W4 (discovery level) - needs W3's wording to match
4. W1 and W5 (sound, payoff) - independent, can run in parallel with 2-3
5. W6 (skip to the change)
6. W10 items 1-6 (small, high value), then W7, the W8 cheap part, the rest of W10, W9

After step 4, stop and have a person who has never seen the game play waves 01-05 without help.
The test for the whole plan: unprompted, they put the tough turret in front on wave 02 or 03, and
they press Retry after their first loss instead of putting the phone down.

## 7. Open questions for the owner

- Level locking: the level grid used to allow any level; it now locks ahead of progress. Confirm.
- Audio: is downloading CC0 sound packs acceptable, or should sounds be generated?
- Target: is the web build (`build/web_split`) or the phone build the one that matters first? Phone
  performance decides whether W2 and W6 need threading.
