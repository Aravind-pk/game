"""Build the environment props: .blend, baked textures, .glb for Godot, preview sheet.

    python art/blender/build_props.py [--no-render] [--only crater,pine]
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402

import ng_common as C  # noqa: E402
import ng_props as P  # noqa: E402
import ng_texture as X  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_GLB = os.path.join(REPO, "godot", "assets", "models", "props")
OUT_TEX = os.path.join(REPO, "art", "blender", "models", "textures")
OUT_PREV = os.path.join(REPO, "art", "previews", "props")


def main(argv):
    render = "--no-render" not in argv
    only = set(argv[argv.index("--only") + 1].split(",")) if "--only" in argv else None
    done = []
    for name, fn in P.PROPS.items():
        if only and name not in only:
            continue
        C.reset_scene()
        parts = fn()
        obj = C.join(parts, "Prop_" + name)
        C.apply_palette(P.PROP_PALETTE)
        X.bake_textures("prop_" + name, "prop", OUT_TEX, size=512, samples=12)
        C.export_glb(os.path.join(OUT_GLB, f"{name}.glb"))
        dims = obj.dimensions
        if render:
            h = max(dims.z, 1.0)
            C.render_preview(os.path.join(OUT_PREV, f"{name}.png"), target=(0, 0, h * 0.4),
                             distance=max(dims) * 2.2 + 2, yaw=-30, pitch=24, res=(420, 360), samples=20)
        done.append(name)
        print(f"[props] {name}: {C.triangle_count()} tris, {dims.x:.1f}x{dims.y:.1f}x{dims.z:.1f} m")
    if render:
        sheet(done)


def sheet(names):
    try:
        from PIL import Image
    except ImportError:
        return
    ims = [Image.open(os.path.join(OUT_PREV, f"{n}.png")) for n in names]
    cols = 4
    w, h = ims[0].size
    s = Image.new("RGB", (w * cols, h * ((len(ims) + cols - 1) // cols)), (246, 240, 230))
    for i, im in enumerate(ims):
        s.paste(im, ((i % cols) * w, (i // cols) * h))
    s.save(os.path.join(REPO, "art", "previews", "props_sheet.png"))


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    main(argv)
