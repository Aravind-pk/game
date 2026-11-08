"""Make the UI card portraits for units that have a sprite kit.

Usage (from the repo root):  python tools/sprites/make_portraits.py

Writes godot/assets/ui/art/<model>.png from a frame of each unit's atlas.
"""
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
PORTRAIT_WIDTH = 440
# atlas folder, kit, animation, frame, portrait file
PORTRAITS = [
    ("turrets", "kestrel", "aim", 2, "kestrel"),
    ("monsters", "burrower", "walk_SW", 0, "shale_digger"),
]


def main():
    for folder, kit, anim, index, name in PORTRAITS:
        base = ROOT / "godot" / "assets" / "sprites" / folder / kit
        f = json.loads(base.with_suffix(".json").read_text())["anims"][anim]["frames"][index]
        frame = Image.open(base.with_suffix(".png")).convert("RGBA").crop((f["x"], f["y"], f["x"] + f["w"], f["y"] + f["h"]))
        height = round(frame.height * PORTRAIT_WIDTH / frame.width)
        frame.resize((PORTRAIT_WIDTH, height), Image.LANCZOS).save(ROOT / "godot" / "assets" / "ui" / "art" / f"{name}.png", optimize=True)
        print(name, PORTRAIT_WIDTH, height)


if __name__ == "__main__":
    main()
