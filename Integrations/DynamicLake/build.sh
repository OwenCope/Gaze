#!/bin/zsh
# Builds the universal plugin executable and assembles build/Gaze.dynamiclakeplugin plus a zip.
set -euo pipefail
cd "${0:A:h}"

VERSION=$(/usr/bin/plutil -extract version raw Resources/plugin.json)
OUT=build
PKG=$OUT/Gaze.dynamiclakeplugin
ZIP=$OUT/Gaze-$VERSION.zip
rm -rf "$PKG" "$ZIP"
mkdir -p "$OUT/obj" "$PKG"

for arch in arm64 x86_64; do
	xcrun swiftc -O -target "$arch-apple-macos14.0" Sources/main.swift -o "$OUT/obj/gaze-dynamiclake-$arch"
done
lipo -create "$OUT/obj/gaze-dynamiclake-arm64" "$OUT/obj/gaze-dynamiclake-x86_64" -output "$PKG/gaze-dynamiclake"
strip -x "$PKG/gaze-dynamiclake"
# Signed with a real identity when one is available: DynamicLake Playground blocks
# ad-hoc signed plugin executables.
IDENTITY="${GAZE_PLUGIN_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(.*\)"/\1/p' | head -1)}"
codesign --force --options runtime --timestamp=none --sign "${IDENTITY:--}" "$PKG/gaze-dynamiclake"

cp Resources/plugin.json Resources/icon.png Resources/README.md "$PKG/"
ditto -c -k --keepParent "$PKG" "$ZIP"

bytes() { stat -f %z "$1"; }
check() { # name size limit
	printf '%-12s %9d bytes (limit %d)\n' "$1" "$2" "$3"
	(( $2 <= $3 )) || { echo "error: $1 is over the limit" >&2; exit 1; }
}
check manifest "$(bytes "$PKG/plugin.json")" $((128 * 1024))
check icon "$(bytes "$PKG/icon.png")" $((1536 * 1024))
check extracted "$(du -sk "$PKG" | awk '{print $1 * 1024}')" $((20 * 1024 * 1024))
check archive "$(bytes "$ZIP")" $((7 * 1024 * 1024))
lipo -archs "$PKG/gaze-dynamiclake"
shasum -a 256 "$ZIP"
echo "Built $PKG and $ZIP"
