"""Adapt the skill's field-sheet review to native game scale and one-shot playback.
Run after inspect-sheet.mjs creates evidence/authored/field-review.html.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
folder = ROOT / 'art/sprites/wall'
s = (folder / 'evidence/authored/field-review.html').read_text()
s = s.replace('max="256" value="96"', 'max="540" value="270"')
s = s.replace('id="smoothing" type="checkbox"', 'id="smoothing" type="checkbox" checked')
s = s.replace('?3:1', '?2:1').replace('grid-template-columns:1fr 1fr','grid-template-columns:1fr')
s = s.replace('</style>','#sheet,.players>section:nth-child(2){display:none}.stage{min-height:0}canvas{image-rendering:auto}\n</style>')
s = s.replace('<label>FPS','<label>Speed <select id="speed"><option value="1">1×</option><option value="0.4">0.4×</option></select></label><label>FPS')
s = s.replace("const duration=frames[index].durationMs||1000/(Number(document.getElementById('fps').value)||8);", "const duration=(frames[index].durationMs||1000/(Number(document.getElementById('fps').value)||8))/Number(document.getElementById('speed').value);")
s = s.replace('index=(index+1)%frames.length;last=time;render();','if(index<frames.length-1){index++;}else{setPlaying(false);}last=time;render();')
s = s.replace('play.onclick=()=>setPlaying(!playing);','play.onclick=()=>{if(!playing&&index===frames.length-1){index=0;render();}setPlaying(!playing);};')
s = s.replace('Dark background','Native 270 px gate and 2× enlargement — last frame holds')
(folder / 'gate-review.html').write_text(s)
print('Wrote art/sprites/wall/gate-review.html')
