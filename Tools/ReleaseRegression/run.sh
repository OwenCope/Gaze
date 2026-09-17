#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/Tools/Release/Signing.sh"
DEV_HASH=1111111111111111111111111111111111111111
RELEASE_HASH=2222222222222222222222222222222222222222
FIXTURE="  1) $DEV_HASH \"Apple Development: Test (TEAM)\"
  2) $RELEASE_HASH \"Developer ID Application: Test (TEAM)\"
     2 valid identities found"
test "$(gaze_signing_identity 0 '' "$FIXTURE")" = "$DEV_HASH"
test "$(gaze_signing_identity 1 '' "$FIXTURE")" = "$RELEASE_HASH"
test "$(gaze_signing_identity 1 "$RELEASE_HASH" "$FIXTURE")" = "$RELEASE_HASH"
test "$(gaze_signing_identity 1 'Developer ID Application: Test (TEAM)' "$FIXTURE")" = "$RELEASE_HASH"
test "$(gaze_signing_identity 0 "$RELEASE_HASH" "$FIXTURE")" = "$RELEASE_HASH"
for requested in '-' "$DEV_HASH" 'Apple Development: Test (TEAM)' missing 'Developer ID Application: Test'; do
	if gaze_signing_identity 1 "$requested" "$FIXTURE" >/dev/null 2>&1; then
		echo "FAIL: invalid release identity accepted" >&2; exit 1
	fi
done
for mode in 0 1; do
	if gaze_signing_identity "$mode" '' '0 valid identities found' >/dev/null 2>&1; then
		echo "FAIL: missing identity accepted" >&2; exit 1
	fi
	if gaze_signing_identity "$mode" '-' "$FIXTURE" >/dev/null 2>&1; then
		echo "FAIL: ad-hoc identity accepted" >&2; exit 1
	fi
done
if gaze_signing_identity 1 '' "1) $DEV_HASH \"Apple Development: Test (TEAM)\"" >/dev/null 2>&1; then
	echo "FAIL: development-only machine accepted for release" >&2; exit 1
fi
node - "$ROOT" <<'NODE'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const source = fs.readFileSync(`${process.argv[2]}/build.sh`, 'utf8');
assert(source.indexOf('gaze_signing_identity ') < source.indexOf('\nrequire_toolchain'));
assert(source.indexOf('gaze_signing_identity ') < source.indexOf('mktemp -d'));
assert(source.includes('DEFAULT_OUTPUT="$ROOT/build/release/Gaze.app"'));
assert(source.includes('SIGNING_FLAGS+=(--timestamp)'));
assert(source.includes('SIGNING_FLAGS=(--options runtime)'));
assert(source.indexOf("'^Authority=Developer ID Application: '") < source.indexOf('mv "$STAGE" "$APP"'));
assert(source.indexOf("'^Timestamp='") < source.indexOf('mv "$STAGE" "$APP"'));
assert(source.includes('codesign --verify --strict -R "=$REFERENCE_REQUIREMENT"'));
console.log('PASS: 23 release identity and build-wiring checks; synthetic identities only.');
NODE
bash "$ROOT/Tools/ReleaseRegression/verify-artifact.sh"
bash "$ROOT/Tools/ReleaseRegression/preflight-checks.sh"
bash "$ROOT/Tools/ReleaseRegression/source-archive.sh"
