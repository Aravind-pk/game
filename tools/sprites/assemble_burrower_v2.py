from pathlib import Path
import json,math,hashlib
import numpy as np
from extract_kit import components
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[2]
SRC=ROOT/'art/sprites/burrower_v2'
OUT=ROOT/'art/sprites/burrower_v2/assembled';OUT.mkdir(exist_ok=True)
# Shared scale per source sheet; no per-frame resizing. Stable ground anchor plus preserved vertical motion.
specs=[('walk_S.png',4,2,[('walk_S',0,8)],0),('walk_E_NE.png',4,4,[('walk_E',0,8),('walk_NE',8,8)],0),('walk_N_SW.png',4,4,[('walk_N',0,8),('walk_SW',8,8)],0),('attack_S_SW_E.png',6,3,[('attack_S',0,6),('attack_SW',6,6),('attack_E',12,6)],0),('death_S_E.png',5,4,[('death_S',0,10),('death_E',10,10)],0),('emerge.png',4,3,[('emerge',0,12)],11),('turntable.png',4,4,[('turntable',0,16)],0)]
anims={};tiles=[];manifest={}
for name,cols,rows,groups,reference in specs:
 im=Image.open(SRC/name).convert('RGBA');cells=[];boxes=[]
 for i in range(cols*rows):
  l=round((i%cols)*im.width/cols);t=round((i//cols)*im.height/rows);r=round((i%cols+1)*im.width/cols);b=round((i//cols+1)*im.height/rows)
  a=np.array(im.crop((l,t,r,b)));a[a[:,:,3]<160]=0
  if name != "emerge.png":
   comps=components(a[:,:,3]>0)
   if comps:
    keep=np.zeros(a.shape[:2],bool);main=max(comps,key=len);keep[main[:,0],main[:,1]]=True;a[~keep]=0
  cell=Image.fromarray(a);box=cell.getbbox();assert box,name
  cells.append(cell);boxes.append(box)
 # Calibrate sheet against reference standing body width, keep one scale for entire sheet.
 target=150 if name not in ['walk_E_NE.png'] else 175
 scale=target/(boxes[reference][2]-boxes[reference][0])
 manifest[name]={'sha256':hashlib.sha256((SRC/name).read_bytes()).hexdigest(),'grid':[cols,rows],'shared_scale':scale}
 for key,start,count in groups:
  subset=boxes[start:start+count];baseline=float(np.median([b[3] for b in subset]))
  if key.startswith('death'):baseline=boxes[start][3]
  if key=='emerge':baseline=boxes[-1][3]
  center=float(np.median([(b[0]+b[2])/2 for b in subset]))
  frames=[]
  for i in range(start,start+count):
   cell=cells[i]; resized=cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.LANCZOS)
   tile=Image.new('RGBA',(256,224));px=round(128-center*scale);py=round(190-baseline*scale);tile.alpha_composite(resized,(px,py))
   bb=tile.getbbox();assert bb and bb[0]>0 and bb[1]>0 and bb[2]<256 and bb[3]<224,(key,i,bb)
   frames.append(dict(x=0,y=0,w=256,h=224,ax=128,ay=190,sh=120 if key!='emerge' or i>=start+8 else 0));tiles.append((key,len(frames)-1,tile))
  anims[key]={'frames':frames}
atlas=Image.new('RGBA',(2048,math.ceil(len(tiles)/8)*224))
for i,(key,j,tile) in enumerate(tiles):
 x=i%8*256;y=i//8*224;atlas.paste(tile,(x,y));anims[key]['frames'][j].update(x=x,y=y)
atlas.save(OUT/'burrower.png');(OUT/'burrower.json').write_text(json.dumps({'image':'burrower.png','anims':anims}));(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2))
board=Image.new('RGB',atlas.size,(111,103,85));board.paste(atlas,mask=atlas.getchannel('A'));board.save(OUT/'contact.png');print('PASS',len(tiles),'frames; all frame bounds; shared source scales')
