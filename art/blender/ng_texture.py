"""Bake painted-looking surface detail into textures that stay palette-agnostic.

For every model we bake (Cycles, CPU):
  * <model>_detail.png  — greyscale: ambient occlusion x material grain x edge wear.
                          Used as glTF baseColorTexture; the palette colour is the
                          baseColorFactor, so colour schemes still swap freely.
  * <model>_normal.png  — tangent-space normal map of fine surface relief
                          (stone pits and cracks on monsters, panel grain on turrets).

All meshes of a model share one UV atlas, so shared role materials (NG_primary...)
can point at a single pair of images.
"""

import os

import bpy

from ng_common import EMISSIVE_ROLES

STONE_ROLES = {"armor", "primary", "joints"}  # monster surfaces that get rock grain
PROP_STONE = {"concrete", "concrete_dark", "rock"}  # prop surfaces that get cracks


def _meshes():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def _unwrap(objs, margin=0.006):
    ctx = bpy.context
    for o in ctx.selected_objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
        if not o.data.uv_layers:
            o.data.uv_layers.new(name="UVMap")
    ctx.view_layer.objects.active = objs[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=margin, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(margin=margin, rotate=True)
    bpy.ops.object.mode_set(mode="OBJECT")


def _new_image(name, size, non_color=False):
    img = bpy.data.images.new(name, size, size, alpha=False, float_buffer=False)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def _detail_graph(nt, kind, role):
    """Build nodes that output the greyscale detail value; returns output socket."""
    N, L = nt.nodes, nt.links
    ao = N.new("ShaderNodeAmbientOcclusion")
    ao.samples = 16
    ao.inputs["Distance"].default_value = 0.35 if kind == "monster" else 0.25
    # edge mask via Bevel normal vs true normal
    bev = N.new("ShaderNodeBevel")
    bev.samples = 8
    bev.inputs["Radius"].default_value = 0.025
    geo = N.new("ShaderNodeNewGeometry")
    dot = N.new("ShaderNodeVectorMath"); dot.operation = "DOT_PRODUCT"
    L.new(bev.outputs["Normal"], dot.inputs[0]); L.new(geo.outputs["Normal"], dot.inputs[1])
    edge = N.new("ShaderNodeMapRange")  # dot 1 -> flat (0), dot 0.9 -> edge (1)
    edge.inputs["From Min"].default_value = 0.995
    edge.inputs["From Max"].default_value = 0.93
    L.new(dot.outputs["Value"], edge.inputs["Value"])

    tc = N.new("ShaderNodeTexCoord")
    noise = N.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 6.0 if kind == "monster" else 9.0
    noise.inputs["Detail"].default_value = 8.0
    noise.inputs["Roughness"].default_value = 0.6
    L.new(tc.outputs["Object"], noise.inputs["Vector"])
    mottle = N.new("ShaderNodeMapRange")
    lo, hi = {"monster": (0.72, 1.08), "prop": (0.7, 1.1)}.get(kind, (0.88, 1.03))
    mottle.inputs["From Min"].default_value = 0.35
    mottle.inputs["From Max"].default_value = 0.65
    mottle.inputs["To Min"].default_value = lo
    mottle.inputs["To Max"].default_value = hi
    L.new(noise.outputs["Fac"], mottle.inputs["Value"])

    val = mottle.outputs["Result"]
    if (kind == "monster" and role in STONE_ROLES) or (kind == "prop" and role in PROP_STONE):
        # thin dark crack lines from voronoi edges
        vor = N.new("ShaderNodeTexVoronoi")
        vor.feature = "DISTANCE_TO_EDGE"
        vor.inputs["Scale"].default_value = 7.0
        L.new(tc.outputs["Object"], vor.inputs["Vector"])
        crack = N.new("ShaderNodeMapRange")
        crack.inputs["From Min"].default_value = 0.0
        crack.inputs["From Max"].default_value = 0.035
        crack.inputs["To Min"].default_value = 0.55
        crack.inputs["To Max"].default_value = 1.0
        L.new(vor.outputs["Distance"], crack.inputs["Value"])
        m1 = N.new("ShaderNodeMath"); m1.operation = "MULTIPLY"
        L.new(val, m1.inputs[0]); L.new(crack.outputs["Result"], m1.inputs[1])
        val = m1.outputs["Value"]

    # AO darkening (soft) and edge highlight (painted chipped edges)
    aom = N.new("ShaderNodeMapRange")
    aom.inputs["To Min"].default_value = 0.45
    aom.inputs["To Max"].default_value = 1.0
    L.new(ao.outputs["AO"], aom.inputs["Value"])
    m2 = N.new("ShaderNodeMath"); m2.operation = "MULTIPLY"
    L.new(val, m2.inputs[0]); L.new(aom.outputs["Result"], m2.inputs[1])
    e = N.new("ShaderNodeMath"); e.operation = "MULTIPLY"
    e.inputs[1].default_value = 0.35 if kind == "monster" else 0.22
    L.new(edge.outputs["Result"], e.inputs[0])
    add = N.new("ShaderNodeMath"); add.operation = "ADD"; add.use_clamp = True
    L.new(m2.outputs["Value"], add.inputs[0]); L.new(e.outputs["Value"], add.inputs[1])
    return add.outputs["Value"]


def _height_graph(nt, kind, role):
    N, L = nt.nodes, nt.links
    tc = N.new("ShaderNodeTexCoord")
    noise = N.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 18.0 if kind == "monster" else 30.0
    noise.inputs["Detail"].default_value = 10.0
    L.new(tc.outputs["Object"], noise.inputs["Vector"])
    bump = N.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.45 if kind == "monster" else 0.12
    bump.inputs["Distance"].default_value = 0.02
    h = noise.outputs["Fac"]
    if (kind == "monster" and role in STONE_ROLES) or (kind == "prop" and role in PROP_STONE):
        vor = N.new("ShaderNodeTexVoronoi")
        vor.feature = "DISTANCE_TO_EDGE"
        vor.inputs["Scale"].default_value = 7.0
        L.new(tc.outputs["Object"], vor.inputs["Vector"])
        cr = N.new("ShaderNodeMapRange")
        cr.inputs["From Max"].default_value = 0.04
        L.new(vor.outputs["Distance"], cr.inputs["Value"])
        mul = N.new("ShaderNodeMath"); mul.operation = "MULTIPLY"
        L.new(h, mul.inputs[0]); L.new(cr.outputs["Result"], mul.inputs[1])
        h = mul.outputs["Value"]
    L.new(h, bump.inputs["Height"])
    return bump.outputs["Normal"]


def bake_textures(model_id, kind, out_dir, size=1024, samples=16):
    """kind: 'monster' or 'turret'. Rewires every NG_* material to use the baked maps."""
    objs = _meshes()
    _unwrap(objs)
    detail = _new_image(f"{model_id}_detail", size)
    normal = _new_image(f"{model_id}_normal", size, non_color=True)

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.render.bake.margin = 6

    mats = {m for o in objs for m in o.data.materials if m}
    saved = {}
    for m in mats:
        saved[m.name] = [n.name for n in m.node_tree.nodes]

    def setup(pass_kind):
        for m in mats:
            nt = m.node_tree
            for n in list(nt.nodes):
                if n.name not in saved[m.name]:
                    nt.nodes.remove(n)
            role = m.name[3:]
            out = nt.nodes["Material Output"]
            bsdf = nt.nodes["Principled BSDF"]
            img_node = nt.nodes.new("ShaderNodeTexImage")
            img_node.image = detail if pass_kind == "detail" else normal
            nt.nodes.active = img_node
            if pass_kind == "detail":
                em = nt.nodes.new("ShaderNodeEmission")
                if role in EMISSIVE_ROLES:
                    em.inputs["Color"].default_value = (1, 1, 1, 1)
                else:
                    nt.links.new(_detail_graph(nt, kind, role), em.inputs["Color"])
                nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
            else:
                if role not in EMISSIVE_ROLES:
                    nt.links.new(_height_graph(nt, kind, role), bsdf.inputs["Normal"])
                nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    def select_all():
        for o in bpy.context.selected_objects:
            o.select_set(False)
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]

    setup("detail")
    select_all()
    bpy.ops.object.bake(type="EMIT")
    setup("normal")
    select_all()
    scene.render.bake.normal_space = "TANGENT"
    bpy.ops.object.bake(type="NORMAL")

    os.makedirs(out_dir, exist_ok=True)
    for img in (detail, normal):
        img.filepath_raw = os.path.join(out_dir, img.name + ".png")
        img.file_format = "PNG"
        img.save()

    # final materials: detail x palette colour, plus normal map
    for m in mats:
        nt = m.node_tree
        for n in list(nt.nodes):
            if n.name not in saved[m.name]:
                nt.nodes.remove(n)
        role = m.name[3:]
        out = nt.nodes["Material Output"]
        bsdf = nt.nodes["Principled BSDF"]
        nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
        if role in EMISSIVE_ROLES:
            continue
        tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = detail; tex.name = "NG_detail"
        tint = nt.nodes.new("ShaderNodeMix"); tint.name = "NG_tint"
        tint.data_type = "RGBA"; tint.blend_type = "MULTIPLY"
        tint.inputs["Factor"].default_value = 1.0
        tint.inputs[7].default_value = bsdf.inputs["Base Color"].default_value
        nt.links.new(tex.outputs["Color"], tint.inputs[6])
        nt.links.new(tint.outputs[2], bsdf.inputs["Base Color"])
        ntex = nt.nodes.new("ShaderNodeTexImage"); ntex.image = normal; ntex.name = "NG_normal"
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(ntex.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    return detail, normal
