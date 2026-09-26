#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/Tools/Scripts/toolchain.sh"
require_toolchain
SDK="$(oldest_usable_sdk | awk '{print $1}')"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-enrollment-tests.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
xcrun swiftc -parse-as-library -warnings-as-errors -sdk "$SDK" -target "$(host_target)" \
	"$ROOT/Sources/Recognition/FrameQuality.swift" \
	"$ROOT/Sources/Camera/FacePose.swift" \
	"$ROOT/Sources/Enrollment/EnrollmentModel.swift" \
	"$ROOT/Sources/Setup/SetupSessionWork.swift" \
	"$ROOT/Tests/Enrollment/SetupLifecycleTests.swift" \
	"$ROOT/Tests/Enrollment/Tests.swift" -o "$BUILD/enrollment-tests"
"$BUILD/enrollment-tests"
