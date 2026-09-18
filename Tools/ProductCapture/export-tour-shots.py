#!/usr/bin/env python3
"""Crop photographed Gaze settings for the native tour and website."""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--captures", required=True, type=Path)
parser.add_argument("--website", required=True, type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]

# 16:10 close-ups of the real controls; no composited or repainted UI.
shots = {
    "general": (80, 126, 1360, 926),
    "notch": (80, 130, 1360, 930),
    "unlock": (80, 290, 1360, 1090),
    "security": (80, 340, 1360, 1140),
}
# Keep the photographed window's side margins under the tour's overlay controls.
native_crops = {
    "general": (0, 95, 1440, 995),
    "notch": (0, 95, 1440, 995),
    "unlock": (0, 285, 1440, 1185),
    "security": (0, 295, 1440, 1195),
}
for name in shots:
    with Image.open(args.captures / f"{name}.png") as source:
        if source.size != (1440, 1200):
            raise SystemExit(f"Unexpected {name} capture size: {source.size}; inspect before cropping")

records = []
args.website.mkdir(parents=True, exist_ok=True)
for name, crop in shots.items():
    source_path = args.captures / f"{name}.png"
    with Image.open(source_path) as source:
        photo = source.crop(crop).convert("RGB")
        native_photo = source.crop(native_crops[name]).convert("RGB")
    native = root / "Resources/Art" / f"tour-{name}.png"
    web = args.website / f"gaze-settings-{name}.webp"
    native_photo.save(native, optimize=True)
    photo.save(web, "WEBP", quality=92, method=6)
    records.append({
        "source": source_path.name,
        "sourceSHA256": hashlib.sha256(source_path.read_bytes()).hexdigest(),
        "crop": list(crop), "size": list(photo.size),
        "native": str(native.relative_to(root)),
        "nativeCrop": list(native_crops[name]), "nativeSize": list(native_photo.size),
        "nativeSHA256": hashlib.sha256(native.read_bytes()).hexdigest(),
        "web": web.name, "webSHA256": hashlib.sha256(web.read_bytes()).hexdigest(),
    })
manifest = {
    "method": "ScreenCaptureKit currentProcess photographs of current Gaze Settings views, using the isolated ProductCapture app and a system-wallpaper window behind the native glass.",
    "content": "Empty enrollment, automatic unlocking off, isolated preferences. No user recordings, camera image, biometric scores, or credentials.",
    "editing": "Rectangular crops and WebP encoding only. No UI retouching or generated screenshots.",
    "captures": records,
}
data = json.dumps(manifest, indent=2) + "\n"
(root / "Tools/ProductCapture/tour-shots.json").write_text(data)
(args.website / "gaze-captures.json").write_text(data)
print("Exported four real app close-ups for the tour and website.")
