"""Render transparent UI icons for the game from the saved .blend models.

    python art/blender/render_icons.py      (or: blender --background --python ...)
Writes godot/assets/ui/icons/<model>.png
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402

import build_all as B  # noqa: E402
import ng_common as C  # noqa: E402


def main():
    for mid, _title, _role, _builder, family, (tz, dist) in B.MODELS:
        path = os.path.join(B.BLEND_DIR, f"{mid}.blend")
        if not os.path.exists(path):
            print("[icons] missing", path)
            continue
        bpy.ops.wm.open_mainfile(filepath=path)
        C.apply_palette(B.palettes_for(family)[B.ICON_PALETTE[family]])
        C.render_preview(os.path.join(B.ICON_DIR, f"{mid}.png"), target=(0, -0.2, tz),
                         distance=dist, yaw=-50, pitch=18, res=(320, 260), samples=24,
                         background=False)
        print("[icons]", mid)


if __name__ == "__main__":
    main()
