#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/Tools/Scripts/toolchain.sh"
require_toolchain
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-toolbar-tests.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
SDK="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
APP="$BUILD/Toolbar Checks.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Art"
cp "$ROOT/Resources/Art/gaze-toolbar"*.png "$APP/Contents/Resources/Art/"
{ printf 'import SwiftUI\n'; sed -n '/^enum SettingsPane:/,/^struct SettingsView:/p' "$ROOT/Sources/App/SettingsView.swift" | sed '$d'; } > "$BUILD/SettingsPane.swift"
xcrun swiftc -parse-as-library -warnings-as-errors -sdk "$SDK" -target "$(uname -m)-apple-macos26.0" \
	"$BUILD/SettingsPane.swift" "$ROOT/Sources/App/GazeBrand.swift" "$ROOT/Sources/App/GazeSettingsPicker.swift" \
	"$ROOT/Sources/App/Theme.swift" "$ROOT/Tests/Support/PreviewPreferences.swift" \
	"$ROOT/Tests/Toolbar/ToolbarTests.swift" -o "$APP/Contents/MacOS/ToolbarChecks"
"$APP/Contents/MacOS/ToolbarChecks" "${1:-$BUILD/renders}"
