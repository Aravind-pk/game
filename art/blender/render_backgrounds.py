"""Pre-render the painted battlefield background for every level.

The game draws only units and effects live; everything static (terrain, grass, ruins,
craters, the settlement wall) is rendered here once per level with Cycles, from the exact
orthographic camera the game uses (godot/levels/camera.json).

    python art/blender/render_backgrounds.py [--only 05] [--samples 48] [--preview]
Writes godot/assets/backgrounds/level_<id>.jpg
"""

import json
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Euler, Vector  # noqa: E402

import ng_common as C  # noqa: E402
import ng_props as P  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
LEVELS = os.path.join(REPO, "godot", "levels")
OUT = os.path.join(REPO, "godot", "assets", "backgrounds")
CELL = 2.0
WALL_SCALE = 0.8


# ---------------------------------------------------------------- helpers

def load_level(path):
    d = json.load(open(path))
    d["wall_row"] = d["rows"] - 1
    return d


def B(px, py, lv, z=0.0):
    """sim ground metres -> Blender world (Godot +Z == Blender -Y)."""
    W, H = lv["cols"] * CELL, lv["rows"] * CELL
    return Vector((px - W / 2, -(py - H / 2), z))


def place(name, builder_kwargs, pos, yaw_deg=0.0, scale=1.0, scale_xyz=None):
    parts = P.PROPS[name](**builder_kwargs) if builder_kwargs else P.PROPS[name]()
    obj = C.join(parts, f"bg_{name}_{len(bpy.data.objects)}")
    obj.location = pos
    obj.rotation_euler = (0, 0, math.radians(yaw_deg))
    obj.scale = Vector(scale_xyz) if scale_xyz else Vector((scale, scale, scale))
    return obj


def obstacle_kind(i, r):
    """Same rule the game uses for occluder heights (scripts/game/battlefield.gd)."""
    w, h = r[2], r[3]
    span = max(w, h)
    if w >= 2 and h >= 2:
        return ("ruin_corner" if i % 2 == 0 else "block_pile"), 1.0
    if span >= 3:
        return "container", span * CELL / 6.2
    if span == 2:
        return ["ruin_wall", "car", "barrier"][i % 3], 1.0
    return ["ruin_pillar", "rocks", "block_pile"][i % 3], (0.6 if i % 3 == 2 else 0.8)


# ---------------------------------------------------------------- materials

def hex_lin(h):
    return C.hex_rgb(h)


def grungify_role_materials():
    """Add soft colour variation + bump to every prop role material (painterly surfaces)."""
    for m in bpy.data.materials:
        if not m.name.startswith("NG_") or not m.use_nodes:
            continue
        role = m.name[3:]
        if role in C.EMISSIVE_ROLES:
            continue
        nt = m.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        base = tuple(bsdf.inputs["Base Color"].default_value)
        tc = nt.nodes.new("ShaderNodeTexCoord")
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 3.5
        noise.inputs["Detail"].default_value = 6.0
        nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].color = tuple(c * 0.72 for c in base[:3]) + (1,)
        ramp.color_ramp.elements[1].color = tuple(min(1.0, c * 1.12) for c in base[:3]) + (1,)
        ramp.color_ramp.elements[0].position = 0.3
        ramp.color_ramp.elements[1].position = 0.75
        nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
        ao.inputs["Distance"].default_value = 0.4
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = "MULTIPLY"
        mul.inputs["Factor"].default_value = 0.55
        nt.links.new(ramp.outputs["Color"], mul.inputs[6])
        nt.links.new(ao.outputs["AO"], mul.inputs[7])
        nt.links.new(mul.outputs[2], bsdf.inputs["Base Color"])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.25
        n2 = nt.nodes.new("ShaderNodeTexNoise")
        n2.inputs["Scale"].default_value = 22.0
        nt.links.new(tc.outputs["Object"], n2.inputs["Vector"])
        nt.links.new(n2.outputs["Fac"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
        bsdf.inputs["Roughness"].default_value = max(0.6, bsdf.inputs["Roughness"].default_value)


def ground_material(field_center_x):
    m = bpy.data.materials.new("bg_ground")
    m.use_nodes = True
    nt = m.node_tree
    N, L = nt.nodes, nt.links
    bsdf = N["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 1.0
    tc = N.new("ShaderNodeNewGeometry")  # world-space position (the plane is scaled)

    def noise(scale, detail=6.0, rough=0.55):
        n = N.new("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        L.new(tc.outputs["Position"], n.inputs["Vector"])
        return n

    def ramp(fac, stops):
        r = N.new("ShaderNodeValToRGB")
        r.color_ramp.elements[0].position, r.color_ramp.elements[0].color = stops[0][0], hex_lin(stops[0][1])
        r.color_ramp.elements[1].position, r.color_ramp.elements[1].color = stops[-1][0], hex_lin(stops[-1][1])
        for pos, col in stops[1:-1]:
            e = r.color_ramp.elements.new(pos)
            e.color = hex_lin(col)
        L.new(fac, r.inputs["Fac"])
        return r

    big = noise(0.06, 4.0, 0.6)
    mid = noise(0.16)
    fine = noise(1.4, 8.0, 0.7)
    grass = ramp(mid.outputs["Fac"], [(0.18, "#3b5224"), (0.38, "#506a2c"), (0.6, "#677f36"), (0.82, "#8c9248")])
    # worn dirt: big noise + a central worn band down the field toward the gate
    sep = N.new("ShaderNodeSeparateXYZ")
    L.new(tc.outputs["Position"], sep.inputs["Vector"])
    band = N.new("ShaderNodeMath")
    band.operation = "ABSOLUTE"
    sub = N.new("ShaderNodeMath")
    sub.operation = "SUBTRACT"
    sub.inputs[1].default_value = field_center_x
    L.new(sep.outputs["X"], sub.inputs[0])
    L.new(sub.outputs["Value"], band.inputs[0])
    bandr = N.new("ShaderNodeMapRange")
    bandr.inputs["From Min"].default_value = 3.0
    bandr.inputs["From Max"].default_value = 11.0
    bandr.inputs["To Min"].default_value = 0.1
    bandr.inputs["To Max"].default_value = -0.1
    L.new(band.outputs["Value"], bandr.inputs["Value"])
    add = N.new("ShaderNodeMath")
    add.operation = "ADD"
    L.new(big.outputs["Fac"], add.inputs[0])
    L.new(bandr.outputs["Result"], add.inputs[1])
    dirt_mask = N.new("ShaderNodeMapRange")
    dirt_mask.inputs["From Min"].default_value = 0.56
    dirt_mask.inputs["From Max"].default_value = 0.64
    L.new(add.outputs["Value"], dirt_mask.inputs["Value"])
    dirt = ramp(fine.outputs["Fac"], [(0.3, "#6a573c"), (0.55, "#86704c"), (0.8, "#a08a60")])
    mix = N.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    L.new(dirt_mask.outputs["Result"], mix.inputs["Factor"])
    L.new(grass.outputs["Color"], mix.inputs[6])
    L.new(dirt.outputs["Color"], mix.inputs[7])
    # fine mottling
    mott = N.new("ShaderNodeMix")
    mott.data_type = "RGBA"
    mott.blend_type = "MULTIPLY"
    mott.inputs["Factor"].default_value = 0.22
    L.new(mix.outputs[2], mott.inputs[6])
    mot_r = ramp(fine.outputs["Fac"], [(0.2, "#9a9a9a"), (0.8, "#ffffff")])
    L.new(mot_r.outputs["Color"], mott.inputs[7])
    L.new(mott.outputs[2], bsdf.inputs["Base Color"])
    bump = N.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.35
    L.new(fine.outputs["Fac"], bump.inputs["Height"])
    L.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return m, dirt_mask


def tuft_object():
    """A small grass tuft: 6 thin blades, 12-28 cm tall."""
    import bmesh
    bm = bmesh.new()
    rng = random.Random(3)
    for i in range(6):
        a = i / 6 * math.tau + rng.uniform(-0.3, 0.3)
        h = rng.uniform(0.12, 0.28)
        lean = rng.uniform(0.03, 0.09)
        d = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-d.y, d.x, 0)) * 0.012
        base = d * 0.03
        v0 = bm.verts.new(base - side)
        v1 = bm.verts.new(base + side)
        v2 = bm.verts.new(base + d * lean + Vector((0, 0, h)))
        bm.faces.new([v0, v1, v2])
    me = bpy.data.meshes.new("tuft")
    bm.to_mesh(me)
    obj = bpy.data.objects.new("tuft", me)
    bpy.context.scene.collection.objects.link(obj)
    obj.hide_render = True
    m = bpy.data.materials.new("bg_tuft")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.9
    oi = nt.nodes.new("ShaderNodeObjectInfo")
    r = nt.nodes.new("ShaderNodeValToRGB")
    r.color_ramp.elements[0].color = hex_lin("#4a6526")
    r.color_ramp.elements[1].color = hex_lin("#a9a55a")
    e = r.color_ramp.elements.new(0.6)
    e.color = hex_lin("#6f8a36")
    nt.links.new(oi.outputs["Random"], r.inputs["Fac"])
    geo = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Object"], sep.inputs["Vector"])
    hr = nt.nodes.new("ShaderNodeMapRange")
    hr.inputs["From Max"].default_value = 0.25
    hr.inputs["To Min"].default_value = 0.7
    nt.links.new(sep.outputs["Z"], hr.inputs["Value"])
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    nt.links.new(r.outputs["Color"], mul.inputs[6])
    nt.links.new(hr.outputs["Result"], mul.inputs[7])
    nt.links.new(mul.outputs[2], bsdf.inputs["Base Color"])
    bsdf.inputs["Subsurface Weight"].default_value = 0.0
    obj.data.materials.append(m)
    return obj


def scatter_grass(area_obj, tuft, density=22.0, seed=7):
    """Geometry nodes: distribute points on the area plane (clumpy noise mask), instance tufts."""
    ng = bpy.data.node_groups.new("bg_grass", "GeometryNodeTree")
    ng.interface.new_socket("Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
    ng.interface.new_socket("Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    N, L = ng.nodes, ng.links
    gi = N.new("NodeGroupInput")
    go = N.new("NodeGroupOutput")
    pos = N.new("GeometryNodeInputPosition")
    noise = N.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 0.22
    L.new(pos.outputs["Position"], noise.inputs["Vector"])
    dens = N.new("ShaderNodeMapRange")
    dens.inputs["From Min"].default_value = 0.38
    dens.inputs["From Max"].default_value = 0.62
    dens.inputs["To Min"].default_value = 0.0
    dens.inputs["To Max"].default_value = density
    L.new(noise.outputs["Fac"], dens.inputs["Value"])
    dist = N.new("GeometryNodeDistributePointsOnFaces")
    dist.distribute_method = "RANDOM"
    dist.inputs["Seed"].default_value = seed
    L.new(gi.outputs[0], dist.inputs["Mesh"])
    L.new(dens.outputs["Result"], dist.inputs["Density"])
    oinfo = N.new("GeometryNodeObjectInfo")
    oinfo.inputs["Object"].default_value = tuft
    inst = N.new("GeometryNodeInstanceOnPoints")
    rrot = N.new("FunctionNodeRandomValue")
    rrot.data_type = "FLOAT_VECTOR"
    rrot.inputs["Max"].default_value = (0.25, 0.25, math.tau)
    rrot.inputs["Min"].default_value = (-0.25, -0.25, 0.0)
    rsc = N.new("FunctionNodeRandomValue")
    rsc.data_type = "FLOAT"
    rsc.inputs[2].default_value = 0.6   # Min (float)
    rsc.inputs[3].default_value = 1.4   # Max (float)
    L.new(dist.outputs["Points"], inst.inputs["Points"])
    L.new(oinfo.outputs["Geometry"], inst.inputs["Instance"])
    L.new(rrot.outputs[0], inst.inputs["Rotation"])
    L.new(rsc.outputs[1], inst.inputs["Scale"])
    join = N.new("GeometryNodeJoinGeometry")
    L.new(inst.outputs["Instances"], join.inputs["Geometry"])
    L.new(join.outputs["Geometry"], go.inputs[0])
    mod = area_obj.modifiers.new("Grass", "NODES")
    mod.node_group = ng


# ---------------------------------------------------------------- scene

def build_scene(lv, cam_cfg):
    C.reset_scene()
    W, H = lv["cols"] * CELL, lv["rows"] * CELL
    vx, vy, vw, vh = lv["view"]
    field_cx = (vx + vw / 2) * CELL - W / 2
    rng = random.Random(int(lv["id"]) * 101)

    # ground
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0, 0))
    ground = bpy.context.object
    ground.scale = (W + 160, H + 160, 1)
    gm, _ = ground_material(field_cx)
    ground.data.materials.append(gm)

    # grass area: the battlefield north of the wall, a little wider than the camera sees
    wall_front_y = lv["wall_row"] * CELL
    bpy.ops.mesh.primitive_plane_add(size=1)
    area = bpy.context.object
    area.name = "bg_grass_area"
    y0, y1 = 10.0, wall_front_y - 0.6
    area.scale = (W + 12, y1 - y0, 1)
    area.location = B(W / 2, (y0 + y1) / 2, lv, 0.0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    area.data.materials.append(gm)
    area.hide_render = False
    scatter_grass(area, tuft_object())
    area.location.z = 0.002

    # level obstacles (the only props inside the field)
    for i, r in enumerate(lv.get("obstacles", [])):
        kind, s = obstacle_kind(i, r)
        cx = (r[0] + r[2] / 2) * CELL
        cy = (r[1] + r[3] / 2) * CELL
        long_x = r[2] >= r[3]
        yaw = 0 if long_x else 90
        if kind in ("ruin_corner", "block_pile", "ruin_pillar", "rocks"):
            yaw = (i * 137) % 360
        place(kind, None, B(cx, cy, lv), yaw, s)

    # craters at every hotspot
    for k, h in enumerate(lv["hotspots"]):
        cx, cy = (h["cell"][0] + 0.5) * CELL, (h["cell"][1] + 0.5) * CELL
        place("crater", {"seed": 11 + k}, B(cx, cy, lv, 0.01), (k * 71) % 360, 1.1)

    # sparse set dressing around the edges only (keeps focus on the field)
    field = (vx * CELL, vy * CELL, (vx + vw) * CELL, (lv["wall_row"]) * CELL)
    hot = [((h["cell"][0] + 0.5) * CELL, (h["cell"][1] + 0.5) * CELL) for h in lv["hotspots"]]
    placed = []

    def free(px, py, rad):
        if field[0] - 0.5 < px < field[2] + 0.5 and field[1] - 0.5 < py < field[3]:
            return False
        if any(math.hypot(px - a, py - b) < rad + 3.5 for a, b in hot):
            return False
        return all(math.hypot(px - a, py - b) > rad + r2 for a, b, r2 in placed)

    plan = [("ruin_wall", 4, 2.2), ("ruin_corner", 2, 2.4), ("ruin_pillar", 2, 1.5), ("block_pile", 3, 1.8),
            ("container", 1, 3.2), ("car", 1, 2.2), ("rocks", 4, 1.2), ("bush", 6, 0.9), ("pine", 9, 1.8)]
    for kind, count, rad in plan:
        n = 0
        tries = 0
        while n < count and tries < 400:
            tries += 1
            side = rng.random()
            if kind == "pine" and rng.random() < 0.5:
                px, py = rng.uniform(-6, W + 6), rng.uniform(6, field[1] - 1)   # wood line beyond the top
            elif side < 0.5:
                px, py = rng.uniform(-5, field[0] - 0.5), rng.uniform(field[1] - 6, field[3] - 4)
            else:
                px, py = rng.uniform(field[2] + 0.5, W + 5), rng.uniform(field[1] - 6, field[3] - 4)
            if not free(px, py, rad):
                continue
            placed.append((px, py, rad))
            s = rng.uniform(0.8, 1.15) * (rng.uniform(0.8, 1.2) if kind == "pine" else 1.0)
            place(kind, {"seed": rng.randint(1, 999)} if kind != "container" else None, B(px, py, lv),
                  rng.uniform(0, 360) if kind not in ("container", "car") else rng.choice([0, 180]) + rng.uniform(-15, 15),
                  s)
            n += 1

    # settlement wall: slimmer modular wall, towers and doors at the gate opening
    wz = wall_front_y + 0.9 * WALL_SCALE
    g0, g1 = lv["gate_cols"][0] * CELL, (lv["gate_cols"][1] + 1) * CELL
    gw = g1 - g0
    place("gate_doors", None, B((g0 + g1) / 2, wz, lv), 0, scale_xyz=(gw / 8.0, WALL_SCALE, WALL_SCALE))
    tw = 3.0 * WALL_SCALE
    for tx in (g0 - tw / 2 - 0.1, g1 + tw / 2 + 0.1):
        place("gate_tower", None, B(tx, wz, lv), 0, WALL_SCALE)
    seg = 4.0 * WALL_SCALE
    x = g1 + tw + 0.1 + seg / 2
    k = 0
    while x < W + 30:
        place("logo_wall" if k == 0 else "wall_segment", {"seed": 13 + k} if k else None, B(x, wz, lv), 0, WALL_SCALE)
        x += seg
        k += 1
    x = g0 - tw - 0.1 - seg / 2
    k = 0
    while x > -30:
        place("wall_segment", {"seed": 40 + k}, B(x, wz, lv), 0, WALL_SCALE)
        x -= seg
        k += 1
    for lx in (g0 - 7.0, g1 + 7.0):
        place("lamp_post", None, B(lx, wall_front_y - 1.6, lv), 90 if lx < W / 2 else -90, 0.85)
        lamp = bpy.data.lights.new("lamp", "POINT")
        lamp.energy = 180
        lamp.color = (1.0, 0.75, 0.45)
        lamp.shadow_soft_size = 0.3
        lo = bpy.data.objects.new("lamp", lamp)
        lo.location = B(lx + (0.75 if lx < W / 2 else -0.75), wall_front_y - 1.6, lv, 4.0)
        bpy.context.scene.collection.objects.link(lo)
    # crater glow lights
    for (cx, cy) in hot:
        gl = bpy.data.lights.new("crater_glow", "POINT")
        gl.energy = 260
        gl.color = (1.0, 0.35, 0.12)
        gl.shadow_soft_size = 1.0
        go = bpy.data.objects.new("crater_glow", gl)
        go.location = B(cx, cy, lv, 0.6)
        bpy.context.scene.collection.objects.link(go)

    # settlement yard behind the wall (mostly under the deploy tray)
    bpy.ops.mesh.primitive_plane_add(size=1)
    yard = bpy.context.object
    yard.scale = (W + 80, 40, 1)
    yard.location = B(W / 2, wall_front_y + 20, lv, 0.004)
    ym = bpy.data.materials.new("bg_yard")
    ym.use_nodes = True
    ym.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = hex_lin("#2c333b")
    ym.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.95
    yard.data.materials.append(ym)

    C.apply_palette(P.PROP_PALETTE)
    grungify_role_materials()


def setup_camera_and_light(lv, cfg):
    W, H = lv["cols"] * CELL, lv["rows"] * CELL
    vx, vy, vw, vh = lv["view"]
    tx = (vx + vw / 2) * CELL
    ty = (vy * CELL + lv["wall_row"] * CELL) / 2 + cfg["target_y_offset_m"]
    pitch = math.radians(cfg["pitch_deg"])
    target = B(tx, ty, lv)
    cam_data = bpy.data.cameras.new("GameCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = cfg["width_m"]
    cam_data.sensor_fit = "HORIZONTAL"
    cam_data.clip_end = 400
    cam = bpy.data.objects.new("GameCam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    cam.location = target + Vector((0, -math.cos(pitch), math.sin(pitch))) * 120.0
    cam.rotation_euler = Euler((math.pi / 2 - pitch, 0, 0))
    bpy.context.scene.camera = cam
    # sun: same direction as the game's DirectionalLight (rotation_degrees = (-pitch, yaw, 0))
    sp, sy = math.radians(cfg["sun_pitch_deg"]), math.radians(cfg["sun_yaw_deg"])
    d_godot = Vector((-math.sin(sy) * math.cos(sp), -math.sin(sp), -math.cos(sy) * math.cos(sp)))
    d_blender = Vector((d_godot.x, -d_godot.z, d_godot.y))
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 3.6
    sun_data.color = (1.0, 0.88, 0.72)
    sun_data.angle = math.radians(4.0)
    sun = bpy.data.objects.new("Sun", sun_data)
    bpy.context.scene.collection.objects.link(sun)
    sun.rotation_euler = d_blender.to_track_quat("-Z", "Y").to_euler()
    world = bpy.data.worlds.new("bg_world")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.46, 0.55, 0.75, 1)
    bg.inputs["Strength"].default_value = 0.8
    bpy.context.scene.world = world


def render(lv, cfg, samples, preview):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 4
    scene.render.resolution_x = cfg["image_w"]
    scene.render.resolution_y = cfg["image_h"]
    scene.render.resolution_percentage = 50 if preview else 100
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    for look in ("Medium High Contrast", "None"):
        try:
            scene.view_settings.look = look
            break
        except TypeError:
            continue
    scene.render.image_settings.file_format = "JPEG"
    scene.render.image_settings.quality = 90
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"level_{lv['id']}.jpg")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("[bg] wrote", path)


def main(argv):
    only = argv[argv.index("--only") + 1].split(",") if "--only" in argv else None
    samples = int(argv[argv.index("--samples") + 1]) if "--samples" in argv else 48
    preview = "--preview" in argv
    cfg = json.load(open(os.path.join(LEVELS, "camera.json")))
    for f in sorted(os.listdir(LEVELS)):
        if not f.startswith("level_") or not f.endswith(".json"):
            continue
        lv = load_level(os.path.join(LEVELS, f))
        if only and lv["id"] not in only:
            continue
        build_scene(lv, cfg)
        setup_camera_and_light(lv, cfg)
        render(lv, cfg, samples, preview)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    main(args)
