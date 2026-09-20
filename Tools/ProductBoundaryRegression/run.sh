#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/Tools/MainAppSources.sh"
collect_gaze_main_sources "$ROOT"
for source in "${GAZE_MAIN_SOURCES[@]}"; do
	case "$source" in
		*/Sources/Autofill/*|*/AutofillSettings.swift|*/FaceCheck.swift)
			echo "FAIL: retired autofill source included in Gaze" >&2; exit 1 ;;
	esac
done
echo "PASS Gaze build excludes retired autofill implementations"
if grep -qE 'AutofillService|AutofillWatcher|SavedAppStore|GlobalHotKey|AutofillSection|startAutofill' "${GAZE_MAIN_SOURCES[@]}"; then
	echo "FAIL: autofill runtime wiring remains in Gaze" >&2; exit 1
fi
echo "PASS Gaze has no autofill runtime wiring or saved-app store initialization"
if grep -qE 'case .*autofill|\.autofill|autofillOnActivation' "$ROOT/Sources/App/SettingsView.swift" "$ROOT/Sources/App/Preferences.swift"; then
	echo "FAIL: autofill pane or preference remains" >&2; exit 1
fi
echo "PASS Gaze exposes no autofill pane or activation preference"
for required in LockWatcher.swift PasswordVault.swift BiometricGate.swift LockScreenPasswordSubmission.swift; do
	found=false
	for source in "${GAZE_MAIN_SOURCES[@]}"; do
		if [ "$(basename "$source")" = "$required" ]; then found=true; break; fi
	done
	if [ "$found" != true ]; then echo "FAIL: missing Mac-unlock protection $required" >&2; exit 1; fi
done
echo "PASS Mac-unlock and owner-authentication protections remain included"
ENTITLEMENTS="$ROOT/Tools/GazePasswords/Preview.entitlements"
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$ENTITLEMENTS")" = true
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.user-selected.read-only' "$ENTITLEMENTS")" = true
if grep -qE 'network\.(client|server)|device.camera|automation.apple-events|read-write|keychain-access-groups' "$ENTITLEMENTS"; then
	echo "FAIL: Passwords preview gained unnecessary privilege" >&2; exit 1
fi
echo "PASS Passwords stays sandboxed with read-only user-selected access"
for script in "$ROOT/build.sh" "$ROOT/Tools/GazePasswords/script/build_and_run.sh"; do
	grep -qE -- '--options runtime' "$script"
done
echo "PASS both builds enable Hardened Runtime"
echo "6 product-boundary checks passed; no credential access or app launch"
