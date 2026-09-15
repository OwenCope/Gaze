#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-head-pose-tests.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
xcrun swiftc -parse-as-library -warnings-as-errors \
	"$ROOT/Sources/Camera/FacePose.swift" \
	"$ROOT/Sources/Recognition/LivenessChallenge.swift" \
	"$ROOT/Tools/HeadPoseRegression/Tests.swift" -o "$BUILD/tests"
"$BUILD/tests" "$@"
