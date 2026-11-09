"""Cut the prop sheets into one atlas and tag each solid prop with a ground footprint.

Usage (from the repo root):  python tools/sprites/extract_props.py

Reads   art/sprites/props/*_sheet.png
Writes  godot/assets/sprites/props/props.png and props.json
        art/previews/props_contact.png (every prop with its footprint drawn on it)

The art is drawn at an angle, so a prop's picture is much bigger than the patch of ground it
stands on. The footprint is that patch: the silhouette's lower edge, mirrored back across the
line between its left and right ends, like the shadow directly beneath the object.
"""
import json
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art" / "sprites" / "props"
GROUP_GAP = 9          # pieces closer than this (pixels) belong to the same prop
MIN_SIZE = 32
BODY_OPEN = 7          # removes grass and pebbles when finding the main body
MIN_DEPTH_PX = 8.0     # a footprint is never thinner than this, front to back
BROAD_DEPTH = 0.2      # half the depth of a boulder or cabinet, as a share of its width
MAX_BASE_RISE = 0.42   # the base's edge never climbs above this share of the prop's height
POINTS = 12            # points along the lower edge

# What each row of each sheet holds, then exceptions as (row, column).
# ground and crater: lie flat, drawn under everything. decor: short, walked through.
# solid: boulders and cabinets. thin: walls and barriers. tall: trees and lamps, foot only.
KINDS = {
    "desert": {
        "bands": [160, 313, 488, 668],
        "rows": ["decor", "crater", "solid", "thin", "tall"],
        "except": {
            (0, 12): "ground", (0, 13): "ground", (0, 14): "ground",
            (1, 2): "solid", (2, 9): "decor",
            (3, 6): "solid", (3, 7): "solid", (3, 8): "solid", (3, 9): "tall",
            (4, 0): "decor", (4, 1): "decor", (4, 2): "decor", (4, 3): "decor", (4, 4): "decor", (4, 5): "skip",
        },
    },
    "terrain": {
        "bands": [115, 217, 345, 507, 700],
        "rows": ["decor", "decor", "solid", "ground", "thin", "skip"],
        "except": {
            (3, 0): "crater", (3, 4): "thin", (3, 5): "thin",
            (4, 2): "solid", (4, 4): "tall", (4, 5): "solid", (4, 6): "solid", (4, 7): "solid",
        },
    },
}


def components(mask):
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    out = []
    for sy, sx in zip(*np.nonzero(mask)):
        if seen[sy, sx]:
            continue
        q = deque([(sy, sx)])
        seen[sy, sx] = True
        pts = []
        while q:
            y, x = q.popleft()
            pts.append((y, x))
            for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    q.append((ny, nx))
        out.append(np.array(pts))
    return out


def cut_sheet(path, bands):
    """Returns rows of props: each prop is an RGBA array containing only its own pixels."""
    sheet = np.array(Image.open(path).convert("RGBA"))
    sheet[sheet[..., 3] < 40] = 0
    solid = Image.fromarray((sheet[..., 3] > 40).astype(np.uint8) * 255, "L")
    grown = np.array(solid.filter(ImageFilter.MaxFilter(GROUP_GAP))) > 0
    props = []
    for pts in components(grown):
        y0, x0 = pts.min(0)
        y1, x1 = pts.max(0) + 1
        if x1 - x0 < MIN_SIZE or y1 - y0 < MIN_SIZE:
            continue
        keep = np.zeros(grown.shape, dtype=bool)
        keep[pts[:, 0], pts[:, 1]] = True
        art = sheet[y0:y1, x0:x1].copy()
        art[~keep[y0:y1, x0:x1]] = 0
        ys, xs = np.nonzero(art[..., 3])
        art = art[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        props.append({"art": art, "x": int(x0 + xs.min()), "y": int(y0 + ys.min())})
    rows = [[] for _ in range(len(bands) + 1)]
    for p in props:
        centre = p["y"] + p["art"].shape[0] / 2
        rows[sum(centre > b for b in bands)].append(p)
    return [sorted(row, key=lambda q: q["x"]) for row in rows]


def main_body(art):
    """The largest solid mass, with thin things like grass and rebar opened away."""
    solid = Image.fromarray((art[..., 3] > 200).astype(np.uint8) * 255, "L").convert("L")
    pad = Image.new("L", (solid.width + 20, solid.height + 20), 0)
    pad.paste(solid, (10, 10))
    opened = pad.filter(ImageFilter.MinFilter(BODY_OPEN)).filter(ImageFilter.MaxFilter(BODY_OPEN))
    mask = np.array(opened)[10:-10, 10:-10] > 0
    comps = components(mask)
    out = np.zeros(mask.shape, dtype=bool)
    if comps:
        main = max(comps, key=len)
        out[main[:, 0], main[:, 1]] = True
    return out


def tall_foot(art):
    """Just the trunk or post where it meets the ground, ignoring grass around it."""
    solid = art[..., 3] > 200
    ys, xs = np.nonzero(solid)
    bottom = ys.max()
    band = (ys > bottom - max(16, int((bottom - ys.min()) * 0.1)))
    # The middle of the band, so grass out to one side cannot pull the foot off centre.
    left, right = np.percentile(xs[band], [15, 85])
    centre = (left + right) / 2.0
    w = float(np.clip(right - left, 26, (xs.max() - xs.min()) * 0.42))
    depth = max(MIN_DEPTH_PX, w * 0.32)
    middle = float(bottom - depth)
    angles = np.linspace(0, 2 * np.pi, POINTS, endpoint=False)
    return np.stack([centre + np.cos(angles) * w / 2.0, middle + np.sin(angles) * depth], 1)


def footprint(art, broad):
    body = main_body(art)
    if not body.any():
        body = art[..., 3] > 200
    ys, xs = np.nonzero(body)
    x0, x1 = xs.min(), xs.max()
    columns = np.linspace(x0, x1, POINTS).round().astype(int)
    lower = []
    for c in columns:
        rows = np.nonzero(body[:, max(c - 2, x0):min(c + 3, x1 + 1)].any(1))[0]
        if rows.size:
            lower.append((float(c), float(rows.max())))
    lower = np.array(lower)
    # An overhang is not base: a leaning slab's raised tip must not pull the footprint up.
    ys_all = np.nonzero(body)[0]
    floor = ys_all.max() - (ys_all.max() - ys_all.min()) * MAX_BASE_RISE
    lower[:, 1] = np.maximum(lower[:, 1], floor)
    # Smooth out notches between feet, which are not gaps in the base.
    for _ in range(2):
        lower[1:-1, 1] = np.maximum(lower[1:-1, 1], (lower[:-2, 1] + lower[2:, 1]) / 2)
    start, end = lower[0], lower[-1]
    t = (lower[:, 0] - start[0]) / max(end[0] - start[0], 1.0)
    axis = start[1] + (end[1] - start[1]) * t
    # The front follows the real base. The back mirrors it across the left-right axis,
    # going deeper for boulders and cabinets, which have mass behind their front edge.
    minimum = max(MIN_DEPTH_PX, BROAD_DEPTH * (x1 - x0)) if broad else MIN_DEPTH_PX
    depth = np.maximum(lower[:, 1] - axis, minimum * np.sin(np.pi * t.clip(0.08, 0.92)))
    back = np.stack([lower[:, 0], axis - depth], 1)
    return np.concatenate([lower, back[::-1][1:-1]])


def atlas_of(items, max_w=2400, gap=2):
    x = y = shelf = 0
    placed = []
    for item in sorted(items, key=lambda i: -i["art"].shape[0]):
        h, w = item["art"].shape[:2]
        if x + w > max_w:
            x, y, shelf = 0, y + shelf + gap, 0
        placed.append((item, x, y))
        x += w + gap
        shelf = max(shelf, h)
    atlas = np.zeros((y + shelf, max_w, 4), dtype=np.uint8)
    for item, px, py in placed:
        h, w = item["art"].shape[:2]
        atlas[py:py + h, px:px + w] = item["art"]
        item["rect"] = [px, py, w, h]
    return atlas


def main():
    items = []
    for name, table in KINDS.items():
        rows = cut_sheet(SOURCE / f"{name}_sheet.png", table["bands"])
        print(name, [len(r) for r in rows])
        for r, row in enumerate(rows):
            for c, prop in enumerate(row):
                kind = table["except"].get((r, c), table["rows"][r] if r < len(table["rows"]) else "skip")
                if c in table.get("ground_cols", {}).get(r, ()):
                    kind = "ground"
                if kind == "skip":
                    continue
                item = {"name": f"{name}_{r}_{c}", "kind": kind, "art": prop["art"]}
                if kind in ("solid", "thin", "tall"):
                    item["poly"] = tall_foot(prop["art"]) if kind == "tall" else footprint(prop["art"], kind == "solid")
                items.append(item)
    atlas = atlas_of(items)
    out = ROOT / "godot" / "assets" / "sprites" / "props"
    out.mkdir(parents=True, exist_ok=True)
    Image.fromarray(atlas, "RGBA").save(out / "props.png", optimize=True)
    data = []
    for item in items:
        x, y, w, h = item["rect"]
        entry = {"name": item["name"], "kind": item["kind"], "rect": item["rect"]}
        if "poly" in item:
            poly = item["poly"]
            ground = poly.mean(0)
            entry["anchor"] = [round(float(ground[0]), 1), round(float(ground[1]), 1)]
            entry["poly"] = [[round(float(px - ground[0]), 1), round(float(py - ground[1]), 1)] for px, py in poly]
        else:
            entry["anchor"] = [round(w / 2, 1), round(h * 0.92, 1) if item["kind"] == "decor" else round(h / 2, 1)]
        data.append(entry)
    (out / "props.json").write_text(json.dumps({"image": "props.png", "props": data}))
    contact(items)
    print({k: sum(1 for i in items if i["kind"] == k) for k in ("ground", "crater", "decor", "solid", "thin", "tall")}, "atlas", atlas.shape[:2])


def contact(items):
    cols, cell = 12, 240
    rows = len(items) // cols + 1
    img = Image.new("RGBA", (cols * cell, rows * cell), (150, 128, 96, 255))
    d = ImageDraw.Draw(img)
    for i, item in enumerate(items):
        ox, oy = i % cols * cell, i // cols * cell
        art = Image.fromarray(item["art"], "RGBA")
        scale = min(1.0, (cell - 24) / max(art.size))
        art = art.resize((max(1, round(art.width * scale)), max(1, round(art.height * scale))))
        px, py = ox + (cell - art.width) // 2, oy + (cell - art.height) // 2 + 6
        img.alpha_composite(art, (px, py))
        d.text((ox + 3, oy + 2), f"{item['name']} {item['kind']}", fill="white")
        if "poly" in item:
            points = [(px + x * scale, py + y * scale) for x, y in item["poly"]]
            d.polygon(points, outline=(0, 255, 255))
            d.line(points + points[:1], fill=(0, 255, 255), width=2)
    img.convert("RGB").save(ROOT / "art" / "previews" / "props_contact.png")


if __name__ == "__main__":
    main()
