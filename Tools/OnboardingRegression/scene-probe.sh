#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/toolchain.sh"
require_toolchain
OUTPUT="${1:-$ROOT/build/lesson-scene-probe}"
APP="$OUTPUT/Gaze Lesson Scene Probe.app"
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc -parse-as-library -target "$(host_target)" \
    "$ROOT/Tools/OnboardingRegression/LessonSceneProbe.swift" \
    "$ROOT/Tools/GazePreview/PreviewPreferences.swift" \
    "$ROOT/Sources/App/Theme.swift" \
    "$ROOT/Sources/LockScreen/GazeFaceMark.swift" \
    "$ROOT/Sources/LockScreen/NotchCapsule.swift" \
    "$ROOT/Sources/LockScreen/NotchPanelShape.swift" \
    "$ROOT/Sources/Companion/"*.swift \
    "$ROOT/Sources/Setup/GazeLessonAnimation.swift" \
    "$ROOT/Tools/GazePreview/Tests/CompanionCapture.swift" \
    -o "$APP/Contents/MacOS/LessonSceneProbe"
python3 - "$APP/Contents/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1], 'wb') as stream:
    plistlib.dump({'CFBundleIdentifier':'com.gazeunlock.LessonSceneProbe',
                  'CFBundleExecutable':'LessonSceneProbe', 'CFBundleName':'Gaze Lesson Scene Probe',
                  'CFBundlePackageType':'APPL', 'LSMinimumSystemVersion':'26.0'}, stream)
PY
codesign --force --sign - "$APP" >/dev/null 2>&1
open -n "$APP" --args "$OUTPUT/scene-events.json"
echo "Scene probe: $APP"
echo "Events: $OUTPUT/scene-events.json"
