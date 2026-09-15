#!/bin/bash
set -euo pipefail
PROJECT="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$PROJECT/../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-status-test.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
source "$ROOT/toolchain.sh"
require_toolchain
source "$ROOT/Tools/Release/Signing.sh"
FLAGS=(-parse-as-library -warnings-as-errors)
PROBE_ID=com.gazeunlock.Passwords
case "${1:---gaze}" in
  --gaze) ;;
  --passwords) FLAGS+=(-D PASSWORDS_STATUS); PROBE_ID=com.gazeunlock.Passwords.BrowserBridge ;;
  *) echo 'Usage: test-gaze-status.sh [--gaze|--passwords]' >&2; exit 2 ;;
esac
xcrun swiftc \
  "${FLAGS[@]}" \
  "$ROOT/Sources/Browser/BrowserProtocol.swift" "$ROOT/Sources/Browser/BrowserSocket.swift" \
  "$ROOT/Sources/Browser/BrowserPeerTrust.swift" "$ROOT/Sources/Browser/BrowserAppLocator.swift" \
  "$PROJECT/Tests/GazeStatusProbe.swift" -o "$BUILD/status-probe"
codesign --verify --deep --strict "$ROOT/build/Gaze.app"
codesign -d --extract-certificates="$BUILD/gaze-cert" "$ROOT/build/Gaze.app" >/dev/null 2>&1
CERTIFICATE="$(shasum -a 1 "$BUILD/gaze-cert0" | awk '{print toupper($1)}')"
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null)"
IDENTITY="$(gaze_signing_identity 0 "${GAZE_SIGNING_IDENTITY:-$CERTIFICATE}" "$IDENTITIES")"
codesign --force --options runtime --sign "$IDENTITY" --identifier "$PROBE_ID" "$BUILD/status-probe"
"$BUILD/status-probe"
