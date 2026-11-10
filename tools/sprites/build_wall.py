"""Bake monotonic HP stages and a registered, layered fifteen-frame gate breach.

The collapse is an authored painted sequence, registered to fixed pillar feet.
The approved five HP stages and static side walls remain unchanged.
"""
import hashlib
import json
import math
import shutil
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from fit_background import cut_wall
from bake_authored_breach import bake, SCALE, PIVOT, ORDER

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art/sprites/wall"
OUTPUT = ROOT / "godot/assets/sprites/wall"
SIZE = (1080, 540)
TOP = 80
SECTION = (270, 810)
STAGES = [0, 1, 2, 4, 5]


def build_wall():
    legacy_folder = SOURCE / "evidence/legacy"
    cut_wall(legacy_folder)
    legacy = json.loads((legacy_folder / "wall.json").read_text())
    intact = Image.open(legacy_folder / "wall_00.png").convert("RGBA")
    approved = Image.open(SOURCE / "approved_wall_00.png").convert("RGBA")
    assert np.array_equal(np.array(intact), np.array(approved)), "Approved wall_00 changed"
    shutil.copyfile(SOURCE / "approved_wall_00.png", OUTPUT / "wall_00.png")
    sides = Image.new("RGBA", SIZE)
    sides.paste(intact, (0, TOP))
    ImageDraw.Draw(sides).rectangle((SECTION[0], 0, SECTION[1] - 1, SIZE[1]), fill=(0, 0, 0, 0))
    sides.save(OUTPUT / "sides.png")
    damage = []
    for index, old_index in enumerate(STAGES):
        source = Image.open(legacy_folder / f"wall_{old_index:02d}.png").convert("RGBA")
        frame = Image.new("RGBA", SIZE)
        frame.paste(source.crop((SECTION[0], 0, SECTION[1], source.height)), (SECTION[0], TOP))
        frame.save(OUTPUT / f"damage_{index:02d}.png")
        damage.append(frame)
    reconstructed = sides.copy()
    reconstructed.paste(damage[0].crop((SECTION[0], TOP, SECTION[1], TOP + intact.height)),
                        (SECTION[0], TOP))
    assert np.array_equal(np.array(reconstructed.crop((0, TOP, 1080, TOP + intact.height))),
                          np.array(approved)), "Intact composition changed"

    breach = bake(damage[-1], SIZE)
    for index, frame in enumerate(breach):
        frame.save(OUTPUT / f"breach_{index:02d}.png")

    data = dict(frames=len(damage), damage_frames=[f"damage_{i:02d}.png" for i in range(len(damage))],
                side_texture="sides.png", base_y=float(legacy["base_y"][0]) + TOP,
                top_padding=TOP, rail_above_base=legacy["rail_above_base"],
                breach_frames=[f"breach_{i:02d}.png" for i in range(len(breach))],
                breach_frame_ms=100, charge_after=.9, burst_frames=[3, 4, 5, 6], impact_frame=7)
    (OUTPUT / "wall.json").write_text(json.dumps(data, indent=2))
    manifest = dict(damage_sources=STAGES, method="authored frame sequence", section=SECTION, top_padding=TOP,
                    baseline=data["base_y"], source_scale=SCALE, source_pivot=PIVOT,
                    painted_order=ORDER, alpha_floor=24, entry="damage_04.png",
                    held_pose=14, source_sha256={name: hashlib.sha256((SOURCE / name).read_bytes()).hexdigest()
                    for name in ["approved_wall_00.png", "collapse_authored_raw.png"]})
    (SOURCE / "build.json").write_text(json.dumps(manifest, indent=2))
    review(sides, damage, "damage")
    review(sides, breach, "breach")
    print("PASS intact/side pixels preserved; five HP stages; fifteen breach frames; fixed baseline", data["base_y"])


def review(sides, frames, name):
    folder = SOURCE / "evidence"
    folder.mkdir(exist_ok=True)
    sheet = Image.new("RGBA", (1080 * 2, 540 * math.ceil(len(frames) / 2)))
    field_sheet = Image.new("RGBA", (1200, sheet.height))
    background = Image.open(ROOT / "godot/assets/backgrounds/north_gate_field.jpg").convert("RGBA").crop((0, 1479, 1080, 2019))
    apron = Image.open(ROOT / "godot/assets/backgrounds/apron.png").convert("RGBA")
    apron = apron.resize((round(apron.width * .95), round(apron.height * .95)), Image.Resampling.LANCZOS)
    background.alpha_composite(apron, (round(540 - apron.width / 2), 359))
    contact = Image.new("RGB", (1080, 270 * math.ceil(len(frames) / 2)), (111, 100, 80))
    rectangles = []
    field_rectangles = []
    for index, frame in enumerate(frames):
        x, y = index % 2 * 1080, index // 2 * 540
        sheet.paste(frame, (x, y))
        composite = background.copy()
        composite.alpha_composite(sides)
        composite.alpha_composite(frame)
        reduced = composite.resize((540, 270), Image.Resampling.LANCZOS)
        contact.paste(reduced, (x // 2, y // 2), reduced)
        field_sheet.paste(composite.crop((240, 0, 840, 540)), (index % 2 * 600, y))
        ImageDraw.Draw(contact).text((x // 2 + 10, y // 2 + 8), f"{name} {index}", fill="white")
        rectangles.append(dict(id=f"{name}/{index}", rect=dict(x=x, y=y, w=1080, h=540),
                               anchor=dict(x=540, y=392.6), durationMs=100 if name == "breach" else 500))
        field_rectangles.append(dict(id=f"{name}/{index}", rect=dict(x=index % 2 * 600, y=y, w=600, h=540),
                                     anchor=dict(x=300, y=392.6), durationMs=100 if name == "breach" else 500))
    sheet.save(folder / f"{name}_sheet.png")
    field_sheet.save(folder / f"{name}_field_sheet.png")
    contact.save(folder / f"{name}_contact.png")
    (folder / f"{name}.frames.json").write_text(json.dumps(rectangles, indent=2))
    (folder / f"{name}-field.frames.json").write_text(json.dumps(field_rectangles, indent=2))


if __name__ == "__main__":
    build_wall()
