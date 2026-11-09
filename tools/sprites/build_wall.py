"""Bake monotonic HP stages and a registered, layered fourteen-frame gate breach.

The approved painted doors/lintel supply the visible front surfaces. Generated
damaged door backs supply the surfaces exposed as the panels fall toward camera.
Side walls are sampled once. All motion is authored about fixed world landmarks.
"""
import hashlib
import json
import math
import shutil
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw

from build_pending_kits import source_cells
from fit_background import cut_wall

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art/sprites/wall"
OUTPUT = ROOT / "godot/assets/sprites/wall"
SIZE = (1080, 540)
TOP = 80
SECTION = (270, 810)
STAGES = [0, 1, 2, 4, 5]
ANGLES = [0, 3, 8, 16, 28, 43, 59, 75, 88, 90, 90, 90, 90, 90]
DOORS = [([(388, 150), (536, 166), (536, 301), (384, 293)], -1),
         ([(549, 166), (688, 150), (697, 293), (550, 301)], 1)]
BEAM = [(375, 20), (480, 65), (540, 75), (630, 55), (710, 20),
        (710, 135), (630, 164), (540, 178), (450, 164), (375, 135)]


def masked(image, polygon):
    mask = Image.new("L", image.size)
    ImageDraw.Draw(mask).polygon(polygon, fill=255)
    result = image.copy()
    result.putalpha(ImageChops.multiply(result.getchannel("A"), mask))
    return result


def opacity(image, amount):
    result = image.copy()
    result.putalpha(result.getchannel("A").point(lambda value: round(value * amount)))
    return result


def project(image, source_quad, target_quad):
    # Pillow maps destination pixels back into the immutable painted source.
    equations, values = [], []
    for (x, y), (u, v) in zip(target_quad, source_quad):
        equations.extend([[x, y, 1, 0, 0, 0, -u * x, -u * y],
                          [0, 0, 0, x, y, 1, -v * x, -v * y]])
        values.extend([u, v])
    coefficients = np.linalg.solve(np.array(equations), np.array(values))
    return image.transform(SIZE, Image.Transform.PERSPECTIVE, coefficients,
                           Image.Resampling.BICUBIC)


def door_target(quad, angle, side):
    radians = math.radians(angle)
    result = []
    for x, y in quad:
        height = 302 - y
        forward = height * (0.643 / 0.766) * math.sin(radians)
        fall = -height * math.cos(radians) + forward
        splay = side * 12 * angle / 90 * height / 152
        result.append((x + splay, TOP + 302 + fall))
    return result


def beam_target(quad, index, progress):
    center = np.mean(quad, axis=0)
    target = [(445, 345), (540, 365), (630, 350)][index]
    rotation = math.radians([-14, 6, 18][index] * progress)
    output = []
    for x, y in quad:
        dx, dy = x - center[0], (y - center[1]) * (1 - .78 * progress)
        output.append((center[0] + (target[0] - center[0]) * progress
                       + dx * math.cos(rotation) - dy * math.sin(rotation),
                       TOP + center[1] + (target[1] - center[1]) * progress
                       + dx * math.sin(rotation) + dy * math.cos(rotation)))
    return output


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

    failing = Image.open(legacy_folder / "wall_05.png").convert("RGBA")
    fixed = damage[-1].copy()
    ImageDraw.Draw(fixed).rectangle((382, TOP, 706, TOP + 309), fill=(0, 0, 0, 0))
    fronts = [masked(failing, quad) for quad, _ in DOORS]
    back_cells = source_cells(SOURCE / "door_backs_raw.png", {
        "grid": [2, 1], "alpha_floor": 48, "main_component": True})
    backs = []
    for cell, (quad, _) in zip(back_cells, DOORS):
        x0, y0 = np.min(quad, axis=0)
        x1, y1 = np.max(quad, axis=0)
        texture = cell.crop(cell.getbbox()).resize((int(x1 - x0), int(y1 - y0)), Image.Resampling.LANCZOS)
        layer = Image.new("RGBA", failing.size)
        layer.paste(texture, (int(x0), int(y0)))
        backs.append(masked(layer, quad))
    beam = masked(failing, BEAM)
    beam_parts = []
    for left, right in [(375, 490), (490, 590), (590, 710)]:
        quad = [(left, 20), (right, 20), (right, 178), (left, 178)]
        beam_parts.append((masked(beam, quad), quad))
    dust = source_cells(SOURCE / "dust_raw.png", {"grid": [3, 2], "alpha_floor": 32})
    for index, cloud in enumerate(dust):
        pixels = np.array(cloud)
        horizontal = np.minimum(np.arange(cloud.width), np.arange(cloud.width)[::-1]) / 24.0
        vertical = np.minimum(np.arange(cloud.height), np.arange(cloud.height)[::-1]) / 24.0
        feather = np.clip(np.minimum(vertical[:, None], horizontal[None, :]), 0, 1)
        pixels[:, :, 3] = np.round(pixels[:, :, 3] * feather)
        dust[index] = Image.fromarray(pixels)
    rubble_source = Image.open(legacy_folder / "wall_11.png").convert("RGBA")
    rubble = Image.new("RGBA", SIZE)
    shift = round(float(legacy["base_y"][0]) - float(legacy["base_y"][11]))
    rubble.paste(rubble_source.crop((380, 260, 700, rubble_source.height)), (380, TOP + 260 + shift))
    breach = []
    for index, angle in enumerate(ANGLES):
        frame = fixed.copy()
        for side_index, (quad, side) in enumerate(DOORS):
            projected_height = math.cos(math.radians(angle)) - (0.643 / 0.766) * math.sin(math.radians(angle))
            texture = fronts[side_index] if projected_height >= 0 else backs[side_index]
            frame.alpha_composite(project(texture, quad, door_target(quad, angle, side)))
        progress = min(1, max(0, (index - 1) / 7))
        for part_index, (part, quad) in enumerate(beam_parts):
            frame.alpha_composite(project(part, quad, beam_target(quad, part_index, progress)))
        frame.alpha_composite(opacity(rubble, min(1, max(0, (index - 4) / 5))))
        if 6 <= index <= 12:
            dust_index = min(index - 6, 5)
            cloud = dust[dust_index].resize((589, 589), Image.Resampling.LANCZOS)
            origin_y = 430 if dust_index < 3 else 390
            frame.alpha_composite(opacity(cloud, [.20, .32, .45, .36, .24, .12][dust_index]),
                                  (246, round(TOP + 350 + (index - 6) * 4 - origin_y * 1.15)))
        if index == 0:
            frame = damage[-1].copy()
        frame.save(OUTPUT / f"breach_{index:02d}.png")
        breach.append(frame)

    data = dict(frames=len(damage), damage_frames=[f"damage_{i:02d}.png" for i in range(len(damage))],
                side_texture="sides.png", base_y=float(legacy["base_y"][0]) + TOP,
                top_padding=TOP, rail_above_base=legacy["rail_above_base"],
                breach_frames=[f"breach_{i:02d}.png" for i in range(len(breach))],
                breach_frame_ms=100, charge_after=.9, burst_frames=[1, 3, 5, 7], impact_frame=8)
    (OUTPUT / "wall.json").write_text(json.dumps(data, indent=2))
    manifest = dict(damage_sources=STAGES, door_angles=ANGLES, section=SECTION, top_padding=TOP,
                    baseline=data["base_y"], source_sha256={name: hashlib.sha256((SOURCE / name).read_bytes()).hexdigest()
                    for name in ["approved_wall_00.png", "dust_raw.png", "door_backs_raw.png"]})
    (SOURCE / "build.json").write_text(json.dumps(manifest, indent=2))
    review(sides, damage, "damage")
    review(sides, breach, "breach")
    print("PASS intact/side pixels preserved; five HP stages; fourteen breach frames; fixed baseline", data["base_y"])


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
