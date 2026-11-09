# Needle source prompts

Built-in image_gen.imagegen, transparent_background=true. Model identifier was not exposed. Both calls used godot/assets/ui/art/needle.png as the identity reference. Raw sources were copied unchanged. Extraction and registration are specified in build.json.

## Heads

```text
Game sprite source sheet, exact same NEEDLE anti-materiel rifle turret identity as reference, painted cream/offwhite angular receiver, very long narrow twin-rail dark steel barrel, amber hazard marks and thin cyan side slit. Fixed orthographic camera looking down 35 degrees. A rigid rotating weapon head ONLY, removed from reference pedestal, no base or column attached. 4 columns 2 rows, 8 evenly spaced separate heads all same physical scale, fixed pivot at centre of underside bearing under receiver. All yaw directions in order: row1 muzzle points down toward viewer S, diagonally down-right SSE, down-right SE, mostly right ESE; row2 exact right E, slightly up-right ENE, diagonally up-right NE, straight away up N showing back of receiver. Show top surfaces in all views. Rear view has barrel extending upward behind receiver. Rotate ONE identical rigid object, keep long barrel length and elevation fixed, no recoil, no flash. Spacious equal cells with COMPLETE UNCLIPPED barrel tips, leave 10% padding all sides. True transparent background, no shadow, scenery, text, labels, grid or floor. Designed to display70px total turret width.
```

## Base and destruction

```text
Paint game sprite sheet matching exact NEEDLE long anti-materiel turret reference. 3 columns 2 rows, six separate equal spacious cells, fixed orthographic camera looking down35 degrees, cream worn armour charcoal steel amber hazard marks thin cyan slit. Identical physical scale and fixed octagonal base location in every cell. Cell1 ONLY fixed octagonal foundation and its vertical dark bearing column, remove rotating rifle head entirely, render complete hidden top of bearing. Cells2-6 full NEEDLE long twin-rail rifle pointing RIGHT on that same base, destruction progression: 2 intact complete turret; 3 receiver cracked with sparks and barrel tilting; 4 receiver drops onto mount, barrel bending, a little smoke; 5 plates collapsed, barrel snapped, smoke fading; 6 low dark cream steel rubble wreck with broken rifle lying on same base, no fire or smoke. Real structural collapse. Complete barrel inside every cell, generous margins. True empty transparent alpha, no floor, no shadows, no dark haze backdrop, no labels or text.
```
