"""Fit the painted battlefield to the game's screen layout.

Usage (from the repo root):  python tools/sprites/fit_background.py

Reads   art/backgrounds/north_gate_field.webp
Writes  godot/assets/backgrounds/north_gate_field.jpg

The game centres a 1080x2400 background on the screen, so tall phones never see past its
edge. The painting is 16:9, so it is placed on that canvas with its gate where the game's
gate is, and its edges are mirrored outward.
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
WIDTH, HEIGHT = 1080, 2400

# Lines the painted ground just north of the wall up with where monsters stand attacking
# the gate, in 1080-wide pixels: painted line y=1311, game's gate line y=1224 on a 1920 screen.
SHIFT_UP = 87


def main():
    painting = Image.open(ROOT / "art" / "backgrounds" / "north_gate_field.webp").convert("RGB")
    scaled_h = round(painting.height * WIDTH / painting.width)
    paint = np.array(painting.resize((WIDTH, scaled_h), Image.LANCZOS))
    top = (HEIGHT - scaled_h) // 2 - SHIFT_UP
    canvas = np.pad(paint, ((top, HEIGHT - scaled_h - top), (0, 0), (0, 0)), mode="symmetric")
    out = ROOT / "godot" / "assets" / "backgrounds" / "north_gate_field.jpg"
    out.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(canvas).save(out, quality=90, optimize=True)
    print(f"{out.name}: {canvas.shape[1]}x{canvas.shape[0]}, painting at y={top}")


if __name__ == "__main__":
    main()
