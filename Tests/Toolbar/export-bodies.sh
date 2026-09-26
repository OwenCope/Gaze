#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-toolbar-assets.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
xcrun swiftc -parse-as-library "$ROOT/Sources/Companion/GazeCompanionShader.swift" \
	"$ROOT/Tests/Toolbar/ExportBodies.swift" -o "$BUILD/export"
"$BUILD/export" "${1:-$ROOT/Resources/Art}"
