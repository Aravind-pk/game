# Faultbreaker pilot generation record

Both calls used the built-in `image_gen.imagegen` tool with `transparent_background=true`. The tool did not expose a model identifier. No separately billed API was used. Raw outputs were copied without modification. Both outputs are 1774 × 887 RGBA PNGs.

## First call

Reference was `godot/assets/ui/art/faultbreaker.png`, used for identity and painted appearance.

```text
Create a controlled animation pilot sprite sheet of this exact Faultbreaker monster. Identity reference is attached: huge squat brown muscular quadruped, overlapping slate grey armour plates, narrow amber seams, two massive cream tusk claws on armoured forearms. Painted 2.5D tower defence art. Fixed orthographic camera 35 degrees downward. All eight frames face SOUTH directly toward viewer. One slow OVERHEAD SLAM action, two rows four columns read left to right top to bottom. Frame 1 grounded neutral crouch, 2 brace hind feet and lift chest, 3 both massive forearms raised overhead, 4 maximal overhead anticipation, 5 slam both foreclaws into dirt directly in front of chest, 6 compressed impact, 7 begin recovering, 8 same neutral crouch as frame 1. Hind feet retain stable ground contact. Same body size anatomy lighting armour identity and camera throughout, articulate limbs genuinely. Equal spacious cells, fully separated silhouettes, no text or grid. Transparent alpha background, no ground plane, no cast shadow, no scenery. Need readable broad poses at 60 pixels body width, source bodies about 240 pixels wide. Keep each body's ground pivot centered consistently within its cell. Avoid clipping and neighbouring fragments.
```

Output is `slam_raw.png`. The prompt's description of two foreclaws was insufficiently precise about the multiple blades on each forearm. The next call explicitly corrected that description.

## Targeted repair

References were `godot/assets/ui/art/faultbreaker.png` for identity and `slam_raw.png` as the edit target.

```text
Repair the animation pilot in reference 2 using reference 1 as exact creature identity. Deliver 8 complete separate poses in 4 columns 2 rows with generous gutters. This is an armoured quadruped doing an overhead double forearm slam, not a humanoid. Preserve the HUGE overlapping grey plated forearm gauntlets and THREE long ivory claw blades on EACH forearm throughout every pose including overhead pose. No hands or tiny pincers. Keep rear feet at exactly same horizontal and vertical contact in every cell, same creature scale, camera 35 degrees down. Pose order crouch, brace, raise both armoured forearms, overhead maximum, slam down full extension, impact compression, recovery, crouch. In impact frame huge gauntlets strike ground forward of torso. Background MUST be genuinely empty transparent alpha, all pixels outside silhouettes alpha zero. No painted white/grey checkerboard or textured matte, no shadow or floor. Do not clip any claw at top. Painted muted slate brown cream with thin amber seams, identity unchanged.
```

Output is `slam_repair_raw.png`. Transparency improved substantially. The forearm and claw continuity failed again.

## Inspection setup

The output dimensions do not divide evenly into a 4 × 2 grid. `frames.json` uses rounded cell boundaries, without resampling the sources. Its anchors and timing are provisional review settings, not calibrated engine data. The same manifest applies to both outputs.

```sh
node /home/aravind/.local/opt/sprite-animation-skill/scripts/inspect-sheet.mjs \
  art/sprites/faultbreaker/pilot/slam_raw.png \
  --frames art/sprites/faultbreaker/pilot/frames.json \
  --module-root /home/aravind/.local/opt/sprite-animation-skill \
  --chrome /usr/bin/google-chrome \
  --report art/sprites/faultbreaker/pilot/slam-audit.json \
  --preview art/sprites/faultbreaker/pilot/slam-review.html
```

Repeat for `slam_repair_raw.png` with `slam-repair-audit.json` and `slam-repair-review.html` outputs. Both helper runs completed. The initial equal-grid invocation failed because the image dimensions do not divide evenly. Explicit rectangles resolved that inspection failure.
