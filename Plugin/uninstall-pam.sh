#!/bin/bash
# Removes face authentication for `sudo`.
#
# Run: sudo ./uninstall-pam.sh
#
# Deliberately tolerant: every step is allowed to fail without stopping the rest. Somebody
# running an uninstaller usually wants the machine back to normal, not a script that gives
# up halfway because one file was already gone.
set -uo pipefail

if [ "$(id -u)" -ne 0 ]; then
	echo "Run this with sudo:  sudo $0" >&2
	exit 1
fi

PAM_DIR="/usr/local/lib/pam"
SUDO_LOCAL="/etc/pam.d/sudo_local"

USER_NAME="${SUDO_USER:-$(logname 2>/dev/null || true)}"
USER_HOME="$(dscl . -read "/Users/$USER_NAME" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"

# The PAM line goes first.
#
# Order matters here in a way it does not in the installer: while the line is present and
# the module is missing, PAM logs a failure to load on every sudo. Harmless — `sufficient`
# means it still falls through to the password — but noisy, and there is no reason to pass
# through that state when removing the line first avoids it.
if [ -f "$SUDO_LOCAL" ] && grep -qF "pam_gaze.so" "$SUDO_LOCAL"; then
	echo "→ Removing the auth line from $SUDO_LOCAL"
	chmod 644 "$SUDO_LOCAL"
	grep -vF "pam_gaze.so" "$SUDO_LOCAL" | grep -vF "# Added by Gaze." > "$SUDO_LOCAL.new"
	# An empty sudo_local is fine — `auth include sudo_local` on an empty file is a no-op —
	# but a file with nothing but a blank line in it is untidy, so remove it entirely.
	if [ -s "$SUDO_LOCAL.new" ] && grep -q '[^[:space:]]' "$SUDO_LOCAL.new"; then
		mv "$SUDO_LOCAL.new" "$SUDO_LOCAL"
		chown root:wheel "$SUDO_LOCAL"
		chmod 444 "$SUDO_LOCAL"
	else
		rm -f "$SUDO_LOCAL.new" "$SUDO_LOCAL"
	fi
fi

echo "→ Removing the module"
rm -f "$PAM_DIR/pam_gaze.so" "$PAM_DIR/pam_gaze.requirement"
# Only if we left it empty. Other things may live here.
rmdir "$PAM_DIR" 2>/dev/null || true

if [ -n "$USER_NAME" ] && [ "$USER_NAME" != "root" ] && [ -n "$USER_HOME" ]; then
	AGENT_PLIST="$USER_HOME/Library/LaunchAgents/com.gazeunlock.Gaze.agent.plist"
	if [ -f "$AGENT_PLIST" ]; then
		echo "→ Unregistering the mach service"
		USER_UID="$(id -u "$USER_NAME")"
		sudo -u "$USER_NAME" launchctl bootout "gui/$USER_UID/com.gazeunlock.Gaze.agent" 2>/dev/null || true
		rm -f "$AGENT_PLIST"
	fi
fi

echo
echo "✓ Removed. sudo is back to asking for your password."
echo "  Gaze itself is untouched — the app, your faces and your settings are all still there."
