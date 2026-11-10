"""Register the painted collapse sequence; no deformation or slab animation.

A single scale and pillar-foot pivot apply to every generated pose. The approved
last HP stage is the entry. The final accepted ruined pose holds without looping
geometry. See authored-collapse-prompts.md for generation provenance.
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'art/sprites/wall'
SCALE = 2.035
PIVOT = (156.75, 255.0)
TARGET = (540.0, 392.6)
# Last generated pose 15 pulls the right pillar upright again; retain pose 14.
ORDER = list(range(1, 15))


def bake(entry, size):
    raw = Image.open(SOURCE / 'collapse_authored_raw.png').convert('RGBA')
    result = [entry.copy()]
    manifest = []
    for i in range(16):
        x0, x1 = round(i % 4 * raw.width / 4), round((i % 4 + 1) * raw.width / 4)
        y0, y1 = round(i // 4 * raw.height / 4), round((i // 4 + 1) * raw.height / 4)
        manifest.append(dict(id=f'painted/{i}', rect=dict(x=x0, y=y0, w=x1-x0, h=y1-y0),
                             anchor=dict(x=PIVOT[0], y=PIVOT[1]), durationMs=100))
    (SOURCE / 'collapse_authored_raw.frames.json').write_text(json.dumps(manifest, indent=2))
    for i in ORDER:
        r = manifest[i]['rect']
        cell = raw.crop((r['x'],r['y'],r['x']+r['w'],r['y']+r['h']))
        pixels = np.array(cell)
        pixels[pixels[:, :, 3] < 24] = 0
        cell = Image.fromarray(pixels)
        cell = cell.resize((round(cell.width*SCALE),round(cell.height*SCALE)),Image.Resampling.LANCZOS)
        frame = Image.new('RGBA', size)
        frame.alpha_composite(cell,(round(TARGET[0]-PIVOT[0]*SCALE),round(TARGET[1]-PIVOT[1]*SCALE)))
        p = np.array(frame)
        # Opaque gate art is confined to the original gate opening footprint;
        # translucent smoke/dust can reach beyond it, above the static sides.
        outside = np.ones((size[1],size[0]),dtype=bool)
        outside[:,270:810] = False
        p[outside & (p[:,:,3] > 220)] = 0
        # Faint top/side effect tails fade out before the padded texture edge.
        yy,xx=np.indices(p.shape[:2])
        feather=np.minimum.reduce([np.ones(xx.shape),yy/24,(size[1]-1-yy)/20,xx/20,(size[0]-1-xx)/20])
        p[:,:,3]=np.round(p[:,:,3]*np.clip(feather,0,1))
        result.append(Image.fromarray(p))
    return result
