#!/bin/bash
# Installs face authentication for `sudo`.
#
# Run: sudo ./install-pam.sh [/path/to/Gaze.app]
#
# WHAT THIS TOUCHES
#
#   /usr/local/lib/pam/pam_gaze.so           the module
#   /usr/local/lib/pam/pam_gaze.requirement  the agent's pinned code requirement
#   /etc/pam.d/sudo_local                    one line, backed up first
#   ~/Library/LaunchAgents/…agent.plist      registers the mach service the module talks to
#
# It does **not** touch /etc/pam.d/sudo. That file is Apple's, its first line is already
# `auth include sudo_local`, and sudo_local is the documented place for local additions —
# it is what the system's own Touch ID template tells you to edit. Keeping to it means a
# macOS update cannot half-apply our change and our change cannot break an updated sudo.
#
# WHY THIS CANNOT LOCK YOU OUT
#
# The line added is `auth sufficient`. Success short-circuits; **failure falls through** to
# the next line of the stack, which ends at the ordinary password prompt. Agent not
# running, module deleted, camera busy, wrong face, XPC unavailable — every one of them
# lands on "type your password". There is no path where this denies sudo to someone who
# knows their password.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
	echo "Run this with sudo:  sudo $0" >&2
	exit 1
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
MODULE="$ROOT/build/pam_gaze.so"
PAM_DIR="/usr/local/lib/pam"
SUDO_LOCAL="/etc/pam.d/sudo_local"

# Who invoked sudo. Everything user-owned — the LaunchAgent, the app itself — belongs to
# them, not to root.
USER_NAME="${SUDO_USER:-$(logname 2>/dev/null || true)}"
if [ -z "$USER_NAME" ] || [ "$USER_NAME" = "root" ]; then
	echo "Could not work out which user to install for. Run via sudo from your own account." >&2
	exit 1
fi
USER_HOME="$(dscl . -read "/Users/$USER_NAME" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"

APP="${1:-}"
if [ -z "$APP" ]; then
	for candidate in "/Applications/Gaze.app" "$ROOT/../build/Gaze.app"; do
		[ -d "$candidate" ] && APP="$candidate" && break
	done
fi
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
	echo "Could not find Gaze.app. Pass its path: sudo $0 /path/to/Gaze.app" >&2
	exit 1
fi
APP="$(cd "$APP" && pwd)"

if [ ! -f "$MODULE" ]; then
	echo "pam_gaze.so is not built. Run ./build-pam.sh first." >&2
	exit 1
fi

echo "→ App:  $APP"
echo "→ User: $USER_NAME"

# --- 1. The module ------------------------------------------------------------------

echo "→ Installing the module"
install -d -o root -g wheel -m 755 "$PAM_DIR"
install -o root -g wheel -m 644 "$MODULE" "$PAM_DIR/pam_gaze.so"

# --- 2. The pinned identity ---------------------------------------------------------
#
# Derived from the app being trusted rather than hardcoded, and re-derived on every
# install, because an ad-hoc signature's cdhash changes with every rebuild. Root-owned and
# world-readable: the module must read it, nothing else may write it. If an attacker could
# rewrite this file they would choose who gets to answer a sudo prompt.

echo "→ Pinning the agent's code requirement"
REQUIREMENT="$(codesign -d -r- "$APP" 2>/dev/null | sed -n 's/^designated => //p')"
if [ -z "$REQUIREMENT" ]; then
	echo "Could not read the app's designated requirement. Is it signed?" >&2
	exit 1
fi
printf '%s\n' "$REQUIREMENT" > "$PAM_DIR/pam_gaze.requirement"
chown root:wheel "$PAM_DIR/pam_gaze.requirement"
chmod 644 "$PAM_DIR/pam_gaze.requirement"
echo "   $REQUIREMENT"

# --- 3. The LaunchAgent -------------------------------------------------------------
#
# The module talks to Gaze over a mach service, and a plain application cannot vend one —
# only launchd can register it. Without this the module has nothing to connect to and
# every sudo falls through to the password, silently.

AGENT_PLIST="$USER_HOME/Library/LaunchAgents/com.gazeunlock.Gaze.agent.plist"
echo "→ Registering the mach service"
install -d -o "$USER_NAME" -m 755 "$USER_HOME/Library/LaunchAgents"
cat > "$AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.gazeunlock.Gaze.agent</string>
	<key>ProgramArguments</key>
	<array>
		<string>$APP/Contents/MacOS/Gaze</string>
		<string>--agent</string>
	</array>
	<key>MachServices</key>
	<dict>
		<key>com.gazeunlock.Gaze.unlock</key>
		<true/>
	</dict>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
</dict>
</plist>
PLIST
chown "$USER_NAME" "$AGENT_PLIST"
chmod 644 "$AGENT_PLIST"

# Reloaded as the user, not as root: a LaunchAgent belongs to their GUI session, and
# loading it from root's context registers it in the wrong domain where nothing in the
# user's session can reach it.
USER_UID="$(id -u "$USER_NAME")"
sudo -u "$USER_NAME" launchctl bootout "gui/$USER_UID/com.gazeunlock.Gaze.agent" 2>/dev/null || true
# Quit any hand-launched copy first, so launchd owns the one instance that vends the
# service rather than racing a second one that cannot.
sudo -u "$USER_NAME" osascript -e 'tell application "Gaze" to quit' 2>/dev/null || true
sleep 1
sudo -u "$USER_NAME" launchctl bootstrap "gui/$USER_UID" "$AGENT_PLIST"

# --- 4. The PAM line ----------------------------------------------------------------

LINE="auth       sufficient     $PAM_DIR/pam_gaze.so"

if [ -f "$SUDO_LOCAL" ] && grep -qF "pam_gaze.so" "$SUDO_LOCAL"; then
	echo "→ Already in $SUDO_LOCAL"
else
	if [ -f "$SUDO_LOCAL" ]; then
		BACKUP="$SUDO_LOCAL.before-gaze.$(date +%Y%m%d%H%M%S)"
		cp "$SUDO_LOCAL" "$BACKUP"
		echo "→ Backed up your existing sudo_local to $BACKUP"
	fi
	echo "→ Adding the auth line to $SUDO_LOCAL"
	# Prepended, so face is tried before anything already there. An absolute module path,
	# because /usr/lib/pam is SIP-protected and third-party modules cannot live in it.
	{
		echo "# Added by Gaze. Remove this line, or run uninstall-pam.sh, to undo."
		echo "$LINE"
		[ -f "$SUDO_LOCAL" ] && cat "$SUDO_LOCAL"
	} > "$SUDO_LOCAL.new"
	mv "$SUDO_LOCAL.new" "$SUDO_LOCAL"
	chown root:wheel "$SUDO_LOCAL"
	chmod 444 "$SUDO_LOCAL"
fi

echo
echo "✓ Installed."
echo
echo "  Test it in a SECOND terminal window before closing this one:"
echo "      sudo -k && sudo true"
echo
echo "  If anything is wrong, this window is still authenticated. Undo with:"
echo "      sudo $ROOT/uninstall-pam.sh"
echo
echo "  Face is tried first; your password still works and always will."
