#!/bin/bash
# Settings search regression: compiles the real Sources/App/SettingsSearch.swift
# with the pure-Swift contract checks beside it, then runs them.
#
# Nothing here launches the app or touches preferences, Keychain, camera,
# enrolment or security state. The SwiftUI integration (SettingsView) is
# verified separately by type-checking the full main-app sources.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-settings-search-tests.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -parse-as-library \
	"$ROOT/Sources/App/SettingsSearch.swift" \
	"$ROOT/Tools/SettingsSearchRegression/SettingsSearchTests.swift" \
	-o "$BUILD/settings-search-tests"
"$BUILD/settings-search-tests"
