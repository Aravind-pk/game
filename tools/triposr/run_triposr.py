"""Run TripoSR (open-source single-image -> 3D) on the North Gate concept cut-outs, CPU only.

Setup (Python 3.11):
    pip install torch omegaconf einops "transformers==4.35.0" trimesh huggingface-hub \
        scikit-image scipy pillow
    # TripoSR source: https://github.com/VAST-AI-Research/TripoSR  (pass its folder with --tsr)
    # isosurface.py patched to use scikit-image instead of torchmcubes (see README)

Usage:
    python tools/triposr/run_triposr.py --tsr /path/to/TripoSR \
        --inputs art/modly_inputs --out art/triposr_outputs [--res 256] [--only kestrel]

Background removal is done here with a border flood-fill (the cut-outs have
plain cream/white backgrounds), so rembg and its model download are not needed.
"""

import argparse
import glob
import os
import sys
import time

import numpy as np
from PIL import Image


def remove_plain_background(img, tol_light=0.74, tol_sat=0.24):
    """Alpha-mask light, low-saturation pixels that connect to the image border
    (paper background + soft drop shadows)."""
    from scipy import ndimage
    a = np.asarray(img.convert("RGB")).astype(np.float32) / 255.0
    mx, mn = a.max(-1), a.min(-1)
    sat = (mx - mn) / np.maximum(mx, 1e-6)
    cand = (mx > tol_light) & (sat < tol_sat)
    lab, _ = ndimage.label(cand)
    border = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    bg = np.isin(lab, border[border > 0])
    # keep only the largest foreground blob (drops loose pebbles/dirt)
    fg_lab, n = ndimage.label(~bg)
    if n > 1:
        sizes = ndimage.sum(np.ones_like(fg_lab), fg_lab, range(1, n + 1))
        keep = np.argmax(sizes) + 1
        fg = ndimage.binary_dilation(fg_lab == keep, iterations=1)
    else:
        fg = ~bg
    alpha = ndimage.gaussian_filter(fg.astype(np.float32), 0.7)
    rgba = np.dstack([a, alpha])
    return Image.fromarray((rgba * 255).astype(np.uint8), "RGBA")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tsr", required=True, help="path to the TripoSR source checkout")
    ap.add_argument("--inputs", default="art/modly_inputs")
    ap.add_argument("--out", default="art/triposr_outputs")
    ap.add_argument("--res", type=int, default=256, help="marching-cubes resolution")
    ap.add_argument("--only", default=None)
    ap.add_argument("--model", default="stabilityai/TripoSR")
    args = ap.parse_args()

    sys.path.insert(0, args.tsr)
    import torch
    from tsr.system import TSR
    from tsr.utils import resize_foreground

    torch.set_num_threads(os.cpu_count() or 4)
    os.makedirs(args.out, exist_ok=True)
    t0 = time.time()
    model = TSR.from_pretrained(args.model, config_name="config.yaml", weight_name="model.ckpt")
    model.renderer.set_chunk_size(8192)
    model.to("cpu")
    print(f"[triposr] model loaded in {time.time() - t0:.1f}s")

    paths = sorted(glob.glob(os.path.join(args.inputs, "*.png")))
    if args.only:
        keep = set(args.only.split(","))
        paths = [p for p in paths if os.path.splitext(os.path.basename(p))[0] in keep]
    for p in paths:
        name = os.path.splitext(os.path.basename(p))[0]
        t = time.time()
        img = remove_plain_background(Image.open(p))
        img = resize_foreground(img, 0.85)
        arr = np.asarray(img).astype(np.float32) / 255.0
        arr = arr[..., :3] * arr[..., 3:4] + (1 - arr[..., 3:4]) * 0.5
        prepped = Image.fromarray((arr * 255).astype(np.uint8))
        prepped.save(os.path.join(args.out, f"{name}_input.png"))
        with torch.no_grad():
            codes = model([prepped], device="cpu")
            mesh = model.extract_mesh(codes, True, resolution=args.res)[0]
        out = os.path.join(args.out, f"{name}.glb")
        mesh.export(out)
        print(f"[triposr] {name}: {len(mesh.faces)} faces, {time.time() - t:.1f}s -> {out}")


if __name__ == "__main__":
    main()
