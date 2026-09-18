#!/bin/bash
# Settings-launch handoff regression.
#
# Builds the production SettingsLaunchHandoff.swift into a synthetic AppKit bundle
# with a unique test bundle ID, then verifies:
#   1. Pure eligibility: bare and exact `--settings` launches are eligible; every
#      flagged invocation (--agent, --setup, --setup-step, --ui-review, --scan-only,
#      --browser-only, anything else) bypasses; no-existing-instance redirects false.
#   2. Two-process handoff: a first fixture instance becomes the "running app" (writes
#      a per-PID service marker); launching the same executable with `--settings`
#      must make the first instance receive applicationShouldHandleReopen and exit(0)
#      itself without writing a service marker of its own.
#
# Everything lives under a fresh mktemp directory: bundle, markers, logs. Only
# fixture PIDs are ever signalled, and only after `ps` confirms their executable
# path is the fixture. Production Gaze, its LaunchAgent, camera, credentials, real
# defaults, and services are never touched.
#
# If NSWorkspace reuse fails to deliver reopen in this environment, this script
# reports the exact evidence and exits nonzero rather than claiming success.
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/gaze-settings-handoff.XXXXXX")"
MARKDIR="$SCRATCH/marks"
APP="$SCRATCH/GazeHandoffFixture.app"
EXE="$APP/Contents/MacOS/GazeHandoffFixture"
BUNDLE_ID="com.gazeunlock.Gaze.SettingsLaunchHandoffTest"
LOG="$SCRATCH/harness.log"
mkdir -p "$MARKDIR" "$APP/Contents/MacOS" "$APP/Contents/Resources"

cleanup() {
	for pidfile in "$SCRATCH"/fixture-*.pid; do
		[ -f "$pidfile" ] || continue
		pid="$(cat "$pidfile")"
		# Signal only a process whose executable is provably this fixture.
		if ps -p "$pid" -o comm= 2>/dev/null | grep -q "GazeHandoffFixture"; then
			kill "$pid" 2>/dev/null || true
		else
			echo "REFUSING to signal PID $pid: not the fixture executable" >&2
		fi
	done
}
trap cleanup EXIT

fail() {
	echo "FAIL $1" >&2
	echo "--- harness log ($LOG) ---" >&2
	tail -50 "$LOG" >&2
	echo "--- marks: $(ls "$MARKDIR" 2>/dev/null || echo none) ---" >&2
	exit 1
}

# Xcode-beta toolchain per repo convention (AGENTS.md §2).
if [ -z "${DEVELOPER_DIR:-}" ]; then
	if [ -d /Applications/Xcode-beta.app/Contents/Developer ]; then
		export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
	fi
fi
source "$ROOT/toolchain.sh"
require_toolchain
SDK="$(oldest_usable_sdk | awk '{print $1}')"

echo "== build fixture ==" | tee "$LOG"
# shellcheck disable=SC2154
if [ -n "${SDK:-}" ]; then
	SDKFLAG=(-sdk "$SDK")
else
	SDKFLAG=()
fi
xcrun swiftc -o "$EXE" \
	"${SDKFLAG[@]+"${SDKFLAG[@]}"}" -target "$(host_target)" \
	"$ROOT/Sources/App/SettingsLaunchHandoff.swift" \
	"$ROOT/Tools/SettingsLaunchRegression/Fixture.swift" >>"$LOG" 2>&1 \
	|| fail "fixture did not compile"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.gazeunlock.Gaze.SettingsLaunchHandoffTest' "$APP/Contents/Info.plist" >>"$LOG" 2>&1
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string GazeHandoffFixture' "$APP/Contents/Info.plist" >>"$LOG" 2>&1
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string GazeHandoffFixture' "$APP/Contents/Info.plist" >>"$LOG" 2>&1
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$APP/Contents/Info.plist" >>"$LOG" 2>&1
/usr/libexec/PlistBuddy -c 'Add :LSUIElement bool true' "$APP/Contents/Info.plist" >>"$LOG" 2>&1
codesign --force --sign - "$APP" >>"$LOG" 2>&1 || fail "fixture codesign failed"

echo "== self-test: eligibility + no-existing-instance ==" | tee -a "$LOG"
GAZE_HANDOFF_TEST_DIR="$MARKDIR" GAZE_HANDOFF_SELFTEST=1 "$EXE" 2>&1 | tee -a "$LOG" \
	|| fail "self-test binary exited nonzero"
GAZE_HANDOFF_TEST_DIR="$MARKDIR" GAZE_HANDOFF_SELFTEST=1 "$EXE" 2>/dev/null | grep -q "^FAIL" \
	&& fail "self-test reported FAIL lines"

echo "== two-process handoff ==" | tee -a "$LOG"
export GAZE_HANDOFF_TEST_DIR="$MARKDIR"
"$EXE" >>"$LOG" 2>&1 &
PID1=$!
echo "$PID1" >"$SCRATCH/fixture-1.pid"

# First instance must reach "service started" (its per-PID marker).
for _ in $(seq 1 100); do
	[ -f "$MARKDIR/service-$PID1" ] && break
	sleep 0.1
done
[ -f "$MARKDIR/service-$PID1" ] || fail "first fixture instance (PID $PID1) never wrote its service marker"
ps -p "$PID1" -o comm= 2>/dev/null | grep -q "GazeHandoffFixture" \
	|| fail "PID $PID1 is not the fixture executable"

# Second launch of the SAME executable with --settings must hand off and exit(0).
set +u
"$EXE" --settings >>"$LOG" 2>&1 &
PID2=$!
wait "$PID2"
STATUS2=$?
set -u
echo "second launch exit status: $STATUS2" | tee -a "$LOG"
[ "$STATUS2" -eq 0 ] || fail "second --settings launch exited $STATUS2, expected 0"
[ ! -f "$MARKDIR/service-$PID2" ] || fail "second launch wrote service-$PID2: it started its own stack"

# The first instance must have received the reopen.
for _ in $(seq 1 150); do
	[ -f "$MARKDIR/reopened" ] && break
	sleep 0.1
done
[ -f "$MARKDIR/reopened" ] || fail "first instance never received applicationShouldHandleReopen (no reopened marker); NSWorkspace reuse did not deliver reopen in this environment"

echo "PASS settings-launch handoff: reopen delivered, second launch exited 0 with no service marker" | tee -a "$LOG"
