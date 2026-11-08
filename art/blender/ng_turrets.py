"""North Gate turrets: Kestrel (machine gun), Mule (cannon), Needle (sniper).

Each builder returns (root_empty, head_object). The head (everything above the
turntable) is a separate child object so the game can rotate it toward targets.
"""

import math

import bpy
from mathutils import Vector

from ng_common import (box, cylinder, join, prism, set_transform, tube_along, mirror_x,
                       _link)


def _empty(name, loc=(0, 0, 0)):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = "PLAIN_AXES"
    e.location = Vector(loc)
    _link(e)
    return e


def hash_marks(prefix, origin, normal_axis, count=2, size=(0.05, 0.16), gap=0.09, slant=25,
               mat="accent", depth=0.012):
    """'//' warning marks on a flat face. origin = centre point on the face,
    normal_axis = 'x', '-x', 'y', '-y'."""
    objs = []
    for i in range(count):
        off = (i - (count - 1) / 2) * gap
        if normal_axis in ("x", "-x"):
            sgn = 1 if normal_axis == "x" else -1
            loc = (origin[0] + sgn * depth / 2, origin[1] + off, origin[2])
            o = box(f"{prefix}_hash{i}", (depth, size[0], size[1]), loc, (slant, 0, 0), mat, bev=0.003)
        else:
            sgn = 1 if normal_axis == "y" else -1
            loc = (origin[0] + off, origin[1] + sgn * depth / 2, origin[2])
            o = box(f"{prefix}_hash{i}", (size[0], depth, size[1]), loc, (0, -slant, 0), mat, bev=0.003)
        objs.append(o)
    return objs


def splayed_legs(prefix, n_legs, hub_r, reach, hub_z, foot_size, leg_w, leg_h, angles,
                 strip=True, thin=False):
    """Angled legs radiating from the hub, each with a foot pad and cyan strip."""
    parts = []
    for i, ang in enumerate(angles):
        a = math.radians(ang)
        d = Vector((math.sin(a), -math.cos(a), 0))
        foot = d * reach
        start = d * hub_r + Vector((0, 0, hub_z))
        # leg profile in local (u = outward, v = up) plane, extruded sideways
        if thin:
            prof = [(0.0, 0.0), (0.0, -0.07), (reach - hub_r, -hub_z + 0.12),
                    (reach - hub_r, -hub_z + 0.2)]
        else:
            prof = [(0.0, 0.06), (0.0, -0.14), (reach - hub_r - 0.05, -hub_z + 0.08),
                    (reach - hub_r + 0.08, -hub_z + 0.08), (reach - hub_r + 0.08, -hub_z + leg_h),
                    (reach - hub_r - 0.18, -hub_z + leg_h + 0.06)]
        leg = prism(f"{prefix}_leg{i}", prof, leg_w, mat="frame" if thin else "primary",
                    bev=0.02, axis="Y")
        # prism built in XZ; rotate so +X points along d
        leg.location = start
        leg.rotation_euler = (0, 0, math.atan2(d.y, d.x))
        parts.append(leg)
        # foot pad
        pad = box(f"{prefix}_foot{i}", foot_size, (foot.x, foot.y, foot_size[2] / 2),
                  (0, 0, math.degrees(math.atan2(d.y, d.x))), "frame", bev=0.02,
                  taper=(0.8, 0.8))
        parts.append(pad)
        if strip:
            sp = foot * 0.93 + Vector((0, 0, foot_size[2] + leg_h * 0.45))
            g = box(f"{prefix}_strip{i}", (0.03, leg_w * 0.35, leg_h * 0.55), sp,
                    (0, 0, math.degrees(math.atan2(d.y, d.x))), "glow", bev=0.006)
            g.location = sp + d * 0.05
            parts.append(g)
    return parts


# --------------------------------------------------------------------------
# KESTREL — twin-barrel machine-gun turret
# --------------------------------------------------------------------------

def build_kestrel():
    root = _empty("Kestrel")
    base = []
    base += splayed_legs("k", 4, 0.22, 0.95, 0.5, (0.36, 0.42, 0.1), 0.26, 0.42,
                         [45, 135, 225, 315])
    base.append(cylinder("k_hub", 0.34, 0.22, (0, 0, 0.5), mat="frame", verts=8, bev=0.02))
    base.append(cylinder("k_turntable", 0.42, 0.08, (0, 0, 0.65), mat="secondary", verts=32))
    base.append(cylinder("k_turntable_rim", 0.44, 0.04, (0, 0, 0.6), mat="frame", verts=32))
    base_obj = join(base, "Kestrel_Base")

    head = []
    hz = 1.12
    head.append(cylinder("k_neck", 0.2, 0.3, (0, 0, 0.8), mat="frame", verts=16))
    # main housing — chamfered front
    prof = [(-0.36, -0.24), (0.36, -0.24), (0.36, 0.22), (0.2, 0.32), (-0.3, 0.32), (-0.36, 0.2)]
    head.append(prism("k_body", prof, 0.82, (0, 0.05, hz), mat="primary", bev=0.03, axis="Y"))
    # cream cowl over the top/front
    cowl = [(-0.38, 0.12), (0.38, 0.12), (0.38, 0.28), (0.18, 0.38), (-0.32, 0.38), (-0.38, 0.26)]
    head.append(prism("k_cowl", cowl, 0.5, (0, -0.2, hz), mat="secondary", bev=0.025, axis="Y"))
    head.append(box("k_sideplate_L", (0.04, 0.5, 0.3), (-0.39, 0.05, hz - 0.02), mat="secondary",
                    bev=0.012))
    head.append(box("k_rear", (0.6, 0.12, 0.38), (0, 0.5, hz + 0.02), mat="frame", bev=0.02))
    # barrel shroud block + twin barrels
    head.append(box("k_shroud", (0.48, 0.3, 0.3), (-0.06, -0.48, hz + 0.02), mat="frame", bev=0.03))
    for i, x in enumerate((-0.17, 0.05)):
        z = hz + 0.02
        head.append(cylinder(f"k_barrel{i}", 0.055, 0.9, (x, -1.02, z), (90, 0, 0), "metal", 16, 0.008))
        head.append(cylinder(f"k_muzzle{i}", 0.075, 0.18, (x, -1.42, z), (90, 0, 0), "frame", 8, 0.01))
        head.append(cylinder(f"k_collar{i}", 0.07, 0.06, (x, -0.72, z), (90, 0, 0), "frame", 12, 0.008))
        for s in range(3):
            head.append(box(f"k_vent{i}{s}", (0.012, 0.03, 0.16), (x, -1.37 - s * 0.04, z),
                            mat="metal", bev=0))
    # drum magazine on the right side
    head.append(cylinder("k_drum", 0.3, 0.3, (0.58, 0.18, hz - 0.08), (0, 90, 0), "frame", 32, 0.03))
    head.append(cylinder("k_drum_cap", 0.22, 0.04, (0.745, 0.18, hz - 0.08), (0, 90, 0),
                         "secondary", 24, 0.01))
    head += hash_marks("k_drum", (0.77, 0.18, hz - 0.08), "x", size=(0.05, 0.14), gap=0.08)
    # ammo belt: chain of cartridges arcing from drum to receiver
    belt_pts = []
    for t in range(16):
        f = t / 15
        ang = math.radians(-60 + 200 * f)
        belt_pts.append(Vector((0.46 + 0.02 * math.sin(f * 3.14), 0.18 + math.cos(ang) * 0.36,
                                hz - 0.08 + math.sin(ang) * 0.36)))
    for t, p in enumerate(belt_pts[:-1]):
        nxt = belt_pts[t + 1]
        d = nxt - p
        o = box(f"k_round{t}", (0.12, 0.05, 0.035), (p + nxt) / 2, mat="secondary", bev=0.006)
        o.rotation_euler = (math.atan2(d.z, d.y), 0, 0)
        head.append(o)
        head.append(cylinder(f"k_tip{t}", 0.012, 0.03, (p + nxt) / 2 + Vector((0.07, 0, 0)),
                             (0, 90, 0), "accent", 6, 0))
    head += hash_marks("k_side", (-0.41, 0.05, hz + 0.08), "-x")
    head.append(box("k_sensor", (0.1, 0.05, 0.05), (-0.25, -0.3, hz + 0.37), mat="frame", bev=0.01))
    head.append(box("k_sensor_lens", (0.06, 0.012, 0.03), (-0.25, -0.33, hz + 0.37), mat="glow", bev=0))
    head_obj = join(head, "Kestrel_Head")
    _parent_turret(root, base_obj, head_obj, pivot=(0, 0, 0.7))
    return root, head_obj


# --------------------------------------------------------------------------
# MULE — heavy cannon
# --------------------------------------------------------------------------

def build_mule():
    root = _empty("Mule")
    base = []
    base += splayed_legs("m", 4, 0.4, 1.35, 0.55, (0.52, 0.56, 0.12), 0.42, 0.5,
                         [50, 130, 230, 310])
    base.append(cylinder("m_hub", 0.6, 0.3, (0, 0, 0.55), mat="frame", verts=8, bev=0.03))
    base.append(cylinder("m_turntable", 0.7, 0.1, (0, 0, 0.74), mat="frame", verts=40))
    base.append(cylinder("m_ring", 0.66, 0.04, (0, 0, 0.8), mat="secondary", verts=40))
    for i, ang in enumerate((90, 270)):
        a = math.radians(ang)
        base.append(box(f"m_lamp{i}", (0.05, 0.1, 0.08),
                        (math.cos(a) * 0.61, math.sin(a) * 0.61, 0.55), (0, 0, ang), "glow", 0.01))
    base_obj = join(base, "Mule_Base")

    head = []
    hz = 1.45
    # yoke cheeks
    for s in (-1, 1):
        prof = [(-0.55, -0.62), (0.45, -0.62), (0.4, 0.05), (0.1, 0.32), (-0.45, 0.32)]
        head.append(prism(f"m_cheek{s}", prof, 0.14, (s * 0.6, 0.15, hz - 0.1), (0, 0, 0),
                          "primary", 0.03, axis="X"))
        head.append(cylinder(f"m_trunnion{s}", 0.2, 0.08, (s * 0.65, 0.05, hz), (0, 90, 0),
                             "secondary", 24, 0.015))
        head += hash_marks(f"m_cheek{s}", (s * 0.64, 0.25, hz - 0.35), "x" if s > 0 else "-x",
                           size=(0.06, 0.18), gap=0.1)
    head.append(box("m_yoke", (1.0, 0.9, 0.3), (0, 0.1, 0.95), mat="frame", bev=0.04))
    # hydraulic pistons
    for s in (-1, 1):
        head.append(cylinder(f"m_piston_a{s}", 0.07, 0.55, (s * 0.32, -0.25, 1.15), (-35, 0, 0),
                             "frame", 12, 0.01))
        head.append(cylinder(f"m_piston_b{s}", 0.045, 0.45, (s * 0.32, -0.45, 1.38), (-35, 0, 0),
                             "metal", 12, 0.008))
    # rear drum housing (big cylinder with cream wrap panels)
    head.append(cylinder("m_drum", 0.52, 0.95, (0, 0.62, hz), (0, 90, 0), "secondary", 40, 0.04))
    head.append(cylinder("m_drum_end", 0.46, 1.0, (0, 0.62, hz), (0, 90, 0), "frame", 40, 0.03))
    for k in range(6):
        a = math.radians(k * 30 - 15)
        head.append(box(f"m_drum_seam{k}", (0.97, 0.025, 0.025),
                        (0, 0.62 + math.sin(a) * 0.525, hz + math.cos(a) * 0.525), (math.degrees(-a), 0, 0),
                        "frame", 0))
    for s in (-1, 1):
        head.append(cylinder(f"m_band{s}", 0.56, 0.08, (s * 0.3, 0.62, hz), (0, 90, 0), "primary", 40, 0.02))
    # armoured breech block
    breech = [(-0.5, -0.4), (0.5, -0.4), (0.55, 0.3), (0.3, 0.52), (-0.3, 0.52), (-0.55, 0.3)]
    head.append(prism("m_breech", breech, 0.85, (0, -0.1, hz), mat="primary", bev=0.04, axis="Y"))
    head.append(box("m_topplate", (0.55, 0.6, 0.06), (0, -0.05, hz + 0.53), mat="secondary", bev=0.02))
    # barrel: tapered, then big hexagonal muzzle
    head.append(cylinder("m_barrel", 0.27, 1.25, (0, -1.05, hz + 0.08), (90, 0, 0), "metal", 24,
                         0.02, radius2=0.24))
    head.append(cylinder("m_sleeve", 0.33, 0.55, (0, -0.75, hz + 0.08), (90, 0, 0), "primary", 8, 0.03))
    head += hash_marks("m_sleeve", (0.31, -0.75, hz + 0.18), "x", size=(0.06, 0.14), gap=0.1)
    head += hash_marks("m_sleeveL", (-0.31, -0.75, hz + 0.18), "-x", size=(0.06, 0.14), gap=0.1)
    head.append(cylinder("m_muzzle", 0.42, 0.55, (0, -1.85, hz + 0.08), (90, 0, 0), "secondary", 6,
                         0.04))
    head.append(cylinder("m_bore", 0.27, 0.1, (0, -2.1, hz + 0.08), (90, 0, 0), "frame", 6, 0.0))
    head.append(cylinder("m_bore_dark", 0.24, 0.02, (0, -2.16, hz + 0.08), (90, 0, 0), "metal", 6, 0))
    head.append(box("m_sight", (0.14, 0.3, 0.12), (0.32, -0.25, hz + 0.6), mat="frame", bev=0.02))
    head.append(box("m_sight_lens", (0.08, 0.02, 0.06), (0.32, -0.41, hz + 0.6), mat="glow", bev=0))
    head_obj = join(head, "Mule_Head")
    _parent_turret(root, base_obj, head_obj, pivot=(0, 0, 0.8))
    return root, head_obj


# --------------------------------------------------------------------------
# NEEDLE — long-range rail sniper on a tripod
# --------------------------------------------------------------------------

def build_needle():
    root = _empty("Needle")
    base = []
    # tripod: two armoured front legs + one rear, long and thin
    for i, ang in enumerate((40, 320, 180)):
        a = math.radians(ang)
        d = Vector((math.sin(a), -math.cos(a), 0))
        top = d * 0.12 + Vector((0, 0, 0.95))
        knee = d * 0.75 + Vector((0, 0, 0.55))
        foot = d * 1.15 + Vector((0, 0, 0.1))
        base.append(tube_along(f"n_leg{i}", [top, knee, foot], 0.06, "frame", 10))
        # armour sleeve on upper leg
        mid = (top + knee) / 2
        sl = box(f"n_sleeve{i}", (0.16, 0.5, 0.14), mid, mat="primary", bev=0.025)
        dv = knee - top
        sl.rotation_euler = (0, 0, 0)
        sl.rotation_mode = "QUATERNION"
        sl.rotation_quaternion = dv.to_track_quat("Y", "Z")
        base.append(sl)
        base.append(box(f"n_foot{i}", (0.34, 0.26, 0.1), (foot.x, foot.y, 0.05),
                        (0, 0, math.degrees(math.atan2(d.y, d.x))), "frame", 0.02, (0.8, 0.8)))
        sp = (knee + foot) / 2
        g = box(f"n_strip{i}", (0.03, 0.07, 0.2), sp + Vector((0, 0, 0.12)), mat="secondary", bev=0.006)
        g.rotation_mode = "QUATERNION"
        g.rotation_quaternion = (foot - knee).to_track_quat("Z", "Y")
        base.append(g)
        base += hash_marks(f"n_foot{i}", (foot.x + d.x * 0.17, foot.y + d.y * 0.17, 0.06),
                           "x", count=1, size=(0.03, 0.06)) if False else []
    base.append(cylinder("n_hub", 0.2, 0.25, (0, 0, 0.95), mat="frame", verts=8, bev=0.02))
    base.append(cylinder("n_column", 0.11, 0.3, (0, 0, 1.2), mat="primary", verts=12))
    base.append(cylinder("n_turntable", 0.24, 0.07, (0, 0, 1.36), mat="frame", verts=24))
    base_obj = join(base, "Needle_Base")

    head = []
    hz = 1.62
    # rear body block with cyan vents
    body = [(-0.3, -0.22), (0.3, -0.22), (0.3, 0.16), (0.18, 0.26), (-0.22, 0.26), (-0.3, 0.14)]
    head.append(prism("n_body", body, 0.75, (0, 0.35, hz), mat="primary", bev=0.03, axis="Y"))
    head.append(box("n_backcap", (0.56, 0.1, 0.4), (0, 0.76, hz), mat="frame", bev=0.03))
    for s in (-1, 1):
        for k in range(2):
            head.append(box(f"n_vent{s}{k}", (0.02, 0.18, 0.05), (s * 0.31, 0.25 + k * 0.25, hz - 0.03),
                            mat="glow", bev=0.004))
    head.append(cylinder("n_mount", 0.16, 0.2, (0, 0.2, hz - 0.28), mat="frame", verts=12))
    # upper + lower rails (cream), joined by a spine with the glow channel
    for i, z in enumerate((hz + 0.11, hz - 0.11)):
        head.append(box(f"n_rail{i}", (0.16, 1.9, 0.09), (0, -0.85, z), mat="secondary", bev=0.02,
                        taper=None))
        head.append(box(f"n_railtip{i}", (0.16, 0.18, 0.09), (0, -1.86, z + (0.02 if i == 0 else -0.02)),
                        (0 if i else -10, 0, 0), "secondary", 0.02))
    head.append(box("n_spine", (0.1, 1.75, 0.13), (0, -0.82, hz), mat="frame", bev=0.015))
    head.append(box("n_glow", (0.115, 1.4, 0.035), (0, -0.95, hz), mat="glow", bev=0.006))
    head.append(box("n_collar", (0.24, 0.16, 0.36), (0, -0.05, hz), mat="primary", bev=0.025))
    head.append(cylinder("n_lens_dot", 0.03, 0.02, (0.08, -0.05, hz + 0.19), (0, 0, 0), "glow", 10, 0))
    # scope
    head.append(cylinder("n_scope", 0.06, 0.45, (0.0, 0.15, hz + 0.36), (90, 0, 0), "frame", 16, 0.01))
    head.append(cylinder("n_scope_lens", 0.05, 0.02, (0.0, -0.08, hz + 0.36), (90, 0, 0), "glow", 16, 0))
    head.append(box("n_scope_mount", (0.06, 0.12, 0.1), (0, 0.15, hz + 0.28), mat="frame", bev=0.01))
    # cables from body to mount
    for s in (-1, 1):
        pts = [Vector((s * 0.22, 0.55, hz - 0.2)), Vector((s * 0.26, 0.5, hz - 0.42)),
               Vector((s * 0.18, 0.25, hz - 0.45)), Vector((s * 0.1, 0.15, hz - 0.3))]
        head.append(tube_along(f"n_cable{s}", pts, 0.025, "frame", 8))
    head += hash_marks("n_body", (0.31, 0.5, hz + 0.12), "x", count=1, size=(0.04, 0.1))
    head_obj = join(head, "Needle_Head")
    _parent_turret(root, base_obj, head_obj, pivot=(0, 0, 1.4))
    return root, head_obj


def _parent_turret(root, base_obj, head_obj, pivot):
    """Base is a child of root; head is re-origined at its yaw pivot."""
    import bpy as _bpy
    base_obj.parent = root
    # move head origin to the pivot so rotating it in-game yaws around the turntable
    cursor = _bpy.context.scene.cursor
    cursor.location = Vector(pivot)
    for o in _bpy.context.selected_objects:
        o.select_set(False)
    head_obj.select_set(True)
    _bpy.context.view_layer.objects.active = head_obj
    _bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    cursor.location = (0, 0, 0)
    head_obj.parent = root
