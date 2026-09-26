#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-movement-settings-tests.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
	"$ROOT/Tests/MovementSettings/UnlockBackendStub.swift" \
	"$ROOT/Sources/App/Preferences.swift" \
	"$ROOT/Tests/MovementSettings/MovementSettingsTests.swift" \
	-o "$BUILD/movement-settings-tests"
"$BUILD/movement-settings-tests"
