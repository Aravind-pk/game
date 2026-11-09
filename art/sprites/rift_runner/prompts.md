# Rift Runner source prompts

Built-in image_gen.imagegen, transparent_background=true. Model identifier was not exposed. Raw outputs copied unchanged. Extraction, scales, pivots and alpha cleanup are in build.json. The first nominal south-view attempt was retained as southwest because of its actual yaw. The first lunge sheet was rejected for background contamination and repaired.

## Southwest run

References were rift_runner.png identity.

```text
RIFT RUNNER fast run animation pilot. Use attached exact identity: lean low quadruped predator with long narrow pointed slate-grey armoured head, small brown wiry torso, slim plated back, four long angular brown legs, long slim ivory sickle foreclaws and a tapering segmented tail. This is the LIGHT FAST runner, preserve slender silhouette and small armour coverage, no huge tank gauntlets or broad bulky shell. Painted2.5D muted slate brown cream with tiny amber seams. Fixed orthographic camera35 degrees down, SOUTH facing viewer. Eight-frame in-place fast quadruped gallop in4columns2rows, read left-right then down. Distinct gait: reach with left foreleg/right hindleg, contact and absorb, limbs gather under body, push-off, opposite foreleg/hindleg reach, contact and absorb, gather, push-off returning to first pose. Foreclaws clearly alternate, feet follow two lanes without crossing. Body scale and head width constant, small vertical bob, tail follows spine, no sideways root drift or squash body morphing. Ground pivot same place all cells. Design for55px body width, clear silhouette over painted dirt. Generous margins, complete limbs and tail inside every cell. Real empty transparent alpha, no floor, shadow, text, grid or labels.
```

## South run

References were rift_runner.png identity and walk_SW_raw.png appearance.

```text
TRUE FRONT VIEW south-facing RIFT RUNNER fast run sprite sheet,8 poses4columns2rows. Reference1 exact lean creature identity, reference2 painted appearance ONLY, change its viewing yaw to face directly into camera. Nose points STRAIGHT DOWN toward viewer at exact middle of each cell, head is centred, both shoulders equally visible, hindquarters directly behind head, segmented tail hidden behind spine and does NOT extend sideways. No three-quarter angle, no diagonal view. Fixed orthographic camera35 degrees down. Narrow pointed slate-grey head shield, wiry brown body and four LONG angular legs, slim ivory foreclaws, tapering tail. Light predator, no bulky tank gauntlets. One8frame fast in-place run, clearly alternating left foreleg/right hindleg reaching and planting then gathering and opposite pair, head width/size constant, slight vertical weight bob, separate foot lanes no crossing. Same ground pivot and anatomical scale all cells. Rendered painted game art,55pixel display silhouette, complete feet with generous margins. Real empty transparent alpha, no floor/shadow/text/grid/labels.
```

## East and northeast run

References were rift_runner.png identity and walk_SW_raw.png appearance.

```text
RIFT RUNNER light fast quadruped RUN sheet. Reference1 exact identity, reference2 established painted run appearance. Lean wiry brown torso, long narrow angular slate-grey head shield, slim overlapping dorsal armour and tapering segmented tail, four long jointed legs with ivory sickle foreclaws. NEVER bulky tank, retain narrow silhouette. Fixed orthographic camera35degrees down. 4columns4rows16 equally spaced complete sprites. First TWO rows one8frame EAST run facing exact RIGHT, pointed nose/claws on right, tail extends LEFT. Last TWO rows one8frame NORTHEAST run up-right away: see rear shell and tail trailing DOWN-LEFT, head at upper-right far end partly hidden by back. Same8phase fast gallop each: left fore/right hind reach, contact, gather, push, opposite pair reach, contact, gather, push. Large visible leg articulation and fleeting flight phase, rigid head/back scale, body bob small, ground root fixed and two foot lanes. Same anatomical size palette camera across cells, complete tail and legs inside generous margins, no floor/shadow/text/grid/labels. True empty transparent alpha, intended55px wide in game.
```

## North run

References were rift_runner.png identity and walk_E_NE_raw.png appearance.

```text
RIFT RUNNER true REAR NORTH view fast run sprite sheet.8frames4columns2rows. Exact same lean slate-grey armoured quadruped identity as reference1, painted run appearance reference2. Creature faces STRAIGHT AWAY toward top of cell, NO FACE, no eyes or frontal ivory tusks visible. See pointed overlapping back plates, rear hip pair and long slim segmented tail trailing DOWN toward camera on centre line, head at far top mostly hidden by dorsal shell. Four long wiry brown legs with narrow armour, slim fast silhouette. Fixed orthographic camera35degrees down, never top-down map icon. One8phase in-place fast gallop: left fore/right hind reach, contact/compress, gather, push-off, opposite pair reach, contact, gather, push-off. Feet in separate left/right lanes, tail follows spine with restrained movement, body/head size constant, ground pivot fixed, no lateral root drift. Complete legs tail in spacious equal cells, no floor/shadows/text/grid/labels. True empty transparent alpha.55px intended game width.
```

## Death

References were rift_runner.png identity, walk_S_raw.png and walk_E_NE_raw.png.

```text
RIFT RUNNER death animation sprite sheet,5columns4rows20 spacious cells. Reference1 exact identity and reference2/3 accepted front and side run appearance. Lean brown wiry quadruped, long narrow slate-grey head shield and slim segmented tail, four long angular legs with ivory foreclaws. Camera fixed orthographic35 degrees down. First TWO rows one10frame SOUTH straight toward viewer death, head centred tail hidden behind body. Last TWO rows one10frame EAST RIGHT death with tail left. Each starts in matching running contact stance, recoils briefly, legs buckle and fold, slim body falls low, armour plates sag and separate, ends inert low grey plate and brown limb corpse with long pointed head and tail recognizable. No expanding size or vanishing, no recovery at end. Same anatomical scale, palette, ground point and front foot baseline throughout. Whole silhouette including tail inside margins, no text/grid/floor/shadows. Real empty transparent alpha. Intended55px at game size.
```

## Emerge

References were rift_runner.png identity and walk_S_raw.png.

```text
RIFT RUNNER emerging from ground12frame sheet4columns3rows. Exact lean creature identity reference1, true front run appearance reference2. Slender brown wiry quadruped, long narrow slate-grey pointed head shield, slim dorsal plates, four long angular legs, ivory sickle foreclaws and thin segmented tail. Never broad bulky tank. Fixed orthographic camera35degrees down, SOUTH straight toward viewer, head centred tail behind spine not sideways. Frames1-2 small dark dry-brown ground cracks;3-4 dark opening with a few soil chunks;5-6 pointed armoured head pushes up;7-8 narrow shoulders and forelegs lever out;9-10 hindlegs climb out;11 settles into crouched run contact;12 same stance as front run reference. Same anatomical scale all frames, fixed ground pivot, no enlarging at end, no permanent mound. Complete silhouette with generous cell margins, no floor/shadows/text/grid/labels. Real empty transparent alpha outside small dirt footprint. Creature displays about55px in game.
```

## Lunge candidate

References were rift_runner.png identity, walk_S_raw.png and walk_E_NE_raw.png.

```text
RIFT RUNNER quick low lunge attack sprite sheet6columns3rows18 spacious equal cells. Reference1 exact identity; reference2 true front run; reference3 side run. Lean slate-grey pointed head shield, wiry brown low quadruped body, slim segmented tail and long narrow ivory foreclaws, NEVER bulky tank. Fixed orthographic35degree-down camera. Row1 SOUTH directly toward viewer, centred head and tail behind body. Row2 SOUTHWEST down-left three-quarter toward viewer, tail up-right. Row3 EAST exact RIGHT, tail left. Each row one6frame action:1 run-contact crouch;2 gather hind legs low;3 compressed spring anticipation;4 fast forward lunge with foreclaws extended in facing direction and head low;5 contact impact;6 recover to initial stance. Same anatomical size, head width, palette and ground root. Real distinct leg articulation and forward reach, no overhead pose, no upright humanoid, no huge effects. Keep entire tail and foreclaws in generous cell margins. No floor/shadows/text/grid/labels. Real empty transparent alpha. Readable at55px wide in game.
```

## Lunge repair

References were attack_candidate_raw.png edit target.

```text
Clean the attached RIFT RUNNER lunge sprite sheet. Preserve all18 painted creature poses in their same6column3row layout, same identity anatomy colours and size. Remove ALL coloured noise, red yellow white speckles, grey haze and every pixel outside each creature silhouette. Background must be empty alpha ZERO, not a painted backdrop or checkerboard. Clean continuous antialiased edges of grey armour, brown limbs ivory claws and tail. No added effects, no flames, no smoke, no ground, no text. Keep each whole tail and claw separated inside its own spacious cell with margins. Painted creature artwork is the only retained content. This is production game art displayed55px, clean silhouette is essential.
```


