#!/usr/bin/env python3
"""Build current app views with no agent startup and an inert credential store."""
from pathlib import Path
import hashlib
import json
import os
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/polish-20260918/product-capture"
APP = OUT / "Gaze Product Capture.app"
BIN = APP / "Contents/MacOS/ProductCapture"
BIN.parent.mkdir(parents=True, exist_ok=True)
entry = OUT / "GazeAppDeclarations.swift"
original = (ROOT / "Sources/App/GazeApp.swift").read_text()
assert original.count("@main\n") == 1
entry.write_text(original.replace("@main\n", "", 1))
sources = [p for p in sorted((ROOT / "Sources").glob("*/*.swift"))
           if p.parent.name != "Autofill" and p.name not in
           {"AutofillSettings.swift", "FaceCheck.swift", "GazeApp.swift", "Keychain.swift"}]
sources += [ROOT / "ThirdParty/TourKit/TourKit.swift", entry,
            ROOT / "Tools/ProductCapture/Keychain.swift", ROOT / "Tools/ProductCapture/CaptureApp.swift"]
env = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer")
subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-target", "arm64-apple-macos26.0",
                *map(str, sources), "-o", str(BIN)], env=env, check=True)
resources = APP / "Contents/Resources"
resources.mkdir(parents=True, exist_ok=True)
for name in ["Art", "Credits"]:
    shutil.copytree(ROOT / "Resources" / name, resources / name, dirs_exist_ok=True)
with (APP / "Contents/Info.plist").open("wb") as stream:
    plistlib.dump({"CFBundleIdentifier": "com.gazeunlock.ProductCapture", "CFBundleExecutable": "ProductCapture",
                   "CFBundleName": "Gaze Product Capture", "CFBundlePackageType": "APPL",
                   "CFBundleShortVersionString": "0.1", "LSMinimumSystemVersion": "26.0"}, stream)
subprocess.run(["codesign", "--force", "--sign", "-", str(APP)], check=True)
(OUT / "sources.json").write_text(json.dumps({
    "sourceHashes": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
    "limits": "Current production views, empty enrollment, isolated bundle preferences, stub Keychain. GazeApp declarations compile but its initializer/delegate/services are never run. Screenshots require macOS capture permission; no fallback images are fabricated."
}, indent=2) + "\n")
print(APP)
