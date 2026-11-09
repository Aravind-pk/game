"""Bake the reviewed source manifests into the existing North Gate atlas format.

Run with the project's Pillow/NumPy Python, followed by a kit name.
Source pivots and scales are authored in art/sprites/<kit>/build.json.
"""
import json
import math
import sys
import base64
from io import BytesIO
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from extract_kit import components

ROOT = Path(__file__).resolve().parents[2]


def source_cells(source, spec):
    image = Image.open(source).convert("RGBA")
    columns, rows = spec["grid"]
    x_edges = spec.get("x_edges", [round(i * image.width / columns) for i in range(columns + 1)])
    y_edges = spec.get("y_edges", [round(i * image.height / rows) for i in range(rows + 1)])
    cells = []
    rectangles = []
    for index in range(columns * rows):
        left, right = x_edges[index % columns:index % columns + 2]
        top, bottom = y_edges[index // columns:index // columns + 2]
        cell = np.array(image.crop((left, top, right, bottom)))
        # Generated alpha sometimes retains a low-opacity matte. Remove that matte
        # once, without recolouring the painted surfaces or rescaling each pose.
        floor = spec.get("alpha_floor", 48)
        alpha = cell[:, :, 3].astype(float)
        cell[:, :, 3] = np.clip((alpha - floor) * 255 / (255 - floor), 0, 255)
        cell[cell[:, :, 3] == 0] = 0
        if spec.get("main_component", False):
            groups = components(cell[:, :, 3] > 96)
            main = max(groups, key=len)
            mask = np.zeros(cell.shape[:2], dtype=np.uint8)
            mask[main[:, 0], main[:, 1]] = 255
            expanded = np.array(Image.fromarray(mask).filter(ImageFilter.MaxFilter(5)))
            cell[expanded == 0] = 0
        cells.append(Image.fromarray(cell))
        rectangles.append({"id": str(index), "rect": {
            "x": left, "y": top, "w": right - left, "h": bottom - top}})
    source.with_suffix(".frames.json").write_text(json.dumps(rectangles, indent=2))
    return cells


def register(cell, pivot, scale, anchor, size):
    resized = cell.resize((round(cell.width * scale), round(cell.height * scale)), Image.Resampling.LANCZOS)
    tile = Image.new("RGBA", tuple(size))
    offset = (round(anchor[0] - pivot[0] * scale), round(anchor[1] - pivot[1] * scale))
    # Ignore at most 3/255 Lanczos ringing when checking the pre-crop envelope.
    # The independent decoded-atlas audit uses its own alpha threshold.
    bounds = resized.getchannel("A").point(lambda value: 255 if value > 3 else 0).getbbox()
    if bounds and (offset[0] + bounds[0] <= 0 or offset[1] + bounds[1] <= 0
                   or offset[0] + bounds[2] >= size[0] or offset[1] + bounds[3] >= size[1]):
        raise ValueError(f"Source exceeds the motion envelope at {offset}, bounds {bounds}")
    tile.alpha_composite(resized, offset)
    box = tile.getbbox()
    if not box or box[0] == 0 or box[1] == 0 or box[2] == size[0] or box[3] == size[1]:
        raise ValueError(f"Empty or clipped registered cell at {offset}, bounds {box}")
    return tile


def build(kit):
    folder = ROOT / "art/sprites" / kit
    manifest = json.loads((folder / "build.json").read_text())
    sources = {name: source_cells(folder / name, spec) for name, spec in manifest["sources"].items()}
    size = manifest.get("cell", [256, 256])
    anchor = manifest.get("anchor", [128, 214])
    tiles = []
    animations = {}
    for name, animation in manifest["animations"].items():
        frames = []
        for item in animation["poses"]:
            source = sources[item["source"]][item["index"]]
            tile = register(source, item["pivot"], item["scale"], item.get("anchor", anchor), size)
            if item.get("flip"):
                tile = tile.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            frames.append({"x": 0, "y": 0, "w": size[0], "h": size[1],
                           "ax": size[0] - anchor[0] if item.get("flip") else anchor[0],
                           "ay": anchor[1], "sh": item.get("shadow", 0)})
            tiles.append((name, len(frames) - 1, tile))
        animations[name] = {key: value for key, value in animation.items() if key != "poses"}
        animations[name]["frames"] = frames
    columns = manifest.get("columns", 4)
    atlas = Image.new("RGBA", (size[0] * columns, size[1] * math.ceil(len(tiles) / columns)))
    inspection = []
    for index, (name, frame_index, tile) in enumerate(tiles):
        x, y = index % columns * size[0], index // columns * size[1]
        atlas.paste(tile, (x, y))
        frame = animations[name]["frames"][frame_index]
        frame.update(x=x, y=y)
        inspection.append({"id": f"{name}/{frame_index}", "rect": {"x": x, "y": y, "w": size[0], "h": size[1]},
                           "anchor": {"x": frame["ax"], "y": frame["ay"]},
                           "durationMs": animation_duration(manifest, name, frame_index)})
    output = ROOT / "godot/assets/sprites" / manifest["category"]
    output.mkdir(parents=True, exist_ok=True)
    atlas.save(output / f"{kit}.png")
    (output / f"{kit}.json").write_text(json.dumps({"image": f"{kit}.png", "anims": animations}, indent=2))
    (folder / "atlas.frames.json").write_text(json.dumps(inspection, indent=2))
    make_field_review(folder, manifest, animations, tiles)
    print(f"{kit}: {len(tiles)} frames, {atlas.width} x {atlas.height}")


def animation_duration(manifest, name, index):
    times = manifest["animations"][name].get("duration_ms", 125)
    return times[index] if isinstance(times, list) else times


def make_field_review(folder, manifest, animations, tiles):
    field = Image.open(ROOT / "godot/assets/backgrounds/north_gate_field.jpg").convert("RGB")
    background = field.crop((field.width // 3, field.height // 2, field.width // 3 + 200, field.height // 2 + 200)).resize((200, 200))
    base = next((tile for name, _, tile in tiles if name == "base"), None)
    size = manifest.get("cell", [256, 256])
    anchor = manifest.get("anchor", [128, 214])
    # One scale for all poses. The width is calibrated against the neutral pose,
    # so attack/death poses retain their authored size changes.
    first = tiles[0][2].copy()
    if base is not None:
        composite = base.copy()
        composite.alpha_composite(first)
        first = composite
    box = first.getbbox()
    review_scale = manifest["display_width"] / (box[2] - box[0])
    board = Image.new("RGB", (800, math.ceil(len(tiles) / 4) * 200))
    draw = ImageDraw.Draw(board)
    for index, (name, frame_index, tile) in enumerate(tiles):
        x, y = index % 4 * 200, index // 4 * 200
        board.paste(background, (x, y))
        merged = base.copy() if base is not None and name == "aim" else Image.new("RGBA", tuple(size))
        merged.alpha_composite(tile)
        reduced = merged.resize((round(size[0] * review_scale), round(size[1] * review_scale)), Image.Resampling.LANCZOS)
        board.paste(reduced, (round(x + 100 - anchor[0] * review_scale), round(y + 145 - anchor[1] * review_scale)), reduced)
        draw.text((x + 8, y + 7), f"{name} {frame_index}", fill="white", stroke_fill="black", stroke_width=1)
        draw.line((x + 94, y + 145, x + 106, y + 145), fill="#57e5df")
    board.save(folder / "field-contact.png")
    atlas_path = ROOT / "godot/assets/sprites" / manifest["category"] / f"{folder.name}.png"
    buffer = BytesIO()
    background.save(buffer, format="PNG")
    payload = {"atlas": base64.b64encode(atlas_path.read_bytes()).decode(),
               "background": base64.b64encode(buffer.getvalue()).decode(),
               "animations": animations, "scale": review_scale,
               "durations": {name: [animation_duration(manifest, name, i) for i in range(len(anim["frames"]))]
                             for name, anim in animations.items()}}
    html = """<!doctype html><meta charset="utf-8"><title>Field sprite review</title>
<style>body{background:#252825;color:#eee;font:16px system-ui;margin:24px}canvas{margin:12px;vertical-align:top}button,select,input{font:inherit;margin:8px}</style>
<p>Native game size and 3× enlargement. The cyan cross marks the fixed ground pivot.</p>
<select id="animation"></select><button id="play">Pause</button><button id="step">Step</button>
<label>Speed <select id="speed"><option value="1">Normal</option><option value="0.4">Slow</option></select></label>
<input id="frame" type="range" min="0" value="0"><span id="label"></span><br>
<canvas id="native" width="200" height="200"></canvas><canvas id="large" width="600" height="600"></canvas>
<script>
const data=PAYLOAD, image=new Image(), background=new Image();
image.src='data:image/png;base64,'+data.atlas;background.src='data:image/png;base64,'+data.background;
const select=document.querySelector('#animation'),slider=document.querySelector('#frame');
for(const [id,zoom] of [['native',1],['large',3]]){const canvas=document.querySelector('#'+id),dpr=window.devicePixelRatio||1;canvas.style.width=(200*zoom)+'px';canvas.style.height=(200*zoom)+'px';canvas.width=200*zoom*dpr;canvas.height=200*zoom*dpr}
for(const name of Object.keys(data.animations)){const option=document.createElement('option');option.value=name;option.textContent=name;select.append(option)}
let index=0,playing=true,last=0;
function paint(ctx,f){const s=data.scale;ctx.drawImage(image,f.x,f.y,f.w,f.h,100-f.ax*s,145-f.ay*s,f.w*s,f.h*s)}
function draw(){const name=select.value,frames=data.animations[name].frames;index%=frames.length;slider.max=frames.length-1;slider.value=index;
for(const [id,zoom] of [['native',1],['large',3]]){const ctx=document.querySelector('#'+id).getContext('2d'),density=zoom*(window.devicePixelRatio||1);ctx.setTransform(density,0,0,density,0,0);ctx.drawImage(background,0,0,200,200);
if(name==='aim'&&data.animations.base)paint(ctx,data.animations.base.frames[0]);paint(ctx,frames[index]);ctx.strokeStyle='#57e5df';ctx.beginPath();ctx.moveTo(94,145);ctx.lineTo(106,145);ctx.stroke()}
document.querySelector('#label').textContent=name+' '+(index+1)+' / '+frames.length}
select.onchange=()=>{index=0;last=0;draw()};slider.oninput=()=>{playing=false;index=Number(slider.value);draw()};
document.querySelector('#step').onclick=()=>{playing=false;index++;draw()};document.querySelector('#play').onclick=()=>{playing=!playing;last=0;document.querySelector('#play').textContent=playing?'Pause':'Play'};
function tick(time){if(!last)last=time;let duration=data.durations[select.value][index]/Number(document.querySelector('#speed').value);while(playing&&time-last>=duration){last+=duration;index=(index+1)%data.animations[select.value].frames.length;duration=data.durations[select.value][index]/Number(document.querySelector('#speed').value)}if(!playing)last=time;if(image.complete&&background.complete)draw();requestAnimationFrame(tick)}
Promise.all([image.decode(),background.decode()]).then(()=>requestAnimationFrame(tick));
</script>"""
    (folder / "field-review.html").write_text(html.replace("PAYLOAD", json.dumps(payload)))


if __name__ == "__main__":
    build(sys.argv[1])
