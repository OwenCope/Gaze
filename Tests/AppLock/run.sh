#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/Tools/Scripts/toolchain.sh"
require_toolchain
SDK="$(oldest_usable_sdk | awk '{print $1}')"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-app-lock-tests.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
xcrun swiftc -parse-as-library -warnings-as-errors -sdk "$SDK" -target "$(host_target)" \
	"$ROOT/Sources/Security/AppLockStore.swift" \
	"$ROOT/Sources/Security/AppLockStateMachine.swift" \
	"$ROOT/Sources/Security/AppLockWatcher.swift" \
	"$ROOT/Sources/FinderExtension/FinderLockMenu.swift" \
	"$ROOT/Sources/Security/AppLockURLAction.swift" \
	"$ROOT/Tests/AppLock/Tests.swift" \
	-framework AppKit \
	-o "$BUILD/app-lock-tests"
"$BUILD/app-lock-tests"
