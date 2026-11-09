# Mule source prompts

Built-in image_gen.imagegen, transparent_background=true. Model identifier was not exposed. Both calls used godot/assets/ui/art/mule.png as identity reference. Raw sources were copied unchanged. Registration, scales, pivots and alpha cleanup are in build.json.

## Heads

```text
Game sprite source sheet, exact same MULE howitzer identity as reference, painted cream/offwhite armour, charcoal short thick barrel, amber hazard marks and thin cyan slits. Fixed orthographic camera looking down 35 degrees. A rigid rotating weapon head ONLY, removed from the reference pedestal, no base or column attached. 4 columns 2 rows, 8 evenly spaced separate heads all same physical size, fixed pivot at centre of underside bearing. All yaw directions in order: row1 muzzle points down toward viewer S, diagonally down-right SSE, down-right SE, mostly right ESE; row2 exact right E, slightly up-right ENE, diagonally up-right NE, straight away up N showing back of armour. Show top surfaces in all views; rear view has hidden muzzle and clear solid back armour. This is rotation of ONE identical rigid object, keep barrel length and elevation fixed, no recoil, no flash. Spacious equal cells with complete unclipped barrels. True transparent background, no shadow, scenery, text, labels, grid or floor. Designed to display about70px total turret width.
```

## Base and destruction

```text
Paint a game sprite source sheet matching exact MULE turret reference. 3 columns 2 rows, six separate equal spacious cells, camera orthographic looking down 35 degrees, cream worn armour charcoal steel amber hazard marks small cyan details. Identical turret size and grounded fixed base position in all cells. Cell1 ONLY the fixed octagonal pedestal foundation and its vertical charcoal bearing column with empty top, REMOVE rotating gun head entirely, render complete hidden top bearing. Cells2-6 full MULE howitzer pointing RIGHT, destruction progression: 2 intact complete turret mounted on same base; 3 armoured head cracked and tilting with a few orange sparks; 4 head broken and dropped lower onto mount with smoke; 5 barrel bent downward, plates collapsed, smoke fading; 6 dead flat dark steel cream rubble wreck on same octagonal base, no fire or smoke. Actual structural collapse instead of disappearance. All pieces inside their cells with generous margins, no text or labels or floor or shadows. Real transparent background.
```
