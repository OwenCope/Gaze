#!/bin/bash
# Stages a versioned Gaze DMG from an app bundle built by build.sh.
#
#   ./build.sh                              # or DIST=1 for release
#   DIST=1 ./Tools/Release/BuildDMG.sh      # writes build/installers/Gaze-<version>.dmg
#   ./Tools/Release/BuildDMG.sh --help      # usage, env overrides, then exit
#
# Env overrides:
#   GAZE_DMG_APP         input app bundle (default build/Gaze.app,
#                        or build/release/Gaze.app when DIST=1).
#   GAZE_DMG_OUTPUT_DIR  output dir (default build/installers).
#   GAZE_SIGNING_IDENTITY, GAZE_SIGNING_REFERENCE  see Signing.sh.
# Refuses to overwrite an existing Gaze-<version>.dmg.
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

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
	sed -n '2,/^set /p' "$0" | sed 's/^# \{0,1\}//'
	echo "Version is read from the staged app's CFBundleShortVersionString."
	echo "Existing Gaze-<version>.dmg is never overwritten."
	exit 0
fi
[ $# -eq 0 ] || { echo "Usage: $(basename "$0") [-h|--help]" >&2; exit 1; }

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

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null)" || { echo "Could not read CFBundleShortVersionString from $APP." >&2; exit 1; }
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
mkdir -p "$STAGE/Docs"
cp "$ROOT/LICENSE" "$STAGE/Docs/LICENSE.txt"

# Volume icon from the app's own icon; best-effort without extra tools.
if [ -f "$STAGE/Gaze.app/Contents/Resources/AppIcon.icns" ]; then
	cp "$STAGE/Gaze.app/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
	/usr/bin/SetFile -a C "$STAGE" 2>/dev/null || true
	/usr/bin/SetFile -a V "$STAGE/.VolumeIcon.icns" 2>/dev/null || true
	echo "  ✓ volume icon"
else
	echo "  ! no AppIcon.icns — volume icon skipped"
fi

# Finder background: Pro Black artwork at 1x + retina, pinned as the Finder
# background picture. Geometry mirrors Tools/Release/DMG/artwork.py (shared
# with package.py); keep these in sync there rather than forking new values.
# artwork.py: WINDOW_SIZE=(640, 360), Gaze.app=(176, 180),
# Applications=(464, 180), ICON_SIZE=112, text size 13.
DMG_WINDOW_WIDTH=640
DMG_WINDOW_HEIGHT=360
DMG_WINDOW_LEFT=180
DMG_WINDOW_TOP=140
DMG_ICON_SIZE=112
DMG_TEXT_SIZE=13
DMG_GAZE_X=176
DMG_GAZE_Y=180
DMG_APPS_X=464
DMG_APPS_Y=180

[ -f "$ROOT/Tools/Release/DMG/artwork.py" ] || {
	echo "DMG artwork renderer missing: Tools/Release/DMG/artwork.py; refusing to stage without a Finder background." >&2; exit 1;
}
python3 -c 'import PIL.Image' 2>/dev/null || {
	echo "Pillow is required for the DMG background (pip install -r Tools/Release/DMG/requirements.txt); refusing to ship without it." >&2; exit 1;
}
python3 "$ROOT/Tools/Release/DMG/artwork.py" "$STAGE_ROOT/artwork" >/dev/null || {
	echo "DMG artwork render failed; no image written." >&2; exit 1;
}
for f in background.png "background@2x.png" background-dark.png "background-dark@2x.png"; do
	[ -s "$STAGE_ROOT/artwork/$f" ] || {
		echo "DMG artwork missing or empty: $STAGE_ROOT/artwork/$f; no image written." >&2; exit 1;
	}
done
[ -x /usr/bin/tiffutil ] || {
	echo "Missing /usr/bin/tiffutil; cannot build the Retina background." >&2; exit 1;
}
/usr/bin/tiffutil -cathidpicheck "$STAGE_ROOT/artwork/background.png" "$STAGE_ROOT/artwork/background@2x.png" \
	-out "$STAGE/.background.tiff" >/dev/null || {
	echo "Failed to combine 1x + retina background; no image written." >&2; exit 1;
}
[ -s "$STAGE/.background.tiff" ] || {
	echo "Retina background missing after tiffutil: $STAGE/.background.tiff; no image written." >&2; exit 1;
}
cp "$STAGE_ROOT/artwork/background.png" "$STAGE_ROOT/artwork/background@2x.png" \
	"$STAGE_ROOT/artwork/background-dark.png" "$STAGE_ROOT/artwork/background-dark@2x.png" \
	"$STAGE/.background/"
echo "  ✓ background (1x + retina, light + dark rendered; Retina TIFF staged)"
DMG_WINDOW_RIGHT=$((DMG_WINDOW_LEFT + DMG_WINDOW_WIDTH))
DMG_WINDOW_BOTTOM=$((DMG_WINDOW_TOP + DMG_WINDOW_HEIGHT))
/usr/bin/osascript <<OSA >/dev/null || { echo "Failed to pin the Finder background and icon layout; no image written." >&2; exit 1; }
tell application "Finder"
	open (POSIX file "$STAGE" as alias)
	repeat 50 times
		if exists Finder window "Gaze" then exit repeat
		delay 0.1
	end repeat
	set w to Finder window "Gaze"
	set current view of w to icon view
	set toolbar visible of w to false
	set statusbar visible of w to false
	set sidebar width of w to 0
	set bounds of w to {$DMG_WINDOW_LEFT, $DMG_WINDOW_TOP, $DMG_WINDOW_RIGHT, $DMG_WINDOW_BOTTOM}
	tell its icon view options
		set icon size to $DMG_ICON_SIZE
		set text size to $DMG_TEXT_SIZE
		set arrangement to not arranged
		set background picture to (POSIX file "$STAGE/.background.tiff" as alias)
	end tell
	delay 0.3
	set position of item "Gaze.app" of w to {$DMG_GAZE_X, $DMG_GAZE_Y}
	set position of item "Applications" of w to {$DMG_APPS_X, $DMG_APPS_Y}
	delay 0.3
	close w
	open (POSIX file "$STAGE" as alias)
	delay 0.3
	close Finder window "Gaze"
end tell
OSA
echo "  ✓ Finder background + icon layout pinned"

cat > "$STAGE/Docs/README.txt" <<'EOF'
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
echo "  ✓ Gaze.app + Applications link + Docs"

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
