#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-unlock-flow.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$BUILD/modules}"
xcrun swiftc -parse-as-library -warnings-as-errors \
	"$ROOT/Sources/Camera/CameraFrameLease.swift" \
	"$ROOT/Sources/Security/UnlockChallengeGate.swift" \
	"$ROOT/Sources/Security/LockScreenInputGuard.swift" \
	"$ROOT/Sources/Camera/FacePose.swift" \
	"$ROOT/Sources/Recognition/LivenessChallenge.swift" \
	"$ROOT/Tests/Support/PupilLocatorStub.swift" \
	"$ROOT/Tests/UnlockFlow/Tests.swift" -o "$BUILD/tests"
"$BUILD/tests"
bash "$ROOT/Tests/Recognition/run.sh"
xcrun swiftc -parse-as-library -warnings-as-errors \
	"$ROOT/Sources/Recognition/DeviceBezelGate.swift" \
	"$ROOT/Sources/Recognition/GlareCue.swift" \
	"$ROOT/Tests/UnlockFlow/CueDenyTests.swift" -o "$BUILD/cue-deny-tests"
"$BUILD/cue-deny-tests"
xcrun swiftc -parse-as-library -warnings-as-errors \
	"$ROOT/Sources/Camera/CameraFrameLease.swift" \
	"$ROOT/Sources/Camera/CameraEvidenceContinuity.swift" \
	"$ROOT/Sources/Recognition/FrameQuality.swift" \
	"$ROOT/Tests/UnlockFlow/ContinuityTests.swift" -o "$BUILD/continuity-tests"
"$BUILD/continuity-tests"
xcrun swiftc -parse-as-library -warnings-as-errors \
	"$ROOT/Sources/Camera/CameraFrameLease.swift" \
	"$ROOT/Sources/Camera/CameraEvidenceContinuity.swift" \
	"$ROOT/Sources/Recognition/FrameQuality.swift" \
	"$ROOT/Sources/Recognition/RecognitionFrameGate.swift" \
	"$ROOT/Tests/UnlockFlow/FrameGateTests.swift" -o "$BUILD/frame-gate-tests"
"$BUILD/frame-gate-tests"
xcrun swiftc -parse-as-library -warnings-as-errors \
	"$ROOT/Sources/Security/LockScanDiagnostics.swift" \
	"$ROOT/Tests/UnlockFlow/DiagnosticsTests.swift" -o "$BUILD/diagnostics-tests"
"$BUILD/diagnostics-tests"
xcrun swiftc -parse-as-library -warnings-as-errors \
	"$ROOT/Sources/Camera/CameraFrameLease.swift" \
	"$ROOT/Sources/Camera/FacePose.swift" \
	"$ROOT/Sources/Security/UnlockChallengeGate.swift" \
	"$ROOT/Sources/Recognition/LivenessChallenge.swift" \
	"$ROOT/Tests/Support/PupilLocatorStub.swift" \
	"$ROOT/Tests/UnlockFlow/ChallengePoseIntegrationTests.swift" -o "$BUILD/challenge-pose-integration-tests"
"$BUILD/challenge-pose-integration-tests"
xcrun swiftc -parse-as-library -warnings-as-errors \
	"$ROOT/Sources/Camera/CameraFrameLease.swift" \
	"$ROOT/Sources/Camera/CameraEvidenceContinuity.swift" \
	"$ROOT/Sources/Recognition/RecognitionFrameGate.swift" \
	"$ROOT/Sources/Recognition/RecognitionScanPacing.swift" \
	"$ROOT/Tests/UnlockFlow/ConsumedContinuityIntegrationTests.swift" -o "$BUILD/consumed-continuity-integration-tests"
"$BUILD/consumed-continuity-integration-tests"
xcrun swiftc -parse-as-library -warnings-as-errors \
	"$ROOT/Sources/Camera/CameraFrameLease.swift" \
	"$ROOT/Sources/Camera/FacePose.swift" \
	"$ROOT/Sources/Security/UnlockChallengeGate.swift" \
	"$ROOT/Sources/Recognition/LivenessChallenge.swift" \
	"$ROOT/Tests/Support/PupilLocatorStub.swift" \
	"$ROOT/Tests/UnlockFlow/PoseSourceTests.swift" -o "$BUILD/pose-source-tests"
"$BUILD/pose-source-tests"
xcrun swiftc -parse-as-library -warnings-as-errors \
	"$ROOT/Sources/Camera/CameraFrameLease.swift" \
	"$ROOT/Sources/Camera/FacePose.swift" \
	"$ROOT/Sources/Security/UnlockChallengeGate.swift" \
	"$ROOT/Sources/Recognition/LivenessChallenge.swift" \
	"$ROOT/Tests/Support/PupilLocatorStub.swift" \
	"$ROOT/Tests/UnlockFlow/UnlockChallengeGateCountTests.swift" -o "$BUILD/unlock-challenge-gate-count-tests"
"$BUILD/unlock-challenge-gate-count-tests"
