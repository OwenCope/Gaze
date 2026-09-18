#!/usr/bin/env python3
"""Export captured app windows without cropping or retouching their contents."""
from pathlib import Path
import argparse
import hashlib
import json
from PIL import Image

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--captures', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
names = {'general': 'gaze-settings-general.webp', 'notch': 'gaze-settings-notch.webp',
         'unlock': 'gaze-settings-unlock.webp', 'movement': 'gaze-movement-guide.webp'}
# Validate the whole batch before writing website assets.
for name in names:
    path = args.captures / (name + '.png')
    if not path.is_file():
        raise SystemExit(f'Missing real window capture: {path}. No placeholder will be generated.')
    with Image.open(path) as image:
        if image.width < 640 or image.height < 480:
            raise SystemExit(f'Window capture is unexpectedly small: {path}')
args.output.mkdir(parents=True, exist_ok=True)
records = []
for name, filename in names.items():
    path = args.captures / (name + '.png')
    with Image.open(path) as original:
        image = original.convert('RGBA')
        image.thumbnail((1380, 840), Image.Resampling.LANCZOS)
        canvas = Image.new('RGBA', (1440, 900), (0, 0, 0, 0))
        canvas.alpha_composite(image, ((1440-image.width)//2, (900-image.height)//2))
        output = args.output / filename
        canvas.save(output, 'WEBP', lossless=True, method=6)
        records.append({'source': path.name, 'sourceSize': list(original.size),
                        'sourceSHA256': hashlib.sha256(path.read_bytes()).hexdigest(),
                        'output': filename, 'size': [1440, 900],
                        'sha256': hashlib.sha256(output.read_bytes()).hexdigest()})
(args.output/'gaze-captures.json').write_text(json.dumps({
    'description': 'Current app windows captured with empty demo enrollment; proportional downscale and transparent padding only.',
    'captures': records}, indent=2)+'\n')
print('Exported four actual app captures.')
