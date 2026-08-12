#!/bin/bash
# Builds FaceID.bundle, the SecurityAgent authorization plugin.
# Building is safe. Installing is not — see install.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=../toolchain.sh
. "$ROOT/../toolchain.sh"
require_toolchain
BUNDLE="$ROOT/build/FaceID.bundle"
BIN="$BUNDLE/Contents/MacOS/FaceID"

echo "→ Cleaning"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"

cp "$ROOT/Info.plist" "$BUNDLE/Contents/Info.plist"

SDK="$(xcrun --show-sdk-path --sdk macosx)"
echo "→ Compiling (SDK: $(basename "$SDK"))"

# A bundle, not an executable: SecurityAgent dlopens it and looks up
# AuthorizationPluginCreate.
xcrun clang \
	-bundle \
	-fobjc-arc \
	-O2 \
	-Wall -Wextra -Wno-unused-parameter \
	-target "$(host_target)" \
	-isysroot "$SDK" \
	-framework Cocoa \
	-framework QuartzCore \
	-framework Security \
	-framework SecurityInterface \
	-framework CoreFoundation \
	-lpam \
	"$ROOT/FaceIDPlugin.m" \
	"$ROOT/FaceIDCapsuleView.m" \
	"$ROOT/PeerTrust.c" \
	-o "$BIN"

echo "→ Signing"
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
	| awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')"
[ -n "$IDENTITY" ] || IDENTITY="-"
# Hardened runtime, because AMFI is stricter about third-party code loaded into system
# processes than about ordinary apps. `authorizationhosthelper` carries
# com.apple.private.security.clear-library-validation, so it is *permitted* to load code
# like ours — the question is what it demands of that code first.
codesign --force --sign "$IDENTITY" --options runtime \
	--identifier app.faceid.plugin "$BUNDLE"

echo "✓ Built $BUNDLE"
echo
echo "  Not installed. ./install.sh puts it in /Library/Security/SecurityAgentPlugins/"
echo "  and rewrites system.login.screensaver — read install.sh first."
