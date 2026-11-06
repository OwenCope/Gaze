#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-notch-controller-tests.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
. "$ROOT/Tools/Scripts/toolchain.sh"
require_toolchain
SDK="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
xcrun swiftc -parse-as-library -sdk "$SDK" -target "$(uname -m)-apple-macos26.0" \
	"$ROOT/Tests/Support/PreviewPreferences.swift" \
	"$ROOT/Tests/NotchController/Stubs.swift" \
	"$ROOT/Sources/App/StatusBroadcast.swift" \
	"$ROOT/Sources/LockScreen/NotchCapsuleController.swift" \
	"$ROOT/Sources/LockScreen/WallpaperBrightness.swift" \
	"$ROOT/Sources/App/Theme.swift" \
	"$ROOT/Sources/LockScreen/GazeFaceMark.swift" \
	"$ROOT/Sources/Companion/"*.swift \
	"$ROOT/Sources/LockScreen/NotchCapsule.swift" \
	"$ROOT/Sources/LockScreen/WallpaperGlass.swift" \
	"$ROOT/Sources/LockScreen/LockPanelPreview.swift" \
	"$ROOT/Sources/LockScreen/NotchPanelShape.swift" \
	"$ROOT/Sources/LockScreen/NotchMetrics.swift" \
	"$ROOT/Sources/LockScreen/NativeUnlockAnimation.swift" \
	"$ROOT/Sources/LockScreen/NativeMovementMark.swift" \
	"$ROOT/Sources/LockScreen/NotchPreviewCanvas.swift" \
	"$ROOT/Tests/Support/CompanionCapture.swift" \
	"$ROOT/Tests/NotchController/Tests.swift" \
	-o "$BUILD/notch-tests"
"$BUILD/notch-tests"
