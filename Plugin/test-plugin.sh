#!/bin/bash
# Exercises the plugin inside SecurityAgent WITHOUT touching the lock screen.
#
# This is the safe rehearsal. It installs the bundle and registers a throwaway
# authorization right that uses our mechanism, then asks for that right. The plugin gets
# loaded by the real SecurityAgent, in the real process, with the real callbacks — but if
# it crashes, hangs or denies, the only thing that fails is this test. Your lock screen is
# never involved and never modified.
#
# Run this, and only if it passes, run install.sh.
#
#   sudo ./test-plugin.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="/Applications/Face ID.app"
PLUGIN_DIR="/Library/Security/SecurityAgentPlugins"
TEST_RIGHT="app.faceid.testunlock"

if [ "$(id -u)" -ne 0 ]; then
	echo "Run with sudo." >&2
	exit 1
fi

[ -d "$ROOT/build/FaceID.bundle" ] || { echo "Run ./build-plugin.sh first." >&2; exit 1; }
[ -d "$APP" ] || { echo "Copy 'Face ID.app' to /Applications first." >&2; exit 1; }

echo "→ Pinning the agent requirement"
REQUIREMENT="$(codesign -d -r- "$APP" 2>/dev/null | sed -n 's/^designated => //p')"
[ -n "$REQUIREMENT" ] || { echo "App is not signed." >&2; exit 1; }
# plutil, not PlistBuddy: the requirement contains double quotes around the certificate
# common name, and PlistBuddy's -c parsing strips them. The result is a malformed
# requirement that SecRequirementCreateWithString refuses, so every reply from the agent
# was discarded as "untrusted" — a corrupted input masquerading as a security failure.
plutil -replace FaceIDAgentRequirement -string "$REQUIREMENT" \
	"$ROOT/build/FaceID.bundle/Contents/Info.plist"

# Sign as the invoking user, not as root.
#
# The signing key lives in *your* login keychain, which root cannot open — signing under
# sudo fails with errSecInternalComponent. So drop privileges for this one step. The
# plist edit above must happen first, since the signature has to cover it.
SIGNER="${SUDO_USER:-$(stat -f %Su /dev/console)}"
IDENTITY="$(sudo -u "$SIGNER" security find-identity -v -p codesigning 2>/dev/null \
	| awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')"
[ -n "$IDENTITY" ] || IDENTITY="-"
if ! sudo -u "$SIGNER" codesign --force --sign "$IDENTITY" \
	--identifier app.faceid.plugin "$ROOT/build/FaceID.bundle" 2>/dev/null; then
	echo "  ! signing as $SIGNER failed; falling back to ad-hoc"
	sudo -u "$SIGNER" codesign --force --sign - \
		--identifier app.faceid.plugin "$ROOT/build/FaceID.bundle"
fi

echo "→ Installing the bundle"
mkdir -p "$PLUGIN_DIR"
rm -rf "$PLUGIN_DIR/FaceID.bundle"
cp -R "$ROOT/build/FaceID.bundle" "$PLUGIN_DIR/"
chown -R root:wheel "$PLUGIN_DIR/FaceID.bundle"

echo "→ Installing the LaunchAgent"
cp "$ROOT/app.faceid.agent.plist" /Library/LaunchAgents/
chown root:wheel /Library/LaunchAgents/app.faceid.agent.plist
# Bootstrapped as the user, not as root.
#
# A gui/<uid> domain belongs to that login session, and launchd refuses a root caller
# reaching into it — the symptom is "Bootstrap failed: 5: Input/output error", which
# reads like a broken plist but is really a wrong-domain error.
CONSOLE_UID="$(stat -f %u /dev/console)"
sudo -u "$SIGNER" launchctl bootout "gui/$CONSOLE_UID/app.faceid.agent" 2>/dev/null || true
sudo -u "$SIGNER" launchctl bootstrap "gui/$CONSOLE_UID" \
	/Library/LaunchAgents/app.faceid.agent.plist
sleep 2

if ! sudo -u "$SIGNER" launchctl print "gui/$CONSOLE_UID/app.faceid.agent" >/dev/null 2>&1; then
	echo "The agent did not load. The plugin would have nothing to ask." >&2
	exit 1
fi
echo "  ✓ agent loaded and vending app.faceid.unlock"

echo "→ Registering the throwaway right '$TEST_RIGHT'"
# Note this is a NEW right of our own invention. No existing system right is modified, so
# nothing that already works can break.
cat > /tmp/faceid-test-right.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>class</key>
	<string>evaluate-mechanisms</string>
	<!--
	  NOT ",privileged".

	  A privileged mechanism runs inside authd as root, with no window server
	  connection, so it cannot display anything. Ours builds an SFAuthorizationPluginView
	  and shows the capsule, which means it has to run non-privileged — in SecurityAgent,
	  which is the process that owns the authentication UI. Marking it privileged makes
	  the whole evaluation fail with errAuthorizationInternal (-60008) before the plugin's
	  first line of code runs.
	-->
	<key>mechanisms</key>
	<array>
		<string>FaceID:unlock</string>
	</array>
	<key>tries</key>
	<integer>1</integer>
	<key>comment</key>
	<string>Throwaway right for testing the Face ID plugin. Safe to delete.</string>
</dict>
</plist>
PLIST
security authorizationdb write "$TEST_RIGHT" < /tmp/faceid-test-right.plist

# Verify it actually landed. An unregistered right does not error when you ask for it —
# it quietly falls through to a default rule and returns success, which looks exactly
# like the plugin having allowed the request. That false pass is worse than a failure,
# so refuse to hand over a test that could produce it.
if ! security authorizationdb read "$TEST_RIGHT" 2>/dev/null | grep -q "FaceID:unlock<"; then
	echo "The test right did not register. Not proceeding — a test now would report a" >&2
	echo "misleading success without the plugin being involved at all." >&2
	exit 1
fi
echo "  ✓ right registered and points at FaceID:unlock"

if [ ! -x "$PLUGIN_DIR/FaceID.bundle/Contents/MacOS/FaceID" ]; then
	echo "Plugin binary missing after install." >&2
	exit 1
fi
echo "  ✓ plugin present at $PLUGIN_DIR/FaceID.bundle"

echo
echo "✓ Ready. Now run the test:"
echo
echo "    security authorize -u $TEST_RIGHT"
echo
echo "  Expect: the capsule appears, it looks at you, and it either allows or falls back"
echo "  to a password field. Watch what the plugin is doing in another terminal with:"
echo
echo "    log stream --predicate 'subsystem == \"app.faceid.plugin\"'"
echo
echo "  Whatever happens, your lock screen is untouched."
echo "  Clean up with:  sudo $ROOT/cleanup-test.sh"
