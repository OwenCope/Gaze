#!/bin/bash
# Restart this checkout's Gaze, never an app resolved by name/Launch Services.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$ROOT/build/Gaze.app"
BINARY="$APP/Contents/MacOS/Gaze"
BUILD=1
DRY_RUN=0
RENDER_DIAGNOSTICS=0
LAUNCH_ARG=--settings

usage() {
	echo "Usage: $0 [--no-build] [--agent] [--render-diagnostics] [--dry-run]"
	echo "Default: stop old Gaze, build current sources, launch Settings."
	echo "  --no-build  Restart the latest successful build without recompiling."
	echo "  --agent     Launch in the menu bar without opening Settings."
	echo "  --dry-run   Print the plan without building, stopping, or launching."
	echo "  --render-diagnostics  Log render callback timing for this launch only."
}

for arg in "$@"; do
	case "$arg" in
		--no-build) BUILD=0 ;;
		--agent) LAUNCH_ARG=--agent ;;
		--dry-run) DRY_RUN=1 ;;
		--render-diagnostics) RENDER_DIAGNOSTICS=1 ;;
		-h|--help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done

# Restrict to this user's app processes; never touch PAM/XPC or other helpers.
gaze_pids() {
	local pid command
	for pid in $(/usr/bin/pgrep -u "$(/usr/bin/id -u)" -x Gaze || true); do
		command="$(/bin/ps -p "$pid" -o comm= 2>/dev/null || true)"
		case "$command" in
			*/Gaze.app/Contents/MacOS/Gaze) echo "$pid" ;;
		esac
	done
}

echo "Target: $APP"
echo "Existing Gaze app PIDs: $(gaze_pids | tr '\n' ' ')"
if [ "$DRY_RUN" = 1 ]; then
	echo "Would stop these app processes; build=$BUILD; launch $LAUNCH_ARG; render diagnostics=$RENDER_DIAGNOSTICS."
	exit 0
fi

if [ "$BUILD" = 0 ]; then
	[ -x "$BINARY" ] || { echo "No built app. Run without --no-build first." >&2; exit 1; }
	/usr/bin/codesign --verify --deep --strict "$APP"
else
	export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
	[ -d "$DEVELOPER_DIR" ] || { echo "Missing toolchain: $DEVELOPER_DIR" >&2; exit 1; }
fi

PIDS="$(gaze_pids)"
if [ -n "$PIDS" ]; then
	echo "Stopping Gaze app processes..."
	for pid in $PIDS; do
		# Recheck the scoped process list before signalling.
		if gaze_pids | /usr/bin/grep -qx "$pid"; then
			kill -TERM "$pid" 2>/dev/null || true
		fi
	done
	for ((attempt = 0; attempt < 50; attempt++)); do
		[ -z "$(gaze_pids)" ] && break
		sleep 0.1
	done
	if [ -n "$(gaze_pids)" ]; then
		echo "Gaze is still running or was restarted by a service. Aborting; no forced kill." >&2
		exit 1
	fi
fi

if [ "$BUILD" = 1 ]; then
	mkdir -p "$ROOT/build"
	MARKER="$(mktemp "$ROOT/build/.gaze-run-start.XXXXXX")"
	trap 'rm -f "$MARKER"' EXIT
	echo "Building current sources (log: build/run-gaze-build.log)..."
	# Force the local output even if this shell inherited release build options.
	if ! DIST=0 GAZE_BUILD_OUTPUT="$APP" "$ROOT/build.sh" >"$ROOT/build/run-gaze-build.log" 2>&1; then
		tail -n 50 "$ROOT/build/run-gaze-build.log" >&2
		echo "Build failed. Not launching the previous binary." >&2
		exit 1
	fi
	[ -x "$BINARY" ] && [ "$BINARY" -nt "$MARKER" ] || {
		echo "Build did not produce a fresh executable. Not launching." >&2
		exit 1
	}
fi

/usr/bin/codesign --verify --deep --strict "$APP"
/usr/bin/stat -f 'Binary modified: %Sm' -t '%Y-%m-%d %H:%M:%S' "$BINARY"
/usr/bin/shasum -a 256 "$BINARY"
/usr/bin/open -n --env "GAZE_RENDER_DIAGNOSTICS=$RENDER_DIAGNOSTICS" "$APP" --args "$LAUNCH_ARG"
sleep 2
FOUND=0
for pid in $(gaze_pids); do
	if [ "$(/bin/ps -p "$pid" -o comm=)" = "$BINARY" ]; then
		echo "Running this build: PID $pid"
		FOUND=1
	fi
done
[ "$FOUND" = 1 ] || { echo "Launch requested, but this build is not running." >&2; exit 1; }
