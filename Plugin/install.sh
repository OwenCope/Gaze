#!/bin/bash
# Installs the Gaze authorization plugin.
#
# READ THIS FIRST.
#
# This replaces how your Mac authenticates at the lock screen. Done wrong, you get a lock
# screen that will not let you in. Before running it:
#
#   1. Have uninstall.sh reachable. It is the rollback.
#   2. Have an SSH session open from another machine, or your phone. If the lock screen
#      breaks, that session is how you run the rollback.
#   3. Do not log out or lock the screen until you have tested it once.
#
# Cost, stated plainly: this disables Touch ID and Apple Watch unlock on the lock screen.
# macOS will not run its modern lock screen path and third-party plugins at the same time.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="/Applications/Gaze.app"
PLUGIN_DIR="/Library/Security/SecurityAgentPlugins"
BACKUP="/Library/Application Support/Gaze/screensaver-rule.backup.plist"

if [ "$(id -u)" -ne 0 ]; then
	echo "Run with sudo." >&2
	exit 1
fi

if [ ! -d "$ROOT/build/Gaze.bundle" ]; then
	echo "Plugin not built. Run ./build-plugin.sh first." >&2
	exit 1
fi

if [ ! -d "$APP" ]; then
	echo "Gaze.app must be in /Applications first — the LaunchAgent points there." >&2
	echo "  cp -R '$ROOT/../build/Gaze.app' /Applications/" >&2
	exit 1
fi

# Same vintage, for the same reason as test-plugin.sh: a new plugin against a stale
# /Applications copy recognises faces and draws nothing.
BUILD="$ROOT/../build/Gaze.app"
if [ -d "$BUILD" ] && [ "$BUILD/Contents/MacOS/Gaze" -nt "$APP/Contents/MacOS/Gaze" ]; then
	echo "→ Refreshing /Applications from the current build"
	rm -rf "$APP"
	cp -R "$BUILD" /Applications/
fi

echo "→ Backing up the current authorization rule"
mkdir -p "$(dirname "$BACKUP")"
security authorizationdb read system.login.screensaver > "$BACKUP"
echo "  saved to $BACKUP"

echo "→ Pinning the agent's code requirement"
# Derive the requirement from the app we are about to trust, rather than hardcoding it.
# This is what stops any other process answering the plugin's question — see PeerTrust.h.
REQUIREMENT="$(codesign -d -r- "$APP" 2>/dev/null | sed -n 's/^designated => //p')"
if [ -z "$REQUIREMENT" ]; then
	echo "Could not read the app's designated requirement. Is it signed?" >&2
	exit 1
fi
echo "  $REQUIREMENT"

# plutil, not PlistBuddy: the requirement contains double quotes around the certificate
# common name, and PlistBuddy's -c parsing strips them. The result is a malformed
# requirement that SecRequirementCreateWithString refuses, so every reply from the agent
# was discarded as "untrusted" — a corrupted input masquerading as a security failure.
plutil -replace GazeAgentRequirement -string "$REQUIREMENT" \
	"$ROOT/build/Gaze.bundle/Contents/Info.plist"

echo "→ Re-signing the plugin"
# The Info.plist just changed, so the old signature no longer covers it — and the plugin
# checks its peers strictly, so it had better be valid itself.
#
# Signed as the invoking user: the key is in their login keychain, which root cannot open.
SIGNER="${SUDO_USER:-$(stat -f %Su /dev/console)}"
IDENTITY="$(sudo -u "$SIGNER" security find-identity -v -p codesigning 2>/dev/null \
	| awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')"
[ -n "$IDENTITY" ] || IDENTITY="-"
if ! sudo -u "$SIGNER" codesign --force --sign "$IDENTITY" \
	--identifier com.gazeunlock.Gaze.plugin "$ROOT/build/Gaze.bundle" 2>/dev/null; then
	echo "  ! signing as $SIGNER failed; falling back to ad-hoc"
	sudo -u "$SIGNER" codesign --force --sign - \
		--identifier com.gazeunlock.Gaze.plugin "$ROOT/build/Gaze.bundle"
fi

echo "→ Installing the plugin"
mkdir -p "$PLUGIN_DIR"
rm -rf "$PLUGIN_DIR/Gaze.bundle"
cp -R "$ROOT/build/Gaze.bundle" "$PLUGIN_DIR/"
chown -R root:wheel "$PLUGIN_DIR/Gaze.bundle"

echo "→ Installing the LaunchAgent"
cp "$ROOT/com.gazeunlock.Gaze.agent.plist" /Library/LaunchAgents/
chown root:wheel /Library/LaunchAgents/com.gazeunlock.Gaze.agent.plist
chmod 644 /Library/LaunchAgents/com.gazeunlock.Gaze.agent.plist

# As the user: launchd refuses a root caller bootstrapping into a gui/<uid> domain.
CONSOLE_UID="$(stat -f %u /dev/console)"
sudo -u "$SIGNER" launchctl bootout "gui/$CONSOLE_UID/com.gazeunlock.Gaze.agent" 2>/dev/null || true
sudo -u "$SIGNER" launchctl bootstrap "gui/$CONSOLE_UID" \
	/Library/LaunchAgents/com.gazeunlock.Gaze.agent.plist

echo "→ Verifying the agent is reachable before changing the lock screen"
sleep 2
if ! sudo -u "$SIGNER" launchctl print "gui/$CONSOLE_UID/com.gazeunlock.Gaze.agent" >/dev/null 2>&1; then
	echo
	echo "The agent did not start. NOT changing the lock screen rule." >&2
	echo "Nothing has been broken — your lock screen is untouched." >&2
	exit 1
fi

# The rule change is last, and only after the agent is confirmed running. Doing it first
# would leave a window where the lock screen routes to a plugin with nothing to ask.
#
# Note the mechanism is NOT marked ",privileged". Privileged mechanisms run in authd as
# root with no window server connection and cannot display anything; ours has to show the
# capsule, so it runs in SecurityAgent. Marking it privileged fails the whole evaluation
# with errAuthorizationInternal before any of our code runs.
echo "→ Switching the lock screen to the plugin"
cat > /tmp/gaze-screensaver-rule.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>class</key>
	<string>evaluate-mechanisms</string>
	<key>mechanisms</key>
	<array>
		<string>Gaze:unlock</string>
	</array>
	<key>tries</key>
	<integer>1</integer>
	<key>comment</key>
	<string>Gaze. Restore with: security authorizationdb write system.login.screensaver use-login-window-ui</string>
</dict>
</plist>
PLIST
security authorizationdb write system.login.screensaver < /tmp/gaze-screensaver-rule.plist

echo
echo "✓ Installed."
echo
echo "  TEST NOW, before locking your screen or logging out:"
echo "    log stream --predicate 'subsystem == \"com.gazeunlock.Gaze.plugin\"'"
echo "  then lock the screen from another device's SSH session with:"
echo "    open -a ScreenSaverEngine"
echo
echo "  If anything goes wrong:  sudo $ROOT/uninstall.sh"
