#!/bin/bash
# build-studio.sh — Hank 3 (Droppy Code Hydra head)
#
# Reproducible offline renderer for clean Gaze panel preview videos.
# Synthetic studio media only: a 960x600 stage with the production
# NotchCapsule centred at the top. No desktop, camera, lock, Keychain,
# enrolment, live app, or third-party art anywhere in the pipeline.
#
# Simulated panel previews, not real unlock recordings.
#
# Usage: ./build-studio.sh
#   Renders 3 x 240 frames to /tmp, encodes H.264, writes tracked
#   deliverables to Studio/assets/ (this directory's sibling).
set -euo pipefail

STUDIO="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$STUDIO/../../../.." && pwd)"
ASSETS="$STUDIO/assets"
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
SDK="$(xcrun --sdk macosx --show-sdk-path)"
TARGET="$(uname -m)-apple-macos26.0"
MODE="${1:---all}"
case "$MODE" in --all|--site) ;; *) echo "Usage: $0 [--all|--site]" >&2; exit 2 ;; esac

BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-studio.XXXXXX")"
FRAMES="$BUILD/frames"
mkdir -p "$BUILD" "$FRAMES" "$ASSETS"

echo "studio: compiling renderer"
xcrun swiftc -parse-as-library -O -sdk "$SDK" -target "$TARGET" \
	"$ROOT/Tools/GazePreview/PreviewPreferences.swift" \
	"$ROOT/Sources/App/Theme.swift" \
	"$ROOT/Sources/LockScreen/GazeFaceMark.swift" \
	"$ROOT/Sources/LockScreen/NotchCapsule.swift" \
	"$ROOT/Sources/LockScreen/NotchPanelShape.swift" \
	"$ROOT/Sources/Companion/"*.swift \
	"$ROOT/Tools/GazePreview/Tests/CompanionCapture.swift" \
	"$STUDIO/StudioRenderer.swift" \
	-o "$BUILD/studio-render"

# style-raw-value -> filename tag
render_variant() {
	echo "studio: rendering $2 (style $1)"
	mkdir -p "$FRAMES/$2"
	"$BUILD/studio-render" "$FRAMES/$2" "$1" "$2"
}

render_variant normal normal
render_variant semiLiquidGlass semi-liquid-glass
if [ "$MODE" = --all ]; then render_variant liquidGlass liquid-glass; fi

encode_variant() {
	local tag="$1"
	echo "studio: encoding $tag"
	ffmpeg -hide_banner -v error -y \
		-framerate 30 -i "$FRAMES/$tag/frame-%04d.png" \
		-vf "scale=960:600" -c:v libx264 -pix_fmt yuv420p \
		-crf 19 -preset medium -movflags +faststart -r 30 \
		-an "$ASSETS/gaze-panel-$tag.mp4"
	# Poster: settled scanning phase (t = 1.6 s).
	ffmpeg -hide_banner -v error -y \
		-ss 1.6 -i "$ASSETS/gaze-panel-$tag.mp4" \
		-frames:v 1 "$ASSETS/gaze-panel-$tag-poster.png"
}

encode_variant normal
encode_variant semi-liquid-glass
if [ "$MODE" = --all ]; then encode_variant liquid-glass; fi

echo "studio: verifying"
for mp4 in "$ASSETS"/gaze-panel-*.mp4; do
	echo "--- $mp4"
	ffprobe -hide_banner -v error \
		-show_entries stream=width,height,avg_frame_rate,codec_name,pix_fmt,duration \
		-show_entries format=duration,size -of default=noprint_wrappers=1 "$mp4"
	ffmpeg -hide_banner -v error -i "$mp4" -f null -
	python3 - "$mp4" <<'EOF'
import struct, sys
path = sys.argv[1]
boxes = []
with open(path, "rb") as f:
    while True:
        header = f.read(8)
        if len(header) < 8:
            break
        size, kind = struct.unpack(">I4s", header)
        kind = kind.decode("latin1")
        if size == 0:
            break
        boxes.append(kind)
        f.seek(size - 8, 1)
print("boxes:", boxes[:6])
assert "moov" in boxes and "mdat" in boxes, "missing moov/mdat"
assert boxes.index("moov") < boxes.index("mdat"), "moov must precede mdat (faststart)"
print("faststart: OK")
EOF
done
ls -l "$ASSETS"
(cd "$ASSETS" && shasum -a 256 gaze-panel-*) | tee "$ASSETS/SHASUMS.txt"
echo "studio: frames kept at $FRAMES (outside the repo; delete when done)"
