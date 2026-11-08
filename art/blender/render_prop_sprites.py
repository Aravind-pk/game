"""Render gameplay obstacle props as 2D sprites from the game camera.

Same orthographic pitch, sun and materials as the level backgrounds, rendered at the
background's pixel density so a sprite drops onto the painting 1:1. Each sprite is centred
on the prop's ground origin and carries its soft shadow as alpha (Cycles shadow catcher).

    python art/blender/render_prop_sprites.py [--samples 48]
Writes godot/assets/sprites/props/<name>.png and props.json
"""

import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Euler, Vector  # noqa: E402

import ng_common as C  # noqa: E402
import ng_props as P  # noqa: E402
import render_backgrounds as RB  # noqa: E402

REPO = RB.REPO
OUT = os.path.join(REPO, "godot", "assets", "sprites", "props")

# sprite name -> (prop builder, yaw degrees, square frame size in metres)
SPRITES = {
    "ruin_wall_0": ("ruin_wall", 0, 7.0), "ruin_wall_90": ("ruin_wall", 90, 7.0),
    "car_0": ("car", 0, 6.5), "car_90": ("car", 90, 6.5),
    "barrier_0": ("barrier", 0, 6.0), "barrier_90": ("barrier", 90, 6.0),
    "container_0": ("container", 0, 9.0), "container_90": ("container", 90, 9.0),
    "ruin_corner_a": ("ruin_corner", 20, 8.0), "ruin_corner_b": ("ruin_corner", 200, 8.0),
    "block_pile_a": ("block_pile", 15, 6.0), "block_pile_b": ("block_pile", 140, 6.0),
    "ruin_pillar_a": ("ruin_pillar", 30, 7.0), "ruin_pillar_b": ("ruin_pillar", 210, 7.0),
    "rocks_a": ("rocks", 10, 5.0), "rocks_b": ("rocks", 120, 5.0),
    # settlement gate states (scaled like the wall: 0.8 deep/high)
    "gate_intact": ("gate:intact", 0, 12.0), "gate_damaged": ("gate:damaged", 0, 12.0),
    "gate_destroyed": ("gate:destroyed", 0, 12.0),
}


def build_gate(state):
    """Gate doors in three states. Parts are grouped by side (left / right leaf) by position."""
    import random
    from mathutils import Matrix
    rng = random.Random(5)
    parts = P.gate_doors()
    bpy.context.view_layer.update()  # matrix_world is stale until the depsgraph updates
    frame = [o for o in parts if o.name.startswith("gd_frame")]
    left = [o for o in parts if o not in frame and o.location.x < -0.05]
    right = [o for o in parts if o not in frame and o.location.x > 0.05]
    mid = [o for o in parts if o not in frame and o not in left and o not in right]
    extra = []

    def hinge(objs, pivot, rot):
        M = Matrix.Translation(pivot) @ rot.to_matrix().to_4x4() @ Matrix.Translation(-pivot)
        for o in objs:
            o.matrix_world = M @ o.matrix_world

    if state == "damaged":
        hinge(left, Vector((-4.0, 0, 0)), Euler((math.radians(5), 0, math.radians(-6))))
        hinge(right, Vector((4.0, 0, 0)), Euler((math.radians(3), 0, math.radians(5))))
        for k in range(9):  # dents and scorch
            x = rng.uniform(-3.6, 3.6)
            z = rng.uniform(0.6, 4.6)
            extra.append(C.box(f"scorch{k}", (rng.uniform(0.5, 1.2), 0.05, rng.uniform(0.4, 1.0)),
                               (x, -0.62, z), (0, rng.uniform(-30, 30), 0), "scorch", 0.0))
        for k in range(5):
            extra.append(P.rock_shard(f"dent{k}", (0.25, 0.08, 0.2), (rng.uniform(-3.4, 3.4), -0.62, rng.uniform(1, 4)),
                                      (90, 0, 0), "concrete_dark", seed=k, points=8, bev=0.0))
        extra.append(C.box("hot", (0.4, 0.04, 0.12), (-0.6, -0.64, 2.4), (0, 20, 0), "seams", 0.0))
        extra.append(C.box("hot2", (0.3, 0.04, 0.1), (1.4, -0.64, 3.2), (0, -35, 0), "seams", 0.0))
    elif state == "destroyed":
        # leaves blown inward and down, frame beam sagging, rubble everywhere
        hinge(left, Vector((-4.0, -0.45, 0)), Euler((math.radians(80), math.radians(8), math.radians(-14))))
        hinge(right, Vector((4.0, -0.45, 0)), Euler((math.radians(66), math.radians(-12), math.radians(20))))
        hinge(frame, Vector((-4.3, 0, 5.6)), Euler((0, math.radians(14), 0)))
        for k in range(26):
            sz = rng.uniform(0.15, 0.55)
            extra.append(P.rock_shard(f"rub{k}", (sz, sz * 0.8, sz * 0.6),
                                      (rng.uniform(-4.5, 4.5), rng.uniform(-4.0, 0.5), sz * 0.3),
                                      (rng.uniform(0, 40), 0, rng.uniform(0, 180)),
                                      rng.choice(["concrete", "concrete_dark", "steel"]), seed=k, points=9, bev=0.0))
        for k in range(6):
            extra.append(C.box(f"ember{k}", (0.25, 0.25, 0.05), (rng.uniform(-3, 3), rng.uniform(-1.5, 1.0), 0.06),
                               (0, 0, rng.uniform(0, 90)), "seams", 0.0))
        extra.append(C.cylinder("scorchpool", 3.0, 0.03, (0, -1.5, 0.015), mat="scorch", verts=20, bev=0.0))
    return parts + extra


def render_sprite(name, kind, yaw, frame_m, cfg, samples):
    C.reset_scene()
    if kind.startswith("gate:"):
        parts = build_gate(kind.split(":")[1])
        obj = C.join(parts, "sprite_" + name)
        obj.scale = (1.0, 0.8, 0.8)  # same as the wall (render_backgrounds WALL_SCALE)
    else:
        parts = P.PROPS[kind]()
        obj = C.join(parts, "sprite_" + name)
    obj.rotation_euler = (0, 0, math.radians(yaw))
    C.apply_palette(P.PROP_PALETTE)
    RB.grungify_role_materials()
    # shadow catcher ground
    bpy.ops.mesh.primitive_plane_add(size=frame_m * 3)
    ground = bpy.context.object
    ground.is_shadow_catcher = True
    # camera aimed at the prop's ground origin, same pitch/scale as the game
    px_per_m = cfg["image_w"] / cfg["width_m"]
    pitch = math.radians(cfg["pitch_deg"])
    cam_data = bpy.data.cameras.new("SpriteCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = frame_m
    cam_data.sensor_fit = "HORIZONTAL"
    cam = bpy.data.objects.new("SpriteCam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    cam.location = Vector((0, -math.cos(pitch), math.sin(pitch))) * 60.0
    cam.rotation_euler = Euler((math.pi / 2 - pitch, 0, 0))
    bpy.context.scene.camera = cam
    # light: reuse the background's sun + sky
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
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.46, 0.55, 0.75, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    bpy.context.scene.world = world

    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    res = int(round(frame_m * px_per_m))
    sc.render.resolution_x = res
    sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.view_settings.view_transform = "Standard"
    try:
        sc.view_settings.look = "Medium High Contrast"
    except TypeError:
        pass
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    os.makedirs(OUT, exist_ok=True)
    sc.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    return res


def main(argv):
    only = argv[argv.index("--only") + 1].split(",") if "--only" in argv else None
    samples = int(argv[argv.index("--samples") + 1]) if "--samples" in argv else 48
    cfg = json.load(open(os.path.join(RB.LEVELS, "camera.json")))
    mpath = os.path.join(OUT, "props.json")
    manifest = json.load(open(mpath)) if os.path.exists(mpath) else {"sprites": {}}
    manifest["px_per_m"] = cfg["image_w"] / cfg["width_m"]
    for name, (kind, yaw, frame_m) in SPRITES.items():
        if only and name not in only:
            continue
        res = render_sprite(name, kind, yaw, frame_m, cfg, samples)
        manifest["sprites"][name] = {"kind": kind, "size_px": res, "frame_m": frame_m}
        print("[sprite]", name, res)
    json.dump(manifest, open(os.path.join(OUT, "props.json"), "w"), indent=1)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    main(args)
