#!/bin/bash
set -euo pipefail
PROJECT="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$PROJECT/../.." && pwd)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gaze-vault-persistence-tests.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
source "$ROOT/toolchain.sh"
require_toolchain
xcrun swiftc -parse-as-library -warnings-as-errors \
  "$ROOT/Sources/Browser/BrowserProtocol.swift" \
  "$PROJECT/Live/VaultRecord.swift" "$PROJECT/Live/LocalPasswordStore.swift" \
  "$PROJECT/Live/VerificationCode.swift" "$PROJECT/Live/PasswordCSVImport.swift" \
  "$PROJECT/Live/KeychainPasswordVault.swift" "$PROJECT/Tests/VaultPersistenceTests.swift" -o "$BUILD/tests"
"$BUILD/tests"
