"""Cut painted props out of their flat backgrounds for Godot.

Usage (from the repo root):  python tools/sprites/extract_props.py

Reads   art/sprites/props/*.png  (one prop per image on a flat pale background)
Writes  godot/assets/sprites/props/<name>.png, trimmed, with transparent backgrounds
"""
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
WORK_SIZE = 512
BACKGROUND_TOLERANCE = 34  # how far a pixel can stray from the backdrop colour and still be backdrop
NAMES = {
    "P01_broken_wall": "broken_wall",
    "P02_rock_cluster": "rocks",
    "P03_concrete_barrier": "barrier",
    "P04_rubble_pile": "rubble",
    "P05_utility_cabinet": "cabinet",
    "C02_crater_open": "crater",
}


def backdrop_mask(rgb):
    """Everything connected to the image border that is close to the backdrop colour."""
    h, w = rgb.shape[:2]
    corners = np.array([rgb[2, 2], rgb[2, -3], rgb[-3, 2], rgb[-3, -3]], dtype=float)
    near = np.abs(rgb.astype(float) - np.median(corners, axis=0)).max(2) < BACKGROUND_TOLERANCE
    seen = np.zeros((h, w), dtype=bool)
    queue = deque()
    for x in range(w):
        for y in (0, h - 1):
            if near[y, x] and not seen[y, x]:
                seen[y, x] = True
                queue.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if near[y, x] and not seen[y, x]:
                seen[y, x] = True
                queue.append((y, x))
    while queue:
        y, x = queue.popleft()
        for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
            if 0 <= ny < h and 0 <= nx < w and near[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                queue.append((ny, nx))
    return seen


def main():
    source = ROOT / "art" / "sprites" / "props"
    out = ROOT / "godot" / "assets" / "sprites" / "props"
    out.mkdir(parents=True, exist_ok=True)
    for stem, name in NAMES.items():
        image = Image.open(source / f"{stem}.png").convert("RGB").resize((WORK_SIZE, WORK_SIZE), Image.LANCZOS)
        rgb = np.array(image)
        solid = Image.fromarray((~backdrop_mask(rgb)).astype(np.uint8) * 255, "L")
        # Soften and pull in the edge slightly, so no pale backdrop rim is left around the prop.
        soft = np.array(solid.filter(ImageFilter.GaussianBlur(1.2))).astype(float) / 255.0
        alpha = np.clip((soft - 0.5) * 2.0, 0, 1)
        rgba = np.dstack([rgb, (alpha * 255).astype(np.uint8)])
        ys, xs = np.nonzero(rgba[..., 3])
        cropped = rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        Image.fromarray(cropped, "RGBA").save(out / f"{name}.png", optimize=True)
        print(f"{name}: {cropped.shape[1]}x{cropped.shape[0]}")


if __name__ == "__main__":
    main()
