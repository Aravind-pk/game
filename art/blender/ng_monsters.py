"""North Gate monsters: Shale Digger (Burrower), Rift Runner (Stalker),
Faultbreaker (Brute).

Bodies are sculpted procedurally: metaball volumes -> voxel remesh -> noise
displacement -> decimate. Rock armour plates are faceted convex shards placed
over the body; glowing seams sit in the gaps.
"""

import math
import random

import bpy
from mathutils import Vector

from ng_common import (_link, cylinder, join, role_material, rock_shard, set_transform,
                       tube_along, mirror_x)


# --------------------------------------------------------------------------
# Sculpting helpers
# --------------------------------------------------------------------------

def sculpt_body(name, balls, mat="primary", voxel=0.045, noise=0.035, noise_scale=0.35,
                ratio=0.25, seed=0, smooth_iter=12):
    """Clay-style body: union of ellipsoids -> voxel remesh (fuses them) ->
    heavy smoothing (blends the joins) -> voronoi/cloud displacement -> decimate.

    balls: list of (center, radii(x,y,z)[, rot_deg]) ellipsoids.
    """
    import bmesh
    from mathutils import Euler, Matrix
    bm = bmesh.new()
    for b in balls:
        c, r = Vector(b[0]), b[1]
        rot = Euler([math.radians(a) for a in b[2]]).to_matrix().to_4x4() if len(b) > 2 and \
            isinstance(b[2], (tuple, list)) else Matrix.Identity(4)
        mat4 = Matrix.Translation(c) @ rot @ Matrix.Diagonal((r[0], r[1], r[2], 1))
        bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=16, radius=1.0, matrix=mat4)
    from ng_common import mesh_object
    obj = mesh_object(name, bm, None)
    ctx = bpy.context
    for o in ctx.selected_objects:
        o.select_set(False)
    obj.select_set(True)
    ctx.view_layer.objects.active = obj
    rm = obj.modifiers.new("Remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = voxel
    sm = obj.modifiers.new("Blend", "SMOOTH")
    sm.iterations = smooth_iter
    sm.factor = 0.8
    tex = bpy.data.textures.new(name + "_noise", "VORONOI")
    tex.noise_scale = noise_scale
    disp = obj.modifiers.new("Hide", "DISPLACE")
    disp.texture = tex
    disp.strength = noise
    tex2 = bpy.data.textures.new(name + "_fine", "CLOUDS")
    tex2.noise_scale = noise_scale * 0.3
    disp2 = obj.modifiers.new("Fine", "DISPLACE")
    disp2.texture = tex2
    disp2.strength = noise * 0.5
    sm2 = obj.modifiers.new("Soften", "SMOOTH")
    sm2.iterations = 2
    sm2.factor = 0.5
    dec = obj.modifiers.new("Decimate", "DECIMATE")
    dec.ratio = ratio
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    obj.data.materials.append(role_material(mat))
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def plate_on(name, center, radii, theta, phi, size, tilt=20, lift=1.0, mat="armor", seed=0,
             point=0.08, point_y=0.75, bev=0.018, points=12, twist=0.0, jitter=0.18, curve=0.45):
    """Place a shingle plate tangent to an ellipsoid surface.

    theta: around the body (0 = top, +90 = right side, -90 = left side)
    phi:   along the body (-90 = front/-Y, +90 = back/+Y)
    The plate's +Y (where the point is) faces the back, lifted by `tilt`."""
    th, ph = math.radians(theta), math.radians(phi)
    d = Vector((math.sin(th) * math.cos(ph), math.sin(ph), math.cos(th) * math.cos(ph)))
    c = Vector(center)
    pos = c + Vector((d.x * radii[0], d.y * radii[1], d.z * radii[2])) * lift
    n = Vector((d.x / radii[0] ** 2, d.y / radii[1] ** 2, d.z / radii[2] ** 2)).normalized()
    o = rock_shard(name, size, pos, (0, 0, 0), mat, seed=seed, points=points, point=point,
                   point_y=point_y, bev=bev, jitter=jitter, curve=curve)
    back = Vector((0, 1, 0))
    back = (back - n * back.dot(n))
    if back.length < 1e-4:
        back = Vector((1, 0, 0))
    back.normalize()
    side = back.cross(n)
    from mathutils import Matrix, Quaternion
    m = Matrix((side, back, n)).transposed()
    q = m.to_quaternion() @ Quaternion((1, 0, 0), math.radians(tilt)) @ \
        Quaternion((0, 0, 1), math.radians(twist))
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = q
    return o


def claw(name, base, direction, length, radius, curl=0.6, mat="claws", flat=0.65, segs=7,
         curl_axis=None):
    """Curved, tapering talon. direction: unit-ish vector of initial growth;
    curl bends it toward -Z (or toward curl_axis)."""
    d = Vector(direction).normalized()
    bend = Vector(curl_axis) if curl_axis else Vector((0, 0, -1))
    pts = []
    p = Vector(base)
    step = length / segs
    for i in range(segs + 1):
        pts.append(p.copy())
        d = (d + bend * curl * (1.0 / segs) * 2.2).normalized()
        p = p + d * step
    o = tube_along(name, pts, radius, mat, verts=8, taper=(1.0, 0.04))
    # flatten sideways a bit to read as a blade
    return o


def shard_row(prefix, centers, sizes, rots, seed, mat="armor", point=0.0, points=12, bev=0.02):
    out = []
    for i, (c, s, r) in enumerate(zip(centers, sizes, rots)):
        out.append(rock_shard(f"{prefix}{i}", s, c, r, mat, seed=seed + i, points=points,
                              point=point, bev=bev))
    return out


def glow_strip(name, points, radius, mat="seams"):
    return tube_along(name, [Vector(p) for p in points], radius, mat, verts=6)


def _empty(name):
    e = bpy.data.objects.new(name, None)
    _link(e)
    return e


def _finish(root, parts, name):
    """Join everything per material into one mesh, parent under root."""
    body = join(parts, name + "_Mesh")
    body.parent = root
    return body


# --------------------------------------------------------------------------
# SHALE DIGGER — armoured burrower with huge digging claws (Burrower, Lv1)
# --------------------------------------------------------------------------

def build_shale_digger():
    root = _empty("ShaleDigger")
    parts = []
    TORSO_C, TORSO_R = (0, 0.2, 0.55), (0.6, 0.8, 0.5)
    parts.append(sculpt_body("sd_body", [
        (TORSO_C, (0.56, 0.76, 0.46)),
        ((0, -0.45, 0.5), (0.42, 0.4, 0.34)),         # chest
        ((0, -0.82, 0.42), (0.25, 0.3, 0.2)),         # head
        ((0, -1.08, 0.34), (0.13, 0.18, 0.1)),        # snout
        ((0, 0.95, 0.35), (0.34, 0.4, 0.26)),         # rump
        ((0, 1.35, 0.2), (0.12, 0.32, 0.09)),         # tail
        ((-0.5, -0.5, 0.42), (0.2, 0.22, 0.24)),      # shoulders
        ((0.5, -0.5, 0.42), (0.2, 0.22, 0.24)),
        ((-0.62, -0.72, 0.24), (0.17, 0.26, 0.15), (25, 0, 0)),   # forearms
        ((0.62, -0.72, 0.24), (0.17, 0.26, 0.15), (25, 0, 0)),
        ((-0.45, 0.72, 0.18), (0.15, 0.2, 0.17)),     # hind legs
        ((0.45, 0.72, 0.18), (0.15, 0.2, 0.17)),
    ], mat="primary", noise=0.025, seed=1))

    # shingled dorsal armour: rows from neck to rump, each wrapping the back
    rng = random.Random(7)
    k = 0
    for phi in (-58, -40, -22, -4, 14, 32, 50, 66):
        span = 95 if phi < 40 else 75
        n = 6 if phi < 40 else 4
        for j in range(n):
            th = -span + j * (2 * span / (n - 1)) + rng.uniform(-4, 4) + (8 if (phi // 18) % 2 else 0)
            sz = (0.2 - 0.04 * abs(th) / 95, 0.2, 0.055)
            parts.append(plate_on(f"sd_plate{k}", TORSO_C, TORSO_R, th, phi, sz, tilt=24,
                                  seed=100 + k, point=0.1 + 0.06 * (1 - abs(th) / 95),
                                  twist=rng.uniform(-8, 8)))
            k += 1
    # spine ridge spikes
    for i, phi in enumerate((-50, -32, -14, 4, 22, 40, 58)):
        parts.append(plate_on(f"sd_spine{i}", TORSO_C, TORSO_R, 0, phi, (0.08, 0.11, 0.05), tilt=35,
                              lift=1.08, seed=300 + i, point=0.24 - 0.012 * i, point_y=0.6))
    # head armour
    parts.append(rock_shard("sd_headplate", (0.28, 0.34, 0.09), (0, -0.84, 0.6), (14, 0, 0), "armor",
                            seed=401, points=16, bev=0.02, point=0.05, point_y=0.7))
    parts.append(rock_shard("sd_snoutplate", (0.15, 0.2, 0.06), (0, -1.1, 0.43), (22, 0, 0), "armor",
                            seed=402, bev=0.012))
    for s in (-1, 1):
        parts.append(rock_shard(f"sd_cheek{s}", (0.12, 0.2, 0.07), (s * 0.2, -0.9, 0.48),
                                (10, s * 60, 0), "armor", seed=404 + s, bev=0.012, point=0.05))
        parts.append(rock_shard(f"sd_eye{s}", (0.045, 0.03, 0.022), (s * 0.15, -1.04, 0.5),
                                (0, 0, s * 20), "eyes", seed=410 + s, points=8, bev=0))
        parts.append(glow_strip(f"sd_mouth{s}", [(0, -1.16, 0.27), (s * 0.11, -1.08, 0.29),
                                                 (s * 0.2, -0.96, 0.34)], 0.022))
        parts.append(glow_strip(f"sd_neckglow{s}", [(s * 0.22, -0.72, 0.62), (s * 0.34, -0.62, 0.6),
                                                    (s * 0.44, -0.5, 0.52)], 0.022))
        parts.append(tube_along(f"sd_whisk{s}", [Vector((s * 0.09, -1.18, 0.33)),
                                                  Vector((s * 0.24, -1.38, 0.2)),
                                                  Vector((s * 0.34, -1.5, 0.04))], 0.007,
                                "claws", 5, taper=(1, 0.3)))
        # forearm gauntlet + shoulder pauldron
        parts.append(rock_shard(f"sd_gauntlet{s}", (0.22, 0.28, 0.17), (s * 0.64, -0.74, 0.3),
                                (25, s * 15, 0), "armor", seed=420 + s, points=16, bev=0.02,
                                point=0.06, point_y=0.6))
        parts.append(plate_on(f"sd_pauldron{s}", (s * 0.5, -0.5, 0.42), (0.2, 0.22, 0.24), s * 50, -10,
                              (0.2, 0.2, 0.06), tilt=20, seed=430 + s, point=0.1))
        # three big digging claws
        for c in range(3):
            off = (c - 1) * 0.12
            base = Vector((s * 0.64 + off, -0.95, 0.22 + 0.02 * (1 - abs(c - 1))))
            parts.append(claw(f"sd_claw{s}{c}", base, (s * 0.05 + off * 0.6, -0.75, 0.35),
                              0.52 - 0.07 * abs(c - 1), 0.072, curl=1.25))
        for c in range(2):
            base = Vector((s * (0.42 + c * 0.09), 0.58, 0.07))
            parts.append(claw(f"sd_hclaw{s}{c}", base, (s * 0.2, -1, 0.15), 0.2, 0.035, curl=1.0))
        parts.append(plate_on(f"sd_hip{s}", (s * 0.45, 0.72, 0.18), (0.15, 0.2, 0.17), s * 60, 10,
                              (0.13, 0.15, 0.05), tilt=15, seed=440 + s, point=0.06))
    # tail plates
    for i in range(4):
        parts.append(rock_shard(f"sd_tail{i}", (0.13 - i * 0.02, 0.1, 0.05),
                                (0, 1.1 + i * 0.13, 0.33 - i * 0.04), (-12, 0, 0), "armor",
                                seed=450 + i, point=0.05, point_y=0.7, bev=0.01))
    body = _finish(root, parts, "ShaleDigger")
    return root, body


# --------------------------------------------------------------------------
# RIFT RUNNER — fast segmented crawler with scorpion tail (Stalker, Lv2)
# --------------------------------------------------------------------------

def build_rift_runner():
    root = _empty("RiftRunner")
    parts = []
    segs = 7
    centres = []
    for i in range(segs):
        t = i / (segs - 1)
        centres.append((Vector((0, -0.62 + i * 0.22, 0.48 + 0.04 * math.sin(t * math.pi))),
                        0.25 - 0.07 * abs(t - 0.35)))
    tail = []
    n_tail = 12
    for i in range(n_tail):
        a = math.radians(8 + i * 20)
        r = 0.72 - i * 0.03
        tail.append((Vector((0, 0.7 + math.sin(a) * r * 0.85, 0.5 + (1 - math.cos(a)) * r)),
                     0.14 - i * 0.007, 8 + i * 20))

    balls = [((c.x, c.y, c.z - 0.03), (w * 0.85, 0.17, 0.13)) for c, w in centres]
    balls += [((c.x, c.y, c.z), (w * 0.8, w * 0.85, w * 0.8)) for c, w, _ in tail]
    balls.append(((0, -0.88, 0.45), (0.16, 0.2, 0.12)))  # head
    for li, y in enumerate((-0.68, -0.4, -0.08, 0.24)):
        for s in (-1, 1):
            balls.append(((s * 0.2, y, 0.42), (0.1, 0.09, 0.09)))  # coxa
    parts.append(sculpt_body("rr_under", balls, mat="joints", voxel=0.03, noise=0.012, ratio=0.3,
                             seed=2, smooth_iter=8))
    for i, (c, w) in enumerate(centres):
        parts.append(rock_shard(f"rr_seg{i}", (w * 1.05, 0.13, 0.08), c + Vector((0, 0, 0.1)),
                                (-14, 0, 0), "armor", seed=500 + i, points=14, point=0.05, point_y=0.7,
                                bev=0.012, jitter=0.12))
        for s in (-1, 1):
            parts.append(rock_shard(f"rr_side{i}{s}", (0.08, 0.11, 0.05),
                                    c + Vector((s * w * 0.95, 0.02, 0.02)), (-12, s * 55, 0), "armor",
                                    seed=520 + i * 2 + (s > 0), point=0.07, point_y=0.6, bev=0.01))
        if i < segs - 1:
            parts.append(glow_strip(f"rr_glow{i}", [c + Vector((-w * 0.95, 0.11, -0.02)),
                                                    c + Vector((0, 0.11, -0.1)),
                                                    c + Vector((w * 0.95, 0.11, -0.02))], 0.022))
    for i, (c, w, ang) in enumerate(tail):
        a = math.radians(ang)
        n = Vector((0, -math.sin(a), math.cos(a)))
        parts.append(rock_shard(f"rr_tail{i}", (w * 1.25, 0.13, 0.08), c + n * w * 0.5,
                                (-ang, 0, 0), "armor", seed=560 + i, points=12, point=0.03,
                                point_y=0.7, bev=0.01, jitter=0.12))
    last_c, _, last_a = tail[-1]
    parts.append(claw("rr_sting", last_c, (0, -0.95, -0.2), 0.3, 0.05, curl=1.1))
    parts.append(rock_shard("rr_head", (0.19, 0.25, 0.09), (0, -0.92, 0.55), (14, 0, 0), "armor",
                            seed=590, points=16, bev=0.015, point=0.04, point_y=0.7))
    for s in (-1, 1):
        parts.append(rock_shard(f"rr_eye{s}", (0.04, 0.025, 0.02), (s * 0.11, -1.1, 0.5),
                                (0, 0, s * 25), "eyes", seed=595 + s, points=8, bev=0))
        parts.append(tube_along(f"rr_ant{s}", [Vector((s * 0.06, -1.02, 0.6)),
                                                Vector((s * 0.12, -1.15, 0.9)),
                                                Vector((s * 0.2, -1.3, 1.12)),
                                                Vector((s * 0.3, -1.5, 1.2))], 0.012, "joints", 6,
                                taper=(1, 0.3)))
        parts.append(claw(f"rr_mand{s}", (s * 0.09, -1.08, 0.38), (s * 0.3, -1, 0), 0.16, 0.028,
                          curl=1.2, curl_axis=(-s, 0, 0)))
    # legs: armoured femur arching up, tibia down to an ivory talon
    for li, y in enumerate((-0.68, -0.4, -0.08, 0.24)):
        for s in (-1, 1):
            hip = Vector((s * 0.26, y, 0.42))
            spread = (-0.18, -0.05, 0.08, 0.2)[li]
            knee = Vector((s * 0.58, y + spread * 0.5, 0.72))
            foot = Vector((s * 0.82, y + spread, 0.08))
            if li == 0:
                knee = Vector((s * 0.42, y - 0.3, 0.66))
                foot = Vector((s * 0.5, y - 0.62, 0.2))
            parts.append(tube_along(f"rr_femur{li}{s}", [hip, (hip + knee) / 2 + Vector((0, 0, 0.04)),
                                                         knee], 0.075, "joints", 8, taper=(1.1, 0.75)))
            th = rock_shard(f"rr_thigh{li}{s}", (0.09, 0.21, 0.07), (hip + knee) / 2 + Vector((0, 0, 0.06)),
                            (0, 0, 0), "armor", seed=600 + li * 2 + (s > 0), points=12, point=0.05,
                            point_y=0.6, bev=0.01)
            th.rotation_mode = "QUATERNION"
            th.rotation_quaternion = (knee - hip).to_track_quat("Y", "Z")
            parts.append(th)
            parts.append(tube_along(f"rr_tibia{li}{s}", [knee, knee * 0.45 + foot * 0.55 +
                                                         Vector((s * 0.03, 0, 0)), foot],
                                    0.055, "joints", 8, taper=(1, 0.65)))
            tb = rock_shard(f"rr_shin{li}{s}", (0.065, 0.18, 0.055), knee * 0.6 + foot * 0.4,
                            (0, 0, 0), "armor", seed=640 + li * 2 + (s > 0), points=10, bev=0.008)
            tb.rotation_mode = "QUATERNION"
            tb.rotation_quaternion = (foot - knee).to_track_quat("Y", "Z")
            parts.append(tb)
            d = (foot - knee).normalized()
            parts.append(claw(f"rr_tip{li}{s}", foot - d * 0.03, d, 0.26 if li == 0 else 0.18,
                              0.04 if li == 0 else 0.03, curl=1.5 if li == 0 else 0.8,
                              curl_axis=(0, 1, 0.3) if li == 0 else (-s * 0.4, 0, -1)))
            parts.append(glow_strip(f"rr_hipglow{li}{s}", [hip + Vector((0, -0.04, -0.06)),
                                                           hip + Vector((s * 0.08, -0.04, -0.06))], 0.02))
    body = _finish(root, parts, "RiftRunner")
    return root, body


# --------------------------------------------------------------------------
# FAULTBREAKER — massive rock golem with tusks (Brute, Lv3)
# --------------------------------------------------------------------------

def build_faultbreaker():
    root = _empty("Faultbreaker")
    parts = []
    TORSO_C, TORSO_R = (0, 0.25, 1.35), (0.95, 0.85, 0.8)
    parts.append(sculpt_body("fb_body", [
        (TORSO_C, (0.9, 0.78, 0.75)),
        ((0, -0.35, 1.15), (0.62, 0.45, 0.52)),       # chest
        ((0, -0.66, 1.0), (0.28, 0.28, 0.26)),        # head
        ((0, 0.75, 0.6), (0.62, 0.48, 0.48)),         # hips
        ((-1.05, -0.12, 1.45), (0.45, 0.45, 0.42)),   # shoulders
        ((1.05, -0.12, 1.45), (0.45, 0.45, 0.42)),
        ((-1.22, -0.35, 0.95), (0.34, 0.34, 0.48)),   # upper arms
        ((1.22, -0.35, 0.95), (0.34, 0.34, 0.48)),
        ((-1.28, -0.52, 0.42), (0.36, 0.36, 0.36)),   # forearms
        ((1.28, -0.52, 0.42), (0.36, 0.36, 0.36)),
        ((-0.55, 0.85, 0.28), (0.32, 0.36, 0.3)),     # legs
        ((0.55, 0.85, 0.28), (0.32, 0.36, 0.3)),
    ], mat="joints", voxel=0.055, noise=0.04, ratio=0.2, seed=3, smooth_iter=10))

    rng = random.Random(11)
    k = 0
    # back: big blocky plates in rows
    for phi in (-50, -28, -6, 16, 38, 60):
        n = 6
        for j in range(n):
            th = -115 + j * 46 + rng.uniform(-6, 6) + (18 if phi in (-28, 16, 60) else 0)
            sz = (0.46, 0.4, 0.15)
            parts.append(plate_on(f"fb_plate{k}", TORSO_C, TORSO_R, th, phi, sz, tilt=14, seed=700 + k,
                                  point=0.14 if abs(th) < 60 else 0.08, point_y=0.4, points=11,
                                  bev=0.03, twist=rng.uniform(-12, 12), jitter=0.12))
            k += 1
    for s in (-1, 1):
        sc, sr = (s * 1.05, -0.12, 1.45), (0.45, 0.45, 0.42)
        for j, (th, ph) in enumerate(((s * 10, -10), (s * 55, -20), (s * 60, 30), (s * 20, 40),
                                     (s * 100, 0), (s * 100, -50), (s * 140, 20))):
            parts.append(plate_on(f"fb_shoulder{s}{j}", sc, sr, th, ph, (0.34, 0.32, 0.14), tilt=12,
                                  seed=740 + j + (10 if s > 0 else 0), point=0.2 if j == 0 else 0.1,
                                  point_y=0.3, points=11, bev=0.03, jitter=0.12))
        ac, ar = (s * 1.22, -0.35, 0.95), (0.34, 0.34, 0.48)
        for j, (th, ph) in enumerate(((s * 80, -20), (s * 60, -60), (s * 120, 0), (s * 90, 30),
                                     (s * 30, -70), (s * 150, -40))):
            parts.append(plate_on(f"fb_arm{s}{j}", ac, ar, th, ph, (0.3, 0.3, 0.13), tilt=6,
                                  seed=760 + j + (10 if s > 0 else 0), point=0.04, points=11, bev=0.03,
                                  jitter=0.12))
        # fist: knuckle blocks planted on the ground
        parts.append(rock_shard(f"fb_fist{s}", (0.4, 0.38, 0.26), (s * 1.3, -0.6, 0.3),
                                (0, 0, s * 8), "armor", seed=780 + s, points=12, flat_bottom=True,
                                bev=0.03, jitter=0.12))
        for kk in range(4):
            x = s * (1.06 + kk * 0.16)
            parts.append(rock_shard(f"fb_knuckle{s}{kk}", (0.09, 0.12, 0.12), (x, -0.98, 0.15),
                                    (0, 0, 0), "joints", seed=785 + kk + (4 if s > 0 else 0), points=10,
                                    flat_bottom=True, bev=0.02, jitter=0.12))
        parts.append(rock_shard(f"fb_thumb{s}", (0.1, 0.13, 0.11), (s * 0.96, -0.86, 0.26),
                                (0, 0, s * 30), "joints", seed=795 + s, points=10, bev=0.02))
        parts.append(rock_shard(f"fb_forearm{s}", (0.32, 0.3, 0.24), (s * 1.33, -0.5, 0.68),
                                (0, s * 10, 0), "armor", seed=798 + s, points=12, bev=0.03, jitter=0.12))
        parts.append(rock_shard(f"fb_foot{s}", (0.3, 0.35, 0.16), (s * 0.6, 0.78, 0.14), (0, 0, 0),
                                "armor", seed=802 + s, points=11, flat_bottom=True, bev=0.03))
        for j, (th, ph) in enumerate(((s * 40, -70), (s * 80, -45))):
            parts.append(plate_on(f"fb_chest{s}{j}", (0, -0.35, 1.15), (0.62, 0.45, 0.52), th, ph,
                                  (0.26, 0.24, 0.11), tilt=0, seed=820 + j + (5 if s > 0 else 0),
                                  point=0.0, points=11, bev=0.03, jitter=0.12))
        parts.append(plate_on(f"fb_hip{s}", (s * 0.55, 0.85, 0.28), (0.32, 0.36, 0.3), s * 70, 20,
                              (0.28, 0.3, 0.12), tilt=10, seed=830 + s, point=0.05, points=11))
        parts.append(rock_shard(f"fb_pec{s}", (0.3, 0.24, 0.12), (s * 0.4, -0.66, 1.42),
                                (60, 0, s * 25), "armor", seed=806 + s, points=11, bev=0.03, jitter=0.12))
    # head: brow plate, tusks, eyes, chevron mouth glow
    parts.append(rock_shard("fb_brow", (0.32, 0.24, 0.1), (0, -0.82, 1.2), (25, 0, 0), "armor",
                            seed=810, points=12, bev=0.02, point=0.05, point_y=-0.5))
    for s in (-1, 1):
        parts.append(claw(f"fb_tusk{s}", (s * 0.2, -0.86, 0.95), (s * 0.15, -0.5, -0.6), 0.45, 0.075,
                          curl=1.0, curl_axis=(0, -0.6, 1)))
        parts.append(rock_shard(f"fb_eye{s}", (0.05, 0.02, 0.025), (s * 0.12, -0.94, 1.1),
                                (0, 0, -s * 20), "eyes", seed=815 + s, points=8, bev=0))
        parts.append(glow_strip(f"fb_mouth{s}", [(0, -0.94, 0.86), (s * 0.12, -0.91, 0.93),
                                                 (s * 0.22, -0.85, 0.99)], 0.03))
        parts.append(glow_strip(f"fb_mouth2{s}", [(0, -0.92, 0.78), (s * 0.1, -0.89, 0.83),
                                                  (s * 0.18, -0.83, 0.88)], 0.022))
        parts.append(glow_strip(f"fb_crack{s}", [(s * 0.15, -0.8, 1.55), (s * 0.3, -0.78, 1.42),
                                                 (s * 0.28, -0.8, 1.25)], 0.025))
    body = _finish(root, parts, "Faultbreaker")
    return root, body
