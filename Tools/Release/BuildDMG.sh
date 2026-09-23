#!/bin/bash
# Stages a versioned Gaze DMG from an app bundle built by build.sh.
#
#   ./build.sh                              # or DIST=1 for release
#   DIST=1 ./Tools/Release/BuildDMG.sh      # writes build/installers/Gaze-<version>.dmg
#
# Never builds, signs the app, or changes an install. The app must already
# exist at build/Gaze.app (local) or build/release/Gaze.app (DIST=1).
# DMG staging is blocked when Tools/Release/ModelClearance/validate.py
# refuses — in particular the bundled FaceEmbedding and Spoof models ship
# only on a PASS. For DIST=1 the staged app must carry a Developer ID
# Application signature with a secure timestamp, and the finished DMG is
# signed with the same identity plus --timestamp.
#
# PAM posture: the authorization plugin stays disabled. The DMG carries no
# installer and runs nothing; Plugin/install.sh makes no changes by design.
# Install steps are explicit and printed in the staged README.txt.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=Signing.sh
. "$ROOT/Tools/Release/Signing.sh"

BUNDLE_ID=com.gazeunlock.Gaze
OUT_DIR="${GAZE_DMG_OUTPUT_DIR:-$ROOT/build/installers}"

if [ "${DIST:-}" = "1" ]; then
	APP="${GAZE_DMG_APP:-$ROOT/build/release/Gaze.app}"
else
	APP="${GAZE_DMG_APP:-$ROOT/build/Gaze.app}"
fi

[ -d "$APP" ] || { echo "Missing app bundle (run build.sh first): $APP" >&2; exit 1; }
[ "$(basename "$APP")" = "Gaze.app" ] || { echo "The input app must be named Gaze.app: $APP" >&2; exit 1; }

echo "→ Model clearance gate"
python3 "$ROOT/Tools/Release/ModelClearance/validate.py" || {
	echo "Model clearance refused; DMG staging blocked, no image written." >&2; exit 1;
}
for model in FaceEmbedding Spoof; do
	[ -d "$APP/Contents/Resources/$model.mlmodelc" ] || {
		echo "Bundled $model.mlmodelc missing from $APP; DMG staging blocked." >&2; exit 1;
	}
done
echo "  ✓ FaceEmbedding + Spoof bundled and cleared"

echo "→ Verifying staged app"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null)" = "$BUNDLE_ID" ] || {
	echo "Unexpected bundle identifier in $APP." >&2; exit 1;
}
codesign --verify --deep --strict "$APP" || {
	echo "App signature verification failed; DMG staging blocked." >&2; exit 1;
}

IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null)" || {
	echo "Unable to inspect valid signing identities; no image written." >&2; exit 1;
}
IDENTITY="$(gaze_signing_identity "${DIST:-0}" "${GAZE_SIGNING_IDENTITY:-}" "$IDENTITIES")" || exit 1

SIGNATURE="$(codesign -dv --verbose=4 "$APP" 2>&1)"
if [ "${DIST:-}" = "1" ]; then
	printf '%s\n' "$SIGNATURE" | grep -q '^Authority=Developer ID Application: ' || {
		echo "Release DMG requires a Developer ID Application app signature." >&2; exit 1;
	}
	printf '%s\n' "$SIGNATURE" | grep -q '^Timestamp=' || {
		echo "Release app signature has no secure timestamp." >&2; exit 1;
	}
	printf '%s\n' "$SIGNATURE" | grep -q 'flags=.*runtime' || {
		echo "Release app signature lacks the hardened runtime." >&2; exit 1;
	}
	echo "  ✓ Developer ID + timestamp + hardened runtime"
fi

# Stable identity: the staged app must satisfy the existing bundle's
# designated requirement, so a stray certificate cannot ship under our name.
SIGNING_REFERENCE="${GAZE_SIGNING_REFERENCE:-$ROOT/build/Gaze.app}"
if [ -d "$SIGNING_REFERENCE" ] && [ "$SIGNING_REFERENCE" != "$APP" ]; then
	REFERENCE_TEAM="$(codesign -dv "$SIGNING_REFERENCE" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
	if [ -n "${REFERENCE_TEAM:-}" ] && [ "$REFERENCE_TEAM" != "not set" ]; then
		REFERENCE_REQUIREMENT="$(codesign -d -r- "$SIGNING_REFERENCE" 2>&1 | sed -n 's/^designated => //p')"
		[ -n "${REFERENCE_REQUIREMENT:-}" ] || { echo "Could not read the existing Gaze signing requirement." >&2; exit 1; }
		codesign --verify --strict -R "=$REFERENCE_REQUIREMENT" "$APP" || {
			echo "Staged app identity differs from the existing Gaze app; no image written." >&2; exit 1;
		}
		echo "  ✓ Matches the existing Gaze signing requirement"
	fi
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
case "$VERSION" in
	""|*[!0-9A-Za-z.\-]*)
		echo "Version '$VERSION' is unsuitable for a filename." >&2; exit 1;;
esac

mkdir -p "$OUT_DIR"
IMAGE="$OUT_DIR/Gaze-$VERSION.dmg"
[ -e "$IMAGE" ] && { echo "Output already exists; remove it or set GAZE_DMG_OUTPUT_DIR: $IMAGE" >&2; exit 1; }

STAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/gaze-dmg-stage.XXXXXX")"
trap 'rm -rf "$STAGE_ROOT"' EXIT
STAGE="$STAGE_ROOT/Gaze"
mkdir -p "$STAGE/.background"

echo "→ Staging DMG contents"
/usr/bin/ditto "$APP" "$STAGE/Gaze.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/LICENSE" "$STAGE/LICENSE.txt"

# Volume icon from the app's own icon; best-effort without extra tools.
if [ -f "$STAGE/Gaze.app/Contents/Resources/AppIcon.icns" ]; then
	cp "$STAGE/Gaze.app/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
	/usr/bin/SetFile -a C "$STAGE" 2>/dev/null || true
	/usr/bin/SetFile -a V "$STAGE/.VolumeIcon.icns" 2>/dev/null || true
	echo "  ✓ volume icon"
else
	echo "  ! no AppIcon.icns — volume icon skipped"
fi

# Finder background: reuse the DMG artwork renderer when its dependencies
# are installed; otherwise ship without a custom background.
if [ -f "$ROOT/Tools/Release/DMG/artwork.py" ] && python3 -c 'import PIL' 2>/dev/null; then
	python3 "$ROOT/Tools/Release/DMG/artwork.py" "$STAGE_ROOT/artwork" >/dev/null
	cp "$STAGE_ROOT/artwork/background.png" "$STAGE/.background/background.png"
	echo "  ✓ background"
else
	echo "  ! Pillow unavailable — DMG ships without a custom background"
fi

cat > "$STAGE/README.txt" <<'EOF'
Gaze — face unlock for the Mac
==============================

Install (explicit steps)
------------------------
1. Drag Gaze.app into Applications.
2. Eject this disk image.
3. Open Gaze from Applications (first launch may ask you to confirm
   an app from an identified developer in System Settings > Privacy
   & Security, then grant camera access on first enrolment).
4. Enrol your face in the setup window; the menu-bar agent unlocks
   while the screen is locked.

Authorization plugin: DISABLED
------------------------------
This DMG installs no authorization plugin and changes no login,
PAM, launchd, or authorization-database configuration. The legacy
face-only plugin is disabled pending a security redesign:
Plugin/install.sh prints an explanation and exits without making
changes. Do not run historical install scripts. If a previous
install broke the lock screen, roll back with:

    sudo Plugin/uninstall.sh

See Plugin/README.md and SECURITY.md before changing any
authorization policy.
EOF
echo "  ✓ Gaze.app + Applications link + README.txt + LICENSE.txt"

echo "→ Creating $IMAGE"
/usr/bin/hdiutil create -volname "Gaze $VERSION" -srcfolder "$STAGE" \
	-format UDZO -imagekey zlib-level=9 -o "$STAGE_ROOT/Gaze-tmp.dmg" >/dev/null
mv "$STAGE_ROOT/Gaze-tmp.dmg" "$IMAGE"

if [ "${DIST:-}" = "1" ]; then
	echo "→ Signing DMG with Developer ID"
	/usr/bin/codesign --force --sign "$IDENTITY" --timestamp "$IMAGE"
	/usr/bin/codesign --verify --strict "$IMAGE"
	DMG_SIG="$(codesign -dv --verbose=4 "$IMAGE" 2>&1)"
	printf '%s\n' "$DMG_SIG" | grep -q '^Authority=Developer ID Application: ' || {
		echo "DMG signature is not Developer ID Application; removing output." >&2;
		rm -f "$IMAGE"; exit 1;
	}
	printf '%s\n' "$DMG_SIG" | grep -q '^Timestamp=' || {
		echo "DMG signature has no secure timestamp; removing output." >&2;
		rm -f "$IMAGE"; exit 1;
	}
	echo "  ✓ DMG Developer ID signature + timestamp"
fi

/usr/bin/hdiutil verify "$IMAGE" >/dev/null
echo "✓ Built $IMAGE"
