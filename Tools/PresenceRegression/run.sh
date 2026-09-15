#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-presence-tests.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
	"$ROOT/Sources/Security/PresenceAbsenceGate.swift" \
	"$ROOT/Sources/Security/PresenceCheckSchedule.swift" \
	"$ROOT/Tools/PresenceRegression/Tests.swift" \
	-o "$BUILD/presence-tests"
"$BUILD/presence-tests"
