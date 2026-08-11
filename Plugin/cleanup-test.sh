#!/bin/bash
# Removes everything test-plugin.sh set up.
#
# Safe to run at any point, including if the test hung or crashed. It only touches the
# throwaway right and our own files — no system authorization rule is involved, because
# the test never modified one.
set -u

if [ "$(id -u)" -ne 0 ]; then
	echo "Run with sudo." >&2
	exit 1
fi

echo "→ Removing the throwaway right"
security authorizationdb remove app.faceid.testunlock 2>/dev/null \
	&& echo "  ✓ removed" || echo "  (not present)"

echo "→ Unloading the agent"
CONSOLE_UID="$(stat -f %u /dev/console)"
sudo -u "${SUDO_USER:-$(stat -f %Su /dev/console)}" launchctl bootout "gui/$CONSOLE_UID/app.faceid.agent" 2>/dev/null || true
rm -f /Library/LaunchAgents/app.faceid.agent.plist

echo "→ Removing the plugin"
rm -rf /Library/Security/SecurityAgentPlugins/FaceID.bundle
rm -f /tmp/faceid-test-right.plist

echo "✓ Clean. Your lock screen was never modified by the test."
