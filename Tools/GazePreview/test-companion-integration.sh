#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-companion-tests.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
SDK="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
xcrun swiftc -parse-as-library -sdk "$SDK" -target "$(uname -m)-apple-macos26.0" \
	"$ROOT/Tools/GazePreview/PreviewPreferences.swift" "$ROOT/Sources/App/Theme.swift" \
	"$ROOT/Sources/LockScreen/GazeFaceMark.swift" "$ROOT/Sources/LockScreen/NotchCapsule.swift" \
	"$ROOT/Sources/LockScreen/NotchPanelShape.swift" "$ROOT/Sources/Companion/"*.swift \
	"$ROOT/Sources/Setup/SetupMark.swift" "$ROOT/Tools/GazePreview/Tests/CompanionCapture.swift" \
	"$ROOT/Sources/Setup/GazeLessonAnimation.swift" \
	"$ROOT/Sources/Enrollment/RecognitionTestPanel.swift" \
	"$ROOT/Tools/GazePreview/Tests/CompanionLifecycleTests.swift" \
	"$ROOT/Tools/GazePreview/Tests/CompanionDirectionTests.swift" \
	"$ROOT/Tools/GazePreview/Tests/GuidanceCaptionTests.swift" \
	"$ROOT/Tools/GazePreview/Tests/MovementProgressTests.swift" \
	"$ROOT/Tools/GazePreview/Tests/RenderDiagnosticsTests.swift" \
	"$ROOT/Tools/GazePreview/Tests/CompanionIntegrationTests.swift" -o "$BUILD/integration-tests"
"$BUILD/integration-tests" "${1:-$BUILD/renders}" "${@:2}"
