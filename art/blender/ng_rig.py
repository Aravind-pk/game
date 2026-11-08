"""Skeletons, skin weights and animations for the North Gate monsters.

rig(model_id) is called after the model is built, decimated and textured. It:
  1. creates an armature whose bones follow the anatomy the builders produce,
  2. skins the joined mesh with smooth distance-based weights (2 strongest bones),
  3. keys the actions  idle / walk / attack / emerge / death  (24 fps).

Rotations are authored in model space (X = right, Y = back, Z = up; the monster faces -Y)
and converted into each bone's local frame, so the animation code reads naturally:
"rotate the left front leg -30 degrees about X" swings it forward.
"""

import math

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

FPS = 24


# ---------------------------------------------------------------- skeleton definitions
# name: (head, tail, parent)

def _mirror(bones):
    out = {}
    for name, (h, t, p) in bones.items():
        out[name] = (h, t, p)
        if name.endswith("_L"):
            rn = name[:-2] + "_R"
            rp = p[:-2] + "_R" if p and p.endswith("_L") else p
            out[rn] = ((-h[0], h[1], h[2]), (-t[0], t[1], t[2]), rp)
    return out


def shale_digger_bones():
    return _mirror({
        "body": ((0, 0.75, 0.5), (0, -0.4, 0.55), None),
        "head": ((0, -0.5, 0.52), (0, -1.15, 0.4), "body"),
        "tail": ((0, 0.95, 0.35), (0, 1.6, 0.18), "body"),
        "arm_L": ((-0.46, -0.42, 0.5), (-0.63, -0.72, 0.26), "body"),
        "claw_L": ((-0.63, -0.72, 0.26), (-0.65, -1.35, 0.25), "arm_L"),
        "leg_L": ((-0.42, 0.68, 0.38), (-0.46, 0.6, 0.04), "body"),
    })


def _rift_tail_points():
    pts = []
    for i in range(12):
        a = math.radians(8 + i * 20)
        r = 0.72 - i * 0.03
        pts.append((0, 0.7 + math.sin(a) * r * 0.85, 0.5 + (1 - math.cos(a)) * r))
    return pts


def rift_runner_bones():
    b = {
        "thorax": ((0, -0.2, 0.5), (0, -0.72, 0.5), None),
        "abdomen": ((0, -0.2, 0.5), (0, 0.42, 0.52), "thorax"),
        "head": ((0, -0.72, 0.5), (0, -1.15, 0.48), "thorax"),
    }
    tp = _rift_tail_points()
    chain = [(0, 3), (3, 6), (6, 9), (9, 11)]
    parent = "abdomen"
    for k, (i, j) in enumerate(chain):
        b[f"tail{k + 1}"] = (tp[i], tp[j], parent)
        parent = f"tail{k + 1}"
    b["sting"] = (tp[11], (0, tp[11][1] - 0.3, tp[11][2] - 0.08), "tail4")
    for li, y in enumerate((-0.68, -0.4, -0.08, 0.24)):
        spread = (-0.18, -0.05, 0.08, 0.2)[li]
        hip = (-0.26, y, 0.42)
        knee = (-0.58, y + spread * 0.5, 0.72)
        foot = (-0.82, y + spread, 0.08)
        if li == 0:
            knee = (-0.42, y - 0.3, 0.66)
            foot = (-0.5, y - 0.62, 0.2)
        par = "thorax" if li < 2 else "abdomen"
        b[f"femur{li}_L"] = (hip, knee, par)
        b[f"tibia{li}_L"] = (knee, foot, f"femur{li}_L")
    return _mirror(b)


def faultbreaker_bones():
    return _mirror({
        "hips": ((0, 0.8, 0.55), (0, 0.3, 1.2), None),
        "torso": ((0, 0.3, 1.2), (0, -0.45, 1.5), "hips"),
        "head": ((0, -0.5, 1.1), (0, -0.98, 1.0), "torso"),
        "arm_L": ((-0.95, -0.1, 1.5), (-1.24, -0.36, 0.88), "torso"),
        "fore_L": ((-1.24, -0.36, 0.88), (-1.3, -0.55, 0.4), "arm_L"),
        "fist_L": ((-1.3, -0.55, 0.4), (-1.3, -1.0, 0.15), "fore_L"),
        "leg_L": ((-0.55, 0.82, 0.62), (-0.6, 0.8, 0.08), "hips"),
    })


SKELETONS = {
    "shale_digger": shale_digger_bones,
    "rift_runner": rift_runner_bones,
    "faultbreaker": faultbreaker_bones,
}


# ---------------------------------------------------------------- armature + skinning

def _build_armature(name, bones):
    arm_data = bpy.data.armatures.new(name + "_Armature")
    arm = bpy.data.objects.new(name + "_Armature", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones
    # parents first
    order, seen = [], set()

    def visit(n):
        if n in seen:
            return
        p = bones[n][2]
        if p:
            visit(p)
        seen.add(n)
        order.append(n)

    for n in bones:
        visit(n)
    for n in order:
        h, t, p = bones[n]
        b = eb.new(n)
        b.head = Vector(h)
        b.tail = Vector(t)
        b.roll = 0.0
        if p:
            b.parent = eb[p]
            b.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def _seg_dist(p, a, b):
    ab = b - a
    t = np.clip(((p - a) @ ab) / max(ab @ ab, 1e-9), 0.0, 1.0)
    proj = a + np.outer(t, ab)
    return np.linalg.norm(p - proj, axis=1)


def _skin(mesh_obj, arm, bones):
    me = mesh_obj.data
    n = len(me.vertices)
    co = np.empty(n * 3)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    M = np.array(mesh_obj.matrix_world)
    world = co @ M[:3, :3].T + M[:3, 3]
    names = list(bones.keys())
    D = np.stack([_seg_dist(world, np.array(bones[k][0]), np.array(bones[k][1])) for k in names], axis=1)
    # two closest bones, inverse-distance^4 blend
    idx = np.argsort(D, axis=1)[:, :2]
    d = np.take_along_axis(D, idx, axis=1) + 1e-4
    w = 1.0 / d ** 4
    w /= w.sum(axis=1, keepdims=True)
    groups = {k: mesh_obj.vertex_groups.new(name=k) for k in names}
    for vi in range(n):
        for j in range(2):
            if w[vi, j] > 0.02:
                groups[names[idx[vi, j]]].add([vi], float(w[vi, j]), "REPLACE")
    mod = mesh_obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    mw = mesh_obj.matrix_world.copy()
    mesh_obj.parent = arm
    mesh_obj.matrix_world = mw


# ---------------------------------------------------------------- animation helpers

class Animator:
    def __init__(self, arm):
        self.arm = arm
        self.rest = {b.name: b.matrix_local.to_quaternion() for b in arm.data.bones}
        self.rest_parent = {}
        for b in arm.data.bones:
            self.rest_parent[b.name] = b.matrix_local.to_3x3()
        if arm.animation_data is None:
            arm.animation_data_create()

    def begin(self, name, frames):
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        self.arm.animation_data.action = act
        self.action = act
        self.frames = frames
        for pb in self.arm.pose.bones:
            pb.rotation_mode = "QUATERNION"
        # rest key on every bone at both ends keeps every channel in every action
        for f in (0, frames):
            for pb in self.arm.pose.bones:
                pb.rotation_quaternion = Quaternion()
                pb.location = Vector()
                pb.keyframe_insert("rotation_quaternion", frame=f)
                pb.keyframe_insert("location", frame=f)
        return act

    def rot(self, bone, frame, x=0.0, y=0.0, z=0.0):
        """Model-space rotation (degrees, applied X then Y then Z) converted to the bone's frame."""
        from mathutils import Euler
        q_model = Euler((math.radians(x), math.radians(y), math.radians(z)), "XYZ").to_quaternion()
        r = self.rest[bone]
        q_local = r.inverted() @ q_model @ r
        pb = self.arm.pose.bones[bone]
        pb.rotation_quaternion = q_local
        pb.keyframe_insert("rotation_quaternion", frame=frame)

    def move(self, bone, frame, x=0.0, y=0.0, z=0.0):
        r = self.rest_parent[bone]
        pb = self.arm.pose.bones[bone]
        pb.location = r.inverted() @ Vector((x, y, z))
        pb.keyframe_insert("location", frame=frame)

    def end(self, cyclic):
        if cyclic:
            for fc in _fcurves(self.action):
                for kp in fc.keyframe_points:
                    kp.interpolation = "BEZIER"
        self.arm.animation_data.action = None


def _fcurves(action):
    try:
        return list(action.fcurves)
    except AttributeError:  # Blender 5 layered actions
        out = []
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    out.extend(bag.fcurves)
        return out


def _cycle(n, frames, fn):
    """Call fn(frame, phase 0..2pi) on n evenly spaced keys of a loop (last == first)."""
    for k in range(n + 1):
        f = round(k * frames / n)
        fn(f, 2 * math.pi * k / n)


# ---------------------------------------------------------------- actions per monster

def anim_shale_digger(A):
    s, c = math.sin, math.cos
    A.begin("idle", 24)
    _cycle(4, 24, lambda f, p: (A.move("body", f, z=0.02 * s(p)), A.rot("head", f, x=4 * s(p + 1))))
    A.end(True)

    A.begin("walk", 14)  # scuttling dig-walk

    def walk(f, p):
        A.move("body", f, z=0.04 * abs(s(p)), x=0.02 * s(p))
        A.rot("body", f, y=4 * s(p))
        A.rot("arm_L", f, x=-28 * s(p))
        A.rot("arm_R", f, x=28 * s(p))
        A.rot("claw_L", f, x=-12 * s(p + 0.6))
        A.rot("claw_R", f, x=12 * s(p + 0.6))
        A.rot("leg_L", f, x=25 * s(p))
        A.rot("leg_R", f, x=-25 * s(p))
        A.rot("tail", f, z=12 * s(p))
        A.rot("head", f, z=-5 * s(p))
    _cycle(8, 14, walk)
    A.end(True)

    A.begin("attack", 24)  # alternating raking swipes
    for f, l, r, b in ((0, 0, 0, 0), (6, -55, 10, -6), (10, 30, 0, 8), (14, 10, -55, -6), (18, 0, 30, 8), (24, 0, 0, 0)):
        A.rot("arm_L", f, x=l)
        A.rot("arm_R", f, x=r)
        A.rot("claw_L", f, x=l * 0.6)
        A.rot("claw_R", f, x=r * 0.6)
        A.rot("body", f, x=b)
    A.end(True)

    A.begin("emerge", 22)  # claws heave the body out of the ground
    for f, b, arm in ((0, -35, -80), (8, -20, -100), (14, -10, 20), (22, 0, 0)):
        A.rot("body", f, x=b)
        A.rot("arm_L", f, x=arm)
        A.rot("arm_R", f, x=arm + (10 if f else 0))
        A.rot("head", f, x=-b * 0.4)
    A.end(False)

    A.begin("death", 24)
    for f, roll, curl in ((0, 0, 0), (8, 25, 30), (16, 80, 60), (24, 95, 70)):
        A.rot("body", f, y=roll)
        A.move("body", f, z=-0.15 * (f / 24))
        for side in ("L", "R"):
            A.rot(f"arm_{side}", f, x=-curl)
            A.rot(f"leg_{side}", f, x=curl * 0.5)
        A.rot("head", f, x=curl * 0.4)
        A.rot("tail", f, x=-curl * 0.3)
    A.end(False)


def anim_rift_runner(A):
    s = math.sin
    legs = [(li, side) for li in range(4) for side in ("L", "R")]
    # alternating tetrapod gait: (0L,1R,2L,3R) vs (0R,1L,2R,3L)
    def phase_of(li, side):
        return 0.0 if (li % 2 == 0) == (side == "L") else math.pi

    A.begin("idle", 24)
    _cycle(4, 24, lambda f, p: (A.move("thorax", f, z=0.015 * s(p)), A.rot("tail1", f, x=-4 * s(p)),
                                 A.rot("tail3", f, x=-6 * s(p + 1))))
    A.end(True)

    A.begin("walk", 10)

    def walk(f, p):
        A.move("thorax", f, z=0.025 * abs(s(2 * p)))
        A.rot("abdomen", f, z=5 * s(p))
        A.rot("tail1", f, z=-6 * s(p))
        A.rot("tail2", f, x=-5 * s(p + 1))
        for li, side in legs:
            if li == 0:
                continue
            q = p + phase_of(li, side)
            sign = 1 if side == "L" else -1
            A.rot(f"femur{li}_{side}", f, z=sign * 22 * s(q), y=sign * 10 * max(0.0, s(q + 1.57)))
            A.rot(f"tibia{li}_{side}", f, y=-sign * 8 * max(0.0, s(q + 1.57)))
        for side in ("L", "R"):
            A.rot(f"femur0_{side}", f, x=-10 * s(p + (0 if side == "L" else math.pi)))
    _cycle(8, 10, walk)
    A.end(True)

    A.begin("attack", 18)  # rear up, raptorial strike + tail stab
    for f, rear, strike, tail in ((0, 0, 0, 0), (6, -14, -50, 25), (10, 6, 35, -45), (18, 0, 0, 0)):
        A.rot("thorax", f, x=rear)
        A.rot("femur0_L", f, x=strike)
        A.rot("femur0_R", f, x=strike)
        A.rot("tibia0_L", f, x=strike * 0.6)
        A.rot("tibia0_R", f, x=strike * 0.6)
        A.rot("tail2", f, x=tail)
        A.rot("tail3", f, x=tail)
    A.end(True)

    A.begin("emerge", 22)
    for f, b in ((0, -40), (10, -25), (16, -8), (22, 0)):
        A.rot("thorax", f, x=b)
        A.rot("tail1", f, x=-b * 0.8)
        for li, side in legs:
            sign = 1 if side == "L" else -1
            A.rot(f"femur{li}_{side}", f, y=sign * (b * 0.6))
    A.end(False)

    A.begin("death", 24)
    for f, k in ((0, 0), (8, 0.4), (16, 0.9), (24, 1.0)):
        A.rot("thorax", f, y=170 * k)
        A.move("thorax", f, z=0.1 * k)
        for li, side in legs:
            sign = 1 if side == "L" else -1
            A.rot(f"femur{li}_{side}", f, y=-sign * 50 * k)
            A.rot(f"tibia{li}_{side}", f, y=-sign * 60 * k)
        A.rot("tail1", f, x=40 * k)
    A.end(False)


def anim_faultbreaker(A):
    s = math.sin
    A.begin("idle", 30)
    _cycle(4, 30, lambda f, p: (A.move("hips", f, z=0.03 * s(p)), A.rot("torso", f, x=3 * s(p)),
                                 A.rot("head", f, z=6 * s(p * 0.5))))
    A.end(True)

    A.begin("walk", 26)  # heavy knuckle-walk

    def walk(f, p):
        A.move("hips", f, z=0.08 * abs(s(p)), x=0.06 * s(p))
        A.rot("torso", f, y=7 * s(p), z=-6 * s(p))
        A.rot("arm_L", f, x=-26 * s(p))
        A.rot("arm_R", f, x=26 * s(p))
        A.rot("fore_L", f, x=-10 * s(p - 0.5))
        A.rot("fore_R", f, x=10 * s(p - 0.5))
        A.rot("leg_L", f, x=18 * s(p))
        A.rot("leg_R", f, x=-18 * s(p))
        A.rot("head", f, z=-4 * s(p))
    _cycle(8, 26, walk)
    A.end(True)

    A.begin("attack", 30)  # double-fist overhead slam
    for f, arm, fore, torso in ((0, 0, 0, 0), (10, -120, -40, -18), (15, -130, -30, -22), (19, 20, 10, 16),
                                (24, 10, 5, 10), (30, 0, 0, 0)):
        for side in ("L", "R"):
            A.rot(f"arm_{side}", f, x=arm)
            A.rot(f"fore_{side}", f, x=fore)
        A.rot("torso", f, x=torso)
    A.end(True)

    A.begin("emerge", 22)
    for f, t, arm in ((0, 40, -90), (8, 25, -110), (15, 8, -20), (22, 0, 0)):
        A.rot("torso", f, x=t)
        for side in ("L", "R"):
            A.rot(f"arm_{side}", f, x=arm)
    A.end(False)

    A.begin("death", 30)
    for f, k in ((0, 0), (10, 0.35), (20, 0.85), (30, 1.0)):
        A.rot("torso", f, x=55 * k)
        A.move("hips", f, z=-0.45 * k)
        A.rot("hips", f, y=12 * k)
        for side in ("L", "R"):
            A.rot(f"arm_{side}", f, x=-30 * k, y=(20 if side == "L" else -20) * k)
        A.rot("head", f, x=25 * k)
    A.end(False)


ANIMS = {
    "shale_digger": anim_shale_digger,
    "rift_runner": anim_rift_runner,
    "faultbreaker": anim_faultbreaker,
}


def rig(model_id):
    if model_id not in SKELETONS:
        return None
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    mesh = meshes[0]
    root = mesh.parent
    bones = SKELETONS[model_id]()
    arm = _build_armature(mesh.name.replace("_Mesh", ""), bones)
    if root:
        arm.parent = root
    _skin(mesh, arm, bones)
    bpy.context.scene.render.fps = FPS
    ANIMS[model_id](Animator(arm))
    bpy.context.scene.frame_set(0)
    return arm
