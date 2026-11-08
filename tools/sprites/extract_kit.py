"""Turn a monster's six 256px sprite sheets into one atlas + JSON for Godot.

Usage (from the repo root):  python tools/sprites/extract_kit.py burrower

Reads   art/sprites/<kit>/{A_walk_front,B_walk_rear,C_walk_turn,D_emerge,E_attack,F_death}.png
Writes  godot/assets/sprites/monsters/<kit>.png and <kit>.json
        art/previews/<kit>_contact.png (every frame on its ground anchor, for checking)

The row tables say what each row actually shows, which differs from what the sheets
were requested to show. Check the contact sheet when processing a new kit.
"""
import json
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
CELL = 256
KEY = np.array([1.0, 248.0, 3.0])

ATLAS_SCALE = 0.75  # atlas pixels per sheet pixel
TARGET_AREA = 15000.0  # solid pixels every standing pose is scaled to match
FOOT_LIMIT = 4.0  # sheet pixels a walk frame may move to reach the ground line
SHADOW_WIDTH = 0.82  # engine shadow width as a share of body width

WALK_ROWS = [
    # Sheet A was requested as S/SSE/SE/ESE, but rows 1-3 all face left.
    ("A_walk_front", 0, "walk_S"),
    ("A_walk_front", 1, "walk_SSW"),
    ("A_walk_front", 2, "walk_SW"),
    ("A_walk_front", 3, "walk_WSW"),
    ("B_walk_rear", 0, "walk_E"),
    ("B_walk_rear", 1, "walk_ENE"),
    ("B_walk_rear", 2, "walk_NE"),
    ("B_walk_rear", 3, "walk_NNE"),
]
# Columns 1-6 only: columns 0 and 7 are copies of walk frames in a different view.
# Sheet E was requested as S/SE/E: row 1 came back as the side view, row 2 faces down-left.
ATTACK_ROWS = [("attack_S", 0), ("attack_E", 1), ("attack_SW", 2)]
DEATH_ROWS = [("death_S", 0), ("death_E", 1)]


def unmix(sheet):
    """Flatten onto the key colour, then solve C = a*F + (1-a)*Key.

    Green shadow turns into black with alpha, and green fringe into nothing.
    """
    rgb = sheet[..., :3].astype(float)
    a0 = sheet[..., 3:4].astype(float) / 255.0
    flat = rgb * a0 + KEY * (1 - a0)
    r, g, b = flat[..., 0], flat[..., 1], flat[..., 2]
    alpha = np.clip(1.0 - (g - np.maximum(r, b)) / 238.0, 0, 1)
    alpha[alpha < 0.07] = 0
    alpha[alpha > 0.93] = 1

    # Olive tints inside the body are paint, not transparency: fill them back in.
    solid = alpha > 0.85
    near = sum(np.roll(np.roll(solid, dy, 0), dx, 1).astype(int)
               for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx)
    alpha[(alpha > 0.6) & (near >= 6)] = 1

    a = np.maximum(alpha, 1e-3)[..., None]
    fg = np.clip((flat - (1 - alpha[..., None]) * KEY) / a, 0, 255)
    limit = np.maximum(fg[..., 0], fg[..., 2]) * 1.04
    fg[..., 1] = np.minimum(fg[..., 1], limit)
    return np.dstack([fg, alpha * 255])


def components(mask):
    """4-connected labelling, returns a list of pixel index arrays."""
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


def clean(cell, min_area=4):
    """Drop stray specks far from the main body."""
    comps = components(cell[..., 3] > 25)
    if not comps:
        return cell
    main = max(comps, key=len)
    top, bottom = main[:, 0].min(), main[:, 0].max()
    keep = np.zeros(cell.shape[:2], dtype=bool)
    for c in comps:
        if len(c) >= min_area and c[:, 0].max() >= top - 22 and c[:, 0].min() <= bottom + 12:
            keep[c[:, 0], c[:, 1]] = True
    out = cell.copy()
    out[~keep] = 0
    return out


def strip_shadow(cell):
    """Remove the painted shadow under the body. The engine draws one consistent shadow."""
    r, g, b, a = cell[..., 0], cell[..., 1], cell[..., 2], cell[..., 3]
    ys = np.nonzero(a > 240)[0]
    mid = (int(ys.min()) + int(ys.max())) // 2
    dark = ((r + g + b) / 3 < 45) & (a < 235)
    dark[:mid] = False
    out = cell.copy()
    out[dark] = 0
    return out


def area(cell):
    return float((cell[..., 3] > 240).sum())


def solid_width(cell):
    xs = np.nonzero(cell[..., 3] > 240)[1]
    return float(xs.max() - xs.min())


def size_to_target(a):
    """Scale that gives a body of solid area `a` the same visual mass as every other row."""
    return float(np.sqrt(TARGET_AREA / a))


def foot_line(cell):
    """Lowest row with a run of brown pixels: the planted feet, ignoring claw tips and slashes."""
    r, g, b, a = cell[..., 0], cell[..., 1], cell[..., 2], cell[..., 3]
    lum = (r + g + b) / 3
    brown = (a > 200) & (r > b + 14) & (lum < 150) & (lum > 22)
    return float(np.nonzero(brown.sum(1) >= 6)[0].max())


def luma_alpha(cell):
    return cell[..., :3].mean(2) * (cell[..., 3] / 255.0)


def shell_shift(ref, frame, top_frac=0.6, search=7):
    """Best (dx, dy) moving `frame` onto `ref`, scored on the upper body only so
    leg motion survives and only frame-to-frame slide is removed."""
    h = int(ref.shape[0] * top_frac)
    target = ref[:h]
    best, best_score = (0, 0), float("inf")
    for dy in range(-search, search + 1):
        for dx in range(-search, search + 1):
            score = np.abs(target - np.roll(np.roll(frame, dy, 0), dx, 1)[:h]).mean()
            if score < best_score:
                best, best_score = (dx, dy), score
    return best


def lock_shell(cells):
    ref = luma_alpha(cells[0])
    out = []
    for c in cells:
        dx, dy = shell_shift(ref, luma_alpha(c))
        out.append(np.roll(np.roll(c, dy, 0), dx, 1))
    return out


def trim(cell, pad=1):
    ys, xs = np.nonzero(cell[..., 3] > 0)
    y0, y1 = max(ys.min() - pad, 0), min(ys.max() + pad + 1, cell.shape[0])
    x0, x1 = max(xs.min() - pad, 0), min(xs.max() + pad + 1, cell.shape[1])
    return cell[y0:y1, x0:x1], x0, y0


def resize(cell, factor):
    """Lanczos on premultiplied colour, so no dark or bright halo at the edges."""
    a = cell[..., 3:4] / 255.0
    pre = np.dstack([cell[..., :3] * a, cell[..., 3]])
    h, w = pre.shape[:2]
    size = (max(1, round(w * factor)), max(1, round(h * factor)))
    bands = [
        np.array(Image.fromarray(pre[..., i].astype(np.float32), "F").resize(size, Image.LANCZOS))
        for i in range(4)
    ]
    out = np.dstack(bands)
    alpha = np.clip(out[..., 3], 0, 255)
    safe = np.maximum(alpha / 255.0, 1e-3)[..., None]
    return np.dstack([np.clip(out[..., :3] / safe, 0, 255), alpha])


def grounded(cells):
    """Feet on one ground line, with a small limit so an odd frame cannot jolt the shell."""
    lines = [foot_line(c) for c in cells]
    median = float(np.median(lines))
    width = float(np.median([solid_width(c) for c in cells])) * SHADOW_WIDTH
    row = size_to_target(float(np.median([area(c) for c in cells])))
    out = []
    for c, line in zip(cells, lines):
        ay = float(np.clip(line, median - FOOT_LIMIT, median + FOOT_LIMIT))
        scale = float(np.clip(size_to_target(area(c)), row * 0.95, row * 1.05))
        out.append((c, CELL / 2, ay, scale, width))
    return out


def build_frames(folder):
    sheets = {p.stem: unmix(np.array(Image.open(p).convert("RGBA"))) for p in sorted(folder.glob("*.png"))}

    def cell(sheet, row, col, keep_shadow=False):
        raw = sheets[sheet][row * CELL:(row + 1) * CELL, col * CELL:(col + 1) * CELL]
        return clean(raw if keep_shadow else strip_shadow(raw))

    frames = {}  # name -> list of (cell, ax, ay, scale, shadow width)

    for sheet, row, name in WALK_ROWS:
        frames[name] = grounded(lock_shell([cell(sheet, row, c) for c in range(8)]))

    # Sheet C's three rows make a turntable once their odd end frames are dropped:
    # row 0 turns S to W, row 1 columns 1-6 turn W to N, row 2 columns 2-6 turn N to E.
    frames["pivot"] = grounded([cell("C_walk_turn", 0, c) for c in range(8)])
    frames["turn_wn"] = grounded([cell("C_walk_turn", 1, c) for c in range(1, 7)])
    frames["turn_ne"] = grounded([cell("C_walk_turn", 2, c) for c in range(2, 7)])

    for name, row in ATTACK_ROWS:
        strip = [cell("E_attack", row, c) for c in range(1, 7)]
        # Judge size on the frames before the slash, which would count as body area.
        scale = size_to_target(float(np.median([area(c) for c in strip[:3]])))
        width = float(np.median([solid_width(c) for c in strip[:3]])) * SHADOW_WIDTH
        frames[name] = [(c, CELL / 2, foot_line(c), scale, width) for c in strip]

    for name, row in DEATH_ROWS:
        strip = [cell("F_death", row, c) for c in range(10)]
        # The first two frames are the standing body; after that it really does shrink.
        scales = [size_to_target(area(strip[0])), size_to_target(area(strip[1]))]
        scales += [scales[1]] * 8
        frames[name] = [(c, CELL / 2, foot_line(c), s, solid_width(c) * SHADOW_WIDTH) for c, s in zip(strip, scales)]

    emerge = [cell("D_emerge", r, c, keep_shadow=True) for r in range(2) for c in range(6)]
    ys = np.nonzero(emerge[0][..., 3] > 120)[0]
    hole_y = (ys.min() + ys.max()) / 2.0
    # From frame 9 the body is out of the soil: remove its shadow and treat it like the walk.
    for i in range(8, 12):
        emerge[i] = clean(strip_shadow(emerge[i]))
    grow_to = size_to_target(area(emerge[8]))
    frames["emerge"] = []
    for i, c in enumerate(emerge):
        t = float(np.clip((i - 4) / 4.0, 0, 1))
        ay = hole_y + (foot_line(c) - hole_y) * t
        scale = size_to_target(area(c)) if i >= 8 else 1.0 + (grow_to - 1.0) * float(np.clip((i - 4) / 3.0, 0, 1))
        width = solid_width(c) * SHADOW_WIDTH if i >= 8 else 0.0
        frames["emerge"].append((c, CELL / 2, ay, scale, width))
    return frames


def pack(frames, max_w=2600, gap=2):
    entries = []
    for name, seq in frames.items():
        for idx, (cell, ax, ay, scale, sh) in enumerate(seq):
            t, x0, y0 = trim(cell)
            factor = ATLAS_SCALE * scale
            entries.append((name, idx, resize(t, factor), (ax - x0) * factor, (ay - y0) * factor, sh * factor))

    x = y = shelf = 0
    placed = []
    for e in sorted(entries, key=lambda e: -e[2].shape[0]):
        h, w = e[2].shape[:2]
        if x + w > max_w:
            x, y, shelf = 0, y + shelf + gap, 0
        placed.append((e, x, y))
        x += w + gap
        shelf = max(shelf, h)
    atlas = np.zeros((y + shelf, max_w, 4), dtype=np.uint8)
    anims = {n: {"frames": [None] * len(s)} for n, s in frames.items()}
    for (name, idx, t, ax, ay, sh), x, y in placed:
        h, w = t.shape[:2]
        atlas[y:y + h, x:x + w] = t.round().astype(np.uint8)
        anims[name]["frames"][idx] = {
            "x": x, "y": y, "w": w, "h": h,
            "ax": round(float(ax), 1), "ay": round(float(ay), 1), "sh": round(float(sh), 1),
        }
    return atlas, anims


def contact_sheet(atlas, anims, path):
    cw, ch = 165, 165
    img = Image.new("RGBA", (cw * 12 + 90, ch * len(anims)), (150, 128, 96, 255))
    d = ImageDraw.Draw(img)
    src = Image.fromarray(atlas, "RGBA")
    for r, (name, anim) in enumerate(anims.items()):
        d.text((4, r * ch + 70), name, fill="white")
        for c, f in enumerate(anim["frames"]):
            ox, oy = 90 + c * cw + cw // 2, r * ch + ch - 22
            spr = src.crop((f["x"], f["y"], f["x"] + f["w"], f["y"] + f["h"]))
            img.alpha_composite(spr, (int(ox - f["ax"]), int(oy - f["ay"])))
            d.line((ox - 6, oy, ox + 6, oy), fill="cyan")
            d.line((ox, oy - 6, ox, oy + 6), fill="cyan")
    img.convert("RGB").save(path)


def main(kit):
    atlas, anims = pack(build_frames(ROOT / "art" / "sprites" / kit))
    out = ROOT / "godot" / "assets" / "sprites" / "monsters"
    out.mkdir(parents=True, exist_ok=True)
    Image.fromarray(atlas, "RGBA").save(out / f"{kit}.png", optimize=True)
    (out / f"{kit}.json").write_text(json.dumps({"image": f"{kit}.png", "anims": anims}))
    contact_sheet(atlas, anims, ROOT / "art" / "previews" / f"{kit}_contact.png")
    print(f"{kit}: {sum(len(a['frames']) for a in anims.values())} frames, atlas {atlas.shape[1]}x{atlas.shape[0]}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "burrower")
