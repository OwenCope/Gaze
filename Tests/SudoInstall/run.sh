#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-sudo-install-tests.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
xcrun swiftc -parse-as-library -warnings-as-errors \
	"$ROOT/Sources/Security/SudoInstallScript.swift" \
	"$ROOT/Tests/SudoInstall/SudoInstallScriptTests.swift" \
	-o "$BUILD/sudo-install-tests"
"$BUILD/sudo-install-tests"
