"""Prepare the field, the paved apron and the 12 wall damage frames for Godot.

Usage (from the repo root):  python tools/sprites/fit_background.py

Reads   art/backgrounds/north_gate_field.png, art/sprites/apron.png, art/sprites/wall/frames_*.png
Writes  godot/assets/backgrounds/north_gate_field.jpg and apron.png
        godot/assets/sprites/wall/wall_00.png ... wall_11.png and wall.json
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
WIDTH, HEIGHT = 1080, 2400
ABOVE_BASE, BELOW_BASE = 255, 22   # sheet pixels kept above and below the foot of the wall
SIDE_STRIP = (60, 230)             # part of the wall that survives in every frame


def fit_field(out):
    painting = Image.open(ROOT / "art" / "backgrounds" / "north_gate_field.png").convert("RGB")
    scaled_h = round(painting.height * WIDTH / painting.width)
    paint = np.array(painting.resize((WIDTH, scaled_h), Image.LANCZOS))
    top = (HEIGHT - scaled_h) // 2
    canvas = np.pad(paint, ((top, HEIGHT - scaled_h - top), (0, 0), (0, 0)), mode="symmetric")
    Image.fromarray(canvas).save(out / "north_gate_field.jpg", quality=90, optimize=True)


def cut_apron(out):
    apron = np.array(Image.open(ROOT / "art" / "sprites" / "apron.png").convert("RGBA"))
    ys, xs = np.nonzero(apron[..., 3] > 40)
    Image.fromarray(apron[ys.min():ys.max() + 1, xs.min():xs.max() + 1], "RGBA").save(out / "apron.png", optimize=True)


def wall_bases(sheet):
    profile = (sheet[:, SIDE_STRIP[0]:SIDE_STRIP[1], 3] > 200).sum(1)
    bases, start = [], None
    for y, count in enumerate(profile):
        if count > 120 and start is None:
            start = y
        elif count <= 120 and start is not None:
            if y - start > 40:
                bases.append(y)
            start = None
    if start is not None:
        bases.append(len(profile))
    return bases


def cut_wall():
    out = ROOT / "godot" / "assets" / "sprites" / "wall"
    out.mkdir(parents=True, exist_ok=True)
    index = 0
    rail_above_base = 0.0
    base_ys = []
    for name in ("frames_1_intact.png", "frames_2_destroyed.png"):
        sheet = np.array(Image.open(ROOT / "art" / "sprites" / "wall" / name).convert("RGBA"))
        bases = wall_bases(sheet)
        # One scale per sheet: a frame's own width changes as rubble spills out, so using it would pop.
        band = (sheet[bases[0] - 60:bases[0] - 20, :, 3] > 200).any(0)
        x0, x1 = np.nonzero(band)[0][[0, -1]]
        scale = WIDTH / (x1 - x0 + 1)
        for base in bases:
            y0, y1 = max(0, base - ABOVE_BASE), min(sheet.shape[0], base + BELOW_BASE)
            frame = sheet[y0:y1, x0:x1 + 1].copy()
            frame[frame[..., 3] < 24] = 0
            picture = Image.fromarray(frame, "RGBA").resize((WIDTH, round(frame.shape[0] * scale)), Image.LANCZOS)
            picture.save(out / f"wall_{index:02d}.png", optimize=True)
            base_ys.append(round(float((base - y0) * scale), 1))
            if index == 0:
                middle = frame.shape[1] // 2
                centre = (frame[:, middle - 40:middle + 40, 3] > 200).sum(1)
                rail_above_base = float((base - y0 - np.nonzero(centre > 12)[0][0]) * scale)
            index += 1
    (out / "wall.json").write_text(json.dumps({"frames": index, "base_y": base_ys, "rail_above_base": round(rail_above_base, 1)}))
    print(f"wall: {index} frames, base lines {base_ys}, rail {rail_above_base:.0f} above base")


def main():
    out = ROOT / "godot" / "assets" / "backgrounds"
    out.mkdir(parents=True, exist_ok=True)
    fit_field(out)
    cut_apron(out)
    cut_wall()


if __name__ == "__main__":
    main()
