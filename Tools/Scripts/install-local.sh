#!/bin/bash
# Puts a freshly built Gaze in place of the copy this Mac actually runs, and restarts it.
#
# Gaze runs from wherever its launch agent points (~/Library/LaunchAgents/
# com.gazeunlock.Gaze.agent.plist), with KeepAlive, so quitting it just relaunches the
# old copy and building somewhere else changes nothing you can see. This swaps the app
# at that path, keeping the previous one beside it, and restarts the agent.
#
#   Tools/Scripts/install-local.sh                  install build/dmg-launch/Gaze.app
#   Tools/Scripts/install-local.sh path/to/Gaze.app install that build
#   Tools/Scripts/install-local.sh --restore        put the previous copy back
set -euo pipefail

AGENT_LABEL="com.gazeunlock.Gaze.agent"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DOMAIN="gui/$(id -u)"

if [ ! -f "$AGENT_PLIST" ]; then
	echo "No Gaze launch agent at $AGENT_PLIST. Open Gaze once so it installs one." >&2
	exit 1
fi

# The executable the agent launches, and the .app around it.
EXECUTABLE="$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$AGENT_PLIST")"
TARGET="${EXECUTABLE%/Contents/MacOS/*}"
PREVIOUS="${TARGET%.app} previous.app"

if [ "${1:-}" = "--restore" ]; then
	[ -d "$PREVIOUS" ] || { echo "No previous copy at $PREVIOUS" >&2; exit 1; }
	SOURCE="$PREVIOUS"
else
	SOURCE="${1:-$ROOT/build/dmg-launch/Gaze.app}"
	[ -d "$SOURCE" ] || { echo "No build at $SOURCE. Run ./build.sh first." >&2; exit 1; }
fi

version() { /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$1/Contents/Info.plist" 2>/dev/null || echo "?"; }

codesign --verify --deep --strict "$SOURCE" || { echo "$SOURCE is not validly signed; not installing." >&2; exit 1; }

echo "Stopping Gaze…"
launchctl bootout "$DOMAIN/$AGENT_LABEL" 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
	pgrep -f "$EXECUTABLE" >/dev/null || break
	sleep 0.5
done

STAGING="$(mktemp -d)/Gaze.app"
ditto "$SOURCE" "$STAGING"
if [ "${1:-}" = "--restore" ]; then
	rm -rf "$TARGET"
else
	rm -rf "$PREVIOUS"
	[ -d "$TARGET" ] && mv "$TARGET" "$PREVIOUS"
fi
mv "$STAGING" "$TARGET"

echo "Starting Gaze $(version "$TARGET")…"
launchctl bootstrap "$DOMAIN" "$AGENT_PLIST"
sleep 2
if pgrep -f "$EXECUTABLE" >/dev/null; then
	echo "Running $(version "$TARGET") from $TARGET"
	[ -d "$PREVIOUS" ] && echo "Previous copy ($(version "$PREVIOUS")) kept at $PREVIOUS. Undo with: $0 --restore"
else
	echo "Gaze did not start. Check Console for com.gazeunlock.Gaze." >&2
	exit 1
fi
