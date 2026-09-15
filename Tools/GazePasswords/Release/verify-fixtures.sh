#!/bin/bash
# Fixture tests for Tools/GazePasswords/Release/verify.sh and wiring checks
# for the live packaging chain. Synthetic bundle, mocked signing and
# notarization tools, no network, no app launch, no Keychain access.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PROJECT="$ROOT/Tools/GazePasswords"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/passwords-release-fixture.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
APP="$SCRATCH/Gaze Passwords.app"
BIN="$SCRATCH/bin"
mkdir -p "$BIN" "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources/BrowserExtension"
cp "$PROJECT/Live/Info.plist" "$APP/Contents/Info.plist"
printf 'synthetic fixture; never execute\n' > "$APP/Contents/MacOS/GazePasswords"
printf 'synthetic fixture; never execute\n' > "$APP/Contents/Helpers/GazeBrowserBridge"
chmod +x "$APP/Contents/MacOS/GazePasswords" "$APP/Contents/Helpers/GazeBrowserBridge"
printf 'synthetic fixture profile; never embed\n' > "$APP/Contents/embedded.provisionprofile"
mkdir -p "$SCRATCH/Gaze.app"
for resource in background.js login-form.js popup.js popup.html popup.css icon128.png; do
  printf 'synthetic resource' > "$APP/Contents/Resources/BrowserExtension/$resource"
done
printf 'synthetic icon' > "$APP/Contents/Resources/PasswordsIcon.icns"

python3 - "$PROJECT/BrowserExtension/public-key.txt" "$SCRATCH" <<'PY'
import base64, hashlib, json, plistlib, sys
from datetime import datetime, timedelta, timezone
key = open(sys.argv[1]).read().strip()
scratch = sys.argv[2]
digest = hashlib.sha256(base64.b64decode(key)).digest()[:16]
extension_id = "".join(chr(97 + n) for b in digest for n in (b >> 4, b & 15))
json.dump({"extensionID": extension_id}, open(scratch + "/BrowserIdentity.json", "w"))
manifest = {"manifest_version": 3, "name": "Gaze Passwords", "version": "0.2.0",
            "permissions": ["activeTab", "scripting", "nativeMessaging"], "key": key,
            "background": {"service_worker": "background.js", "type": "module"},
            "action": {"default_popup": "popup.html"}}
json.dump(manifest, open(scratch + "/manifest.json", "w"))
good_leaf = b"fixture-signing-leaf"
bad_leaf = b"fixture-unknown-leaf"
open(scratch + "/leaf-good.der", "wb").write(good_leaf)
open(scratch + "/leaf-bad.der", "wb").write(bad_leaf)
import os
os.makedirs(scratch + "/profiles", exist_ok=True)
def save(name, body):
    plistlib.dump(body, open(scratch + "/profiles/" + name + ".plist", "wb"))
base_expiry = datetime.now(timezone.utc) + timedelta(days=30)
def base():
    return {"Name": "Fixture", "ExpirationDate": base_expiry, "Platform": ["OSX"],
            "TeamIdentifier": ["CAAVJCSL92"],
            "Entitlements": {"com.apple.application-identifier": "CAAVJCSL92.com.gazeunlock.Passwords",
                             "keychain-access-groups": ["CAAVJCSL92.*"],
                             "com.apple.developer.team-identifier": "CAAVJCSL92"},
            "DeveloperCertificates": [good_leaf]}
good = base(); save("good", good)
good = base(); good["ProvisionsAllDevices"] = True; save("distribution", good)
bad = base(); bad["ExpirationDate"] = datetime.now(timezone.utc) - timedelta(days=1); save("expired", bad)
bad = base(); bad["TeamIdentifier"] = ["WRONGTEAM1"]; save("wrong-team", bad)
bad = base(); bad["Entitlements"] = dict(bad["Entitlements"], **{"com.apple.application-identifier": "CAAVJCSL92.*"}); save("wildcard-appid", bad)
bad = base(); bad["Entitlements"] = dict(bad["Entitlements"], **{"keychain-access-groups": ["CAAVJCSL92.other"]}); save("missing-keychain", bad)
bad = base(); bad["Platform"] = ["iOS"]; save("bad-platform", bad)
bad = base(); bad["DeveloperCertificates"] = [bad_leaf]; save("wrong-cert", bad)
def entitlements(name, **over):
    body = {"com.apple.application-identifier": "CAAVJCSL92.com.gazeunlock.Passwords",
            "com.apple.developer.team-identifier": "CAAVJCSL92",
            "keychain-access-groups": ["CAAVJCSL92.com.gazeunlock.Passwords"]}
    body.update(over)
    plistlib.dump(body, open(scratch + "/entitlements-" + name + ".plist", "wb"))
entitlements("good")
entitlements("extra-group", **{"keychain-access-groups": ["CAAVJCSL92.com.gazeunlock.Passwords", "CAAVJCSL92.other"]})
entitlements("bad-appid", **{"com.apple.application-identifier": "CAAVJCSL92.other"})
entitlements("bad-group", **{"keychain-access-groups": ["CAAVJCSL92.other"]})
entitlements("bad-team", **{"com.apple.developer.team-identifier": "WRONGTEAM1"})
entitlements("unsafe", **{"com.apple.security.get-task-allow": True})
PY
cp "$SCRATCH/manifest.json" "$APP/Contents/Resources/BrowserExtension/manifest.json"
cp "$SCRATCH/BrowserIdentity.json" "$APP/Contents/Resources/BrowserIdentity.json"

cat > "$BIN/codesign" <<'MOCK'
#!/bin/bash
case "$1" in
	--verify) test "${GAZE_TEST_FAILURE:-}" != signature ;;
	-dv)
		shift
		target=""
		for a in "$@"; do case "$a" in -*) ;; *) target="$a" ;; esac; done
		case "$target" in
			*Helpers/GazeBrowserBridge*)
                if [ "${GAZE_TEST_FAILURE:-}" = helper-id ]; then echo 'Identifier=wrong.helper' >&2; else echo 'Identifier=com.gazeunlock.Passwords.BrowserBridge' >&2; fi
                [ "${GAZE_TEST_TIMESTAMP:-0}" = 1 ] && [ "${GAZE_TEST_FAILURE:-}" != helper-timestamp ] && echo 'Timestamp=2026-09-15T00:00:00Z' >&2
				if [ "${GAZE_TEST_FAILURE:-}" = helper-adhoc ]; then
					echo 'Signature=adhoc' >&2
				elif [ "${GAZE_TEST_AUTH:-dev}" = did ] && [ "${GAZE_TEST_FAILURE:-}" != helper-dev ]; then
                    echo 'Authority=Developer ID Application: Fixture (CAAVJCSL92)' >&2
                else
					echo 'Authority=Apple Development: Fixture (CAAVJCSL92)' >&2
				fi
				if [ "${GAZE_TEST_FAILURE:-}" = helper-team ]; then
					echo 'TeamIdentifier=WRONGTEAM1' >&2
				else
					echo 'TeamIdentifier=CAAVJCSL92' >&2
				fi
				[ "${GAZE_TEST_FAILURE:-}" = helper-runtime ] || echo 'CodeDirectory v=20500 size=0 flags=0x10000(runtime) hashes=0+0 location=embedded' >&2
				exit 0 ;;
			*/Gaze.app) echo "TeamIdentifier=${GAZE_TEST_GAZE_TEAM:-CAAVJCSL92}" >&2; exit 0 ;;
			*)
                if [ "${GAZE_TEST_FAILURE:-}" = app-id ]; then echo 'Identifier=wrong.app' >&2; else echo 'Identifier=com.gazeunlock.Passwords' >&2; fi
				case "${GAZE_TEST_AUTH:-dev}" in
					did) echo 'Authority=Developer ID Application: Fixture (CAAVJCSL92)' >&2 ;;
					adhoc) echo 'Signature=adhoc' >&2 ;;
					*) echo 'Authority=Apple Development: Fixture (CAAVJCSL92)' >&2 ;;
				esac
				if [ "${GAZE_TEST_FAILURE:-}" = team ]; then
					echo 'TeamIdentifier=WRONG' >&2
				else
					echo 'TeamIdentifier=CAAVJCSL92' >&2
				fi
				[ "${GAZE_TEST_TIMESTAMP:-0}" = 1 ] && echo 'Timestamp=2026-09-15T00:00:00Z' >&2
				[ "${GAZE_TEST_FAILURE:-}" = runtime ] || echo 'CodeDirectory v=20500 size=0 flags=0x10000(runtime) hashes=0+0 location=embedded' >&2
				exit 0 ;;
		esac ;;
	-d)
		prev=""
		for a in "$@"; do
			case "$a" in
				--extract-certificates=*) cp "$GAZE_TEST_LEAF" "${a#--extract-certificates=}0"; cp "$GAZE_TEST_CHAIN" "${a#--extract-certificates=}1"; exit 0 ;;
			esac
			if [ "$prev" = "--extract-certificates" ]; then cp "$GAZE_TEST_LEAF" "${a}0"; exit 0; fi
			prev="$a"
		done
        case "${!#}" in
          *Helpers/GazeBrowserBridge)
            if [ "${GAZE_TEST_FAILURE:-}" = helper-keychain ]; then cat "$GAZE_TEST_ENTITLEMENTS";
            elif [ "${GAZE_TEST_FAILURE:-}" = helper-unsafe ]; then printf '%s' '<?xml version="1.0"?><plist version="1.0"><dict><key>com.apple.security.cs.allow-jit</key><true/></dict></plist>'; fi ;;
          *) cat "$GAZE_TEST_ENTITLEMENTS" ;;
        esac ;;
	*) exit 90 ;;
esac
MOCK
cat > "$BIN/security" <<'MOCK'
#!/bin/bash
test "$1" = cms && test "$2" = -D || exit 90
test "${GAZE_TEST_FAILURE:-}" != profile-decode || exit 1
out=""
prev=""
for a in "$@"; do
	[ "$prev" = "-o" ] && out="$a"
	prev="$a"
done
cp "$GAZE_TEST_PROFILE" "$out"
MOCK
cat > "$BIN/xcrun" <<'MOCK'
#!/bin/bash
test "$1" = stapler && test "$2" = validate && test "${GAZE_TEST_FAILURE:-}" != stapler
MOCK
cat > "$BIN/spctl" <<'MOCK'
#!/bin/bash
test "$1" = --assess && test "${GAZE_TEST_FAILURE:-}" != gatekeeper
MOCK
chmod +x "$BIN/"*
export PATH="$BIN:$PATH"
export GAZE_APP="$SCRATCH/Gaze.app"

reset_env() {
  unset GAZE_TEST_FAILURE GAZE_TEST_AUTH GAZE_TEST_TIMESTAMP GAZE_TEST_GAZE_TEAM
  export GAZE_TEST_PROFILE="$SCRATCH/profiles/good.plist"
  export GAZE_TEST_ENTITLEMENTS="$SCRATCH/entitlements-good.plist"
  export GAZE_TEST_LEAF="$SCRATCH/leaf-good.der"
  export GAZE_TEST_CHAIN="$SCRATCH/leaf-good.der"
  export GAZE_APP="$SCRATCH/Gaze.app"
}
COUNT=0
check() {
  local expected="$1" mode="$2" marker="$3"
  local actual=0
  bash "$PROJECT/Release/verify.sh" "$mode" "$APP" > "$SCRATCH/output" 2>&1 || actual=$?
  if [ "$expected" = pass ]; then
    test "$actual" = 0 || { cat "$SCRATCH/output"; exit 1; }
  else
    test "$actual" != 0 || { echo "FAIL: unsafe fixture passed ($mode $marker)" >&2; exit 1; }
  fi
  grep -Fq "$marker" "$SCRATCH/output" || { cat "$SCRATCH/output"; exit 1; }
  COUNT=$((COUNT + 1))
}

reset_env
check pass --local 'artifact validation, NOT proof'
for failure in signature team runtime helper-team helper-adhoc helper-runtime profile-decode app-id helper-id helper-keychain; do
  reset_env
  export GAZE_TEST_FAILURE="$failure"
  check fail --local 'FAIL:'
done
reset_env
export GAZE_TEST_AUTH=adhoc
check fail --local 'No signing authority'
reset_env
export GAZE_TEST_GAZE_TEAM=WRONGTEAM1
check fail --local 'does not match Passwords team'
reset_env
export GAZE_APP="$SCRATCH/nowhere.app"
check pass --local 'same-team cross-check skipped'
for profile in expired wrong-team wildcard-appid missing-keychain bad-platform; do
  reset_env
  export GAZE_TEST_PROFILE="$SCRATCH/profiles/$profile.plist"
  check fail --local 'FAIL:'
done
reset_env
export GAZE_TEST_PROFILE="$SCRATCH/profiles/expired.plist"
check fail --local 'profile is expired'
reset_env
export GAZE_TEST_PROFILE="$SCRATCH/profiles/wildcard-appid.plist"
check fail --local 'wildcard profiles refused'
reset_env
export GAZE_TEST_PROFILE="$SCRATCH/profiles/wrong-cert.plist"
check fail --local 'does not list the signing certificate'
reset_env
export GAZE_TEST_LEAF="$SCRATCH/leaf-bad.der"
check fail --local 'does not list the signing certificate'
for entitlements in bad-appid bad-group bad-team extra-group; do
  reset_env
  export GAZE_TEST_ENTITLEMENTS="$SCRATCH/entitlements-$entitlements.plist"
  check fail --local 'entitlement mismatch'
done
reset_env
mv "$APP/Contents/embedded.provisionprofile" "$SCRATCH/embedded.provisionprofile"
check fail --local 'Embedded provisioning profile missing'
mv "$SCRATCH/embedded.provisionprofile" "$APP/Contents/embedded.provisionprofile"
reset_env
python3 - "$APP/Contents/Resources/BrowserIdentity.json" <<'PY'
import json, sys
identity = json.load(open(sys.argv[1]))
identity["extensionID"] = "a" * 32
json.dump(identity, open(sys.argv[1], "w"))
PY
check fail --local 'Extension identity mismatch'
cp "$SCRATCH/BrowserIdentity.json" "$APP/Contents/Resources/BrowserIdentity.json"
reset_env
python3 - "$APP/Contents/Resources/BrowserExtension/manifest.json" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1]))
del manifest["key"]
json.dump(manifest, open(sys.argv[1], "w"))
PY
check fail --local 'Extension manifest key missing'
cp "$SCRATCH/manifest.json" "$APP/Contents/Resources/BrowserExtension/manifest.json"
reset_env
python3 - "$APP/Contents/Resources/BrowserExtension/manifest.json" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1]))
manifest["permissions"] = ["activeTab", "scripting", "nativeMessaging", "webRequest"]
json.dump(manifest, open(sys.argv[1], "w"))
PY
check fail --local 'Extension permissions differ'
cp "$SCRATCH/manifest.json" "$APP/Contents/Resources/BrowserExtension/manifest.json"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier example.invalid.fixture' "$APP/Contents/Info.plist"
reset_env
check fail --local 'Unexpected bundle identifier'
cp "$PROJECT/Live/Info.plist" "$APP/Contents/Info.plist"
reset_env
chmod -x "$APP/Contents/MacOS/GazePasswords"
check fail --local 'executable missing'
chmod +x "$APP/Contents/MacOS/GazePasswords"
reset_env
mv "$APP/Contents/Helpers/GazeBrowserBridge" "$SCRATCH/GazeBrowserBridge"
check fail --local 'Native helper'
mv "$SCRATCH/GazeBrowserBridge" "$APP/Contents/Helpers/GazeBrowserBridge"
reset_env
mv "$APP/Contents/Resources/BrowserExtension/manifest.json" "$SCRATCH/missing-manifest.json"
check fail --local 'extension manifest missing'
mv "$SCRATCH/missing-manifest.json" "$APP/Contents/Resources/BrowserExtension/manifest.json"
reset_env
mv "$APP/Contents/Info.plist" "$SCRATCH/Info.plist"
check fail --local 'Bundle Info.plist missing'
mv "$SCRATCH/Info.plist" "$APP/Contents/Info.plist"
reset_env
check pass --local 'Executable SHA-256:'

reset_env
check fail --distribution 'requires a Developer ID Application signature'
reset_env
export GAZE_TEST_AUTH=did
check fail --distribution 'Secure timestamp missing'
reset_env
export GAZE_TEST_AUTH=did GAZE_TEST_TIMESTAMP=1 GAZE_TEST_PROFILE="$SCRATCH/profiles/distribution.plist"
check pass --distribution 'Authority: Developer ID Application'
reset_env
export GAZE_TEST_AUTH=did GAZE_TEST_TIMESTAMP=1 GAZE_TEST_PROFILE="$SCRATCH/profiles/distribution.plist"
mv "$APP/Contents/embedded.provisionprofile" "$SCRATCH/embedded.provisionprofile"
check fail --distribution 'Embedded provisioning profile missing'
mv "$SCRATCH/embedded.provisionprofile" "$APP/Contents/embedded.provisionprofile"
reset_env
export GAZE_TEST_AUTH=did GAZE_TEST_TIMESTAMP=1 GAZE_TEST_PROFILE="$SCRATCH/profiles/distribution.plist"
export GAZE_TEST_ENTITLEMENTS="$SCRATCH/entitlements-unsafe.plist"
check fail --distribution 'Unsafe distribution entitlement'
reset_env
export GAZE_TEST_AUTH=did GAZE_TEST_TIMESTAMP=1 GAZE_TEST_PROFILE="$SCRATCH/profiles/distribution.plist" GAZE_TEST_FAILURE=stapler
check fail --distribution 'Stapled notarization'
reset_env
export GAZE_TEST_AUTH=did GAZE_TEST_TIMESTAMP=1 GAZE_TEST_PROFILE="$SCRATCH/profiles/distribution.plist" GAZE_TEST_FAILURE=gatekeeper
check fail --distribution 'Gatekeeper did not accept'

reset_env
export GAZE_TEST_AUTH=did GAZE_TEST_TIMESTAMP=1
check fail --distribution 'requires a distribution provisioning profile'
for failure in helper-dev helper-timestamp helper-unsafe; do
  reset_env
  export GAZE_TEST_AUTH=did GAZE_TEST_TIMESTAMP=1 GAZE_TEST_PROFILE="$SCRATCH/profiles/distribution.plist" GAZE_TEST_FAILURE="$failure"
  check fail --distribution 'FAIL:'
done
reset_env
mv "$APP/Contents/Resources/BrowserExtension/popup.js" "$SCRATCH/popup.js"
check fail --local 'extension resource missing'
mv "$SCRATCH/popup.js" "$APP/Contents/Resources/BrowserExtension/popup.js"
for capability in host_permissions optional_host_permissions optional_permissions externally_connectable content_scripts web_accessible_resources; do
  reset_env
  python3 - "$APP/Contents/Resources/BrowserExtension/manifest.json" "$capability" <<'PYCAP'
import json, sys
path, key = sys.argv[1:]
values = json.load(open(path))
values[key] = ["<all_urls>"]
json.dump(values, open(path, 'w'))
PYCAP
  check fail --local 'Extension permissions differ'
  cp "$SCRATCH/manifest.json" "$APP/Contents/Resources/BrowserExtension/manifest.json"
done

node - "$ROOT" <<'NODE'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const root = process.argv[2];
const build = fs.readFileSync(`${root}/Tools/GazePasswords/script/build-live.sh`, 'utf8');
assert(build.includes('gaze_signing_identity 0'), 'stable identity selection');
assert(build.includes('verify-profile.swift" "$STAGING/profile.plist" "$TEAM" "$IDENTITY"'), 'certificate-matched profile check');
assert(build.includes('staged extension key does not match'), 'extension identity consistency gate');
assert(build.includes("flags=.*runtime"), 'hardened runtime assertions');
assert(build.includes('rotate_away'), 'previous-artifact rotation');
assert(build.includes('does not match the Passwords app'), 'signed entitlement assertions');
const profile = fs.readFileSync(`${root}/Tools/GazePasswords/script/verify-profile.swift`, 'utf8');
assert(profile.includes('Insecure.SHA1'), 'certificate matching');
assert(profile.includes('DeveloperCertificates'), 'certificate list check');
assert(profile.includes('ExpirationDate'), 'expiration check');
assert(profile.includes('"OSX"'), 'platform check');
assert(profile.includes('Wildcard profiles are refused'), 'exact app identifier');
const verify = fs.readFileSync(`${root}/Tools/GazePasswords/Release/verify.sh`, 'utf8');
assert(verify.includes('--distribution'), 'local/distribution modes');
assert(verify.includes('Developer ID Application'), 'distribution authority gate');
assert(verify.includes('does not list the signing certificate'), 'certificate gate');
assert(verify.includes('NOT proof'), 'no-launch-proof disclaimer');
console.log('PASS: packaging wiring checks; source assertions only, no signing or network.');
NODE
COUNT=$((COUNT + 1))
echo "PASS: $COUNT packaging verifier checks; synthetic bundle, mocked signing/notarization tools, no network or app launch."
