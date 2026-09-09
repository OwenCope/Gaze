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
printf 'APPL????' > "$STAGE/Contents/PkgInfo"

# App icon.
#
# The source of truth is an Icon Composer bundle, Resources/AppIcon.icon, which carries
# separate light and dark appearances (green glass / black glass). `actool` compiles it to
# an Assets.car — the modern icon macOS reads via CFBundleIconName, and the only form that
# keeps the light/dark split — plus a flat AppIcon.icns fallback (CFBundleIconFile) for
# anything that can't read the catalog. Both land in Contents/Resources.
#
# `--include-all-app-icons` with the .icon passed as a direct input is what makes actool
# actually emit the icon; pointing it at a wrapping .xcassets silently produces nothing.
if [ -d "$ROOT/Resources/AppIcon.icon" ]; then
	echo "→ Compiling app icon (light/dark)"
	xcrun actool "$ROOT/Resources/AppIcon.icon" \
		--app-icon AppIcon --include-all-app-icons \
		--compile "$STAGE/Contents/Resources" \
		--platform macosx --target-device mac \
		--minimum-deployment-target "$MIN_SDK_MAJOR.0" \
		--development-region en --enable-on-demand-resources NO \
		--output-partial-info-plist "$STAGE/Contents/Resources/.icon-partial.plist" \
		>/dev/null
	rm -f "$STAGE/Contents/Resources/.icon-partial.plist"
	echo "  ✓ Assets.car + AppIcon.icns"
elif [ -f "$ROOT/Resources/AppIcon.icns" ]; then
	cp "$ROOT/Resources/AppIcon.icns" "$STAGE/Contents/Resources/AppIcon.icns"
	echo "  ✓ AppIcon.icns (flat, no light/dark)"
else
	echo "  ! no app icon"
fi

# An embedding model is optional. Without one the app falls back to the
# landmark-geometry embedder, which is weaker — see Recognition/FaceEmbedder.swift.
if [ -d "$ROOT/Resources/FaceEmbedding.mlmodelc" ]; then
	# A model already compiled to .mlmodelc (e.g. extracted from a distributed
	# build) — copy it straight in, no coremlc pass needed.
	echo "→ Using prebuilt Core ML model"
	cp -R "$ROOT/Resources/FaceEmbedding.mlmodelc" "$STAGE/Contents/Resources/"
	echo "  ✓ FaceEmbedding.mlmodelc (prebuilt)"
elif [ -d "$ROOT/Resources/FaceEmbedding.mlpackage" ]; then
	echo "→ Compiling Core ML model"
	xcrun coremlc compile "$ROOT/Resources/FaceEmbedding.mlpackage" "$STAGE/Contents/Resources" >/dev/null
	echo "  ✓ FaceEmbedding.mlmodelc"
else
	echo "  ! no FaceEmbedding model — using landmark-geometry fallback"
fi

# The anti-spoof model, if one has been dropped in.
#
# `LivenessDetector` looks for `Liveness.mlmodelc` in the bundle and disables the
# whole feature when it is missing — which it always was, because nothing here
# compiled it. The setting sat permanently greyed out reading "No anti-spoof
# model is installed", and there was no way to install one.
#
# Optional for the same reason the embedder is: the weights are somebody else's
# and their licence decides whether they can ship.
if [ -d "$ROOT/Resources/Liveness.mlmodelc" ]; then
	echo "→ Using prebuilt anti-spoof model"
	cp -R "$ROOT/Resources/Liveness.mlmodelc" "$STAGE/Contents/Resources/"
	echo "  ✓ Liveness.mlmodelc (prebuilt)"
elif [ -d "$ROOT/Resources/Liveness.mlpackage" ]; then
	echo "→ Compiling anti-spoof model"
	xcrun coremlc compile "$ROOT/Resources/Liveness.mlpackage" "$STAGE/Contents/Resources" >/dev/null
	echo "  ✓ Liveness.mlmodelc"
else
	echo "  ! no Liveness model — a photograph of you will pass"
fi

# The face-spoof OBJECT detector (Roboflow, trained by scripts/train_spoof.swift). Spots a
# held phone/screen/printed photo in frame — a different signal from the passive texture
# model. Optional; `SpoofDetector` disables itself when it's absent.
if [ -d "$ROOT/Resources/Spoof.mlmodelc" ]; then
	echo "→ Using prebuilt spoof detector"
	cp -R "$ROOT/Resources/Spoof.mlmodelc" "$STAGE/Contents/Resources/"
	echo "  ✓ Spoof.mlmodelc (prebuilt)"
elif [ -f "$ROOT/Resources/Spoof.mlmodel" ] || [ -d "$ROOT/Resources/Spoof.mlpackage" ]; then
	echo "→ Compiling spoof detector"
	SPOOF_SRC="$ROOT/Resources/Spoof.mlmodel"; [ -d "$ROOT/Resources/Spoof.mlpackage" ] && SPOOF_SRC="$ROOT/Resources/Spoof.mlpackage"
	xcrun coremlc compile "$SPOOF_SRC" "$STAGE/Contents/Resources" >/dev/null
	echo "  ✓ Spoof.mlmodelc"
else
	echo "  ! no Spoof model — object-detection anti-spoof off"
fi

# Setup's card art — screenshots of Gaze in use, shot on a real desktop. Copied whole
# rather than named file by file so adding a fourth card is a matter of dropping a PNG in
# the folder. Optional: `SetupFactArt` draws a vector fallback for anything missing, so a
# checkout without the images still builds and still runs.
if [ -d "$ROOT/Resources/Art" ]; then
	echo "→ Copying setup art"
	mkdir -p "$STAGE/Contents/Resources/Art"
	cp "$ROOT/Resources/Art/"*.png "$STAGE/Contents/Resources/Art/" 2>/dev/null || true
	# Cards can be clips as well as stills — an unlock is an animation, and a still of one
	# is a wasted card.
	cp "$ROOT/Resources/Art/"*.mp4 "$STAGE/Contents/Resources/Art/" 2>/dev/null || true
	# Screenshots arrive with Finder metadata attached — a resource fork from a Quick Look
	# edit, a "where from" attribute from a download. codesign refuses to sign a bundle
	# containing any of it ("resource fork, Finder information, or similar detritus not
	# allowed"), and the error names the bundle rather than the file, so it reads as a
	# broken build rather than a stray xattr on one PNG.
	xattr -cr "$STAGE/Contents/Resources/Art" 2>/dev/null || true
	art_count=$(find "$STAGE/Contents/Resources/Art" \( -name '*.png' -o -name '*.mp4' \) | wc -l | tr -d ' ')
	echo "  ✓ $art_count image(s)"
fi

# The credits avatars — each person's own picture, or their app's icon.
#
# Bundled rather than fetched. The site pulls these from GitHub *on the server* precisely
# so that reading the credits page does not hand GitHub the IP of everyone who reads it;
# an app that fetched them at runtime would do exactly what the site went out of its way
# to avoid, once per launch, from every user's Mac. These are snapshots, resized to 128pt
# — ample for a 26pt row at 2x, and the difference between 148KB and 3.7MB in the bundle.
if [ -d "$ROOT/Resources/Credits" ]; then
	echo "→ Copying credit portraits"
	mkdir -p "$STAGE/Contents/Resources/Credits"
	cp "$ROOT/Resources/Credits/"*.png "$STAGE/Contents/Resources/Credits/" 2>/dev/null || true
	# Same Finder-metadata problem as the setup art; same fix.
	xattr -cr "$STAGE/Contents/Resources/Credits" 2>/dev/null || true
	credit_count=$(find "$STAGE/Contents/Resources/Credits" -name '*.png' | wc -l | tr -d ' ')
	echo "  ✓ $credit_count portrait(s)"
fi

# The onboarding animations are our own now (see `SetupMark.swift`) — plain SwiftUI,
# no third-party framework. FaceIDKit (Aviorrok's, licensed to this app alone) used to be
# linked here; it was dropped so nothing in the build depends on a file others can't have.

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
