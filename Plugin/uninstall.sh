#!/bin/bash
# Removes the Face ID authorization plugin and restores Apple's lock screen.
#
# THIS IS THE ROLLBACK. If the lock screen ever stops accepting your password, run this —
# over SSH from another machine if you cannot get in locally. It is written to keep going
# on errors, because a rollback that stops halfway is worse than none.
#
#   sudo ./uninstall.sh
set -u

if [ "$(id -u)" -ne 0 ]; then
	echo "Run with sudo." >&2
	exit 1
fi

echo "→ Restoring system.login.screensaver"
# Apple's default. This alone is enough to get your lock screen working again, even if
# everything below fails.
security authorizationdb write system.login.screensaver < /dev/null 2>/dev/null || true
/usr/bin/security authorizationdb write system.login.screensaver use-login-window-ui \
	2>/dev/null && echo "  ✓ back to use-login-window-ui" \
	|| echo "  ! could not rewrite the rule — see the manual command below"

echo "→ Unloading the agent"
for uid in $(/usr/bin/who | /usr/bin/awk '{print $1}' | sort -u \
	| while read -r u; do id -u "$u" 2>/dev/null; done); do
	launchctl bootout "gui/$uid/app.faceid.agent" 2>/dev/null || true
done
rm -f /Library/LaunchAgents/app.faceid.agent.plist

echo "→ Removing the plugin"
rm -rf /Library/Security/SecurityAgentPlugins/FaceID.bundle

echo
echo "✓ Done. Touch ID on the lock screen works again after a restart."
echo
echo "If the lock screen is still broken, run this by hand:"
echo "  sudo security authorizationdb write system.login.screensaver use-login-window-ui"
