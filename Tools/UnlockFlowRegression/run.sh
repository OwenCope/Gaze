#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-unlock-flow.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
xcrun swiftc -parse-as-library -warnings-as-errors \
	"$ROOT/Sources/Camera/CameraFrameLease.swift" \
	"$ROOT/Sources/Security/UnlockChallengeGate.swift" \
	"$ROOT/Sources/Security/LockScreenInputGuard.swift" \
	"$ROOT/Sources/Camera/FacePose.swift" \
	"$ROOT/Sources/Recognition/LivenessChallenge.swift" \
	"$ROOT/Tools/UnlockFlowRegression/Tests.swift" -o "$BUILD/tests"
"$BUILD/tests"
xcrun swiftc -parse-as-library -warnings-as-errors \
	"$ROOT/Sources/Camera/CameraFrameLease.swift" \
	"$ROOT/Sources/Camera/CameraEvidenceContinuity.swift" \
	"$ROOT/Sources/Recognition/UnlockFrameEvaluator.swift" \
	"$ROOT/Tools/UnlockFlowRegression/EvaluatorTests.swift" -o "$BUILD/evaluator-tests"
"$BUILD/evaluator-tests"
xcrun swiftc -parse-as-library -warnings-as-errors \
	"$ROOT/Sources/Camera/CameraFrameLease.swift" \
	"$ROOT/Sources/Camera/CameraEvidenceContinuity.swift" \
	"$ROOT/Sources/Recognition/FrameQuality.swift" \
	"$ROOT/Tools/UnlockFlowRegression/ContinuityTests.swift" -o "$BUILD/continuity-tests"
"$BUILD/continuity-tests"
xcrun swiftc -parse-as-library -warnings-as-errors \
	"$ROOT/Sources/Camera/CameraFrameLease.swift" \
	"$ROOT/Sources/Camera/CameraEvidenceContinuity.swift" \
	"$ROOT/Sources/Recognition/RecognitionFrameGate.swift" \
	"$ROOT/Tools/UnlockFlowRegression/FrameGateTests.swift" -o "$BUILD/frame-gate-tests"
"$BUILD/frame-gate-tests"
xcrun swiftc -parse-as-library -warnings-as-errors \
	"$ROOT/Sources/Security/LockScanDiagnostics.swift" \
	"$ROOT/Tools/UnlockFlowRegression/DiagnosticsTests.swift" -o "$BUILD/diagnostics-tests"
"$BUILD/diagnostics-tests"
xcrun swiftc -parse-as-library -warnings-as-errors \
	"$ROOT/Sources/Camera/CameraFrameLease.swift" \
	"$ROOT/Sources/Camera/FacePose.swift" \
	"$ROOT/Sources/Security/UnlockChallengeGate.swift" \
	"$ROOT/Sources/Recognition/LivenessChallenge.swift" \
	"$ROOT/Tools/UnlockFlowRegression/ChallengePoseIntegrationTests.swift" -o "$BUILD/challenge-pose-integration-tests"
"$BUILD/challenge-pose-integration-tests"
xcrun swiftc -parse-as-library -warnings-as-errors \
	"$ROOT/Sources/Camera/CameraFrameLease.swift" \
	"$ROOT/Sources/Camera/CameraEvidenceContinuity.swift" \
	"$ROOT/Sources/Recognition/RecognitionFrameGate.swift" \
	"$ROOT/Sources/Recognition/RecognitionScanPacing.swift" \
	"$ROOT/Tools/UnlockFlowRegression/ConsumedContinuityIntegrationTests.swift" -o "$BUILD/consumed-continuity-integration-tests"
"$BUILD/consumed-continuity-integration-tests"
xcrun swiftc -parse-as-library -warnings-as-errors \
	"$ROOT/Sources/Camera/CameraFrameLease.swift" \
	"$ROOT/Sources/Camera/FacePose.swift" \
	"$ROOT/Sources/Security/UnlockChallengeGate.swift" \
	"$ROOT/Sources/Recognition/LivenessChallenge.swift" \
	"$ROOT/Tools/UnlockFlowRegression/PoseSourceTests.swift" -o "$BUILD/pose-source-tests"
"$BUILD/pose-source-tests"
xcrun swiftc -parse-as-library -warnings-as-errors \
	"$ROOT/Sources/Camera/CameraFrameLease.swift" \
	"$ROOT/Sources/Camera/FacePose.swift" \
	"$ROOT/Sources/Security/UnlockChallengeGate.swift" \
	"$ROOT/Sources/Recognition/LivenessChallenge.swift" \
	"$ROOT/Tools/UnlockFlowRegression/UnlockChallengeGateCountTests.swift" -o "$BUILD/unlock-challenge-gate-count-tests"
"$BUILD/unlock-challenge-gate-count-tests"
