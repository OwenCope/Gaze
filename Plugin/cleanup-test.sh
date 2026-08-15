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
security authorizationdb remove com.gazeunlock.Gaze.testunlock 2>/dev/null \
	&& echo "  ✓ removed" || echo "  (not present)"

echo "→ Unloading the agent"
CONSOLE_UID="$(stat -f %u /dev/console)"
sudo -u "${SUDO_USER:-$(stat -f %Su /dev/console)}" launchctl bootout "gui/$CONSOLE_UID/com.gazeunlock.Gaze.agent" 2>/dev/null || true
rm -f /Library/LaunchAgents/com.gazeunlock.Gaze.agent.plist

echo "→ Removing the plugin"
rm -rf /Library/Security/SecurityAgentPlugins/Gaze.bundle
rm -f /tmp/gaze-test-right.plist

echo "✓ Clean. Your lock screen was never modified by the test."
