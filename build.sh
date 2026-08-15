#!/bin/bash
# Builds Gaze.app. No Xcode project — swiftc plus a hand-assembled bundle,
# same shape as Pact.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=toolchain.sh
. "$ROOT/toolchain.sh"
require_toolchain
APP="$ROOT/build/Gaze.app"

# Built aside and swapped in at the end, rather than deleted and rebuilt in place.
#
# In-place rebuilds leave a window where the bundle exists but its executable does not,
# and the Dock draws a prohibitory sign over the icon for as long as that lasts —
# intermittently, depending on when you happen to look.
STAGE="$ROOT/build/.staging-Gaze.app"
BIN="$STAGE/Contents/MacOS/Gaze"

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

# A distribution build links against the oldest SDK installed that still compiles this,
# so the binary cannot reference a symbol an older Mac lacks. The linker also has to be
# told the SDK version explicitly: left alone it stamps the toolchain's newest regardless
# of -sdk, and that stamp is part of how the loader decides what to allow.
SDK_FLAGS=()
if [ "${DIST:-}" = "1" ] && read -r dist_sdk dist_version <<<"$(oldest_usable_sdk)" && [ -n "${dist_sdk:-}" ]; then
	SDK="$dist_sdk"
	SDK_FLAGS=(-Xlinker -platform_version -Xlinker macos -Xlinker "$MIN_SDK_MAJOR.0" -Xlinker "$dist_version")
else
	SDK="$(xcrun --show-sdk-path --sdk macosx)"
fi

echo "→ Compiling (SDK: $(basename "$SDK"), $(host_target))"
xcrun swiftc \
	-parse-as-library \
	-O -wmo \
	-target "$(host_target)" \
	-sdk "$SDK" \
	${SDK_FLAGS[@]+"${SDK_FLAGS[@]}"} \
	-framework SwiftUI \
	-framework AppKit \
	-framework AVFoundation \
	-framework Vision \
	-framework CoreML \
	-framework CryptoKit \
	-framework LocalAuthentication \
	-framework OpenDirectory \
	"$ROOT"/Sources/*/*.swift \
	-o "$BIN"

# Prefer a real signing identity over ad-hoc.
#
# Not cosmetic: the Keychain ACL protecting the vault key is bound to the app's code
# identity, and an ad-hoc signature is regenerated on every build. That makes the app a
# *different* application each time, so macOS challenges it for the keychain password on
# every single rebuild. A stable identity keeps the ACL matching.
#
# All of which is true only on the machine that owns the certificate. An "Apple
# Development" signature is not a distribution signature: on any other Mac amfid
# has no provisioning profile naming that machine, so it refuses the binary and
# the kernel kills it at exec. No dialog, no crash report, no bounce — the app
# simply never starts, which is indistinguishable from a broken build.
#
# So: DIST=1 for anything anyone else will run. The keychain-prompt problem it
# reintroduces belongs to iterative rebuilds, and a release is signed once.
if [ "${DIST:-}" = "1" ]; then
	echo "→ Signing ad-hoc for distribution"
	IDENTITY="-"
else
	IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
		| awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')"

	if [ -n "$IDENTITY" ]; then
		echo "→ Signing as $IDENTITY (this Mac only — use DIST=1 to hand out)"
	else
		echo "→ Signing (ad-hoc — expect a keychain prompt after each rebuild)"
		IDENTITY="-"
	fi
fi

codesign --force --sign "$IDENTITY" \
	--entitlements "$ROOT/Resources/Gaze.entitlements" \
	--identifier com.gazeunlock.Gaze "$STAGE"

echo "→ Swapping in"
# Atomic-ish: the finished bundle replaces the old one in a single rename, so the app is
# never on disk in a half-built state.
rm -rf "$APP.old"
[ -d "$APP" ] && mv "$APP" "$APP.old"
mv "$STAGE" "$APP"
rm -rf "$APP.old"

echo "✓ Built $APP"
