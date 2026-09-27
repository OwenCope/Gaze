#!/bin/bash
# Regression for ReleaseUpdateChecker schedule lifecycle: stopping the schedule
# cancels cleanly instead of reporting a false offline failure. Compiles the
# real production files with a URLProtocol-backed harness; no production
# request, no app launch, no camera.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/Tools/Scripts/toolchain.sh"
require_toolchain

# Wiring: the schedule must run on its own instance, never .shared.
if grep -q "ReleaseUpdateChecker\.shared" "$ROOT/Sources/App/ReleaseUpdateChecker.swift"; then
	echo "✗ schedule must not reference ReleaseUpdateChecker.shared" >&2
	exit 1
fi
grep -q "func stopScheduledChecks" "$ROOT/Sources/App/ReleaseUpdateChecker.swift" || {
	echo "✗ ReleaseUpdateChecker.stopScheduledChecks is missing" >&2
	exit 1
}
grep -q "\[weak self\]" "$ROOT/Sources/App/ReleaseUpdateChecker.swift" || {
	echo "✗ schedule timer must capture self weakly" >&2
	exit 1
}
echo "✓ schedule wiring (instance-owned, weak timer, stoppable)"

BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-update-lifecycle-tests.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
xcrun swiftc -parse-as-library \
	"$ROOT/Sources/App/ReleaseUpdateChecker.swift" \
	"$ROOT/Sources/App/ReleaseURLPolicy.swift" \
	"$ROOT/Sources/App/UpdateInstaller.swift" \
	"$ROOT/Tests/UpdateLifecycle/Tests.swift" \
	-framework AppKit \
	-framework Security \
	-framework CryptoKit \
	-o "$BUILD/update-lifecycle-tests"
"$BUILD/update-lifecycle-tests"
