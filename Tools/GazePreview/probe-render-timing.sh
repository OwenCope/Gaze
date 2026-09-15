#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-render-probe.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
SDK="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
xcrun swiftc -parse-as-library -sdk "$SDK" -target "$(uname -m)-apple-macos26.0" \
	"$ROOT/Tools/GazePreview/PreviewPreferences.swift" "$ROOT/Sources/App/Theme.swift" \
	"$ROOT/Sources/LockScreen/GazeFaceMark.swift" "$ROOT/Sources/LockScreen/NotchCapsule.swift" \
	"$ROOT/Sources/LockScreen/NotchPanelShape.swift" "$ROOT/Sources/Companion/"*.swift \
	"$ROOT/Tools/GazePreview/Tests/CompanionCapture.swift" \
	"$ROOT/Tools/GazePreview/Tests/RenderTimingProbe.swift" -o "$BUILD/render-probe"
GAZE_RENDER_DIAGNOSTICS=1 "$BUILD/render-probe" "${1:-15}" "${2:-}"
