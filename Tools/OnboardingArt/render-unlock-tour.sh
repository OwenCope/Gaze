#!/bin/bash
# Tools/OnboardingArt/render-unlock-tour.sh — build + run the unlock-tour artwork renderer.
#
# Compiles RenderUnlockTour.swift together with the REAL lock-screen sources
# (verbatim, no copies) and renders Resources/Art/tour-how-unlock.png
# (1320x825): the production NotchCapsule movement prompt over a cropped
# lock-screen photograph. No app launch, no camera, no credentials, no lock,
# no real preferences touched. Binary and intermediates stay under build/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/Resources/Art"
WORK="$ROOT/build/unlock-tour"
BIN="$WORK/RenderUnlockTour"

mkdir -p "$WORK"

# Accept an override, default to the beta toolchain like the other renderers.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
TARGET="$(uname -m)-apple-macos26.0"

xcrun swiftc -parse-as-library -O -sdk "$SDK" -target "$TARGET" \
	"$ROOT/Tools/GazePreview/PreviewPreferences.swift" \
	"$ROOT/Sources/App/Theme.swift" \
	"$ROOT/Sources/LockScreen/GazeFaceMark.swift" \
	"$ROOT/Sources/LockScreen/NotchCapsule.swift" \
	"$ROOT/Sources/LockScreen/NotchPanelShape.swift" \
	"$ROOT/Sources/Companion/"*.swift \
	"$ROOT/Tools/GazePreview/Tests/CompanionCapture.swift" \
	"$ROOT/Tools/OnboardingArt/RenderUnlockTour.swift" \
	-o "$BIN"

"$BIN" "$OUT" "$WORK"
