#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_ROOT="$ROOT/build"
mkdir -p "$BUILD_ROOT"
BUILD="$(mktemp -d "$BUILD_ROOT/setup-back-checks.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
source "$ROOT/toolchain.sh"
require_toolchain
xcrun swiftc -parse-as-library \
	"$ROOT/Sources/Setup/SetupPlan.swift" \
	"$ROOT/Tools/SetupBackRegression/Tests.swift" \
	-o "$BUILD/setup-back-checks"
"$BUILD/setup-back-checks"
