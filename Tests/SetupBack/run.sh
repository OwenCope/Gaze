#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_ROOT="$ROOT/build"
mkdir -p "$BUILD_ROOT"
BUILD="$(mktemp -d "$BUILD_ROOT/setup-back-checks.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
source "$ROOT/Tools/Scripts/toolchain.sh"
require_toolchain
xcrun swiftc -parse-as-library \
	"$ROOT/Sources/Setup/SetupPlan.swift" \
	"$ROOT/Tests/SetupBack/Tests.swift" \
	-o "$BUILD/setup-back-checks"
"$BUILD/setup-back-checks"
