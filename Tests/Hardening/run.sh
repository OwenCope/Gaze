#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-hardening-tests.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
xcrun swiftc -parse-as-library -warnings-as-errors \
	"$ROOT/Sources/Security/AutofillSecurity.swift" \
	"$ROOT/Sources/Security/LockoutManager.swift" \
	"$ROOT/Sources/Camera/CameraFrameLease.swift" \
	"$ROOT/Sources/Camera/CameraSessionGate.swift" \
	"$ROOT/Sources/Camera/CameraEvidenceContinuity.swift" \
	"$ROOT/Sources/Recognition/RecognitionFrameGate.swift" \
	"$ROOT/Sources/Recognition/AntiSpoofGate.swift" \
	"$ROOT/Sources/App/ReleaseURLPolicy.swift" \
	"$ROOT/Tests/Hardening/HardeningTests.swift" \
	-o "$BUILD/hardening-tests"
"$BUILD/hardening-tests"
