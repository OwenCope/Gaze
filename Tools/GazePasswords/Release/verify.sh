#!/bin/bash
# Verifies a built Gaze Passwords app without launching it, installing
# anything. Distribution assessment uses the system Gatekeeper tools.
#
#   bash Tools/GazePasswords/Release/verify.sh [--local|--distribution] [APP]
#
# --local (default) accepts the Apple Development protected build: the
# embedded provisioning profile must be present, unexpired, team- and
# app-matched, and must list the signing certificate.
#
# --distribution requires Developer ID Application authority, a secure
# timestamp, release-safe entitlements and (when run by the owner) a stapled
# notarization ticket plus Gatekeeper acceptance. It refuses development
# signatures outright and never treats codesign success as notarization.
#
# Either mode refuses missing/expired profiles, wrong signing
# identities, wrong entitlements, mismatched extension identities and absent
# required contents. Passing is artifact validation, NOT proof of working
# unlock, vault persistence, live face approval or safe distribution.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
MODE='--local'
APP=''
for arg in "$@"; do
  case "$arg" in
    --local|--distribution) MODE="$arg" ;;
    *) APP="$arg" ;;
  esac
done
[ -n "$APP" ] || APP="$ROOT/build/browser-integration/Gaze Passwords.app"
GAZE_APP="${GAZE_APP:-$ROOT/build/Gaze.app}"
BUNDLE_ID='com.gazeunlock.Passwords'
HELPER_ID='com.gazeunlock.Passwords.BrowserBridge'
fail() { echo "FAIL: $*" >&2; exit 1; }
note() { echo "note: $*" >&2; }

test -d "$APP" || fail "Passwords bundle missing: $APP"
PLIST="$APP/Contents/Info.plist"
test -f "$PLIST" || fail 'Bundle Info.plist missing'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST" 2>/dev/null)" = "$BUNDLE_ID" \
  || fail 'Unexpected bundle identifier'
EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST" 2>/dev/null)" \
  || fail 'CFBundleExecutable missing from Info.plist'
test "$EXECUTABLE" = GazePasswords || fail 'Unexpected bundle executable'
BIN="$APP/Contents/MacOS/$EXECUTABLE"
test -x "$BIN" || fail 'Passwords executable missing or not executable'
HELPER="$APP/Contents/Helpers/GazeBrowserBridge"
test -x "$HELPER" || fail 'Native helper GazeBrowserBridge missing or not executable'
EXTENSION_DIR="$APP/Contents/Resources/BrowserExtension"
test -f "$EXTENSION_DIR/manifest.json" || fail 'Bundled browser extension manifest missing'
test -f "$APP/Contents/Resources/BrowserIdentity.json" || fail 'Bundled BrowserIdentity.json missing'
for resource in background.js login-form.js popup.js popup.html popup.css icon128.png; do
  test -f "$EXTENSION_DIR/$resource" || fail "Bundled extension resource missing: $resource"
done
test -f "$APP/Contents/Resources/PasswordsIcon.icns" || fail 'App icon missing'
for key in CFBundleName CFBundleDisplayName CFBundleShortVersionString CFBundleVersion LSMinimumSystemVersion; do
  /usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" >/dev/null 2>&1 || fail "Info.plist key $key missing"
done

codesign --verify --deep --strict -R="anchor apple generic and identifier \"$BUNDLE_ID\"" "$APP" || fail 'Code signature verification failed'
SIGNATURE="$(codesign -dv --verbose=4 "$APP" 2>&1)" || fail 'Signature metadata unavailable'
printf '%s\n' "$SIGNATURE" | grep -q '^Authority=' || fail 'No signing authority (ad-hoc signatures are not supported)'
[ "$(printf '%s\n' "$SIGNATURE" | sed -n 's/^Identifier=//p')" = "$BUNDLE_ID" ] || fail 'Signed app identifier mismatch'
TEAM="$(printf '%s\n' "$SIGNATURE" | sed -n 's/^TeamIdentifier=//p')"
[[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]] || fail 'No valid signing team on the app'
printf '%s\n' "$SIGNATURE" | grep -q 'flags=.*runtime' || fail 'Hardened Runtime missing from the app signature'

codesign --verify --strict -R="anchor apple generic and identifier \"$HELPER_ID\"" "$HELPER" || fail 'Helper signature verification failed'
HELPER_SIGNATURE="$(codesign -dv --verbose=4 "$HELPER" 2>&1)" || fail 'Helper signature metadata unavailable'
printf '%s\n' "$HELPER_SIGNATURE" | grep -q '^Authority=' || fail 'Nested helper has no signing authority'
[ "$(printf '%s\n' "$HELPER_SIGNATURE" | sed -n 's/^Identifier=//p')" = "$HELPER_ID" ] || fail 'Signed helper identifier mismatch'
HELPER_TEAM="$(printf '%s\n' "$HELPER_SIGNATURE" | sed -n 's/^TeamIdentifier=//p')"
[ "$HELPER_TEAM" = "$TEAM" ] || fail 'Nested helper team does not match the app team'
printf '%s\n' "$HELPER_SIGNATURE" | grep -q 'flags=.*runtime' || fail 'Hardened Runtime missing from the nested helper signature'

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/passwords-release-verify.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
codesign -d --entitlements :- "$APP" > "$SCRATCH/entitlements.plist" 2>/dev/null \
  || fail 'App entitlements unavailable'
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.application-identifier' "$SCRATCH/entitlements.plist" 2>/dev/null)" = "$TEAM.$BUNDLE_ID" \
  || fail 'App application-identifier entitlement mismatch'
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.team-identifier' "$SCRATCH/entitlements.plist" 2>/dev/null)" = "$TEAM" \
  || fail 'App team-identifier entitlement mismatch'
test "$(/usr/libexec/PlistBuddy -c 'Print :keychain-access-groups:0' "$SCRATCH/entitlements.plist" 2>/dev/null)" = "$TEAM.$BUNDLE_ID" \
  || fail 'App Keychain access group entitlement mismatch'
python3 - "$SCRATCH/entitlements.plist" "$TEAM.$BUNDLE_ID" <<'PYGROUP' || fail 'App Keychain access group entitlement mismatch'
import plistlib, sys
entitlements = plistlib.load(open(sys.argv[1], 'rb'))
sys.exit(0 if entitlements.get('keychain-access-groups') == [sys.argv[2]] else 1)
PYGROUP
codesign -d --entitlements :- "$HELPER" > "$SCRATCH/helper-entitlements.plist" 2>/dev/null || fail 'Helper entitlements unavailable'
python3 - "$SCRATCH/helper-entitlements.plist" <<'PYHELPER' || fail 'Helper must not have vault Keychain entitlements'
import plistlib, sys
from pathlib import Path
raw = Path(sys.argv[1]).read_bytes()
values = plistlib.loads(raw) if raw.strip() else {}
sys.exit(1 if values.get('keychain-access-groups') else 0)
PYHELPER

if [ "$MODE" = '--distribution' ]; then
  printf '%s\n' "$SIGNATURE" | grep -q '^Authority=Developer ID Application: ' \
    || fail 'Distribution requires a Developer ID Application signature'
  printf '%s\n' "$SIGNATURE" | grep -q '^Timestamp=' \
    || fail 'Secure timestamp missing; distribution signatures must be timestamped'
  printf '%s\n' "$HELPER_SIGNATURE" | grep -q '^Authority=Developer ID Application: ' \
    || fail 'Distribution helper requires a Developer ID Application signature'
  printf '%s\n' "$HELPER_SIGNATURE" | grep -q '^Timestamp=' || fail 'Secure timestamp missing from helper'
  python3 - "$SCRATCH/entitlements.plist" "$SCRATCH/helper-entitlements.plist" <<'PYSAFE' || fail 'Unsafe distribution entitlement'
import plistlib, sys
from pathlib import Path
for path in sys.argv[1:]:
    raw = Path(path).read_bytes()
    values = plistlib.loads(raw) if raw.strip() else {}
    unsafe = ['get-task-allow', 'cs.disable-library-validation', 'cs.allow-dyld-environment-variables',
              'cs.allow-unsigned-executable-memory', 'cs.disable-executable-page-protection', 'cs.allow-jit']
    if any(values.get('com.apple.security.' + name) is True for name in unsafe):
        sys.exit(1)
PYSAFE
fi
  test -f "$APP/Contents/embedded.provisionprofile" || fail 'Embedded provisioning profile missing'
  security cms -D -i "$APP/Contents/embedded.provisionprofile" -o "$SCRATCH/profile.plist" \
    || fail 'Embedded provisioning profile could not be decoded'
  PROFILE_INFO="$(python3 - "$SCRATCH/profile.plist" "$TEAM" "$BUNDLE_ID" "$MODE" <<'PY'
import plistlib, sys
from datetime import datetime, timezone
profile = plistlib.load(open(sys.argv[1], "rb"))
team, bundle = sys.argv[2], sys.argv[3]
expiry = profile.get("ExpirationDate")
if expiry is None or expiry.replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc):
    sys.stderr.write("profile expired or undated\n")
    sys.exit(10)
if team not in profile.get("TeamIdentifier", []):
    sys.stderr.write("profile team mismatch\n")
    sys.exit(11)
platforms = profile.get("Platform")
if platforms is not None and "OSX" not in platforms:
    sys.stderr.write("profile platform mismatch\n")
    sys.exit(14)
entitlements = profile.get("Entitlements", {})
if entitlements.get("com.apple.developer.team-identifier") != team:
    sys.stderr.write("profile team entitlement mismatch\n")
    sys.exit(11)
if entitlements.get("com.apple.application-identifier") != team + "." + bundle:
    sys.stderr.write("profile application-identifier mismatch\n")
    sys.exit(12)
groups = entitlements.get("keychain-access-groups", [])
if team + "." + bundle not in groups and team + ".*" not in groups:
    sys.stderr.write("profile Keychain group mismatch\n")
    sys.exit(13)
if sys.argv[4] == '--distribution' and (profile.get('ProvisionsAllDevices') is not True
    or profile.get('ProvisionedDevices') or entitlements.get('com.apple.security.get-task-allow') is True):
    sys.stderr.write("development profile cannot authorize distribution\n")
    sys.exit(15)
print("profile=%s expiry=%s" % (profile.get("Name", "(unnamed)"), expiry.isoformat()))
PY
)" || {
    code=$?
    case "$code" in
      10) fail 'Embedded provisioning profile is expired' ;;
      11) fail 'Embedded provisioning profile team mismatch' ;;
      12) fail 'Embedded provisioning profile application-identifier mismatch (wildcard profiles refused)' ;;
      13) fail 'Embedded provisioning profile Keychain group mismatch' ;;
      14) fail 'Embedded provisioning profile platform mismatch' ;;
      15) fail 'Distribution requires a distribution provisioning profile' ;;
      *) fail 'Embedded provisioning profile check failed' ;;
    esac
  }
  codesign -d --extract-certificates="$SCRATCH/certs" "$APP" >/dev/null 2>&1 \
    || fail 'Signing certificates unavailable'
  python3 - "$SCRATCH/profile.plist" "$SCRATCH/certs0" <<'PY' || fail 'Embedded profile does not list the signing certificate'
import hashlib, plistlib, sys
profile = plistlib.load(open(sys.argv[1], "rb"))
authorized = {hashlib.sha1(bytes(c)).hexdigest() for c in profile.get("DeveloperCertificates", [])}
with open(sys.argv[2], "rb") as f:
    leaf = hashlib.sha1(f.read()).hexdigest()
sys.exit(0 if leaf in authorized else 1)
PY
  TASK_ALLOW="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$SCRATCH/entitlements.plist" 2>/dev/null || true)"
  [ "$TASK_ALLOW" != true ] || note 'get-task-allow permits debugging; this build is development-only'
if [ "$MODE" = '--distribution' ]; then
  xcrun stapler validate "$APP" || fail 'Stapled notarization ticket not validated'
  spctl --assess --type execute "$APP" || fail 'Gatekeeper did not accept the distribution bundle'
fi

EXTENSION_ID="$(python3 - "$EXTENSION_DIR/manifest.json" "$APP/Contents/Resources/BrowserIdentity.json" <<'PY'
import base64, hashlib, json, re, sys
manifest = json.load(open(sys.argv[1]))
identity = json.load(open(sys.argv[2]))
if "key" not in manifest:
    sys.stderr.write("extension manifest has no key\n")
    sys.exit(20)
digest = hashlib.sha256(base64.b64decode(manifest["key"], validate=True)).digest()[:16]
derived = "".join(chr(97 + n) for b in digest for n in (b >> 4, b & 15))
if identity.get("extensionID") != derived:
    sys.stderr.write("extension identity mismatch\n")
    sys.exit(21)
if not re.fullmatch(r"[a-p]{32}", derived):
    sys.stderr.write("extension identity malformed\n")
    sys.exit(22)
for field in ['host_permissions', 'optional_host_permissions', 'optional_permissions', 'content_scripts', 'externally_connectable', 'web_accessible_resources']:
    if manifest.get(field):
        sys.stderr.write("unexpected extension capability: " + field + "\n")
        sys.exit(23)
if manifest.get('manifest_version') != 3 or manifest.get('background') != {'service_worker': 'background.js', 'type': 'module'} or manifest.get('action', {}).get('default_popup') != 'popup.html':
    sys.stderr.write("extension entry point mismatch\n")
    sys.exit(24)
permissions = manifest.get("permissions", [])
if sorted(permissions) != ["activeTab", "nativeMessaging", "scripting"]:
    sys.stderr.write("extension permissions drift\n")
    sys.exit(23)
print(derived)
PY
)" || {
    code=$?
    case "$code" in
      20) fail 'Extension manifest key missing' ;;
      21) fail 'Extension identity mismatch between manifest key and BrowserIdentity.json' ;;
      22) fail 'Extension identity malformed' ;;
      23) fail 'Extension permissions differ from activeTab/scripting/nativeMessaging' ;;
      24) fail 'Extension entry point mismatch' ;;
      *) fail 'Extension identity check failed' ;;
    esac
  }

if [ -d "$GAZE_APP" ]; then
  codesign --verify --deep --strict -R='anchor apple generic and identifier "com.gazeunlock.Gaze"' "$GAZE_APP" || fail 'Gaze signature verification failed'
  GAZE_TEAM="$(codesign -dv "$GAZE_APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
  [ "$GAZE_TEAM" = "$TEAM" ] || fail "Gaze team $GAZE_TEAM does not match Passwords team $TEAM"
else
  [ "$MODE" != '--distribution' ] || fail 'Gaze companion bundle required for distribution integration check'
  note "no local Gaze.app at $GAZE_APP; same-team cross-check skipped"
fi

if [ "$MODE" = '--distribution' ]; then
  AUTHORITY_KIND='Developer ID Application'
else
  AUTHORITY_KIND="$(printf '%s\n' "$SIGNATURE" | sed -n 's/^Authority=\([^:]*\): .*/\1/p' | head -1)"
fi
echo "PASS ($MODE): bundle, signatures, hardened runtime, entitlements, profile, extension identity and required contents"
echo "Team: $TEAM"
echo "Authority: $AUTHORITY_KIND"
echo "Extension: $EXTENSION_ID"
if [ "$MODE" = '--local' ]; then
  echo "$PROFILE_INFO"
fi
echo "Executable SHA-256: $(shasum -a 256 "$BIN" | awk '{print $1}')"
echo "This is artifact validation, NOT proof of working unlock, vault persistence, live face approval, notarization, redistribution rights or clean-install compatibility. Complete Tools/GazePasswords/Release/RELEASE-READINESS.md before distributing."
