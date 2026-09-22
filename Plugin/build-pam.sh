#!/bin/bash
# Builds the disabled PAM compatibility module. See Plugin/README.md.
#
# Universal, because a PAM module is loaded into whatever process is authenticating and
# that is not always the architecture you built on: Rosetta shells, x86_64 Homebrew, and
# anything launched under `arch -x86_64` all load sudo as x86_64 on an Apple Silicon Mac.
# A single-architecture module simply fails to load there, and — because the stack is
# `sufficient` — it fails silently, falling through to the password with nothing to say
# why.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/build"
mkdir -p "$OUT"

# shellcheck source=../Tools/Release/Signing.sh
. "$ROOT/../Tools/Release/Signing.sh"
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null)" || {
	echo "Unable to inspect valid signing identities. The existing module was not replaced." >&2
	exit 1
}
IDENTITY="$(gaze_signing_identity "${DIST:-0}" "${GAZE_SIGNING_IDENTITY:-}" "$IDENTITIES")" || exit 1
SIGNING_FLAGS=(--options runtime)
if [ "${DIST:-}" = "1" ]; then
	SIGNING_FLAGS+=(--timestamp)
fi

# The SDK, not the live system. Command Line Tools may be selected while Xcode-beta is the
# thing with a current SDK, and `security/pam_modules.h` is only in the SDK.
SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
if [ -z "$SDK" ]; then
	echo "No macOS SDK found. Install the Command Line Tools or Xcode." >&2
	exit 1
fi

echo "→ Compiling pam_gaze.so"
clang -shared \
	-arch arm64 -arch x86_64 \
	-isysroot "$SDK" \
	-mmacosx-version-min=13.0 \
	-Wall -Wextra -Werror \
	-o "$OUT/pam_gaze.so" \
	"$ROOT/pam_gaze.c" \
	-I"$ROOT" \
	-framework Security -framework CoreFoundation \
	-lpam

echo "→ Signing"
codesign --force "${SIGNING_FLAGS[@]}" --sign "$IDENTITY" "$OUT/pam_gaze.so"

codesign --verify --strict "$OUT/pam_gaze.so"
if [ "${DIST:-}" = "1" ]; then
	SIGNATURE="$(codesign -dv --verbose=4 "$OUT/pam_gaze.so" 2>&1)"
	printf '%s\n' "$SIGNATURE" | grep -q '^Authority=Developer ID Application: ' || {
		echo "Release signature is not Developer ID Application. Output was not replaced." >&2; exit 1;
	}
	printf '%s\n' "$SIGNATURE" | grep -q '^Timestamp=' || {
		echo "Release signature has no secure timestamp. Output was not replaced." >&2; exit 1;
	}
fi

echo "✓ Built $OUT/pam_gaze.so"
lipo -archs "$OUT/pam_gaze.so"
