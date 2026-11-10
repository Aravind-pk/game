# Authored collapse replacement

Built-in image generation; model identifier not exposed. References: `breach_start_reference.png` (last approved HP stage) and `breach_end_reference.png` (original wall_11, aligned to the first-sheet baseline). Transparent background requested. No separate billed API.

## Sequence request

Use case: illustration-story / game animation sprite sheet.
Paint ONE continuous authored 16-frame collapse sequence in a spacious 4-column x 4-row sheet, chronological left to right then top to bottom. All 16 cells show the SAME fortress gate, same fixed front orthographic camera about35 degrees down, same scale, same ground registration. Use reference1 as EXACT START identity, palette and proportions; reference2 as EXACT END STATE target. Grey painted stone pillars with orange square lamps, sagging steel double doors with yellow hazard stripes and cyan lintel. Weathered hand-painted realism for a small portrait tower-defense game. Gate displayed270pixels wide, prioritize bold readable silhouettes. Render large high-resolution sheet, ideally3072x3072, each gate540px wide with generous empty gutters and full smoke/debris extents.
IMPORTANT: This is VIOLENT DESTRUCTION with newly painted shape changes, not a lowering shutter, no vertically shrinking door slab, no planar-squash animation. Door leaves tear and deform independently.
Frame0: match reference1 failing gate.
1: doors swell/bulge toward camera, glowing centre seam, new cracks upwards.
2: left door buckles convex, right twists, cyan light flickers unevenly.
3: seam bursts flame, hinge mounts rip, cyan goes dark; pillar tops fracture.
4: LEFT door folds sharply outward, RIGHT door tears free spinning clockwise diagonally in AIR, lintel BREAKS in middle into two falling jagged pieces, stone chunks airborne.
5: biggest violent explosion: two separate asymmetric torn leaves in AIR, left folded/V-shaped falling toward lower left, right rotated tilted toward lower right, dust and orange fire behind; no complete bar spanning the opening.
6: airborne twisted door fragments falling lower, broken stone blocks fall from cracked pillars, opening visible.
7: impact: left folded leaf hits rubble, right panel bounces onto its corner; chunks scatter forward, large low brown dust cloud.
8: second bounce and settling: jagged pile grows across threshold, two pillars cracked and visibly leaning outward, broken rebar, small fires.
9: dust rolls outward, door plates land twisted into rubble, dark opening, irregular jagged pillar tops.
10: rubble settles, dust thins, no huge continuous slab; orange flames in two small pockets.
11: nearly reference2 end state, charcoal rubble heap and torn hazard-striped plates across low threshold, pillar lamps still orange; thin pale smoke.
12: match reference2 ruined gate state, standing fractured leaning pillars, sizeable rubble heap and twisted door plates, small fires, smoke.
13,14,15: SAME STATIC wreck geometry as12, only subtle fire flicker and thin smoke changes. The last4 are loopable fire/smoke, not repaired or tidier.
The camera and pillar FOOT positions must not move. Pillars keep same stone material and lamp locations; they crack and lean, never replace with different architecture. Never less structural damage than previous. Keep maximum damaged footprint and contact plane consistent with reference2.
Draw ONLY gate pillars, doors, lintel, loose rubble, smoke, flames. NO side walls, no floor, paving, landscape, sky, labels, borders, numbers or checkerboard. True empty transparent alpha outside silhouettes and inside breached opening, generous gutters so nothing touches other cells. Each cell centered on the same two pillar base centres and same baseline. Reference2 open central gap must be wide enough for monsters to run through above rubble. Preserve reference style, materials, camera and muted palette throughout.
