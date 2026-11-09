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
