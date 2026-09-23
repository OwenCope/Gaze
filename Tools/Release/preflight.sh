#!/bin/bash
# Read-only release preflight for Gaze (not Gaze Passwords).
#
# Reports whether this machine can currently produce a distributable Gaze
# release: required tools, source bundle metadata, model sources, a
# Developer ID Application signing identity, and notarization tooling.
#
# It never builds, signs, notarizes, uploads, publishes, touches private
# keys or the network, launches the app, or changes any setting. A local
# Apple Development build is reported as local-only information, never
# failed as a release candidate. Test hooks: GAZE_PREFLIGHT_IDENTITIES
# Use --build-tools-only for a clearly labelled tool check without clearance.
# (when set, even empty, replaces `security find-identity` output) and
# GAZE_PREFLIGHT_RESOURCES (replaces Resources/ as the metadata source).
set -uo pipefail
TOOLS_ONLY=0
case "${1:-}" in
	"") ;;
	--build-tools-only) TOOLS_ONLY=1 ;;
	*) echo 'Usage: preflight.sh [--build-tools-only]' >&2; exit 2 ;;
esac
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RESOURCES="${GAZE_PREFLIGHT_RESOURCES:-$ROOT/Resources}"
BUNDLE_ID=com.gazeunlock.Gaze
MISSING=0
ok() { echo "ok: $*"; }
missing() { echo "missing: $*" >&2; MISSING=$((MISSING + 1)); }
note() { echo "note: $*"; }

for tool in codesign security xcrun spctl python3; do
	command -v "$tool" >/dev/null 2>&1 && ok "tool $tool" || missing "tool $tool is not on PATH (install the Xcode command line tools)"
done
xcrun --find notarytool >/dev/null 2>&1 && ok "tool notarytool via xcrun" || missing "notarytool is not available via xcrun (notarization cannot run here)"
xcrun --find stapler >/dev/null 2>&1 && ok "tool stapler via xcrun" || missing "stapler is not available via xcrun"

PLIST="$RESOURCES/Info.plist"
if [ -f "$PLIST" ]; then
	test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST" 2>/dev/null)" = "$BUNDLE_ID" \
		&& ok "source bundle identifier $BUNDLE_ID" \
		|| missing "Resources/Info.plist CFBundleIdentifier is not $BUNDLE_ID"
	for key in CFBundleExecutable CFBundleName CFBundleShortVersionString CFBundleVersion LSMinimumSystemVersion NSCameraUsageDescription; do
		/usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" >/dev/null 2>&1 \
			&& ok "source Info.plist key $key" \
			|| missing "Resources/Info.plist key $key is absent"
	done
else
	missing "Resources/Info.plist is absent"
fi

ENTITLEMENTS="$RESOURCES/Gaze.entitlements"
if [ -f "$ENTITLEMENTS" ]; then
	test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.device.camera' "$ENTITLEMENTS" 2>/dev/null)" = true \
		&& ok "source camera entitlement" \
		|| missing "Resources/Gaze.entitlements does not enable com.apple.security.device.camera"
else
	missing "Resources/Gaze.entitlements is absent"
fi

for model in FaceEmbedding Spoof; do
	if [ -d "$RESOURCES/$model.mlmodelc" ] || [ -d "$RESOURCES/$model.mlpackage" ] || [ -f "$RESOURCES/$model.mlmodel" ]; then
		ok "model source $model"
	else
		missing "no $model source (Resources/$model.mlmodelc, .mlpackage or .mlmodel); the release bundle requires $model.mlmodelc"
	fi
done

if [ -n "${GAZE_PREFLIGHT_IDENTITIES+x}" ]; then
	IDENTITIES="$GAZE_PREFLIGHT_IDENTITIES"
else
	IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
fi
if printf '%s\n' "$IDENTITIES" | grep -q 'Developer ID Application: '; then
	ok "Developer ID Application signing identity: $(printf '%s\n' "$IDENTITIES" | sed -n 's/.*\(Developer ID Application: [^"]*\).*/\1/p' | head -1)"
elif printf '%s\n' "$IDENTITIES" | grep -q 'Apple Development: '; then
	missing "no Developer ID Application identity (this machine can only make local Apple Development builds; provision a Developer ID Application certificate before DIST=1)"
else
	missing "no valid signing identity at all (provision an Apple Development identity for local builds, Developer ID Application for release)"
fi

for candidate in "$ROOT/build/release/Gaze.app" "$ROOT/build/Gaze.app"; do
	if [ -d "$candidate" ]; then
		AUTHORITY="$(codesign -dv --verbose=4 "$candidate" 2>&1 | sed -n 's/^Authority=\([^:]*\): .*/\1/p' | head -1)"
		note "local build present at ${candidate#$ROOT/} (signed: ${AUTHORITY:-ad-hoc/none}; local signing state is informational, not a release verdict)"
	fi
done

if [ "$TOOLS_ONLY" = 0 ]; then
	python3 "$ROOT/Tools/Release/ModelClearance/validate.py" || missing "model/asset clearance evidence is incomplete (see Tools/Release/ModelClearance/OWNER-ANSWERS.md)"
else
	note 'Build-tools-only check: model/asset clearance is NOT checked; this is not permission to distribute.'
fi
if [ "$MISSING" = 0 ]; then
	echo "PREFLIGHT PASS: checked prerequisites present (build-tools-only=$TOOLS_ONLY); a signed/notarized artifact and live acceptance are still required."
else
	echo "PREFLIGHT FAIL: $MISSING missing distribution prerequisite(s); local Apple Development builds are unaffected" >&2
	echo "Next steps for the owner: provision a Developer ID Application certificate, run DIST=1 GAZE_SIGNING_IDENTITY=\"Developer ID Application: ...\" bash build.sh, notarize and staple the release bundle, then validate it with bash Tools/Release/verify.sh build/release/Gaze.app. Do not upload until model redistribution rights are recorded (Tools/Release/READINESS.md)." >&2
	exit 1
fi
