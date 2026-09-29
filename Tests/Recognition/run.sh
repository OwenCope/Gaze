#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-recognition-tests.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
xcrun swiftc -O -parse-as-library -warnings-as-errors -module-cache-path "${CLANG_MODULE_CACHE_PATH:-$BUILD/modules}" \
	"$ROOT/Sources/Camera/FacePose.swift" \
	"$ROOT/Sources/Recognition/ModelResidency.swift" \
	"$ROOT/Sources/Recognition/FaceEmbedder.swift" \
	"$ROOT/Sources/Recognition/FaceAligner.swift" \
	"$ROOT/Sources/Recognition/FaceTemplateMatcher.swift" \
	"$ROOT/Sources/Recognition/FrameQuality.swift" \
	"$ROOT/Sources/Recognition/UnlockFrameEvaluator.swift" \
	"$ROOT/Sources/Recognition/DeviceBezelGate.swift" \
	"$ROOT/Sources/Recognition/GlareCue.swift" \
	"$ROOT/Sources/Recognition/AntiSpoofGate.swift" \
	"$ROOT/Sources/Recognition/SpoofDetector.swift" \
	"$ROOT/Sources/Enrollment/EnrollmentModel.swift" \
	"$ROOT/Tests/Recognition/Tests.swift" -o "$BUILD/tests"
"$BUILD/tests"
