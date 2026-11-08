"""North Gate environment props (post-apocalyptic battlefield + settlement gate).

Every builder returns a list of parts which build_props.py joins into one mesh per
prop. Same conventions as the units: metres, origin on the ground, the side the game
camera sees faces -Y in Blender (+Z in Godot).
"""

import math
import random

import bpy
from mathutils import Vector

from ng_common import box, cylinder, prism, rock_shard, tube_along, mesh_object, role_material

PROP_PALETTE = {
    "concrete": "#8E9196",
    "concrete_dark": "#5E646B",
    "steel": "#3E4752",
    "rebar": "#6B4A3A",
    "rust": "#8A4B2E",
    "container": "#9C4632",
    "paint": "#6E7F86",
    "glass": "#1E2833",
    "bark": "#4A3A2C",
    "foliage": "#2F4A2C",
    "foliage_light": "#4E6B36",
    "rock": "#6E6A66",
    "stripe": "#F2B630",
    "stripe_dark": "#22252A",
    "vine": "#3E5F2A",
    "lamp": "#FFC66E",
    "glow": "#2FF3FF",
    "seams": "#FF5A1F",
    "scorch": "#2A2220",
    "logo": "#E9E4D8",
}


def _rng(seed):
    return random.Random(seed)


def rebar(name, base, length, bend=0.3, seed=0):
    r = _rng(seed)
    d = Vector((r.uniform(-0.3, 0.3), r.uniform(-0.3, 0.3), 1.0)).normalized()
    p0 = Vector(base)
    p1 = p0 + d * length * 0.6
    p2 = p1 + (d + Vector((r.uniform(-1, 1), r.uniform(-1, 1), 0)) * bend).normalized() * length * 0.4
    return tube_along(name, [p0, p1, p2], 0.022, "rebar", 6)


def rubble(prefix, centre, spread, count, seed, size=0.25, mat="concrete"):
    r = _rng(seed)
    parts = []
    for i in range(count):
        s = size * r.uniform(0.5, 1.4)
        loc = (centre[0] + r.uniform(-spread[0], spread[0]), centre[1] + r.uniform(-spread[1], spread[1]),
               s * 0.35)
        parts.append(rock_shard(f"{prefix}{i}", (s, s * r.uniform(0.6, 1.0), s * 0.6), loc,
                                (r.uniform(-20, 20), r.uniform(-20, 20), r.uniform(0, 180)), mat,
                                seed=seed * 31 + i, points=9, flat_bottom=True, bev=0.01, jitter=0.3))
    return parts


def jagged_top(width, height, teeth, seed, drop=0.9):
    """Wall profile (x, z) with a broken, jagged top edge."""
    r = _rng(seed)
    pts = [(-width / 2, 0.0), (width / 2, 0.0)]
    top = []
    for i in range(teeth + 1):
        x = width / 2 - i * width / teeth
        z = height - r.uniform(0, drop) * (0.4 + 0.6 * abs(math.sin(i * 1.7 + seed)))
        top.append((x, max(0.6, z)))
    return pts + top


# ---------------------------------------------------------------- ruins

def ruin_wall(seed=1):
    parts = []
    prof = jagged_top(4.0, 2.8, 7, seed)
    parts.append(prism("rw_wall", prof, 0.45, (0, 0, 0), mat="concrete", bev=0.02, axis="Y"))
    parts.append(box("rw_base", (4.05, 0.5, 0.45), (0, 0, 0.22), mat="concrete_dark", bev=0.02))
    # panel seams / window hole frame
    parts.append(box("rw_frame", (1.0, 0.08, 0.9), (-0.7, -0.24, 1.5), mat="concrete_dark", bev=0.01))
    parts.append(box("rw_hole", (0.8, 0.1, 0.7), (-0.7, -0.27, 1.5), mat="glass", bev=0.0))
    r = _rng(seed)
    for i in range(5):
        parts.append(rebar(f"rw_rebar{i}", (r.uniform(-1.8, 1.8), 0, 1.8 + r.uniform(0, 0.6)), 0.7, seed=seed + i))
    parts += rubble("rw_rub", (0.3, -0.7), (1.8, 0.4), 9, seed + 3)
    # vines
    for k in range(2):
        x = r.uniform(-1.6, 1.6)
        pts = [Vector((x + math.sin(t * 2.3 + k) * 0.2, -0.26, 0.1 + t * 1.6)) for t in [i / 6 for i in range(7)]]
        parts.append(tube_along(f"rw_vine{k}", pts, 0.035, "vine", 5))
    return parts


def ruin_corner(seed=2):
    parts = []
    parts.append(prism("rc_a", jagged_top(3.4, 3.2, 6, seed), 0.4, (0, 0.0, 0), mat="concrete", axis="Y"))
    b = prism("rc_b", jagged_top(2.6, 2.6, 5, seed + 5), 0.4, (1.5, 1.1, 0), mat="concrete", axis="Y")
    b.rotation_euler[2] = math.radians(90)
    parts.append(b)
    parts.append(box("rc_slab", (2.2, 1.2, 0.2), (-0.8, -1.2, 0.35), (12, -8, 25), "concrete_dark", 0.02))
    parts += rubble("rc_rub", (0.0, -0.9), (1.4, 0.6), 10, seed + 2)
    r = _rng(seed)
    for i in range(4):
        parts.append(rebar(f"rc_rebar{i}", (r.uniform(-1.4, 1.4), 0, 2.2 + r.uniform(0, 0.5)), 0.6, seed=seed + 9 + i))
    return parts


def ruin_pillar(seed=3):
    parts = []
    parts.append(box("rp_col", (0.8, 0.8, 3.4), (0, 0, 1.7), mat="concrete", bev=0.03))
    parts.append(rock_shard("rp_top", (0.45, 0.45, 0.3), (0, 0, 3.4), (0, 0, 20), "concrete", seed=seed,
                            points=10, point=0.3, bev=0.01))
    parts.append(box("rp_band", (0.86, 0.86, 0.3), (0, 0, 0.3), mat="concrete_dark", bev=0.02))
    parts.append(box("rp_beam", (3.2, 0.6, 0.5), (1.1, 0.2, 0.9), (0, -28, 10), "concrete", 0.03))
    for i in range(3):
        parts.append(rebar(f"rp_rebar{i}", (0.25 * (i - 1), 0.2, 3.3), 0.6, seed=seed + i))
    parts += rubble("rp_rub", (0.6, -0.4), (1.2, 0.6), 8, seed + 4)
    return parts


def block_pile(seed=4):
    """Stacked concrete cubes like the grey block clusters in the concept."""
    parts = []
    r = _rng(seed)
    spots = [(-0.9, 0, 0), (0.25, 0.1, 0), (-0.35, 0.05, 1), (1.2, -0.2, 0), (0.7, 0.9, 0)]
    for i, (x, y, layer) in enumerate(spots):
        s = r.uniform(0.95, 1.15)
        parts.append(box(f"bp_{i}", (s, s, s), (x, y, s / 2 + layer * 1.0), (0, 0, r.uniform(-12, 12)),
                         "concrete", 0.04))
    parts += rubble("bp_rub", (0, -0.9), (1.4, 0.3), 6, seed + 1, size=0.18)
    return parts


def barrier(seed=5):
    parts = []
    prof = [(-0.35, 0), (0.35, 0), (0.3, 0.15), (0.12, 0.35), (0.1, 0.85), (-0.1, 0.85), (-0.12, 0.35),
            (-0.3, 0.15)]
    for i in range(2):
        b = prism(f"jb_{i}", prof, 2.0, (i * 2.1 - 1.05, 0, 0), (0, 0, 90 if False else 0),
                  "concrete", 0.015, axis="X")
        b.rotation_euler[2] = math.radians(3 * (i - 0.5))
        parts.append(b)
        for k in range(4):
            s = box(f"jb_s{i}{k}", (0.22, 0.03, 0.18), (i * 2.1 - 1.05 - 0.6 + k * 0.4, -0.115, 0.6),
                    (0, 25, 0), "stripe" if k % 2 == 0 else "stripe_dark", 0.0)
            parts.append(s)
    return parts


def container(seed=6):
    parts = []
    L, W, H = 6.0, 2.4, 2.6
    parts.append(box("ct_body", (L, W, H), (0, 0, H / 2), mat="container", bev=0.03))
    for i in range(22):  # corrugation ribs on the camera side and top edge
        x = -L / 2 + 0.2 + i * (L - 0.4) / 21
        parts.append(box(f"ct_rib{i}", (0.09, 0.06, H - 0.3), (x, -W / 2 - 0.02, H / 2), mat="container", bev=0.0))
    for z in (0.08, H - 0.12):
        parts.append(box(f"ct_rail{z}", (L + 0.04, W + 0.04, 0.16), (0, 0, z), mat="rust", bev=0.01))
    for i in range(8):  # roof corrugation
        parts.append(box(f"ct_roof{i}", (0.35, W - 0.1, 0.05), (-L / 2 + 0.5 + i * (L - 1.0) / 7, 0, H + 0.02),
                         mat="container", bev=0.0))
    for x in (-L / 2, L / 2):
        parts.append(box(f"ct_post{x}", (0.16, W + 0.06, H), (x, 0, H / 2), mat="rust", bev=0.01))
    parts.append(box("ct_door", (0.06, W - 0.3, H - 0.3), (L / 2 + 0.05, 0, H / 2), mat="rust", bev=0.0))
    for k in range(3):
        parts.append(box(f"ct_patch{k}", (0.8, 0.03, 0.5), (-2 + k * 1.8, -W / 2 - 0.06, 0.7 + k * 0.5),
                         mat="rust", bev=0.0))
    return parts


def car(seed=7):
    parts = []
    body = [(-2.0, 0.35), (2.0, 0.35), (2.05, 0.8), (1.6, 0.95), (0.7, 1.0), (0.1, 1.5), (-1.4, 1.55),
            (-1.95, 1.2)]
    parts.append(prism("car_body", body, 1.7, (0, 0, 0), mat="paint", bev=0.06, axis="Y"))
    win = [(0.55, 1.02), (0.12, 1.45), (-1.3, 1.5), (-1.75, 1.18), (-1.75, 1.02)]
    parts.append(prism("car_win", win, 1.72, (0, 0, 0), mat="glass", bev=0.02, axis="Y"))
    for x in (-1.3, 1.3):
        for y in (-0.82, 0.82):
            parts.append(cylinder(f"car_wheel{x}{y}", 0.36, 0.25, (x, y, 0.3), (90, 0, 0), "stripe_dark", 14, 0.03))
    for k in range(4):
        parts.append(box(f"car_rust{k}", (0.6, 0.03, 0.3), (-1.4 + k * 0.9, -0.86, 0.55 + (k % 2) * 0.2),
                         mat="rust", bev=0.0))
    parts.append(box("car_bumper", (0.15, 1.75, 0.2), (2.02, 0, 0.45), mat="steel", bev=0.02))
    parts.append(box("car_light", (0.05, 0.35, 0.12), (2.06, -0.6, 0.72), mat="glass", bev=0.0))
    return parts


# ---------------------------------------------------------------- nature

def pine(seed=8, height=6.5):
    parts = []
    r = _rng(seed)
    parts.append(cylinder("pn_trunk", 0.16, height * 0.45, (0, 0, height * 0.22), mat="bark", verts=8,
                          radius2=0.1))
    layers = 5
    for i in range(layers):
        t = i / (layers - 1)
        rad = (1.6 - 1.25 * t) * r.uniform(0.92, 1.08)
        z = height * (0.22 + 0.62 * t)
        cone = cylinder(f"pn_cone{i}", rad, height * 0.3, (0, 0, z + height * 0.15), mat=(
            "foliage" if i % 2 == 0 else "foliage_light"), verts=9, bev=0.0, radius2=0.05)
        cone.rotation_euler[2] = r.uniform(0, 3.14)
        # jag the skirt: push alternate bottom verts in/out
        me = cone.data
        for k, v in enumerate(me.vertices):
            if v.co.z < 0:
                f = 1.0 + (0.18 if k % 2 == 0 else -0.12)
                v.co.x *= f
                v.co.y *= f
                v.co.z -= 0.15 if k % 2 == 0 else 0.0
        parts.append(cone)
    return parts


def bush(seed=9):
    parts = []
    r = _rng(seed)
    for i in range(5):
        s = r.uniform(0.45, 0.8)
        parts.append(rock_shard(f"bs_{i}", (s, s, s * 0.8), (r.uniform(-0.7, 0.7), r.uniform(-0.5, 0.5), s * 0.6),
                                (0, 0, r.uniform(0, 180)), "foliage" if i % 2 else "foliage_light",
                                seed=seed * 7 + i, points=14, bev=0.0, jitter=0.25))
    return parts


def rocks(seed=10):
    parts = []
    r = _rng(seed)
    for i in range(3):
        s = r.uniform(0.6, 1.2)
        parts.append(rock_shard(f"rk_{i}", (s, s * 0.8, s * 0.7), (i * 0.9 - 0.9, r.uniform(-0.3, 0.3), s * 0.4),
                                (r.uniform(-10, 10), 0, r.uniform(0, 180)), "rock", seed=seed * 5 + i, points=12,
                                flat_bottom=True, bev=0.02, jitter=0.25))
    return parts


def crater(seed=11):
    """Spawn fissure: scorched dish, ring of broken slabs, glowing cracks."""
    parts = []
    r = _rng(seed)
    bm_disc = cylinder("cr_scorch", 2.6, 0.04, (0, 0, 0.02), mat="scorch", verts=20, bev=0.0)
    parts.append(bm_disc)
    for i in range(11):
        a = i / 11 * math.tau + r.uniform(-0.2, 0.2)
        d = r.uniform(1.4, 2.1)
        s = r.uniform(0.35, 0.6)
        parts.append(rock_shard(f"cr_slab{i}", (s, s * 0.7, s * 0.35), (math.cos(a) * d, math.sin(a) * d, 0.2),
                                (r.uniform(20, 45), 0, math.degrees(a) + 90), "rock", seed=seed * 13 + i,
                                points=10, bev=0.01, jitter=0.3))
    for i in range(7):  # radial glowing cracks
        a = i / 7 * math.tau + r.uniform(-0.3, 0.3)
        pts = [Vector((0, 0, 0.05))]
        rad = 0
        while rad < 2.2:
            rad += r.uniform(0.3, 0.5)
            a += r.uniform(-0.35, 0.35)
            pts.append(Vector((math.cos(a) * rad, math.sin(a) * rad, 0.05)))
        parts.append(tube_along(f"cr_crack{i}", pts, 0.06, "seams", 5, taper=(1.6, 0.3)))
    parts.append(cylinder("cr_core", 0.6, 0.06, (0, 0, 0.06), mat="seams", verts=10, bev=0.0))
    return parts


def lamp_post(seed=12):
    parts = []
    parts.append(cylinder("lp_pole", 0.09, 5.0, (0, 0, 2.5), mat="steel", verts=10))
    parts.append(box("lp_base", (0.4, 0.4, 0.4), (0, 0, 0.2), mat="concrete_dark", bev=0.02))
    parts.append(box("lp_arm", (1.1, 0.08, 0.08), (0.45, 0, 4.9), mat="steel", bev=0.01))
    parts.append(box("lp_head", (0.5, 0.3, 0.16), (0.9, 0, 4.82), mat="steel", bev=0.02))
    parts.append(box("lp_light", (0.42, 0.24, 0.04), (0.9, 0, 4.73), mat="lamp", bev=0.0))
    parts.append(box("lp_box", (0.22, 0.12, 0.35), (0, -0.12, 1.4), mat="steel", bev=0.01))
    return parts


# ---------------------------------------------------------------- settlement wall / gate

def _railing(prefix, x0, x1, y, z, h=0.9):
    parts = [box(f"{prefix}_top", (x1 - x0, 0.06, 0.06), ((x0 + x1) / 2, y, z + h), mat="steel", bev=0.0),
             box(f"{prefix}_mid", (x1 - x0, 0.04, 0.04), ((x0 + x1) / 2, y, z + h * 0.5), mat="steel", bev=0.0)]
    n = max(2, int((x1 - x0) / 0.8))
    for i in range(n + 1):
        x = x0 + i * (x1 - x0) / n
        parts.append(box(f"{prefix}_post{i}", (0.05, 0.05, h), (x, y, z + h / 2), mat="steel", bev=0.0))
    return parts


def wall_segment(seed=13, vines=True):
    """4 m modular reinforced concrete wall section with walkway and railing."""
    parts = []
    W, H, D = 4.0, 4.2, 1.8
    parts.append(box("ws_core", (W, D, H), (0, 0, H / 2), mat="concrete", bev=0.03))
    for k, x in enumerate((-1.0, 1.0)):  # recessed panels on the camera side
        parts.append(box(f"ws_panel{k}", (1.8, 0.06, 2.6), (x, -D / 2 - 0.02, 2.3), mat="concrete_dark", bev=0.015))
    parts.append(box("ws_plinth", (W + 0.02, D + 0.3, 0.7), (0, 0, 0.35), mat="concrete_dark", bev=0.03))
    parts.append(box("ws_cap", (W + 0.02, D + 0.2, 0.25), (0, 0, H + 0.12), mat="concrete_dark", bev=0.02))
    for k in range(5):  # hazard band
        parts.append(box(f"ws_haz{k}", (0.45, 0.03, 0.22), (-1.6 + k * 0.8, -D / 2 - 0.17, 0.62), (0, 30, 0),
                         "stripe", 0.0))
    parts += _railing("ws_rail", -W / 2, W / 2, -D / 2 + 0.1, H + 0.25)
    parts.append(box("ws_pipe", (W, 0.12, 0.12), (0, -D / 2 - 0.08, 3.75), mat="steel", bev=0.0))
    if vines:
        r = _rng(seed)
        for k in range(3):
            x = r.uniform(-1.7, 1.7)
            pts = [Vector((x + math.sin(t * 9 + k) * 0.25, -D / 2 - 0.06, H - t * r.uniform(1.8, 3.4)))
                   for t in [i / 7 for i in range(8)]]
            parts.append(tube_along(f"ws_vine{k}", pts, 0.05, "vine", 5, taper=(1.2, 0.5)))
            for j in range(4):
                p = pts[1 + j]
                parts.append(rock_shard(f"ws_leaf{k}{j}", (0.18, 0.06, 0.14), (p.x, p.y - 0.04, p.z), (90, 0, 0),
                                        "foliage_light", seed=seed + k * 9 + j, points=8, bev=0.0))
    return parts


def gate_tower(seed=14):
    parts = []
    W, D, H = 3.0, 3.0, 7.0
    parts.append(box("gt_core", (W, D, H), (0, 0, H / 2), mat="steel", bev=0.04))
    parts.append(box("gt_plinth", (W + 0.3, D + 0.3, 1.0), (0, 0, 0.5), mat="concrete_dark", bev=0.03))
    parts.append(box("gt_cap", (W + 0.4, D + 0.4, 0.4), (0, 0, H + 0.2), mat="concrete", bev=0.03))
    parts.append(box("gt_window", (1.6, 0.05, 0.45), (0, -D / 2 - 0.02, 5.6), mat="lamp", bev=0.0))
    parts.append(box("gt_slit", (0.25, 0.05, 1.2), (0.9, -D / 2 - 0.02, 3.6), mat="glow", bev=0.0))
    parts.append(box("gt_panel", (2.2, 0.06, 2.2), (0, -D / 2 - 0.03, 2.6), mat="concrete_dark", bev=0.01))
    for k in range(4):
        parts.append(box(f"gt_haz{k}", (0.4, 0.03, 0.2), (-0.9 + k * 0.6, -D / 2 - 0.05, 1.2), (0, 30, 0),
                         "stripe", 0.0))
    parts += _railing("gt_rail", -W / 2 - 0.2, W / 2 + 0.2, -D / 2 - 0.1, H + 0.4)
    for x in (-1.1, 1.1):  # floodlights
        parts.append(box(f"gt_fl{x}", (0.45, 0.3, 0.3), (x, -D / 2 - 0.1, H + 0.75), (-20, 0, 0), "steel", 0.02))
        parts.append(box(f"gt_fll{x}", (0.38, 0.03, 0.22), (x, -D / 2 - 0.27, H + 0.7), (-20, 0, 0), "lamp", 0.0))
    parts.append(cylinder("gt_ant", 0.03, 1.6, (1.0, 0.8, H + 1.2), mat="steel", verts=6, bev=0.0))
    return parts


def gate_doors(width=8.0, seed=15):
    parts = []
    H, D = 5.4, 0.9
    parts.append(box("gd_frame", (width + 0.6, D + 0.4, 0.6), (0, 0, H + 0.3), mat="steel", bev=0.03))
    for side in (-1, 1):
        cx = side * width / 4
        parts.append(box(f"gd_leaf{side}", (width / 2 - 0.08, D, H), (cx, 0, H / 2), mat="steel", bev=0.03))
        for k in range(3):  # raised panels
            parts.append(box(f"gd_pan{side}{k}", (width / 2 - 0.6, 0.08, 1.15), (cx, -D / 2 - 0.03, 1.9 + k * 1.25),
                             mat="concrete_dark", bev=0.015))
        for k in range(5):  # hazard chevrons at the bottom
            parts.append(box(f"gd_chev{side}{k}", (0.42, 0.03, 1.0),
                             (cx - 1.4 + k * 0.7, -D / 2 - 0.08, 0.6), (0, 35 * side, 0), "stripe", 0.0))
        parts.append(box(f"gd_dark{side}", (width / 2 - 0.2, 0.04, 1.1), (cx, -D / 2 - 0.05, 0.6),
                         mat="stripe_dark", bev=0.0))
        parts.append(box(f"gd_light{side}", (0.3, 0.05, 0.2), (side * (width / 2 - 0.5), -D / 2 - 0.05, H - 0.4),
                         mat="glow", bev=0.0))
    parts.append(box("gd_seam", (0.08, 0.05, H), (0, -D / 2 - 0.03, H / 2), mat="stripe_dark", bev=0.0))
    return parts


def text_mesh(name, text, size, loc, mat, extrude=0.03):
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = text
    cu.size = size
    cu.extrude = extrude
    cu.align_x = "CENTER"
    obj = bpy.data.objects.new(name, cu)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = Vector(loc)
    obj.rotation_euler = (math.radians(90), 0, 0)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.view_layer.objects.active
    obj.data.materials.clear()
    obj.data.materials.append(role_material(mat))
    return obj


def logo_wall(seed=16):
    """Wall section with the North Gate emblem and the G-01 marking."""
    parts = wall_segment(seed, vines=False)
    D = 1.8
    # emblem: two stacked chevrons (mountain) like the UI logo
    for k, (w, z) in enumerate(((1.6, 2.3), (1.0, 2.9))):
        prof = [(-w / 2, 0), (0, w * 0.55), (w / 2, 0), (w / 2 - 0.28, 0), (0, w * 0.55 - 0.32), (-w / 2 + 0.28, 0)]
        ch = prism(f"lw_chev{k}", prof, 0.05, (-0.9, -D / 2 - 0.07, z - 0.4), mat="logo", bev=0.0, axis="Y")
        parts.append(ch)
    parts.append(text_mesh("lw_g01", "G-01", 0.9, (0.95, -D / 2 - 0.07, 2.45), "logo"))
    parts.append(text_mesh("lw_ng", "NORTH GATE", 0.26, (0.95, -D / 2 - 0.07, 2.05), "logo"))
    return parts


PROPS = {
    "ruin_wall": ruin_wall,
    "ruin_corner": ruin_corner,
    "ruin_pillar": ruin_pillar,
    "block_pile": block_pile,
    "barrier": barrier,
    "container": container,
    "car": car,
    "pine": pine,
    "bush": bush,
    "rocks": rocks,
    "crater": crater,
    "lamp_post": lamp_post,
    "wall_segment": wall_segment,
    "logo_wall": logo_wall,
    "gate_tower": gate_tower,
    "gate_doors": gate_doors,
}
