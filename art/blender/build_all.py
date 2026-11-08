"""Build every North Gate model, save .blend sources, export .glb files for Godot
and render preview colour-study sheets.

Usage (from the repo root):
    blender --background --python art/blender/build_all.py
    # or with the bpy module:  python art/blender/build_all.py [--no-render] [--no-textures]
    #                          [--tex-size 1024] [--only kestrel,mule]
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import ng_common as C  # noqa: E402
import ng_monsters as M  # noqa: E402
import ng_turrets as T  # noqa: E402
import ng_texture as X  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
BLEND_DIR = os.path.join(REPO, "art", "blender", "models")
PREVIEW_DIR = os.path.join(REPO, "art", "previews")
GLB_DIR = os.path.join(REPO, "godot", "assets", "models")
ICON_DIR = os.path.join(REPO, "godot", "assets", "ui", "icons")
ICON_PALETTE = {"turrets": "polar_ceramic", "monsters": "basalt_ember"}  # in-game defaults
TEX_DIR = os.path.join(REPO, "art", "blender", "models", "textures")

# triangle budgets for mobile (monsters appear in crowds)
TRI_BUDGET = {"shale_digger": 9000, "rift_runner": 9000, "faultbreaker": 12000}

# id, display name, game role, builder, family, preview camera (target z, distance)
MODELS = [
    ("kestrel", "KESTREL", "MG Turret", T.build_kestrel, "turrets", (0.9, 6.0)),
    ("mule", "MULE", "Cannon", T.build_mule, "turrets", (1.2, 9.0)),
    ("needle", "NEEDLE", "Sniper", T.build_needle, "turrets", (1.1, 7.5)),
    ("shale_digger", "SHALE DIGGER", "Burrower", M.build_shale_digger, "monsters", (0.5, 6.0)),
    ("rift_runner", "RIFT RUNNER", "Stalker", M.build_rift_runner, "monsters", (0.6, 6.5)),
    ("faultbreaker", "FAULTBREAKER", "Brute", M.build_faultbreaker, "monsters", (1.1, 10.0)),
]


def palettes_for(family):
    return C.TURRET_PALETTES if family == "turrets" else C.MONSTER_PALETTES


def main(argv):
    render = "--no-render" not in argv
    textures = "--no-textures" not in argv
    tex_size = int(argv[argv.index("--tex-size") + 1]) if "--tex-size" in argv else 1024
    only = None
    if "--only" in argv:
        only = set(argv[argv.index("--only") + 1].split(","))
    report = []
    for mid, title, role, builder, family, (tz, dist) in MODELS:
        if only and mid not in only:
            continue
        C.reset_scene()
        builder()
        pals = palettes_for(family)
        first = next(iter(pals))
        C.apply_palette(pals[first])
        if mid in TRI_BUDGET:
            C.decimate_to(TRI_BUDGET[mid])
        if textures:
            X.bake_textures(mid, "turret" if family == "turrets" else "monster", TEX_DIR, tex_size)
        tris = C.triangle_count()
        C.save_blend(os.path.join(BLEND_DIR, f"{mid}.blend"))
        for pname, pal in pals.items():
            C.apply_palette(pal)
            C.export_glb(os.path.join(GLB_DIR, family, f"{mid}_{pname}.glb"))
            if render:
                C.render_preview(os.path.join(PREVIEW_DIR, "renders", f"{mid}_{pname}.png"),
                                 target=(0, -0.2, tz), distance=dist, yaw=-50, pitch=18,
                                 res=(640, 520), samples=32)
        if render:
            C.apply_palette(pals[ICON_PALETTE[family]])
            C.render_preview(os.path.join(ICON_DIR, f"{mid}.png"), target=(0, -0.2, tz),
                             distance=dist, yaw=-50, pitch=18, res=(320, 260), samples=24,
                             background=False)
        report.append((mid, role, tris))
        print(f"[north-gate] {mid}: {tris} triangles, {len(pals)} palettes")
    if render:
        try:
            make_sheets()
        except ImportError:
            print("[north-gate] Pillow not installed; skipping contact sheets")
    print("[north-gate] done:", report)


def make_sheets():
    from PIL import Image, ImageDraw, ImageFont

    def font(sz):
        for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
                  "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf"):
            if os.path.exists(f):
                return ImageFont.truetype(f, sz)
        return ImageFont.load_default()

    for family, title in (("turrets", "NORTH GATE — TURRET MODELS"),
                          ("monsters", "NORTH GATE — MONSTER MODELS")):
        models = [m for m in MODELS if m[4] == family]
        pals = palettes_for(family)
        cw, ch, lw, top = 640, 520, 300, 170
        W, H = lw + cw * len(models), top + ch * len(pals)
        sheet = Image.new("RGB", (W, H), (246, 240, 230))
        d = ImageDraw.Draw(sheet)
        d.text((W // 2, 60), title, fill=(30, 26, 24), font=font(54), anchor="mm")
        for ci, m in enumerate(models):
            d.text((lw + ci * cw + cw // 2, 135), f"{m[1]}  ·  {m[2]}", fill=(40, 34, 30),
                   font=font(30), anchor="mm")
        for ri, (pname, pal) in enumerate(pals.items()):
            y0 = top + ri * ch
            d.line([(20, y0), (W - 20, y0)], fill=(200, 190, 178), width=2)
            d.text((24, y0 + 30), f"{chr(65 + ri)}  {pname.replace('_', ' ').upper()}",
                   fill=(30, 26, 24), font=font(21))
            for k, (role, hexcol) in enumerate(pal.items()):
                yy = y0 + 85 + k * 52
                d.rectangle([28, yy, 72, yy + 36], fill=hexcol, outline=(60, 50, 45))
                d.text((86, yy + 2), hexcol.upper(), fill=(30, 26, 24), font=font(18))
                d.text((86, yy + 21), role, fill=(110, 100, 92), font=font(14))
            for ci, m in enumerate(models):
                p = os.path.join(PREVIEW_DIR, "renders", f"{m[0]}_{pname}.png")
                if os.path.exists(p):
                    sheet.paste(Image.open(p).convert("RGB"), (lw + ci * cw, y0))
        out = os.path.join(PREVIEW_DIR, f"{family}_sheet.png")
        sheet.save(out)
        print("[north-gate] sheet:", out)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    main(argv)
