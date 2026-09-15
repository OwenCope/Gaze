#!/bin/bash
set -euo pipefail
PROJECT="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$PROJECT/../.." && pwd)"
source "$ROOT/toolchain.sh"
require_toolchain
for test in test-browser.sh test-native-bridge.sh test-native-session.sh test-browser-save.sh test-browser-fill.sh test-browser-setup.sh \
  test-icons.sh test-unlock.sh test-navigation.sh test-removal.sh test-verification-code.sh test-import.sh test-vault-persistence.sh; do
  printf '\n=== %s ===\n' "$test"
  bash "$PROJECT/$test"
done
printf '\n=== Production password-entry hold ===\n'
bash "$ROOT/Tools/LockScreenSecurityRegression/test-production-hold.sh"
bash "$ROOT/Tools/LockScreenSecurityRegression/run.sh"
printf '\nOffline regression suite passed. No real vault, browser installation, camera capture, network fixtures or password posting was used.\n'
