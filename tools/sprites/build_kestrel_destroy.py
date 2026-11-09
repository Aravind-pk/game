"""Replace Kestrel destruction while preserving all approved aim/base pixels and metadata."""
import copy
import json
from pathlib import Path

import numpy as np
from PIL import Image

from build_pending_kits import source_cells

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art/sprites/kestrel_v3"
OUTPUT = ROOT / "godot/assets/sprites/turrets"


def main():
    baseline = Image.open(SOURCE / "kestrel-atlas-v3.png").convert("RGBA")
    data = json.loads((SOURCE / "kestrel-atlas-v3.json").read_text())
    cells = source_cells(SOURCE / "destroy_heads_raw.png", {
        "grid": [4, 2], "alpha_floor": 48, "main_component": True})
    source_cells(SOURCE / "destroy_raw.png", {"grid": [4, 2]})
    atlas = Image.new("RGBA", baseline.size)
    for name in ["aim", "base"]:
        for frame in data["anims"][name]["frames"]:
            rect = (frame["x"], frame["y"], frame["x"] + frame["w"], frame["y"] + frame["h"])
            atlas.paste(baseline.crop(rect), (frame["x"], frame["y"]))
    frames = []
    inspection = []
    for index, cell in enumerate(cells):
        tile = Image.new("RGBA", (128, 160))
        if index == 0:
            frame = data["anims"]["aim"]["frames"][4]
            tile.paste(baseline.crop((frame["x"], frame["y"], frame["x"] + 128, frame["y"] + 120)), (0, 20))
        else:
            resized = cell.resize((round(cell.width * .30), round(cell.height * .30)), Image.Resampling.LANCZOS)
            tile.alpha_composite(resized, (round(64 - 220 * .30), round(99 - 307 * .30)))
        x, y = index % 4 * 128, 640 + index // 4 * 160
        atlas.paste(tile, (x, y))
        frames.append(dict(x=x, y=y, w=128, h=160, ax=64, ay=145, sh=0))
        inspection.append(dict(id=f"destroy/{index}", rect=dict(x=x, y=y, w=128, h=160),
                               anchor=dict(x=64, y=145), durationMs=140))
    original = copy.deepcopy(data["anims"])
    data["anims"]["destroy"] = dict(frames=frames, frame_ms=140, layered_base=True, entry_aim=True)
    checks = []
    for name in ["aim", "base"]:
        assert data["anims"][name] == original[name]
        for index, frame in enumerate(original[name]["frames"]):
            rect = (frame["x"], frame["y"], frame["x"] + frame["w"], frame["y"] + frame["h"])
            assert np.array_equal(np.array(atlas.crop(rect)), np.array(baseline.crop(rect)))
            checks.append(f"{name}/{index}")
    atlas.save(OUTPUT / "kestrel.png")
    (OUTPUT / "kestrel.json").write_text(json.dumps(data, indent=2))
    (SOURCE / "destroy.frames.json").write_text(json.dumps(inspection, indent=2))
    (SOURCE / "preservation.json").write_text(json.dumps({"pixel_identical": checks,
        "json_identical": ["aim", "base"], "baseline": "kestrel-atlas-v3.png"}, indent=2))
    # Composite review frames use the actual immutable pedestal.
    base = original["base"]["frames"][0]
    pedestal = atlas.crop((base["x"], base["y"], base["x"] + base["w"], base["y"] + base["h"]))
    sheet = Image.new("RGBA", (512, 320))
    for index, frame in enumerate(frames):
        tile = Image.new("RGBA", (128, 160))
        tile.alpha_composite(pedestal, (64 - base["ax"], 145 - base["ay"]))
        tile.alpha_composite(atlas.crop((frame["x"], frame["y"], frame["x"] + 128, frame["y"] + 160)))
        sheet.paste(tile, (index % 4 * 128, index // 4 * 160))
    evidence = SOURCE / "evidence"
    evidence.mkdir(exist_ok=True)
    sheet.save(evidence / "destroy_composite.png")
    (evidence / "composite.frames.json").write_text(json.dumps([
        dict(id=f"destroy/{index}", rect=dict(x=index % 4 * 128, y=index // 4 * 160, w=128, h=160),
             anchor=dict(x=64, y=145), durationMs=140) for index in range(8)], indent=2))
    print("PASS 16 aim frames and base unchanged in pixels and JSON; 8 layered destruction frames")


if __name__ == "__main__":
    main()
