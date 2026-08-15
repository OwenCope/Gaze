#!/bin/bash
# Builds PanelTest.app — shows the plugin's SecurityAgent panel without touching the
# lock screen. See PanelTest/main.swift for why this is needed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=../toolchain.sh
. "$ROOT/../toolchain.sh"
require_toolchain
APP="$ROOT/build/PanelTest.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>PanelTest</string>
	<key>CFBundleExecutable</key><string>PanelTest</string>
	<key>CFBundleIdentifier</key><string>com.gazeunlock.Gaze.paneltest</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>LSMinimumSystemVersion</key><string>26.0</string>
</dict>
</plist>
PLIST

SDK="$(xcrun --show-sdk-path --sdk macosx)"
xcrun swiftc \
	-O \
	-target "$(host_target)" \
	-sdk "$SDK" \
	-framework AppKit \
	-framework Security \
	"$ROOT/PanelTest/main.swift" \
	-o "$APP/Contents/MacOS/PanelTest"

IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
	| awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')"
[ -n "$IDENTITY" ] || IDENTITY="-"
codesign --force --sign "$IDENTITY" --identifier com.gazeunlock.Gaze.paneltest "$APP"

echo "✓ Built $APP"
echo
echo "  Install the plugin first:  sudo ./test-plugin.sh"
echo "  Then run:                  open '$APP'"
echo
echo "  Expect the SecurityAgent panel with the capsule. Look away so the face fails,"
echo "  then type your password into the field. That is the path the lock screen depends"
echo "  on and the only part still untested."
