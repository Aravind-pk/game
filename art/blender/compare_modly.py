"""Render a Modly (or any image-to-3D) .glb next to our procedural model with
identical camera, lights and scale, and print a stats comparison.

Usage:
    python art/blender/compare_modly.py <model_id> <path/to/modly_output.glb> [palette]
    # e.g. python art/blender/compare_modly.py shale_digger art/modly_outputs/shale_digger.glb
    # options: --rot=X,Y,Z  (degrees, applied after import, to make the model stand up / face -Y)
    #          --label=TripoSR
    #          --srgb_vertex_colors=1  (TripoSR/trimesh exports: fixes washed-out vertex colours)

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
    """World-space bounds from actual vertices (object bound boxes are local and can be
    inflated when a joined object carries a rotation)."""
    import numpy as np
    pts = []
    for o in bpy.context.scene.objects:
        if o.type != "MESH":
            continue
        co = np.empty(len(o.data.vertices) * 3, dtype=np.float64)
        o.data.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        M = np.array(o.matrix_world)
        pts.append(co @ M[:3, :3].T + M[:3, 3])
    allp = np.concatenate(pts)
    return Vector(allp.min(0)), Vector(allp.max(0))


def stats(label):
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    imgs = [i for i in bpy.data.images if i.size[0] > 0]
    lo, hi = scene_bounds()
    return {"label": label, "objects": len(meshes), "triangles": C.triangle_count(),
            "materials": len(bpy.data.materials), "textures": [f"{i.size[0]}x{i.size[1]}" for i in imgs],
            "size_m": tuple(round(v, 2) for v in (hi - lo))}


def _linearize_vertex_colors():
    """TripoSR (via trimesh) writes sRGB bytes into COLOR_0, which glTF defines as linear,
    so they display washed out. Convert them back to linear."""
    import numpy as np
    for o in bpy.context.scene.objects:
        if o.type != "MESH":
            continue
        for ca in o.data.color_attributes:
            n = len(ca.data)
            c = np.empty(n * 4, dtype=np.float32)
            ca.data.foreach_get("color", c)
            c = c.reshape(-1, 4)
            rgb = c[:, :3]
            c[:, :3] = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
            ca.data.foreach_set("color", c.ravel())


def main(model_id, glb, palette=None, rot="0,0,0", label="image-to-3D", srgb_vertex_colors="0"):
    srgb_vertex_colors = str(srgb_vertex_colors) in ("1", "true", "yes")
    spec = next(m for m in B.MODELS if m[0] == model_id)
    _, title, role, builder, family, (tz, dist) = spec
    pals = B.palettes_for(family)
    palette = palette or next(iter(pals))
    cam = dict(target=(0, -0.2, tz), distance=dist, yaw=-50, pitch=18, res=(640, 520), samples=32,
               crease_lines=False)  # silhouette-only: dense AI meshes make crease lines noisy

    # ours
    C.reset_scene(); builder(); C.apply_palette(pals[palette])
    ours = stats("procedural (ours)")
    lo, hi = scene_bounds()
    target_dims = hi - lo
    C.render_preview(os.path.join(OUT, f"{model_id}_ours.png"), **cam)

    # modly: import, normalise to same longest dimension, sit on ground, face -Y like ours
    C.reset_scene()
    bpy.ops.import_scene.gltf(filepath=glb)
    import math
    rx, ry, rz = (math.radians(float(v)) for v in rot.split(","))
    from mathutils import Euler
    R = Euler((rx, ry, rz)).to_matrix().to_4x4()
    for o in bpy.context.scene.objects:
        if o.parent is None:
            o.matrix_world = R @ o.matrix_world
    bpy.context.view_layer.update()
    if srgb_vertex_colors:
        _linearize_vertex_colors()
    theirs = stats(f"{label} (raw)")
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
        d.text((a.width + 20, 12), f"{title} - {label} ({theirs['triangles']} tris)", fill=(0, 0, 0))
        s.save(os.path.join(OUT, f"{model_id}_compare.png"))
    except ImportError:
        pass
    for st in (ours, theirs):
        print("[compare]", st)
    print("[compare] note: if the image-to-3D model faces the wrong way, rotate it in Blender "
          "so its front points to -Y and re-run.")


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    pos = [a for a in args if not a.startswith("--")]
    kw = dict(a[2:].split("=", 1) for a in args if a.startswith("--"))
    main(*pos, **kw)
