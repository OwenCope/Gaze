#!/bin/bash
# Builds Face ID.app. No Xcode project — swiftc plus a hand-assembled bundle,
# same shape as Pact.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=toolchain.sh
. "$ROOT/toolchain.sh"
require_toolchain
APP="$ROOT/build/Face ID.app"

# Built aside and swapped in at the end, rather than deleted and rebuilt in place.
#
# In-place rebuilds leave a window where the bundle exists but its executable does not,
# and the Dock draws a prohibitory sign over the icon for as long as that lasts —
# intermittently, depending on when you happen to look.
STAGE="$ROOT/build/.staging-Face ID.app"
BIN="$STAGE/Contents/MacOS/FaceID"

echo "→ Cleaning"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"

echo "→ Bundle skeleton"
cp "$ROOT/Resources/Info.plist" "$STAGE/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$STAGE/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$STAGE/Contents/PkgInfo"

# An embedding model is optional. Without one the app falls back to the
# landmark-geometry embedder, which is weaker — see Recognition/FaceEmbedder.swift.
if [ -d "$ROOT/Resources/FaceEmbedding.mlpackage" ]; then
	echo "→ Compiling Core ML model"
	xcrun coremlc compile "$ROOT/Resources/FaceEmbedding.mlpackage" "$STAGE/Contents/Resources" >/dev/null
	echo "  ✓ FaceEmbedding.mlmodelc"
else
	echo "  ! no FaceEmbedding.mlpackage — using landmark-geometry fallback"
fi

SDK="$(xcrun --show-sdk-path --sdk macosx)"
echo "→ Compiling (SDK: $(basename "$SDK"), $(host_target))"
xcrun swiftc \
	-parse-as-library \
	-O -wmo \
	-target "$(host_target)" \
	-sdk "$SDK" \
	-framework SwiftUI \
	-framework AppKit \
	-framework AVFoundation \
	-framework Vision \
	-framework CoreML \
	-framework CryptoKit \
	-framework LocalAuthentication \
	"$ROOT"/Sources/*/*.swift \
	-o "$BIN"

# Prefer a real signing identity over ad-hoc.
#
# Not cosmetic: the Keychain ACL protecting the vault key is bound to the app's code
# identity, and an ad-hoc signature is regenerated on every build. That makes the app a
# *different* application each time, so macOS challenges it for the keychain password on
# every single rebuild. A stable identity keeps the ACL matching.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
	| awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')"

if [ -n "$IDENTITY" ]; then
	echo "→ Signing as $IDENTITY"
else
	echo "→ Signing (ad-hoc — expect a keychain prompt after each rebuild)"
	IDENTITY="-"
fi

codesign --force --sign "$IDENTITY" \
	--entitlements "$ROOT/Resources/FaceID.entitlements" \
	--identifier app.faceid.FaceID "$STAGE"

echo "→ Swapping in"
# Atomic-ish: the finished bundle replaces the old one in a single rename, so the app is
# never on disk in a half-built state.
rm -rf "$APP.old"
[ -d "$APP" ] && mv "$APP" "$APP.old"
mv "$STAGE" "$APP"
rm -rf "$APP.old"

echo "✓ Built $APP"
