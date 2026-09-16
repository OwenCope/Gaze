#!/usr/bin/env python3
"""Export native setup content details, excluding uncapturable glass action rows."""
from pathlib import Path
from PIL import Image
import argparse, hashlib, json
parser=argparse.ArgumentParser()
parser.add_argument('source',type=Path)
parser.add_argument('output',type=Path)
args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
regions={
 'setup-welcome-detail':('welcome-dark.png',(240,250,1520,950)),
 'setup-companion-detail':('meetGaze-dark.png',(170,105,1590,805)),
 'setup-how-detail':('how-dark.png',(280,195,1480,960)),
 'setup-movement-detail':('lesson-turnLeft-dark.png',(24,24,1096,505)),
}
manifest=[]
for name,(source,box) in regions.items():
 image=Image.open(args.source/source).convert('RGB').crop(box)
 target=args.output/(name+'.webp');image.save(target,'WEBP',lossless=True,method=6)
 assert Image.open(target).convert('RGB').tobytes()==image.tobytes()
 manifest.append({'source':source,'crop':box,'output':target.name,'dimensions':image.size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
print(json.dumps(manifest,indent=2))
