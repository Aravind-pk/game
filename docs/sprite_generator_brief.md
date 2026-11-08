# Burrower sprite sheet: generator brief

**Upload with every prompt:** `art/sprites/burrower/A_walk_front.png` (as the character reference).

Generate one sheet per prompt. Asking for everything at once is what makes frames drift, so keep the sheets separate. Paste the shared rules first, then one sheet block.

---

## Shared rules (paste with every sheet)

```
Create a 2.5D game sprite sheet of the exact creature in the reference image: the Burrower,
an armoured digger with an overlapping dark-grey plated shell, orange glowing seams, brown
muscular limbs and two large cream claws. Same design, proportions, palette, outline and
painted shading on every frame. Use the reference's SE and SW walk rows as the quality target.

The camera looks down from about 35 degrees, the same on every frame.

Grid: exact 256x256 pixel cells with no gaps, no gridlines, no borders.
Background: flat solid #00FF00 everywhere. No gradients on the background.
No text, labels, numbers, arrows or markings anywhere in the image.
Each cell: the creature is centred on x=128, its feet rest on the line y=216, and it stays
at least 24 pixels from every cell edge. Same creature size in every cell.
Shadow: one soft dark ellipse under the body, the same size and position in every frame.
Never use green or olive on the creature itself, including its feet, claws and shadow edges.
Every frame in a row is the same pose family, drawn from the same camera angle. Do not
redesign, resize or shift the creature between frames.
```

## Walk rules (add to sheets A, B and C)

```
Each row is one looping 8-frame walk cycle, read left to right, in place (the creature does
not travel across the cell).
F1 left claw planted forward, right hind leg back.
F2 weight comes down onto the left claw (body at its lowest).
F3 limbs passing, body rising.
F4 body at its highest, right claw swinging forward.
F5 mirror of F1: right claw planted forward, left hind leg back.
F6 weight comes down onto the right claw (body at its lowest).
F7 limbs passing, body rising.
F8 body at its highest, left claw swinging forward, flowing straight into F1.
The limbs must move clearly and differently on every frame. Planted feet do not slide.
The shell only moves up and down by 2 to 4 pixels. It never slides or sways sideways.
```

---

## Sheet A: walk, front half (2048x1024, 8 columns, 4 rows)

```
Row 1 S: facing the camera. Symmetrical. The centre line of the shell stays on x=128 in all
8 frames, with no left-right wobble. Only the limbs change.
Row 2 SSE: turned 22.5 degrees to the viewer's right of facing the camera.
Row 3 SE: turned 45 degrees, facing down and to the right.
Row 4 ESE: turned 67.5 degrees, facing mostly right and slightly down.
```

## Sheet B: walk, side and rear (2048x1024, 8 columns, 4 rows)

```
Row 1 E: exact side view. Head and claws point to the RIGHT of the image, tail end on the left.
One head only.
Row 2 ENE: facing mostly right and slightly away from the camera.
Row 3 NE: rear three-quarter view, facing up and to the right. We see the back of the shell
and the hind legs; the claws are partly hidden.
Row 4 NNE: rear view, turned 22.5 degrees to the right of facing directly away.
```

## Sheet C: walk north and turns (2048x768, 8 columns, 3 rows)

```
Row 1 N: true back view, facing directly away from the camera. Rear of the shell and hind
legs. No face or front of claws visible. The centre line of the shell stays on x=128 in all
8 frames. This row follows the walk rules.

Rows 2 and 3 are turns on the spot, 8 frames each, not looping:
Row 2: starts facing the camera (S) and pivots smoothly to an exact side view facing right
(E), rotating about 11 degrees per frame.
Row 3: starts in the side view facing right (E) and pivots smoothly to facing directly away
(N), rotating about 11 degrees per frame.
The feet step to carry the turn and the body rotates evenly. No sudden jump between frames.
```

## Sheet D: emerge (1536x512, 6 columns, 2 rows, read left to right then down)

```
12-frame emerge from the ground, centred on the same point in every cell.
F1-F2 hairline cracks spreading on the ground. F3-F5 the ground opens into a dark hole with
flying soil. F6-F9 the shell and claws push up through the soil. F10-F11 the body climbs out.
F12 fully out, with no mound left, in exactly the same pose as the S walk F1.
Earth tones are dark brown to match a sun-baked dirt field, not pale sand. Soil is only
scattered around the opening, and its edges fade cleanly into the background.
```

## Sheet E: attack (2048x768, 8 columns, 3 rows)

```
One 8-frame claw attack per row. Row 1 S facing the camera. Row 2 SE. Row 3 E facing right.
F1-F2 settle into stance. F3 rear back, body high and claws raised (anticipation).
F4 fast lunge forward with the claws swinging down. F5 full extension: the impact frame, with
a bright yellow-orange slash arc starting at the claw tips and sweeping FORWARD, in the
direction the creature faces. F6 slash fading. F7-F8 recover to the F1 pose.
The body visibly moves forward in the lunge, and the slash never trails behind the body.
```

## Sheet F: death (2560x512, 10 columns, 2 rows)

```
One 10-frame death per row. Row 1 S facing the camera. Row 2 E facing right.
F1-F3 recoil from a hit, F4-F6 limbs give way, F7-F9 the shell plates slump and separate,
F10 a flat pile of shell plates and rubble that holds as the last frame.
Same ground point in every frame.
```

---

## Output checklist

Reject and regenerate a sheet if:

- The creature's design, colours or size change between frames.
- The E row faces left, or any row has claws on both ends.
- The N or NE rows show the creature's face.
- Text, gridlines or other marks appear in the image.
- The S or N shell drifts sideways between frames.
- There's green on the creature.

Directions on the west side (SSW, SW, WSW, W, WNW, NW, NNW) are not needed, because the engine mirrors them from the east side. Attack and death get the same treatment.

**Total:** 72 walk frames, 16 turn frames, 12 emerge, 24 attack, 20 death: 144 frames across 6 sheets.
