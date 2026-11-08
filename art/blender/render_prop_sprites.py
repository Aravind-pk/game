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
}


def render_sprite(name, kind, yaw, frame_m, cfg, samples):
    C.reset_scene()
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
    samples = int(argv[argv.index("--samples") + 1]) if "--samples" in argv else 48
    cfg = json.load(open(os.path.join(RB.LEVELS, "camera.json")))
    manifest = {"px_per_m": cfg["image_w"] / cfg["width_m"], "sprites": {}}
    for name, (kind, yaw, frame_m) in SPRITES.items():
        res = render_sprite(name, kind, yaw, frame_m, cfg, samples)
        manifest["sprites"][name] = {"kind": kind, "size_px": res, "frame_m": frame_m}
        print("[sprite]", name, res)
    json.dump(manifest, open(os.path.join(OUT, "props.json"), "w"), indent=1)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    main(args)
