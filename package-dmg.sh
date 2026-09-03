#!/bin/bash
# Builds a release-signed Gaze.app and packages it as a drag-to-install DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Gaze.app"

# Always rebuild so the disk image represents the current checkout, and use the
# distribution path so the app is not tied to this Mac's development certificate.
DIST=1 "$ROOT/build.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/build/Gaze-$VERSION.dmg"
STAGE="$(mktemp -d "$ROOT/build/.dmg-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

echo "→ Preparing Gaze $VERSION disk image"
cp -R "$APP" "$STAGE/Gaze.app"
ln -s /Applications "$STAGE/Applications"

echo "→ Creating $DMG"
hdiutil create \
	-volname "Gaze $VERSION" \
	-srcfolder "$STAGE" \
	-ov \
	-format UDZO \
	"$DMG" >/dev/null

echo "✓ Built $DMG"
