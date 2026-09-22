#!/bin/bash
# Builds Gaze.bundle, the SecurityAgent authorization plugin.
# Building is safe. Installing is not — see install.sh.
set -euo pipefail

printf '%s\n' \
	'The legacy face-only authorization plugin is disabled pending a security redesign.' \
	'This script makes no changes. The GazePlugin.m path cannot be built or installed.' \
	'See SECURITY.md and Plugin/README.md before changing an existing authorization policy.' >&2
exit 1

ROOT="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=../toolchain.sh
. "$ROOT/../toolchain.sh"
# shellcheck source=../Tools/Release/Signing.sh
. "$ROOT/../Tools/Release/Signing.sh"
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null)" || {
	echo "Unable to inspect valid signing identities. The existing bundle was not replaced." >&2
	exit 1
}
IDENTITY="$(gaze_signing_identity "${DIST:-0}" "${GAZE_SIGNING_IDENTITY:-}" "$IDENTITIES")" || exit 1
SIGNING_FLAGS=(--options runtime)
if [ "${DIST:-}" = "1" ]; then
	SIGNING_FLAGS+=(--timestamp)
fi

# Model-clearance gate (mirrors the build.sh DIST gate).
#
# test-plugin.sh refreshes /Applications/Gaze.app from ../build/Gaze.app before
# installing the bundle. When the checkout bundles recognition models, validate.py
# must pass first; on failure this build stops here, so there is nothing fresh for
# test-plugin.sh to copy into /Applications.
if [ "${DIST:-}" = "1" ] \
	|| [ -d "$ROOT/../Resources/FaceEmbedding.mlmodelc" ] \
	|| [ -d "$ROOT/../Resources/FaceEmbedding.mlpackage" ] \
	|| [ -d "$ROOT/../Resources/Spoof.mlmodelc" ] \
	|| [ -d "$ROOT/../Resources/Spoof.mlpackage" ] \
	|| [ -f "$ROOT/../Resources/Spoof.mlmodel" ]; then
	python3 "$ROOT/../Tools/Release/ModelClearance/validate.py" || {
		echo "Model/asset clearance is incomplete; the existing bundle was not replaced, and test-plugin.sh must not copy ../build/Gaze.app to /Applications." >&2
		exit 1
	}
fi
require_toolchain
BUNDLE="$ROOT/build/Gaze.bundle"
BIN="$BUNDLE/Contents/MacOS/Gaze"

echo "→ Cleaning"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"

cp "$ROOT/Info.plist" "$BUNDLE/Contents/Info.plist"

SDK="$(xcrun --show-sdk-path --sdk macosx)"

# A bundle, not an executable: SecurityAgent dlopens it and looks up
# AuthorizationPluginCreate.
#
# A release bundle carries both architectures fused with lipo — SecurityAgent loads
# it in whatever process context authenticates, so a single-arch slice can fail to
# load where the app itself would run fine. A local build compiles just the host.
CLANG_FLAGS=(
	-bundle
	-fobjc-arc
	-O2
	-Wall -Wextra -Wno-unused-parameter
	-isysroot "$SDK"
	-framework Cocoa
	-framework QuartzCore
	-framework Security
	-framework SecurityInterface
	-framework CoreFoundation
	-lpam
	"$ROOT/GazePlugin.m"
	"$ROOT/GazeCapsuleView.m"
	"$ROOT/PeerTrust.c"
)
if [ "${DIST:-}" = "1" ]; then
	echo "→ Compiling universal (SDK: $(basename "$SDK"), arm64 + x86_64)"
	SLICE_DIR="$(mktemp -d "$ROOT/build/.slices-Gaze.XXXXXX")"
	trap 'rm -rf "$SLICE_DIR"' EXIT
	slices=""
	for target in $(release_targets); do
		slice="$SLICE_DIR/Gaze-${target%%-*}"
		xcrun clang "${CLANG_FLAGS[@]}" -target "$target" -o "$slice"
		slices="$slices $slice"
	done
	# shellcheck disable=SC2086
	lipo -create -output "$BIN" $slices
	rm -rf "$SLICE_DIR"
	trap - EXIT
else
	echo "→ Compiling (SDK: $(basename "$SDK"), $(host_target))"
	xcrun clang \
		"${CLANG_FLAGS[@]}" \
		-target "$(host_target)" \
		-o "$BIN"
fi

echo "→ Signing"
# Hardened runtime, because AMFI is stricter about third-party code loaded into system
# processes than about ordinary apps. `authorizationhosthelper` carries
# com.apple.private.security.clear-library-validation, so it is *permitted* to load code
# like ours — the question is what it demands of that code first.
codesign --force "${SIGNING_FLAGS[@]}" --sign "$IDENTITY" \
	--identifier com.gazeunlock.Gaze.plugin "$BUNDLE"

codesign --verify --strict "$BUNDLE"
if [ "${DIST:-}" = "1" ]; then
	SIGNATURE="$(codesign -dv --verbose=4 "$BUNDLE" 2>&1)"
	printf '%s\n' "$SIGNATURE" | grep -q '^Authority=Developer ID Application: ' || {
		echo "Release signature is not Developer ID Application. Output was not replaced." >&2; exit 1;
	}
	printf '%s\n' "$SIGNATURE" | grep -q '^Timestamp=' || {
		echo "Release signature has no secure timestamp. Output was not replaced." >&2; exit 1;
	}
fi

echo "✓ Built $BUNDLE"
echo
echo "  Not installed. ./install.sh puts it in /Library/Security/SecurityAgentPlugins/"
echo "  and rewrites system.login.screensaver — read install.sh first."
