#!/bin/bash
# Builds Gaze.app. No Xcode project — swiftc plus a hand-assembled bundle,
# same shape as Pact.
# GAZE_ARCHS selects the architectures to build (default "arm64 x86_64" for a
# universal binary); GAZE_ARCHS=arm64 builds just one slice and skips lipo.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=Tools/Scripts/toolchain.sh
. "$ROOT/Tools/Scripts/toolchain.sh"
. "$ROOT/Tools/Scripts/MainAppSources.sh"
. "$ROOT/Tools/Release/Signing.sh"
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null)" || {
	echo "Unable to inspect valid signing identities. The existing app was not replaced." >&2
	exit 1
}
IDENTITY="$(gaze_signing_identity "${DIST:-0}" "${GAZE_SIGNING_IDENTITY:-}" "$IDENTITIES")" || exit 1
DEFAULT_OUTPUT="$ROOT/build/Gaze.app"
SIGNING_FLAGS=(--options runtime)
if [ "${DIST:-}" = "1" ]; then
	python3 "$ROOT/Tools/Release/ModelClearance/validate.py" || {
		echo "Release model/asset clearance is incomplete (see NOTICE.md); the existing app was not replaced." >&2
		exit 1
	}
	DEFAULT_OUTPUT="$ROOT/build/release/Gaze.app"
	SIGNING_FLAGS+=(--timestamp)
fi
collect_gaze_main_sources "$ROOT"
require_toolchain
APP="${GAZE_BUILD_OUTPUT:-$DEFAULT_OUTPUT}"
python3 "$ROOT/Tools/Release/check-build-space.py" --output "$APP" --temporary "${TMPDIR:-/tmp}" || {
	echo "Insufficient disk space for a safe build. The existing app was not replaced." >&2
	exit 1
}
SIGNING_REFERENCE="${GAZE_SIGNING_REFERENCE:-$ROOT/build/Gaze.app}"
REFERENCE_REQUIREMENT=""
if [ "${DIST:-}" != "1" ] && [ -d "$SIGNING_REFERENCE" ]; then
	REFERENCE_TEAM="$(codesign -dv "$SIGNING_REFERENCE" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
	if [ -n "$REFERENCE_TEAM" ] && [ "$REFERENCE_TEAM" != "not set" ]; then
		REFERENCE_REQUIREMENT="$(codesign -d -r- "$SIGNING_REFERENCE" 2>&1 | sed -n 's/^designated => //p')"
		[ -n "$REFERENCE_REQUIREMENT" ] || { echo "Could not read the existing Gaze signing requirement." >&2; exit 1; }
	fi
fi

# A checkout under ~/Documents (or any folder iCloud Drive syncs) has new directories
# stamped with com.apple.FinderInfo and com.apple.fileprovider.fpfs#P by the file
# provider, asynchronously. codesign reads those as "resource fork, Finder information,
# or similar detritus" and refuses the bundle — and the message names the bundle rather
# than the attribute, so it reads as a broken build instead of a stray xattr.
#
# Clearing once is not enough. The provider is watching this tree, which has just been
# rewritten file by file, and it re-stamps a directory while a recursive clear is still
# walking the rest of it — so a clear early in the script has worn off by the time
# signing happens. Clear immediately before each sign instead, and retry for the case
# where the stamp lands in the gap anyway.
#
# com.apple.provenance survives the clear and is harmless; codesign ignores it.
gaze_codesign() {
	local target="${*: -1}" attempt
	for attempt in 1 2 3; do
		xattr -cr "$target" 2>/dev/null || true
		codesign "$@" && return 0
		sleep 0.25
	done
	return 1
}

# Built aside and swapped in at the end, rather than deleted and rebuilt in place.
#
# In-place rebuilds leave a window where the bundle exists but its executable does not,
# and the Dock draws a prohibitory sign over the icon for as long as that lasts —
# intermittently, depending on when you happen to look.
#
# Staged in the temporary directory, not beside the output, which is where this used to
# put it. Beside the output is inside the checkout, and a checkout under ~/Documents
# sits in a folder iCloud Drive syncs: the file provider stamps every directory it
# watches being created with com.apple.FinderInfo, and codesign reads that as
# "resource fork, Finder information, or similar detritus" and refuses the bundle. It
# re-stamps as quickly as it can be cleared — a clear immediately before signing still
# lost, three attempts running — so signing inside a managed folder does not work at
# all, and no amount of retrying changes that.
#
# TMPDIR is on the same volume as the output, so the swap at the end is still a rename
# and the app is still never on disk half-built. On the unlikely chance TMPDIR is set
# to another volume, the move degrades to a copy: slower, and no longer atomic, but the
# result is the same app.
mkdir -p "$(dirname "$APP")"
STAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/.staging-Gaze.XXXXXX")"
trap 'rm -rf "$STAGE_ROOT"' EXIT
STAGE="$STAGE_ROOT/Gaze.app"
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
	echo "  ! no FaceEmbedding model — falling back to landmark-geometry embedding"
	echo "    Recognition is markedly weaker, and the fallback lives in a different"
	echo "    feature space, so any face already enrolled against the Core ML embedder"
	echo "    is ignored and the user has to enrol again."
fi

# MediaPipe Iris (Apache 2.0, see ThirdParty/MediaPipeIris): finds the pupil inside each
# eye for the Follow the light movement. Optional: without it, the pixel fallback is used.
#
# The prebuilt branch comes first, as it does for FaceEmbedding above. A checkout whose
# IrisLandmarks.mlpackage is a stub — carrying only Manifest.json, with the real
# Data/com.apple.CoreML tree absent — made coremlc abort here, and the only recourse was
# to move the stub out of the way by hand for every build.
if [ -d "$ROOT/Resources/IrisLandmarks.mlmodelc" ]; then
	echo "→ Using prebuilt iris landmark model"
	cp -R "$ROOT/Resources/IrisLandmarks.mlmodelc" "$STAGE/Contents/Resources/"
	echo "  ✓ IrisLandmarks.mlmodelc (prebuilt)"
elif [ -d "$ROOT/Resources/IrisLandmarks.mlpackage" ]; then
	xcrun coremlc compile "$ROOT/Resources/IrisLandmarks.mlpackage" "$STAGE/Contents/Resources" >/dev/null
	echo "  ✓ IrisLandmarks.mlmodelc"
else
	echo "  ! no iris landmark model — Follow the light falls back to pupil detection by pixel"
fi

# The unused legacy Liveness texture model is excluded from app bundles.
# Lock-screen photo rejection uses the separate Spoof model below.

# The face-crop live/spoof classifier (Tools/Scripts/train-spoof-classifier.swift). Spots a
# phone, screen or printed photo held up as the face — a different signal from the passive
# texture model. Missing weights block unlock when photo rejection is enabled.
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
	echo "  ! no Spoof model — unlocking is refused when the anti-spoof model is missing"
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

# TourKit's MIT licence ships in the bundle because its source is compiled in.
cp "$ROOT/ThirdParty/TourKit/LICENSE" "$STAGE/Contents/Resources/TourKit-LICENSE.txt"
echo "  ✓ TourKit-LICENSE.txt"

# SetupMark supplies Gaze's animations; TourKit supplies the opening slideshow.
# The old proprietary FaceIDKit framework is not linked.

# A distribution build links against the oldest SDK installed that still compiles this,
# so the binary cannot reference a symbol an older Mac lacks. The linker also has to be
# told the SDK version explicitly: left alone it stamps the toolchain's newest regardless
# of -sdk, and that stamp is part of how the loader decides what to allow.
SDK_FLAGS=()
if [ "${DIST:-}" = "1" ] && read -r dist_sdk dist_version <<<"$(oldest_usable_sdk)" && [ -n "${dist_sdk:-}" ]; then
	SDK="$dist_sdk"
	SDK_FLAGS=(-Xlinker -platform_version -Xlinker macos -Xlinker "$MIN_SDK_MAJOR.0" -Xlinker "$dist_version")
else
	SDK="${SDKROOT:-$(xcrun --show-sdk-path --sdk macosx)}"
fi

# The Shortcuts action (Sources/App/ConfirmIdentityIntent.swift) imports AppIntents.
# Linked only when the file is present, so checkouts without it still build.
APP_INTENTS_FLAGS=()
if [ -f "$ROOT/Sources/App/ConfirmIdentityIntent.swift" ]; then
	# The compiler also writes the intent's constant values, which the metadata
	# step below turns into Metadata.appintents: without that file Shortcuts never
	# lists the action.
	APP_INTENTS_FLAGS=(-framework AppIntents
		-emit-const-values-path "$STAGE_ROOT/Gaze.swiftconstvalues"
		-Xfrontend -const-gather-protocols-file
		-Xfrontend "$ROOT/Tools/Scripts/app-intents-protocols.json")
fi

# Every build carries every architecture in GAZE_ARCHS fused with lipo; a single
# entry compiles just that slice and skips the merge. Slices live under STAGE_ROOT,
# which the EXIT trap removes, and a failed slice compile stops the script before
# anything is swapped in — the previous output is only replaced at the end.
GAZE_ARCHS="${GAZE_ARCHS:-arm64 x86_64}"
case "$GAZE_ARCHS" in
*" "*)
	echo "→ Compiling universal (SDK: $(basename "$SDK"), $GAZE_ARCHS)"
	# An array, not a space-joined string. The slices live under the repo, and a checkout
	# whose path contains a space — "Default Project", for one — was cut into pieces by
	# the unquoted expansion below, so lipo reported "file not found" twice and refused
	# to build anything.
	slices=()
	for arch in $GAZE_ARCHS; do
		slice="$STAGE_ROOT/Gaze-$arch"
		xcrun swiftc \
		-parse-as-library \
		-O -wmo \
		-target "$arch-apple-macos${MIN_SDK_MAJOR}.0" \
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
		-framework FinderSync \
		${APP_INTENTS_FLAGS[@]+"${APP_INTENTS_FLAGS[@]}"} \
		"${GAZE_MAIN_SOURCES[@]}" \
		-o "$slice"
		slices+=("$slice")
	done
	lipo -create -output "$BIN" "${slices[@]}"
	;;
*)
	echo "→ Compiling (SDK: $(basename "$SDK"), $GAZE_ARCHS)"
	xcrun swiftc \
		-parse-as-library \
		-O -wmo \
		-target "$GAZE_ARCHS-apple-macos${MIN_SDK_MAJOR}.0" \
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
		-framework FinderSync \
		${APP_INTENTS_FLAGS[@]+"${APP_INTENTS_FLAGS[@]}"} \
		"${GAZE_MAIN_SOURCES[@]}" \
		-o "$BIN"
	;;
esac

# The Finder Sync extension behind right-click Lock/Unlock with Gaze. Built
# per architecture like the main binary, then merged; signed here, before
# Gaze.app itself, so the parent signature covers an already-signed appex.
echo "→ Building Finder Sync extension"
APPEX="$STAGE/Contents/PlugIns/GazeFinder.appex"
mkdir -p "$APPEX/Contents/MacOS"
FINDER_SOURCES=("$ROOT"/Sources/FinderExtension/*.swift "$ROOT/Sources/Security/AppLockStore.swift")
case "$GAZE_ARCHS" in
*" "*)
	# An array, for the same reason the main binary's slices are: the staging directory
	# lives under the repo, and a checkout path containing a space was split by the
	# unquoted expansion below.
	finder_slices=()
	for arch in $GAZE_ARCHS; do
		slice="$STAGE_ROOT/GazeFinder-$arch"
		xcrun swiftc \
		-application-extension \
		-module-name GazeFinder \
		-parse-as-library \
		-O -wmo \
		-target "$arch-apple-macos${MIN_SDK_MAJOR}.0" \
		-sdk "$SDK" \
		${SDK_FLAGS[@]+"${SDK_FLAGS[@]}"} \
		-framework Cocoa \
		-framework FinderSync \
		-Xlinker -e -Xlinker _NSExtensionMain \
		"${FINDER_SOURCES[@]}" \
		-o "$slice"
		finder_slices+=("$slice")
	done
	lipo -create -output "$APPEX/Contents/MacOS/GazeFinder" "${finder_slices[@]}"
	;;
*)
	xcrun swiftc \
		-application-extension \
		-module-name GazeFinder \
		-parse-as-library \
		-O -wmo \
		-target "$GAZE_ARCHS-apple-macos${MIN_SDK_MAJOR}.0" \
		-sdk "$SDK" \
		${SDK_FLAGS[@]+"${SDK_FLAGS[@]}"} \
		-framework Cocoa \
		-framework FinderSync \
		-Xlinker -e -Xlinker _NSExtensionMain \
		"${FINDER_SOURCES[@]}" \
		-o "$APPEX/Contents/MacOS/GazeFinder"
	;;
esac
cp "$ROOT/Sources/FinderExtension/Info.plist" "$APPEX/Contents/Info.plist"
APPEX_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$STAGE/Contents/Info.plist")"
APPEX_BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$STAGE/Contents/Info.plist")"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APPEX_VERSION" -c "Set :CFBundleVersion $APPEX_BUILD" "$APPEX/Contents/Info.plist"
echo "  ✓ GazeFinder.appex"

# The sudo PAM module. Loaded by /usr/bin/sudo once the user turns on "Approve sudo
# with your face"; SudoApproval copies it to /usr/local/lib/pam. Signed with the app.
PAM_ARCH_FLAGS=()
for arch in $GAZE_ARCHS; do PAM_ARCH_FLAGS+=(-arch "$arch"); done
xcrun clang -bundle -O2 -Wall -Werror "${PAM_ARCH_FLAGS[@]}" -isysroot "$SDK" \
	-mmacosx-version-min="${MIN_SDK_MAJOR}.0" -lpam -framework Security -framework CoreFoundation \
	"$ROOT/Sources/PAM/pam_gaze.c" -o "$STAGE/Contents/Resources/pam_gaze.so"
gaze_codesign --force --sign "$IDENTITY" "$STAGE/Contents/Resources/pam_gaze.so"
echo "  ✓ pam_gaze.so"

# Shortcuts metadata, normally made by Xcode. Optional: a failure here only costs
# the Shortcuts action, never the build.
if [ -f "$STAGE_ROOT/Gaze.swiftconstvalues" ] && xcrun -f appintentsmetadataprocessor >/dev/null 2>&1; then
	echo "$STAGE_ROOT/Gaze.swiftconstvalues" > "$STAGE_ROOT/constvals.txt"
	printf '%s\n' "${GAZE_MAIN_SOURCES[@]}" > "$STAGE_ROOT/sources.txt"
	first_arch="${GAZE_ARCHS%% *}"
	if xcrun appintentsmetadataprocessor \
		--output "$STAGE/Contents/Resources" \
		--toolchain-dir "$(dirname "$(dirname "$(dirname "$(xcrun -f swift)")")")" \
		--module-name Gaze \
		--sdk-root "$SDK" \
		--xcode-version "$(xcodebuild -version 2>/dev/null | awk '/Build version/{print $3}')" \
		--platform-family macOS \
		--deployment-target "${MIN_SDK_MAJOR}.0" \
		--target-triple "$first_arch-apple-macos${MIN_SDK_MAJOR}.0" \
		--source-file-list "$STAGE_ROOT/sources.txt" \
		--swift-const-vals-list "$STAGE_ROOT/constvals.txt" \
		--binary-file "$BIN" \
		--dependency-file "$STAGE_ROOT/intents.d" \
		--stringsdata-file "$STAGE_ROOT/intents.stringsdata" \
		--force >/dev/null 2>&1; then
		echo "  ✓ Shortcuts metadata"
	else
		echo "  ! Shortcuts metadata failed; the Confirm It's You action won't appear in Shortcuts."
	fi
fi

if [ "${DIST:-}" = "1" ]; then
	echo "→ Signing release with Developer ID"
else
	echo "→ Signing with a stable local identity"
fi

gaze_codesign --force "${SIGNING_FLAGS[@]}" --sign "$IDENTITY" \
	--entitlements "$ROOT/Sources/FinderExtension/GazeFinder.entitlements" \
	--identifier com.gazeunlock.Gaze.Finder "$APPEX"

codesign --verify --strict "$APPEX"

gaze_codesign --force "${SIGNING_FLAGS[@]}" --sign "$IDENTITY" \
	--entitlements "$ROOT/Resources/Gaze.entitlements" \
	--identifier com.gazeunlock.Gaze "$STAGE"

codesign --verify --strict "$STAGE"
if [ "${DIST:-}" = "1" ]; then
	SIGNATURE="$(codesign -dv --verbose=4 "$STAGE" 2>&1)"
	printf '%s\n' "$SIGNATURE" | grep -q '^Authority=Developer ID Application: ' || {
		echo "Release signature is not Developer ID Application. Output was not replaced." >&2; exit 1;
	}
	printf '%s\n' "$SIGNATURE" | grep -q '^Timestamp=' || {
		echo "Release signature has no secure timestamp. Output was not replaced." >&2; exit 1;
	}
fi
if [ -n "$REFERENCE_REQUIREMENT" ]; then
	codesign --verify --strict -R "=$REFERENCE_REQUIREMENT" "$STAGE" || {
		echo "Signing identity differs from the existing Gaze app. The existing bundle was not replaced." >&2
		exit 1
	}
	echo "  ✓ Matches the existing Gaze signing requirement"
fi

echo "→ Swapping in"
# Atomic-ish: the finished bundle replaces the old one in a single rename, so the app is
# never on disk in a half-built state.
rm -rf "$APP.old"
[ -d "$APP" ] && mv "$APP" "$APP.old"
mv "$STAGE" "$APP"
rm -rf "$APP.old"

echo "✓ Built $APP"
