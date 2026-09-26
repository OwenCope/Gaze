#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-notch-tests.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
SDK="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
xcrun swiftc -parse-as-library -sdk "$SDK" -target "$(uname -m)-apple-macos26.0" \
	"$ROOT/Tests/Support/PreviewPreferences.swift" \
	"$ROOT/Sources/App/Theme.swift" \
	"$ROOT/Sources/LockScreen/GazeFaceMark.swift" \
	"$ROOT/Sources/Companion/"*.swift \
	"$ROOT/Sources/LockScreen/NotchCapsule.swift" \
	"$ROOT/Sources/LockScreen/NotchPanelShape.swift" \
	"$ROOT/Sources/LockScreen/NotchMetrics.swift" \
	"$ROOT/Sources/LockScreen/NotchPreviewCanvas.swift" \
	"$ROOT/Tests/Support/CompanionCapture.swift" \
	"$ROOT/Tests/Notch/NotchTests.swift" \
	-o "$BUILD/notch-tests"
"$BUILD/notch-tests" "${1:-$BUILD/renders}"
