#!/bin/bash
# Settings UX regression: source-invariant checks for the 2026-09-16 review fixes.
#
# The Settings window is never launched here and nothing touches the Keychain,
# preferences, camera or enrolment. This script (1) parse-checks the real
# Sources/App/SettingsView.swift with the project toolchain, then (2) asserts
# the structural invariants the fixes depend on: a visible retained-password
# note in recognition-only mode, keyboard/VoiceOver-reachable face actions,
# and Touch ID copy that names only what its switch gates.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VIEW="$ROOT/Sources/App/SettingsView.swift"

fail=0
need() { # need <fixed-string> <why>
	if grep -F -q "$1" "$VIEW"; then
		echo "ok   - $2"
	else
		echo "FAIL - $2 (missing: $1)"
		fail=1
	fi
}
forbid() { # forbid <fixed-string> <why>
	if grep -F -q "$1" "$VIEW"; then
		echo "FAIL - $2 (still present: $1)"
		fail=1
	else
		echo "ok   - $2"
	fi
}

echo "-- parse --"
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
	-parse "$VIEW" -o /dev/null
echo "ok   - SettingsView.swift parses"

echo "-- recognition-only mode --"
need 'Try Test Recognition below. Nothing runs on the lock screen in this mode.' \
	"hero in .none names Test Recognition, not lock-screen scanning"
forbid 'Recognise your face without entering a password.' \
	"old hero copy implying lock-screen recognition is gone"
need 'if settings.unlockBackend == .none, hasStoredPassword {' \
	"retained-password note gated on .none with an existing stored password"
need 'Nothing can unlock with it in this mode.' \
	"retained note states unlock stays off"
need 'private var retainedPasswordRow: some View {' \
	"retained row reuses the existing Change / Revoke actions"
forbid 'PasswordVault.password' \
	"no password value is ever read (rendering or actions)"

echo "-- enrolled-face actions --"
forbid 'if hovering {' \
	"no overlay action is hover-gated any more"
need 'hovering || isEditing || portraitFocused || removeFocused' \
	"reveal condition joins hover with name-field and action focus"
need 'accessibilityLabel("Remove \(face.name)")' \
	"remove announces per-face to VoiceOver"
need 'accessibilityLabel("Choose a photo for \(face.name)")' \
	"portrait action announces per-face to VoiceOver"
need 'BiometricGate.authorize(.removeEnrollment)' \
	"existing removal authorization path intact"

echo "-- Touch ID row scope --"
need 'Ask before removing a face or changing the stored password' \
	"row titles the two authorize() call sites"
need 'Adding a face always asks, even when this is off.' \
	"row states the always-on add-face prompt"
forbid 'Require Touch ID for changes here' \
	"overbroad title is gone"
need 'isEnabled: BiometricGate.isAvailable,' \
	"no-sensor gating unchanged (policy untouched)"
need 'isOn: bind(\.touchIDFallback))' \
	"same preference binding (policy untouched)"

echo "-- deliberately unchanged --"
need 'Movements to unlock this Mac' \
	"movement-count row untouched"
need 'Lock when I walk away' \
	"walk-away row untouched"
need 'isEnabled: Liveness.isAvailable,' \
	"anti-spoof enablement untouched (separate finding)"

exit "$fail"
