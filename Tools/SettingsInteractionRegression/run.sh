#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/toolchain.sh"
require_toolchain
OUTPUT="${1:-$ROOT/build/settings-interaction-regression}"
mkdir -p "$OUTPUT"
rm -f "$OUTPUT/results.json"
APP="$OUTPUT/Gaze Settings Fixture.app"
mkdir -p "$APP/Contents/MacOS"
python3 "$ROOT/Tools/SettingsInteractionRegression/generate.py" "$OUTPUT/SettingsFixture.swift"
xcrun swiftc -parse-as-library -target "$(host_target)" \
    "$ROOT/Sources/App/Theme.swift" \
    "$ROOT/Sources/Setup/SetupScaffold.swift" \
    "$ROOT/Sources/Setup/SetupControls.swift" \
    "$ROOT/Sources/Enrollment/EnrollmentRing.swift" \
    "$ROOT/Tools/OnboardingRegression/Stubs.swift" \
    "$ROOT/Tools/SettingsInteractionRegression/ServiceStubs.swift" \
    "$ROOT/Tools/SettingsInteractionRegression/Tests.swift" \
    "$ROOT/Tools/SettingsInteractionRegression/CaptureTests.swift" \
    "$OUTPUT/SettingsFixture.swift" "$OUTPUT/CaptureFixture.swift" -o "$APP/Contents/MacOS/SettingsFixture"
python3 - "$APP/Contents/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1], 'wb') as stream:
    plistlib.dump({'CFBundleIdentifier':'com.gazeunlock.SettingsInteractionFixture',
                  'CFBundleExecutable':'SettingsFixture', 'CFBundleName':'Gaze Settings Fixture',
                  'CFBundlePackageType':'APPL', 'LSMinimumSystemVersion':'26.0'}, stream)
PY
codesign --force --sign - "$APP" >/dev/null 2>&1
"$APP/Contents/MacOS/SettingsFixture" "$OUTPUT" "${@:2}"
