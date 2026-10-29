#!/bin/bash
# Status feed contract: compiles the real Sources/App/StatusBroadcast.swift with the
# checks beside it. Posts go to a capture closure, never the distributed centre.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-status-broadcast-tests.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
	"$ROOT/Sources/App/StatusBroadcast.swift" \
	"$ROOT/Tests/StatusBroadcast/StatusBroadcastTests.swift" \
	-o "$BUILD/status-broadcast-tests"
"$BUILD/status-broadcast-tests"
