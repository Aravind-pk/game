"""Shared helpers for the North Gate Blender model scripts.

Run inside Blender (or with the `bpy` Python module):
    blender --background --python art/blender/build_all.py

Conventions
- Units are metres, Z is up, models face -Y in Blender. The glTF exporter
  turns that into +Z forward / Y up, which is Godot's MODEL_FRONT.
- Origin sits on the ground at the centre of the footprint.
- Every material is named after a palette *role* (e.g. ``NG_primary``) so the
  game can recolour a model by swapping materials. One .glb is exported per
  palette as well.
"""

import math
import os
import random

import bpy  # noqa: E402  (must precede bmesh when using the bpy module)
import bmesh
from mathutils import Euler, Matrix, Vector

# --------------------------------------------------------------------------
# Palettes (taken from the concept colour-study sheets)
# --------------------------------------------------------------------------

TURRET_PALETTES = {
    "frontier_olive": {
        "primary": "#6E7F4A",    # sage green armour
        "secondary": "#E3D6B4",  # cream panels
        "frame": "#3A3C3F",      # graphite joints / frame
        "accent": "#F29A1D",     # amber markings
        "glow": "#2FF3FF",       # cyan strips
        "metal": "#55595E",      # barrels
    },
    "polar_ceramic": {
        "primary": "#ECE8E0",
        "secondary": "#5E7396",
        "frame": "#36383B",
        "accent": "#F2B71D",
        "glow": "#2FF3FF",
        "metal": "#55595E",
    },
    "midnight_steel": {
        "primary": "#2E3550",
        "secondary": "#A3A6AC",
        "frame": "#3A3C3F",
        "accent": "#F29A1D",
        "glow": "#2FF3FF",
        "metal": "#4D5156",
    },
}

MONSTER_PALETTES = {
    "basalt_ember": {
        "primary": "#4A3F3A",   # charcoal-brown hide
        "armor": "#4F5A6B",     # blue-grey rock plates
        "joints": "#6B5446",    # dark earth
        "claws": "#E8DCC4",     # ivory
        "seams": "#FF4A1C",     # orange-red glow
        "eyes": "#FFC21A",
    },
    "clayfire": {
        "primary": "#7A3E2A",
        "armor": "#A5503A",
        "joints": "#4A2C20",
        "claws": "#F1DDB0",
        "seams": "#FFB300",
        "eyes": "#FFD23A",
    },
    "abyss_violet": {
        "primary": "#3E2B40",
        "armor": "#6A4E73",
        "joints": "#2A3046",
        "claws": "#D6D0D8",
        "seams": "#FF5A6E",
        "eyes": "#FF5A6E",
    },
}

EMISSIVE_ROLES = {"glow": 6.0, "seams": 5.0, "eyes": 4.0}
METALLIC_ROLES = {"metal": 0.85, "frame": 0.4}
ROUGHNESS = {"claws": 0.45, "glow": 0.3, "metal": 0.35, "secondary": 0.5,
             "armor": 0.85, "primary": 0.7, "joints": 0.75}


def hex_rgb(h):
    h = h.lstrip("#")
    srgb = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    return (*lin, 1.0)


# --------------------------------------------------------------------------
# Scene / material setup
# --------------------------------------------------------------------------

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)


def role_material(role):
    """Get (or create) the material for a palette role."""
    name = "NG_" + role
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    return m


def apply_palette(palette):
    """Recolour every NG_* material in the file from a palette dict."""
    for role, hexcol in palette.items():
        m = bpy.data.materials.get("NG_" + role)
        if not m:
            continue
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        col = hex_rgb(hexcol)
        bsdf.inputs["Base Color"].default_value = col
        bsdf.inputs["Roughness"].default_value = ROUGHNESS.get(role, 0.6)
        bsdf.inputs["Metallic"].default_value = METALLIC_ROLES.get(role, 0.0)
        if role in EMISSIVE_ROLES:
            bsdf.inputs["Emission Color"].default_value = col
            bsdf.inputs["Emission Strength"].default_value = EMISSIVE_ROLES[role]
        m.diffuse_color = col


# --------------------------------------------------------------------------
# Object helpers
# --------------------------------------------------------------------------

def _link(obj, coll=None):
    (coll or bpy.context.scene.collection).objects.link(obj)
    return obj


def mesh_object(name, bm, mat_role=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    _link(obj)
    if mat_role:
        obj.data.materials.append(role_material(mat_role))
    return obj


def set_transform(obj, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    obj.location = Vector(loc)
    obj.rotation_euler = Euler([math.radians(a) for a in rot])
    obj.scale = Vector(scale)
    return obj


def bevel(obj, width=0.02, segments=2, angle=35):
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(angle)
    mod.harden_normals = True
    return obj


def smooth(obj, auto_angle=40):
    for p in obj.data.polygons:
        p.use_smooth = True
    # Blender 4.1+: smooth-by-angle via modifier node group is heavy; mark sharp edges instead.
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle() > math.radians(auto_angle):
            e.smooth = False
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def box(name, size, loc=(0, 0, 0), rot=(0, 0, 0), mat="primary", bev=0.02, taper=None):
    """Box with optional top taper (taper=(sx, sy) scale applied to top face)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
        if taper and v.co.z > 0:
            v.co.x *= taper[0]
            v.co.y *= taper[1]
    obj = mesh_object(name, bm, mat)
    set_transform(obj, loc, rot)
    if bev:
        bevel(obj, bev, 2)
    smooth(obj)
    return obj


def prism(name, profile, depth, loc=(0, 0, 0), rot=(0, 0, 0), mat="primary", bev=0.02, axis="Y"):
    """Extrude a 2D polygon profile [(u, v), ...] along an axis. Profile lies in
    the plane perpendicular to the axis: for axis Y it is (x, z)."""
    bm = bmesh.new()
    vs_front, vs_back = [], []
    for (u, v) in profile:
        if axis == "Y":
            a = Vector((u, -depth / 2, v)); b = Vector((u, depth / 2, v))
        elif axis == "X":
            a = Vector((-depth / 2, u, v)); b = Vector((depth / 2, u, v))
        else:
            a = Vector((u, v, -depth / 2)); b = Vector((u, v, depth / 2))
        vs_front.append(bm.verts.new(a))
        vs_back.append(bm.verts.new(b))
    n = len(profile)
    bm.faces.new(vs_front)
    bm.faces.new(list(reversed(vs_back)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([vs_front[i], vs_back[i], vs_back[j], vs_front[j]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = mesh_object(name, bm, mat)
    set_transform(obj, loc, rot)
    if bev:
        bevel(obj, bev, 2)
    smooth(obj)
    return obj


def cylinder(name, radius, depth, loc=(0, 0, 0), rot=(0, 0, 0), mat="primary", verts=24,
             bev=0.015, radius2=None, cap=True):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=verts,
                          radius1=radius, radius2=radius if radius2 is None else radius2,
                          depth=depth)
    obj = mesh_object(name, bm, mat)
    set_transform(obj, loc, rot)
    if bev:
        bevel(obj, bev, 2, angle=50)
    smooth(obj, 50)
    return obj


def tube_along(name, points, radius, mat="frame", verts=10, taper=None):
    """Sweep a circle along a polyline (list of Vectors). taper: (r_start, r_end) multipliers."""
    bm = bmesh.new()
    pts = [Vector(p) for p in points]
    rings = []
    n = len(pts)
    for i, p in enumerate(pts):
        if i == 0:
            d = (pts[1] - p).normalized()
        elif i == n - 1:
            d = (p - pts[i - 1]).normalized()
        else:
            d = ((pts[i + 1] - p).normalized() + (p - pts[i - 1]).normalized()).normalized()
        up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
        a = d.cross(up).normalized()
        b = d.cross(a).normalized()
        r = radius
        if taper:
            t = i / (n - 1)
            r *= taper[0] + (taper[1] - taper[0]) * t
        ring = []
        for k in range(verts):
            ang = 2 * math.pi * k / verts
            ring.append(bm.verts.new(p + (a * math.cos(ang) + b * math.sin(ang)) * r))
        rings.append(ring)
    for i in range(n - 1):
        for k in range(verts):
            k2 = (k + 1) % verts
            bm.faces.new([rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]])
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = mesh_object(name, bm, mat)
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def rock_shard(name, size, loc=(0, 0, 0), rot=(0, 0, 0), mat="armor", seed=0, points=14,
               flat_bottom=False, point=0.0, bev=0.025, point_y=0.0, jitter=0.22):
    """Faceted rock plate: convex hull of jittered points inside an ellipsoid.

    size  = (x, y, z) half-extents
    point = extra spike length along +Z (makes a pointed shard)
    """
    rng = random.Random(seed)
    bm = bmesh.new()
    pts = []
    for i in range(points):
        # Fibonacci sphere for even coverage + jitter
        k = i + 0.5
        phi = math.acos(1 - 2 * k / points)
        th = math.pi * (1 + 5 ** 0.5) * k
        x, y, z = math.cos(th) * math.sin(phi), math.sin(th) * math.sin(phi), math.cos(phi)
        j = (1 - jitter) + jitter * rng.random()
        if flat_bottom and z < -0.2:
            z = -0.55
        pts.append(Vector((x * size[0] * j, y * size[1] * j, z * size[2] * j)))
    if point:
        pts.append(Vector((rng.uniform(-0.15, 0.15) * size[0],
                           (point_y + rng.uniform(-0.1, 0.1)) * size[1],
                           size[2] * (1 - abs(point_y) * 0.6) + point)))
    for p in pts:
        bm.verts.new(p)
    bmesh.ops.convex_hull(bm, input=bm.verts)
    # Planar dissolve merges almost-coplanar triangles into chunky facets
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(6), verts=bm.verts, edges=bm.edges)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    obj = mesh_object(name, bm, mat)
    set_transform(obj, loc, rot)
    if bev:
        bevel(obj, bev, 1, angle=20)
    return obj


def join(objs, name):
    objs = [o for o in objs if o]
    ctx = bpy.context
    for o in ctx.selected_objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    ctx.view_layer.objects.active = objs[0]
    # apply modifiers first
    for o in objs:
        ctx.view_layer.objects.active = o
        for m in list(o.modifiers):
            bpy.ops.object.modifier_apply(modifier=m.name)
    ctx.view_layer.objects.active = objs[0]
    for o in objs:
        o.select_set(True)
    bpy.ops.object.join()
    out = ctx.view_layer.objects.active
    out.name = name
    out.data.name = name
    return out


def parent_all(objs, root):
    for o in objs:
        if o is root or o.parent is not None:
            continue
        mw = o.matrix_world.copy()
        o.parent = root
        o.matrix_world = mw


def mirror_x(obj):
    """Duplicate an object mirrored across X=0 (world)."""
    dup = obj.copy()
    dup.data = obj.data.copy()
    _link(dup)
    dup.matrix_world = Matrix.Scale(-1, 4, (1, 0, 0)) @ obj.matrix_world
    # Fix inverted normals from negative scale by applying transform
    for o in bpy.context.selected_objects:
        o.select_set(False)
    dup.select_set(True)
    bpy.context.view_layer.objects.active = dup
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    me = dup.data
    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    dup.name = obj.name.replace("_L", "_R") if "_L" in obj.name else obj.name + "_R"
    return dup


# --------------------------------------------------------------------------
# Export / render
# --------------------------------------------------------------------------

def triangle_count():
    total = 0
    deps = bpy.context.evaluated_depsgraph_get()
    for o in bpy.context.scene.objects:
        if o.type != "MESH":
            continue
        me = o.evaluated_get(deps).to_mesh()
        total += sum(len(p.vertices) - 2 for p in me.polygons)
        o.evaluated_get(deps).to_mesh_clear()
    return total


def export_glb(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True,
                              export_yup=True, use_selection=False, export_cameras=False,
                              export_lights=False)


def save_blend(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)


def render_preview(path, target=(0, 0, 0.8), distance=7.0, yaw=-35, pitch=18, res=(900, 700),
                   samples=48, ortho_scale=None):
    """Studio render on a cream background with anime-style outlines."""
    scene = bpy.context.scene
    created = []

    # camera
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    _link(cam); created.append(cam)
    yaw_r, pitch_r = math.radians(yaw), math.radians(pitch)
    tgt = Vector(target)
    offset = Vector((math.sin(yaw_r) * math.cos(pitch_r), -math.cos(yaw_r) * math.cos(pitch_r),
                     math.sin(pitch_r))) * distance
    cam.location = tgt + offset
    cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam_data.lens = 50
    if ortho_scale:
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = ortho_scale
    scene.camera = cam

    # lights: key / fill / rim
    def light(name, kind, loc, energy, size=1.0, color=(1, 1, 1)):
        ld = bpy.data.lights.new(name, kind)
        ld.energy = energy
        ld.color = color
        if kind == "AREA":
            ld.size = size
        lo = bpy.data.objects.new(name, ld)
        lo.location = Vector(loc)
        lo.rotation_euler = (tgt - lo.location).to_track_quat("-Z", "Y").to_euler()
        _link(lo); created.append(lo)

    light("Key", "AREA", (-4, -5, 7), 650, 5, (1.0, 0.96, 0.9))
    light("Fill", "AREA", (6, -3, 3), 160, 6, (0.85, 0.9, 1.0))
    light("Rim", "AREA", (1, 6, 5), 500, 4)

    # shadow catcher ground
    bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
    ground = bpy.context.object
    ground.is_shadow_catcher = True
    created.append(ground)
    noline = bpy.data.collections.get("NG_NoLine") or bpy.data.collections.new("NG_NoLine")
    if noline.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(noline)
    for c in list(ground.users_collection):
        c.objects.unlink(ground)
    noline.objects.link(ground)

    world = bpy.data.worlds.new("PreviewWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.93, 0.89, 0.82, 1)
    bg.inputs["Strength"].default_value = 0.4
    scene.world = world

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"

    # Freestyle outlines for the cel look
    scene.render.use_freestyle = True
    scene.render.line_thickness_mode = "ABSOLUTE"
    scene.render.line_thickness = 1.4
    vl = scene.view_layers[0]
    vl.use_freestyle = True
    fs = vl.freestyle_settings
    if not fs.linesets:
        fs.linesets.new("Outline")
    ls = fs.linesets[0]
    ls.select_by_visibility = True
    ls.select_silhouette = True
    ls.select_border = True
    ls.select_crease = True
    ls.select_by_collection = True
    ls.collection = noline
    ls.collection_negation = "EXCLUSIVE"
    fs.crease_angle = math.radians(120)
    if ls.linestyle is None:
        ls.linestyle = bpy.data.linestyles.new("NGLine")
    ls.linestyle.color = (0.12, 0.1, 0.1)
    ls.linestyle.thickness = 1.6

    # Composite over cream background
    scene.render.filepath = path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    _composite_bg(path)

    for o in created:
        bpy.data.objects.remove(o, do_unlink=True)


def _composite_bg(path, color=(0.965, 0.94, 0.9)):
    import numpy as np
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(-1, 4)
    a = px[:, 3:4]
    px[:, :3] = px[:, :3] * a + np.array(color, dtype=np.float32) * (1 - a)
    px[:, 3] = 1.0
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
