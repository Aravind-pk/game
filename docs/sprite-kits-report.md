# Kestrel destruction and gate breach — 2026-11-10

Both jobs are wired into the game. Both requested Godot tests pass with zero failures. No commits were made. Changes stayed within the current file allowlist; `main.gd`, simulation, levels and the monster attack line were not edited.

## Kestrel G1

Delivered eight destruction frames at 140 ms per frame, replacing the orange/yellow legacy design. The approved grey pedestal is a separate, persistent layer. The first destruction sample uses the turret's actual current aim frame and its existing anchor; subsequent samples burn, tip and crumple the grey head onto that pedestal, ending in a held wreck. The sixteen-view aim behavior is unchanged.

The baker starts from `art/sprites/kestrel_v3/kestrel-atlas-v3.png` and its JSON. Every approved aim rectangle and the base rectangle were compared pixel-for-pixel after packing, and both animation dictionaries were compared for equality. All seventeen rectangles and both dictionaries are identical. Evidence: [preservation results](../art/sprites/kestrel_v3/preservation.json), plus the independent checks in `monster_sprite_check.gd` through the actual sprite renderer. The test also checks entry aim, offsets and fixed base visibility through all eight destruction samples. The old neighbouring-cell slivers are absent from the new destruction cells.

Method: built-in image generation, then deterministic extraction and layered assembly. The first generated candidate included an unwanted pedestal and was rejected as a direct animation source. A second built-in edit removed the pedestals; only the head/effects were extracted. The first painted head sample was replaced by the exact approved aim image. Sources remain `destroy_raw.png` and `destroy_heads_raw.png`. Exact prompts and constraints are in [prompts.md](../art/sprites/kestrel_v3/prompts.md); references were approved `heads.png` and `pedestal.png`, then the first generated sheet for cleanup. The tool did not expose a model identifier. No external billed API was used.

Visual inspection covered all eight composite poses at game size and enlarged, source alpha and the actual MG death transition. [Native field contact](../art/sprites/kestrel_v3/evidence/native-contact.png), [review player](../art/sprites/kestrel_v3/field-review.html), [real combat contact](../art/sprites/kestrel_v3/evidence/mg-transition.png), [short capture player](../art/sprites/kestrel_v3/evidence/mg-destruction/review.html). A legal level-05 MG deployment at cell `(15,17)` was used because the normal automatic deployment leaves both MGs alive. The helper selects the normal “Watch to End” button after defences deplete; the modal appears briefly in the recording. Frames 205–232 cover the intact head, impact, collapse and settled grey wreck on the same pedestal. Enemies partially occlude it, as they do in play.

Fallback: after the exact current-aim entry, collapse uses one authored east-facing sequence, mirrored for west. It is not sixteen separately authored destruction headings. Only one real death placement was recorded; all sixteen entry views remain covered by unchanged aim data and renderer preservation checks. The installed sequence was accepted at game size, with that directional limitation.

## Gate

Delivered five monotonic HP stages and a separate fourteen-frame breach at 10 fps. HP stages reuse original wall indices `0,1,2,4,5`; the regressing second-sheet damage frames no longer drive HP. A single immutable side-wall texture remains outside the central gate. Original `wall_00.png` is byte-identical, and legacy wall_01..11 files were left unchanged for provenance.

The breach starts at the exact last damage stage. The existing painted door fronts fall forward about their ground hinge line, exposing newly generated damaged steel backs. The lintel/light bar splits, drops and settles; cracked pillars remain standing. Generated dust rolls forward and clears; aligned original rubble accumulates at the threshold. The final opening and fallen panels hold. All layers share one 392.6 px anchor, including 80 px transparent top padding that compensates the original 312.6 px baseline. The original rail offset, wall position, gate HP plate and attack line stay fixed. Side walls cannot shimmer because they are drawn once, outside the animated gate texture.

Method: a segmented 2D rig with complete generated hidden door backs, projected forward using a 35-degree camera model, and authored dust effects. No whole-wall regeneration was used. Sources: original two wall sheets, `approved_wall_00.png`, `door_backs_raw.png`, `dust_raw.png`; [exact prompts](../art/sprites/wall/prompts.md), using `gate_reference.png` for material/color only. Built-in image generation only, model identifier unavailable. Geometry, source hashes and stages are in [build.json](../art/sprites/wall/build.json). The bake is deterministic.

The renderer uses a separate fixed 100 ms clock rather than stepping only through HP frames not previously shown. A floating-point boundary tolerance prevents skipped samples at a 10 fps capture cadence. Four existing explosion accents are timed at frames 1/3/5/7; the heavy impact, debris and stronger shake occur at frame 8. Existing monster movement begins after 0.9 s. The last artwork frame is reached at 1.3 s and holds, comfortably inside the existing 3.6 s report delay. No `main.gd` timer change is needed.

All five HP stages and all fourteen breach samples were checked in real level-05 captures. Standard auto-deployment loses at 34.50 s; the short recording covers frames 340–384. The weak run covers 195–261 and shows HP 80 → 53 → 35 → 17 → 8 → 0, then the same full breach. Both traces contain every breach index 0–13 and one invariant gate position. Tests compare the timeline starting from intact and severe damage, check 50 ms and 100 ms stepping, and verify fixed wall, attack-line and HP-plate positions. A runner visibly enters the opening before the report; more distant brutes are still approaching when the timer ends.

Evidence: [unobstructed breach contact](../art/sprites/wall/evidence/breach_contact.png), [damage contact](../art/sprites/wall/evidence/damage_contact.png), [breach review player](../art/sprites/wall/gate-review.html), [damage review player](../art/sprites/wall/damage-review.html), [real breach frames](../art/sprites/wall/evidence/game-breach-contact.png), [real HP damage frames](../art/sprites/wall/evidence/game-damage-contact.png), [normal capture player](../art/sprites/wall/evidence/breach/review.html), [weak capture player](../art/sprites/wall/evidence/weak/review.html). Before frames are retained under `art/sprites/wall/evidence/before/`. The game HUD partly covers falling door panels; the unobstructed contact shows their full progression. This is a layered illustrated collapse, not a simulated rigid-body destruction. No rejected whole-wall animation is installed.

## Checks and limits

- [monster_sprite_check log](../art/sprites/wall/evidence/monster-check.log): PASS, zero failures. [placement_check log](../art/sprites/wall/evidence/placement-check.log): PASS, zero failures. Godot import completed. `git diff --check` passes.
- [Rebuild check](../art/sprites/wall/evidence/rebuild-check.json): output hashes identical across rebuild, intact PNG byte-identical, every shipping gate frame pixel-identical to its audited sheet rectangle.
- Kestrel source sheets, final atlas and composited destruction, plus wall door backs, dust, damage, breach and field-composite sheets were measured using the skill's `auditPixels` implementation. Shipping destruction and gate layers have no blank-frame or edge-contact warnings at threshold 128. The one Kestrel atlas warning is the unchanged approved base touching its top edge. Field-composite edge/opacity warnings are expected because scenery fills those cells. Reports/manifests are in each `evidence/` folder.
- **Inspection-tool gap:** the literal `inspect-sheet.mjs` CLI was run, but fresh Chrome invocations stalled at PNG `Image.decode()`; retries with alternate launch flags also stalled. Opening the final review page timed out. Earlier Kestrel raw-source CLI reports are retained. For the final audits, `tools/sprites/inspect_decoded.mjs` independently decodes PNGs with Pillow and invokes the skill's unmodified exported `auditPixels` function and review template. The reports are valid pixel measurements, but are not claimed as successful final Chrome CLI runs. The custom field players use the same decoded RGBA to avoid that decoder path. They provide native/enlarged, stepping, normal/0.4× and held-last-frame controls, but final browser playback and density checks could not be completed.
- Visual acceptance here is this agent's inspection of every source/packed pose, game-size contacts, and sequential real combat PNGs. There was no independent reviewer. Continuous normal/slow browser playback remains unchecked; no mobile/web export, device-density matrix, performance benchmark or all-level sweep was performed. Other MG death headings were not recorded. These limits do not substitute a technical pass for aesthetic approval.

Rebuild commands (Python needs Pillow and NumPy):

```sh
~/.local/opt/northgate-venv/bin/python tools/sprites/build_kestrel_destroy.py
~/.local/opt/northgate-venv/bin/python tools/sprites/build_wall.py
godot --headless --path godot --import
godot --headless --path godot --script res://tests/monster_sprite_check.gd
godot --headless --path godot --script res://tests/placement_check.gd
```

Short recording examples (use absolute output paths):

```sh
godot --path godot --script "$PWD/tools/sprites/record_combat.gd" --fixed-fps 10 --quit-after 385 -- level=05 phase=combat capture_watch capture=/abs/breach capture_from=34 capture_to=38.4
godot --path godot --script "$PWD/tools/sprites/record_combat.gd" --fixed-fps 10 --quit-after 263 -- level=05 phase=combat weak capture_watch capture=/abs/weak capture_from=19.5 capture_to=26.1
godot --path godot --script "$PWD/tools/sprites/record_combat.gd" --fixed-fps 10 --quit-after 240 -- level=05 phase=deploy capture_mg=15,17 capture_watch capture=/abs/mg capture_from=20.5 capture_to=23.2
```

Review pages and evidence folders are ignored as requested. Captures save only the short windows above; source PNG sequences were not expanded into whole battles.

---

# Previous merged four-kit work (historical report)

The following describes the already merged work, not additional checks repeated in this task.

# Animated sprite kits report

Mule, Needle, Faultbreaker and Rift Runner are registered in the game. All four use the existing PNG atlas and `image` / `anims` / `frames` JSON format. Both requested Godot checks pass with the new registrations. Final 540 × 960 combat recordings for levels 4 and 5 were checked after the extraction corrections.

| Unit | Delivered kit | Registration | Native field review |
|---|---|---|---|
| Mule | 14 aim views, fixed base, 5 destruction frames, head recoil | `TURRET_KITS.mule` | [Playback](../art/sprites/mule/field-review.html), [contact sheet](../art/sprites/mule/field-contact.png) |
| Needle | 14 aim views, fixed base, 5 destruction frames | `TURRET_KITS.needle` | [Playback](../art/sprites/needle/field-review.html), [contact sheet](../art/sprites/needle/field-contact.png) |
| Faultbreaker | 40 walk frames in five authored views, 18 grounded attack frames, 20 death frames, 12 emerge frames, 8 turn holds | `MONSTER_KITS.brute` | [Playback](../art/sprites/faultbreaker/field-review.html), [contact sheet](../art/sprites/faultbreaker/field-contact.png) |
| Rift Runner | 40 run frames in five authored views, 18 lunge frames, 20 death frames, 12 emerge frames, 8 turn holds | `MONSTER_KITS.stalker` | [Playback](../art/sprites/rift_runner/field-review.html), [contact sheet](../art/sprites/rift_runner/field-contact.png) |

Production used the built-in `image_gen.imagegen` tool with the supplied stand-ins as identity references. The tool did not expose a model identifier. No separately billed API was used. Raw generated images are retained unchanged. Generated poses were extracted, cleaned, registered and baked deterministically with `tools/sprites/build_pending_kits.py`, which reuses `extract_kit.components`. Each kit's `build.json` records its source rectangles, scales, pivots, mirrors, timing and cleanup. `sources.json` records source dimensions and SHA-256 hashes.

The review pages composite the actual atlas frames over a crop of `north_gate_field.jpg`, with native and 3× canvases, stepping, normal and slow playback. They account for browser pixel density. Full playback cycles were exercised at 1× and 0.4×, with sampled rendered evidence under each kit's `evidence/playback/` and timing observations in `evidence/playback-check.json`. DPR 2 review screenshots are under `evidence/browser-dpr2.png`. Visual judgments came from decoded poses, contact sheets, browser render samples and combat frames. There was no independent reviewer.

Mule's rotating head is separate from its single fixed pedestal. Eight authored views across the eastern half become fourteen through mirroring. Aim angles and muzzle tips were calibrated per view. The assembled turret is approximately 70–80 px wide on the 540 px game view. Recoil moves only the head and recovers onto its bearing. Destruction collapses the head onto a persistent wreck. The source, native visual, packed-atlas and integration gates passed, with the raw-source caveats described below. Exact prompts and references are in [Mule's generation record](../art/sprites/mule/prompts.md). The [atlas audit](../art/sprites/mule/atlas-audit.json) has no warnings, and the [atlas review](../art/sprites/mule/atlas-review.html) permits decoded-frame inspection. Runtime files are `godot/assets/sprites/turrets/mule.png` and `.json`.

Needle uses the same layered method with a long rifle and its own pedestal. It is about 55 px wide from the front and about 70 px across the side silhouette. The head was lowered onto the bearing after enlarged review exposed a small gap. Recoil is disabled for this kit. Its source, native visual, packed-atlas and integration gates passed, with raw-source caveats below. Exact prompts and references are in [Needle's generation record](../art/sprites/needle/prompts.md). The [final atlas audit](../art/sprites/needle/atlas-audit.json) has no warnings. See the [atlas review](../art/sprites/needle/atlas-review.html) and [bearing review screenshot](../art/sprites/needle/evidence/browser-side.png). Runtime files are `godot/assets/sprites/turrets/needle.png` and `.json`.

Faultbreaker walks in S, SW, E, NE and N, with the renderer supplying western mirrors and nearest authored views for intermediate headings. Front and side widths are about 88–92 px, while the rear is about 76 px. The south cycle uses four authored phases followed by their mirrors. This preserves the body proportions while supplying alternating forefeet. The unused second half of the raw south sheet is retained. Other walk rows use their eight generated poses. Death frames have registered upper-shell centres and ground baselines. Emerge ends on the actual neutral walk frame for a consistent handoff. The new attack is a low grounded shove/body slam. Its source, native visual, packed-atlas and integration gates passed, with the turn fallback and raw-source caveats below. Exact prompts are in [Faultbreaker's generation record](../art/sprites/faultbreaker/prompts.md). See the [atlas audit](../art/sprites/faultbreaker/atlas-audit.json), [atlas review](../art/sprites/faultbreaker/atlas-review.html), [death review](../art/sprites/faultbreaker/evidence/browser-death_E.png) and [grounded attack review](../art/sprites/faultbreaker/evidence/browser-attack_S.png). Runtime files are `godot/assets/sprites/monsters/faultbreaker.png` and `.json`.

The two earlier overhead-slam candidates remain rejected under `art/sprites/faultbreaker/pilot/`. Their raised-arm silhouettes change the forearm construction. Their [original prompt record](../art/sprites/faultbreaker/pilot/prompts.md), audits and HTML reviews remain available. The low attack replaces that failed sequence.

Rift Runner has the same five authored headings, with an eight-phase articulated run, death, emerge and lunge. Side and southwest silhouettes are approximately 50–55 px wide. Front views are about 33–35 px wide and rear views about 24–31 px because the long body and tail are foreshortened. This was a deliberate presentation choice to preserve the slender frontal silhouette. Its bar was raised from 2.7 to 3.0 m to clear the new art. The first nominal south sheet actually faced southwest and was retained under the correct heading. A second generation supplies the true front view. The first lunge candidate had severe background noise. The repaired candidate was cleaned and accepted at game size. Late extraction review corrected rows that cut across claw tips and registered death frames to the upper head/shell, eliminating a sideways entry shift. Its source, native visual, packed-atlas and integration gates passed, with the turn fallback and raw-source caveats below. Exact prompts are in [Rift Runner's generation record](../art/sprites/rift_runner/prompts.md). See the [atlas audit](../art/sprites/rift_runner/atlas-audit.json), [atlas review](../art/sprites/rift_runner/atlas-review.html), [lunge review](../art/sprites/rift_runner/evidence/browser-attack_E.png) and [death review](../art/sprites/rift_runner/evidence/browser-death_S.png). Runtime files are `godot/assets/sprites/monsters/rift_runner.png` and `.json`.

Both monster turntables are documented fallbacks made from eight directional walk holds. They step between views. Smooth painted in-between turns remain optional future art work. Both emerge animations hold the real neutral walk frame for their last two samples. These holds intentionally produce duplicate warnings in the monster atlas audits. Walk, attack and death have their requested frame coverage. Walk/run cadence in combat remains distance-driven by `monster_sprite.gd`; the standalone review timings do not override it. No overhead-slam animation is installed.

Alpha cleanup removes low-opacity mattes and, where configured, keeps the main connected silhouette with a small edge margin. No per-frame body resizing was applied within a source family. Death uses upper-shell landmarks horizontally and the contact baseline vertically. Some generated rows required explicit irregular extraction boundaries. Original raw sheets remain noisy and their own audit reports still contain edge warnings. Those raw reports are retained beside each source as `*-audit.json` and `*-review.html`. The accepted extracted poses were judged at game size. Their packed atlases have no threshold-128 blank frames or edge contacts. Before compositing, the baker also checks the source motion envelope, ignoring Lanczos ringing at alpha 3/255 or below. Frame rectangles, anchors, mirrors, coverage, alpha and timing were checked separately from the artwork judgments.

The turret renderer now accepts optional aim-angle, muzzle and recoil metadata, plus per-kit destruction cadence and frame counts. Kestrel continues using its original sixteen-view defaults. The monster renderer needed no changes. The game changes are limited to the kit tables, Rift Runner's bar height and the turret renderer extension. `monster_sprite_check.gd` now exercises both new monster kits, full-circle movement, emerge, attacks, four death headings and both new turrets.

The requested tests pass with zero failures. Final logs are [monster_sprite_check](../art/sprites/rift_runner/evidence/monster-check.log), [placement_check](../art/sprites/rift_runner/evidence/placement-check.log) and [Godot import](../art/sprites/rift_runner/evidence/import.log). `git diff --check` also passed.

```sh
~/.local/opt/northgate-venv/bin/python tools/sprites/build_pending_kits.py mule
~/.local/opt/northgate-venv/bin/python tools/sprites/build_pending_kits.py needle
~/.local/opt/northgate-venv/bin/python tools/sprites/build_pending_kits.py faultbreaker
~/.local/opt/northgate-venv/bin/python tools/sprites/build_pending_kits.py rift_runner

godot --headless --path godot --import
godot --headless --path godot --script res://tests/monster_sprite_check.gd
godot --headless --path godot --script res://tests/placement_check.gd
```

The skill's `inspect-sheet.mjs` was run on every generated source sheet, including rejected candidates, and on every final atlas. Chrome was `/usr/bin/google-chrome`, and the module root was `/home/aravind/.local/opt/sprite-animation-skill`. Each source has a `.frames.json` describing its extraction rectangles. Atlas inspection uses the kit's `atlas.frames.json`.

```sh
node /home/aravind/.local/opt/sprite-animation-skill/scripts/inspect-sheet.mjs \
  godot/assets/sprites/monsters/faultbreaker.png \
  --frames art/sprites/faultbreaker/atlas.frames.json \
  --module-root /home/aravind/.local/opt/sprite-animation-skill \
  --chrome /usr/bin/google-chrome \
  --report art/sprites/faultbreaker/atlas-audit.json \
  --preview art/sprites/faultbreaker/atlas-review.html
```

Combat was recorded at 10 fps and reviewed through actual game frames. The desktop window manager resized the initial requested 540 × 960 movie window to 541 × 653. `tools/sprites/record_combat.gd` addresses this by loading the normal main scene into a 1080 × 1920 SubViewport and reducing each rendered frame once to 540 × 960. It uses the normal game scene, deployment automation, simulation and sprite renderers. Final evidence uses that capture path.

- [Final level 4 recording](../art/sprites/rift_runner/evidence/level04-final/review.html) and [contact sheet](../art/sprites/rift_runner/evidence/level04-final-contact.jpg) cover all final registrations.
- [Final level 5 recording](../art/sprites/rift_runner/evidence/level05-final/review.html) and [contact sheet](../art/sprites/rift_runner/evidence/level05-final-contact.jpg) exercise Rift Runner movement, targeting, attacks and death.
- [The longer level 4 recording](../art/sprites/faultbreaker/evidence/combat/review.html) includes Needle destruction around 43 s and Mule destruction around 57 s. The corrected late death-registration changes affect monster death poses, which were not triggered for Faultbreaker in this battle.
- [Level 4 before/after comparison](../art/sprites/faultbreaker/evidence/before-after-19s.jpg) uses supplied and new footage with clocks near 19 s. [Level 5 comparison](../art/sprites/rift_runner/evidence/before-after-level05.jpg) and [the runner combat sequence](../art/sprites/rift_runner/evidence/runner-combat-sequence.png) provide additional context. The supplied recording changes playback speed, so matching file indices are not treated as matching simulation times. Superseded/debug capture sequences were reduced to representative screenshots and logs. The final two 420-frame sequences and the longer 700-frame sequence remain complete.

```sh
godot --path godot --script "$PWD/tools/sprites/record_combat.gd" \
  --resolution 540x960 --fixed-fps 10 --quit-after 420 -- \
  level=04 phase=combat capture=/abs/output
```

Remaining limitations are the stepped turn holds, nearest-view intermediate headings and the raw-source edge warnings described above. Faultbreaker death was reviewed in the atlas/browser and exercised through the actual sprite state code in the headless check, but this level 4 battle did not kill a Faultbreaker. All animations and poses were reviewed in the field sheets, with selected normal/slow playback samples and combat frames inspected. Every recorded PNG was not individually reviewed. No independent art review, mobile/Web device run, performance benchmark, exhaustive crowded-overlap sweep or all-fifty-level pass was performed. Actual combat review used 540 × 960. Browser DPR 2 was checked in the review pages only.
