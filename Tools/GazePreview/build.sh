#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="$ROOT/build/Gaze Preview.app"
STAGE="$ROOT/build/.staging-GazePreview.app"
# Generic "macosx" resolves to whatever SDK is installed; pinning 26.5 broke on 27.0.
SDK="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
xcrun swiftc -parse-as-library -O -sdk "$SDK" -target "$(uname -m)-apple-macos26.0" \
	"$ROOT/Tools/GazePreview/PreviewPreferences.swift" \
	"$ROOT/Tools/GazePreview/GazePreviewApp.swift" \
	"$ROOT/Tools/GazePreview/Studies/"*.swift \
	"$ROOT/Sources/Companion/"*.swift \
	"$ROOT/Sources/Enrollment/RecognitionTestPanel.swift" \
	"$ROOT/Sources/App/Theme.swift" \
	"$ROOT/Sources/LockScreen/GazeFaceMark.swift" \
	"$ROOT/Sources/LockScreen/NotchCapsule.swift" \
	"$ROOT/Sources/LockScreen/NotchPanelShape.swift" \
	"$ROOT/Sources/LockScreen/NotchPreviewCanvas.swift" \
	-o "$STAGE/Contents/MacOS/GazePreview"
cp "$ROOT/Tools/GazePreview/Info.plist" "$STAGE/Contents/Info.plist"
bash "$ROOT/Tools/PreviewIcon/build.sh" "$STAGE"
xattr -cr "$STAGE"
codesign --force --sign - "$STAGE"
if [ -d "$APP" ]; then
	mv "$APP" "$ROOT/build/Gaze Preview.previous.$(date +%s).app"
fi
mv "$STAGE" "$APP"
printf 'Built %s\n' "$APP"
