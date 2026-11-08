"""Turn a turret sprite sheet into one atlas + JSON for Godot.

Usage (from the repo root):  python tools/sprites/extract_turret.py kestrel

Reads   art/sprites/<kit>/sheet.png  (4 rows: 14 aim, 14 fire, 14 recoil, 12 destroy)
Writes  godot/assets/sprites/turrets/<kit>.png and <kit>.json
        art/previews/<kit>_contact.png

The base is the part that never moves, so every frame is lined up on it.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

from extract_kit import contact_sheet, luma_alpha, pack

ROOT = Path(__file__).resolve().parents[2]
ROWS = [("aim", 20, 182, 14), ("fire", 215, 355, 14), ("recoil", 393, 525, 14), ("destroy", 539, 700, 12)]
CANVAS_W, CANVAS_H = 340, 240
BASE_X, BASE_BOTTOM = 170, 212
GROUND_ABOVE_BOTTOM = 26  # the base's centre sits this far above its front edge
ALPHA_FLOOR = 48  # background removal left a faint coloured fringe below this
BASE_BAND = 0.4  # lower share of each row that holds only the base


def defringe(sheet):
    out = sheet.astype(float)
    a = out[..., 3]
    out[..., 3] = np.clip((a - ALPHA_FLOOR) * 255.0 / (255.0 - ALPHA_FLOOR), 0, 255)
    out[out[..., 3] <= 0] = 0
    return out


def spans(profile, gap=5):
    out, start, last = [], None, None
    for i, v in enumerate(profile):
        if v:
            if start is None:
                start = i
            last = i
        elif start is not None and i - last >= gap:
            out.append((start, last + 1))
            start = None
    if start is not None:
        out.append((start, last + 1))
    return out


def base_spans(band, count):
    found = [s for s in spans((band[..., 3] > 120).sum(0) > 0) if s[1] - s[0] > 40]
    if len(found) != count:
        raise SystemExit(f"expected {count} turret bases in a row, found {len(found)}")
    return found


def base_refine(ref, frame, top, search=5):
    target = luma_alpha(ref)[top:]
    source = luma_alpha(frame)
    best, best_score = (0, 0), float("inf")
    for dy in range(-search, search + 1):
        for dx in range(-search, search + 1):
            score = np.abs(target - np.roll(np.roll(source, dy, 0), dx, 1)[top:]).mean()
            if score < best_score:
                best, best_score = (dx, dy), score
    return best


def row_frames(sheet, y0, y1, count):
    h = y1 - y0
    band = sheet[y1 - int(h * BASE_BAND):y1]
    bases = base_spans(band, count)
    solid_rows = np.nonzero((band[..., 3] > 200).sum(1) > 20)[0]
    bottom = y1 - int(h * BASE_BAND) + int(solid_rows.max())
    cells = []
    for i, (bx0, bx1) in enumerate(bases):
        # A muzzle flash may reach past its cell, but never into the next turret's base.
        left = bases[i - 1][1] + 1 if i else 0
        right = bases[i + 1][0] - 1 if i + 1 < count else sheet.shape[1]
        centre = (bx0 + bx1) // 2
        x0 = BASE_X - (centre - left)
        canvas = np.zeros((CANVAS_H, CANVAS_W, 4))
        top_src = y0
        y_off = BASE_BOTTOM - (bottom - top_src)
        crop = sheet[top_src:y1, left:right]
        ch, cw = crop.shape[:2]
        sx = max(0, -x0)
        sy = max(0, -y_off)
        w = min(cw - sx, CANVAS_W - max(x0, 0))
        hh = min(ch - sy, CANVAS_H - max(y_off, 0))
        canvas[max(y_off, 0):max(y_off, 0) + hh, max(x0, 0):max(x0, 0) + w] = crop[sy:sy + hh, sx:sx + w]
        cells.append(canvas)
    width = float(np.median([b - a for a, b in bases[:3]]))
    return cells, width


def main(kit):
    sheet = defringe(np.array(Image.open(ROOT / "art" / "sprites" / kit / "sheet.png").convert("RGBA")))
    frames = {}
    reference = None
    ref_width = None
    for name, y0, y1, count in ROWS:
        cells, width = row_frames(sheet, y0, y1, count)
        if reference is None:
            reference = cells[0]
            ref_width = width
        scale = ref_width / width
        locked = []
        for c in cells:
            dx, dy = base_refine(cells[0] if name != "aim" else reference, c, BASE_BOTTOM - 60)
            locked.append(np.roll(np.roll(c, dy, 0), dx, 1))
        frames[name] = [(c, BASE_X, BASE_BOTTOM - GROUND_ABOVE_BOTTOM, scale, 0.0) for c in locked]
    atlas, anims = pack(frames)
    out = ROOT / "godot" / "assets" / "sprites" / "turrets"
    out.mkdir(parents=True, exist_ok=True)
    Image.fromarray(atlas, "RGBA").save(out / f"{kit}.png", optimize=True)
    (out / f"{kit}.json").write_text(json.dumps({"image": f"{kit}.png", "anims": anims}))
    contact_sheet(atlas, anims, ROOT / "art" / "previews" / f"{kit}_contact.png")
    print(f"{kit}: {sum(len(a['frames']) for a in anims.values())} frames, atlas {atlas.shape[1]}x{atlas.shape[0]}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "kestrel")
