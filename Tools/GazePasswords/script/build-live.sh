#!/bin/bash
set -euo pipefail
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$PROJECT/../.." && pwd)"
source "$ROOT/toolchain.sh"
source "$ROOT/Tools/Release/Signing.sh"
require_toolchain
SDK="$(oldest_usable_sdk | awk '{print $1}')"
OUTPUT="${GAZE_PASSWORDS_LIVE_OUTPUT:-$ROOT/build/browser-integration}"
MODE="${1:---build}"
case "$MODE" in --build|--ui-review) ;; *) echo 'Usage: build-live.sh [--build|--ui-review]' >&2; exit 2 ;; esac
if [ "$MODE" = '--build' ] && [ ! -f "${GAZE_PASSWORDS_PROVISIONING_PROFILE:-}" ]; then
  echo 'A matching macOS provisioning profile is required for the protected vault build.' >&2
  echo 'Set GAZE_PASSWORDS_PROVISIONING_PROFILE to its path. Use --ui-review only for a storage-disabled visual build.' >&2
  exit 1
fi
BUNDLE_ID='com.gazeunlock.Passwords'
NAME='Gaze Passwords'
if [ "$MODE" = '--ui-review' ]; then
  BUNDLE_ID='com.gazeunlock.Passwords.UIReview'
  NAME='Gaze Passwords UI Review'
fi
fail() { echo "build-live: $*" >&2; exit 1; }
# Never nest a previous artifact inside another: mv(1) moves the source *into*
# an existing destination directory, so a colliding rotation name would hide
# the new build instead of preserving the old one.
rotate_away() {
  local path="$1" dest stamp i
  [ -e "$path" ] || return 0
  stamp="$(date +%Y%m%d-%H%M%S)"
  dest="$path.previous.$stamp"
  i=0
  while [ -e "$dest" ]; do
    i=$((i + 1))
    dest="$path.previous.$stamp-$i"
  done
  mv "$path" "$dest"
  echo "Preserved previous artifact: $dest"
}
mkdir -p "$OUTPUT"
STAGING="$(mktemp -d "$OUTPUT/.passwords-build.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Gaze Passwords.app"
mkdir -p "$APP/Contents/"{MacOS,Helpers,Resources}
COMMON=("$ROOT/Sources/Browser/BrowserProtocol.swift" "$ROOT/Sources/Browser/BrowserSocket.swift"
  "$ROOT/Sources/Browser/BrowserPeerTrust.swift" "$ROOT/Sources/Browser/BrowserAppLocator.swift")
FLAGS=(-parse-as-library -warnings-as-errors -sdk "$SDK" -target "$(host_target)")
if [ "$MODE" = '--ui-review' ]; then FLAGS+=(-D PASSWORDS_UI_REVIEW); fi
xcrun swiftc "${FLAGS[@]}" "${COMMON[@]}" "$PROJECT/Live/"*.swift "$ROOT/Sources/App/Theme.swift" \
  "$PROJECT/Views/PasswordsAppearance.swift" "$PROJECT/Views/PasswordsCompanion.swift" \
  "$PROJECT/Views/PasswordsCompanionRenderer.swift" "$PROJECT/Views/PasswordsExportOverlay.swift" \
  "$PROJECT/Models/AppleExportWalkthrough.swift" "$ROOT/Sources/Companion/"*.swift \
  "$ROOT/Sources/LockScreen/GazeFaceMark.swift" "$ROOT/Sources/LockScreen/NotchCapsule.swift" \
  "$ROOT/Sources/LockScreen/NotchPanelShape.swift" "$ROOT/Tools/GazePreview/PreviewPreferences.swift" \
  "$ROOT/Sources/Security/AutofillSecurity.swift" -o "$APP/Contents/MacOS/GazePasswords"
xcrun swiftc "${FLAGS[@]}" "${COMMON[@]}" "$PROJECT/NativeHost/"*.swift \
  "$ROOT/Sources/Security/AutofillSecurity.swift" -o "$APP/Contents/Helpers/GazeBrowserBridge"
cp "$PROJECT/Live/Info.plist" "$APP/Contents/Info.plist"
if [ "$MODE" = '--ui-review' ]; then
  plutil -replace CFBundleIdentifier -string com.gazeunlock.Passwords.UIReview "$APP/Contents/Info.plist"
  plutil -replace CFBundleName -string 'Gaze Passwords UI Review' "$APP/Contents/Info.plist"
  plutil -replace CFBundleDisplayName -string 'Gaze Passwords UI Review' "$APP/Contents/Info.plist"
fi
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" = "$BUNDLE_ID" \
  || fail "Staged Info.plist identifier does not match $BUNDLE_ID."
mkdir -p "$STAGING/PasswordsIcon.icon"
cp "$PROJECT/Icon/PasswordsIcon.icon/icon.json" "$STAGING/PasswordsIcon.icon/"
xcrun swift -sdk "$SDK" "$PROJECT/Icon/render.swift" "$STAGING/PasswordsIcon.icon/Assets"
xcrun actool "$STAGING/PasswordsIcon.icon" --app-icon PasswordsIcon --include-all-app-icons \
  --compile "$APP/Contents/Resources" --platform macosx --target-device mac --minimum-deployment-target 26.0 \
  --development-region en --enable-on-demand-resources NO \
  --output-partial-info-plist "$STAGING/icon.plist" >/dev/null
test -f "$APP/Contents/Resources/PasswordsIcon.icns" || fail 'Icon compilation produced no PasswordsIcon.icns.'
node "$PROJECT/script/prepare-extension.mjs" "$PROJECT" "$STAGING/browser-extension" "$APP/Contents/Resources"
sips -s format png -z 128 128 "$APP/Contents/Resources/PasswordsIcon.icns" --out "$STAGING/browser-extension/icon128.png" >/dev/null
cp -R "$STAGING/browser-extension" "$APP/Contents/Resources/BrowserExtension"
# The staged extension key and the recorded identity must agree before signing:
# a stale stage or rotated public key would otherwise ship a helper that
# rejects the bundled extension's origin at runtime.
EXTENSION_ID="$(python3 - "$STAGING/browser-extension/manifest.json" "$APP/Contents/Resources/BrowserIdentity.json" <<'PY'
import base64, hashlib, json, sys
manifest = json.load(open(sys.argv[1]))
identity = json.load(open(sys.argv[2]))
digest = hashlib.sha256(base64.b64decode(manifest["key"])).digest()[:16]
derived = "".join(chr(97 + n) for b in digest for n in (b >> 4, b & 15))
if identity.get("extensionID") != derived:
    sys.stderr.write("build-live: staged extension key does not match Resources/BrowserIdentity.json.\n")
    sys.exit(1)
print(derived)
PY
)" || fail 'Extension identity mismatch.'
echo "Extension identity: $EXTENSION_ID"
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null)" \
  || fail 'Unable to inspect valid signing identities.'
test -f "$ROOT/build/Gaze.app/Contents/MacOS/Gaze" \
  || fail "The existing Gaze app is missing at $ROOT/build/Gaze.app; build it first so the Passwords team can be matched to it."
codesign --verify --deep --strict -R='anchor apple generic and identifier "com.gazeunlock.Gaze"' "$ROOT/build/Gaze.app" 2>/dev/null \
  || fail 'The existing Gaze app signature is invalid; refusing to derive a signing team from it.'
TEAM="$(codesign -dv "$ROOT/build/Gaze.app" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
[[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]] || fail 'The existing Gaze signing team could not be verified.'
codesign -d --extract-certificates="$STAGING/gaze-certificate" "$ROOT/build/Gaze.app" >/dev/null 2>&1 \
  || fail 'The existing Gaze signing certificate could not be read.'
GAZE_CERTIFICATE="$(shasum -a 1 "$STAGING/gaze-certificate0" | awk '{print toupper($1)}')"
IDENTITY="$(gaze_signing_identity 0 "${GAZE_SIGNING_IDENTITY:-$GAZE_CERTIFICATE}" "$IDENTITIES")" || exit 1
cat > "$STAGING/entitlements.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>com.apple.application-identifier</key><string>$TEAM.com.gazeunlock.Passwords</string>
<key>com.apple.developer.team-identifier</key><string>$TEAM</string>
<key>keychain-access-groups</key><array><string>$TEAM.com.gazeunlock.Passwords</string></array>
</dict></plist>
EOF
codesign --force --options runtime --sign "$IDENTITY" --identifier com.gazeunlock.Passwords.BrowserBridge "$APP/Contents/Helpers/GazeBrowserBridge"
if [ "$MODE" = '--ui-review' ]; then
  codesign --force --options runtime --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
else
  security cms -D -i "$GAZE_PASSWORDS_PROVISIONING_PROFILE" -o "$STAGING/profile.plist"
  xcrun swift "$PROJECT/script/verify-profile.swift" "$STAGING/profile.plist" "$TEAM" "$IDENTITY"
  cp "$GAZE_PASSWORDS_PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
  codesign --force --options runtime --sign "$IDENTITY" --identifier "$BUNDLE_ID" --entitlements "$STAGING/entitlements.plist" "$APP"
fi
codesign --verify --deep --strict "$APP" || fail 'Staged signature verification failed; no output was replaced.'
APP_SIGNATURE="$(codesign -dv --verbose=4 "$APP" 2>&1)"
printf '%s\n' "$APP_SIGNATURE" | grep -q '^Authority=' || fail 'The app signature has no authority (ad-hoc signatures are not supported).'
NEW_TEAM="$(printf '%s\n' "$APP_SIGNATURE" | sed -n 's/^TeamIdentifier=//p')"
[ "$NEW_TEAM" = "$TEAM" ] || fail "Passwords team $NEW_TEAM does not match Gaze team $TEAM."
printf '%s\n' "$APP_SIGNATURE" | grep -q 'flags=.*runtime' || fail 'Hardened Runtime is missing from the app signature.'
HELPER_SIGNATURE="$(codesign -dv --verbose=4 "$APP/Contents/Helpers/GazeBrowserBridge" 2>&1)"
printf '%s\n' "$HELPER_SIGNATURE" | grep -q '^Authority=' || fail 'The nested helper has no signing authority.'
[ "$(printf '%s\n' "$HELPER_SIGNATURE" | sed -n 's/^TeamIdentifier=//p')" = "$TEAM" ] \
  || fail 'The nested helper team does not match the app team.'
printf '%s\n' "$HELPER_SIGNATURE" | grep -q 'flags=.*runtime' || fail 'Hardened Runtime is missing from the nested helper signature.'
codesign -d --entitlements :- "$APP" > "$STAGING/signed-entitlements.plist" 2>/dev/null \
  || fail 'Signed app entitlements are unavailable.'
if [ "$MODE" = '--build' ]; then
  test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.application-identifier' "$STAGING/signed-entitlements.plist")" = "$TEAM.com.gazeunlock.Passwords" \
    || fail 'Signed application-identifier does not match the Passwords app.'
  test "$(/usr/libexec/PlistBuddy -c 'Print :keychain-access-groups:0' "$STAGING/signed-entitlements.plist")" = "$TEAM.com.gazeunlock.Passwords" \
    || fail 'Signed Keychain group does not match the Passwords app.'
fi
if [ "$MODE" = '--build' ]; then
  GAZE_APP="$ROOT/build/Gaze.app" bash "$PROJECT/Release/verify.sh" --local "$APP" \
    || fail 'Protected artifact verification failed; previous output retained.'
fi
rotate_away "$OUTPUT/$NAME.app"
mv "$APP" "$OUTPUT/$NAME.app"
rotate_away "$OUTPUT/browser-extension"
mv "$STAGING/browser-extension" "$OUTPUT/browser-extension"
echo "Built $OUTPUT/$NAME.app"
echo 'Nothing was installed in a browser or launched.'
