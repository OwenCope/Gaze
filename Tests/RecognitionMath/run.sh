#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/Tools/Scripts/toolchain.sh"
require_toolchain
SDK="$(oldest_usable_sdk | awk '{print $1}')"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-recognition-math.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
xcrun swiftc -parse-as-library -warnings-as-errors -sdk "$SDK" -target "$(host_target)" \
	"$ROOT/Sources/Recognition/FaceEmbedder.swift" "$ROOT/Sources/Recognition/FaceAligner.swift" \
	"$ROOT/Tests/RecognitionMath/Tests.swift" -o "$BUILD/recognition-math-tests"
"$BUILD/recognition-math-tests"
