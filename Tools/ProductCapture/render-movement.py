#!/usr/bin/env python3
"""Export the actual five guidance animations; this is not a screen recording."""
from pathlib import Path
import hashlib
import json
import os
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/polish-20260918/movement-movie"
OUT.mkdir(parents=True, exist_ok=True)
art = ROOT / "Tools/OnboardingArt/Generate.swift"
declarations = OUT / "OnboardingArtDeclarations.swift"
declarations.write_text(art.read_text().replace("@main\n", "", 1))
sources = [ROOT / "Tools/ProductCapture/MovementMovie.swift", declarations] + [
    ROOT / path for path in [
        "Sources/Companion/GazeCompanionShader.swift", "Sources/Companion/GazeCompanionMotion.swift",
        "Sources/Companion/GazeCompanionRenderer.swift", "Sources/Companion/GazeCompanionView.swift",
        "Sources/Companion/GazeRenderDiagnostics.swift", "Sources/LockScreen/GazeFaceMark.swift"]]
env = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer")
subprocess.run(["xcrun", "swiftc", "-O", "-parse-as-library", *map(str, sources), "-o", str(OUT / "render")], env=env, check=True)
subprocess.run([str(OUT / "render"), str(OUT / "frames")], check=True)
video = OUT / "gaze-movements.mp4"
subprocess.run(["ffmpeg", "-y", "-v", "error", "-framerate", "60", "-i", str(OUT / "frames/%05d.png"),
                "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(video)], check=True)
(OUT / "manifest.json").write_text(json.dumps({
    "type": "Animations rendered from current app code; not a screenshot or a real face check",
    "size": [900, 560], "fps": 60, "durationSeconds": 16,
    "movements": ["Turn left", "Turn right", "Nod", "Blink", "Open mouth"],
    "videoSha256": hashlib.sha256(video.read_bytes()).hexdigest(),
    "sourceHashes": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
    "artRendererSha256": hashlib.sha256(art.read_bytes()).hexdigest()
}, indent=2) + "\n")
print(video)
