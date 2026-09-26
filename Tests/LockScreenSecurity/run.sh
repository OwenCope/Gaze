#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-lockscreen-tests.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT

xcrun swiftc -parse-as-library -warnings-as-errors \
	"$ROOT/Sources/Security/Keystrokes.swift" \
	"$ROOT/Sources/Security/UnlockExecutionPolicy.swift" \
	"$ROOT/Sources/Security/LockScreenPasswordSubmission.swift" \
	"$ROOT/Tests/LockScreenSecurity/SubmissionTests.swift" \
	-o "$BUILD/lockscreen-tests"
"$BUILD/lockscreen-tests"
