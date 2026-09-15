#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-movement-settings-tests.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
	"$ROOT/Tools/MovementSettingsRegression/UnlockBackendStub.swift" \
	"$ROOT/Sources/App/Preferences.swift" \
	"$ROOT/Tools/MovementSettingsRegression/MovementSettingsTests.swift" \
	-o "$BUILD/movement-settings-tests"
"$BUILD/movement-settings-tests"
