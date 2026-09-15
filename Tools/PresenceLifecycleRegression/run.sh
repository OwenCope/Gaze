#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-presence-lifecycle-tests.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library -warnings-as-errors \
	"$ROOT/Sources/Security/UnlockExecutionPolicy.swift" \
	"$ROOT/Tools/PresenceLifecycleRegression/LifecycleTests.swift" \
	-o "$BUILD/presence-lifecycle-tests"
"$BUILD/presence-lifecycle-tests"
bash "$ROOT/Tools/PresenceLifecycleRegression/test-wiring.sh"
