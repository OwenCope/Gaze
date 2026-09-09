#!/bin/bash
# Builds pam_gaze.so — the PAM module that lets `sudo` accept your face.
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
	"$ROOT/pam_gaze.c" "$ROOT/PeerTrust.c" \
	-I"$ROOT" \
	-framework Security -framework CoreFoundation \
	-lpam

echo "→ Signing"
# Ad-hoc is fine and is what the rest of this project uses. PAM does not verify the
# module's signature — the file is root-owned in a root-owned directory, and that is what
# protects it. Signing anyway so the binary is not unsigned on disk.
codesign --force --sign - "$OUT/pam_gaze.so"

echo "✓ Built $OUT/pam_gaze.so"
lipo -archs "$OUT/pam_gaze.so"
