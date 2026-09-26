#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/Tools/Scripts/toolchain.sh"
require_toolchain
SDK="$(oldest_usable_sdk | awk '{print $1}')"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-enrollment-storage-tests.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
xcrun swiftc -parse-as-library -warnings-as-errors -sdk "$SDK" -target "$(host_target)" \
	"$ROOT/Sources/Recognition/FaceEnrollment.swift" \
	"$ROOT/Tests/EnrollmentStorage/Tests.swift" -o "$BUILD/enrollment-storage-tests"
"$BUILD/enrollment-storage-tests"
