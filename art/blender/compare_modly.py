"""Render a Modly (or any image-to-3D) .glb next to our procedural model with
identical camera, lights and scale, and print a stats comparison.

Usage:
    python art/blender/compare_modly.py <model_id> <path/to/modly_output.glb> [palette]
    # e.g. python art/blender/compare_modly.py shale_digger art/modly_outputs/shale_digger.glb

Writes art/previews/compare/<model_id>_compare.png
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import build_all as B  # noqa: E402
import ng_common as C  # noqa: E402

OUT = os.path.join(B.REPO, "art", "previews", "compare")


def scene_bounds():
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for o in bpy.context.scene.objects:
        if o.type != "MESH":
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w)); hi = Vector(map(max, hi, w))
    return lo, hi


def stats(label):
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    imgs = [i for i in bpy.data.images if i.size[0] > 0]
    lo, hi = scene_bounds()
    return {"label": label, "objects": len(meshes), "triangles": C.triangle_count(),
            "materials": len(bpy.data.materials), "textures": [f"{i.size[0]}x{i.size[1]}" for i in imgs],
            "size_m": tuple(round(v, 2) for v in (hi - lo))}


def main(model_id, glb, palette=None):
    spec = next(m for m in B.MODELS if m[0] == model_id)
    _, title, role, builder, family, (tz, dist) = spec
    pals = B.palettes_for(family)
    palette = palette or next(iter(pals))
    cam = dict(target=(0, -0.2, tz), distance=dist, yaw=-50, pitch=18, res=(640, 520), samples=32)

    # ours
    C.reset_scene(); builder(); C.apply_palette(pals[palette])
    ours = stats("procedural (ours)")
    lo, hi = scene_bounds()
    target_dims = hi - lo
    C.render_preview(os.path.join(OUT, f"{model_id}_ours.png"), **cam)

    # modly: import, normalise to same longest dimension, sit on ground, face -Y like ours
    C.reset_scene()
    bpy.ops.import_scene.gltf(filepath=glb)
    theirs = stats("image-to-3D (raw)")
    lo, hi = scene_bounds()
    dims = hi - lo
    scale = max(target_dims) / max(dims)
    centre = (lo + hi) / 2
    for o in bpy.context.scene.objects:
        if o.parent is None:
            o.location = (o.location - Vector((centre.x, centre.y, lo.z))) * scale
            o.scale *= scale
    bpy.context.view_layer.update()
    C.render_preview(os.path.join(OUT, f"{model_id}_modly.png"), **cam)

    try:
        from PIL import Image, ImageDraw
        a = Image.open(os.path.join(OUT, f"{model_id}_ours.png"))
        b = Image.open(os.path.join(OUT, f"{model_id}_modly.png"))
        s = Image.new("RGB", (a.width * 2, a.height + 40), (246, 240, 230))
        s.paste(a, (0, 40)); s.paste(b, (a.width, 40))
        d = ImageDraw.Draw(s)
        d.text((20, 12), f"{title} - procedural Blender ({ours['triangles']} tris)", fill=(0, 0, 0))
        d.text((a.width + 20, 12), f"{title} - image-to-3D ({theirs['triangles']} tris)", fill=(0, 0, 0))
        s.save(os.path.join(OUT, f"{model_id}_compare.png"))
    except ImportError:
        pass
    for st in (ours, theirs):
        print("[compare]", st)
    print("[compare] note: if the image-to-3D model faces the wrong way, rotate it in Blender "
          "so its front points to -Y and re-run.")


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    main(*args)
