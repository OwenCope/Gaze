#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/gaze-release-fixture.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
APP="$SCRATCH/Gaze.app"
BIN="$SCRATCH/bin"
mkdir -p "$BIN" "$APP/Contents/MacOS" "$APP/Contents/Resources/FaceEmbedding.mlmodelc" "$APP/Contents/Resources/Spoof.mlmodelc"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
printf 'synthetic fixture; never execute\n' > "$APP/Contents/MacOS/Gaze"
chmod +x "$APP/Contents/MacOS/Gaze"
cp "$ROOT/Resources/Gaze.entitlements" "$SCRATCH/entitlements.plist"
export GAZE_TEST_ENTITLEMENTS="$SCRATCH/entitlements.plist"
cat > "$BIN/codesign" <<'MOCK'
#!/bin/bash
case "$1" in
	--verify)
		case "$*" in *'anchor apple generic'*) ;; *) exit 91 ;; esac
		test "${GAZE_TEST_FAILURE:-}" != signature ;;
	-dv)
		if [ "${GAZE_TEST_FAILURE:-}" = adhoc ]; then
			echo 'Signature=adhoc' >&2
		else
			if [ "${GAZE_TEST_FAILURE:-}" = app-id ]; then
				echo 'Identifier=wrong.fixture' >&2
			else
				echo 'Identifier=com.gazeunlock.Gaze' >&2
			fi
			if [ "${GAZE_TEST_FAILURE:-}" = authority ]; then
				echo 'Authority=Apple Development: Fixture' >&2
			else
				echo 'Authority=Developer ID Application: Fixture' >&2
			fi
			if [ "${GAZE_TEST_FAILURE:-}" = team ]; then
				echo 'TeamIdentifier=WRONG' >&2
			else
				echo 'TeamIdentifier=CAAVJCSL92' >&2
			fi
		fi
		[ "${GAZE_TEST_FAILURE:-}" = timestamp ] || echo 'Timestamp=Fixture' >&2
		[ "${GAZE_TEST_FAILURE:-}" = runtime ] || echo 'CodeDirectory flags=0x10000(runtime)' >&2
		exit 0 ;;
	-d) cat "$GAZE_TEST_ENTITLEMENTS" ;;
	*) exit 90 ;;
esac
MOCK
cat > "$BIN/xcrun" <<'MOCK'
#!/bin/bash
test "$1" = stapler && test "$2" = validate && test "${GAZE_TEST_FAILURE:-}" != stapler
MOCK
cat > "$BIN/spctl" <<'MOCK'
#!/bin/bash
test "$1" = --assess && test "${GAZE_TEST_FAILURE:-}" != gatekeeper
MOCK
cat > "$BIN/lipo" <<'MOCK'
#!/bin/bash
test "$1" = -archs && echo arm64
MOCK
chmod +x "$BIN/"*
export PATH="$BIN:$PATH"
COUNT=0
check() {
	local expected="$1" marker="$2" actual=0
	bash "$ROOT/Tools/Release/verify.sh" "$APP" > "$SCRATCH/output" 2>&1 || actual=$?
	if [ "$expected" = pass ]; then
		test "$actual" = 0 || { cat "$SCRATCH/output"; exit 1; }
	else
		test "$actual" != 0 || { echo "FAIL: unsafe fixture passed" >&2; exit 1; }
	fi
	grep -Fq "$marker" "$SCRATCH/output" || { cat "$SCRATCH/output"; exit 1; }
	COUNT=$((COUNT + 1))
}
check pass 'artifact validation, NOT proof'
check pass 'Team: CAAVJCSL92'
for failure in signature authority timestamp runtime stapler gatekeeper; do
	export GAZE_TEST_FAILURE="$failure"
	check fail 'FAIL:'
done
export GAZE_TEST_FAILURE=app-id
check fail 'Signed app identifier mismatch'
export GAZE_TEST_FAILURE=team
check fail 'No valid signing team'
export GAZE_TEST_FAILURE=adhoc
check fail 'No signing authority'
export GAZE_TEST_FAILURE=authority
check fail 'Developer ID Application signature required'
unset GAZE_TEST_FAILURE
for entitlement in get-task-allow cs.allow-jit cs.disable-library-validation cs.allow-dyld-environment-variables cs.allow-unsigned-executable-memory cs.disable-executable-page-protection; do
	/usr/libexec/PlistBuddy -c "Add :com.apple.security.$entitlement bool true" "$GAZE_TEST_ENTITLEMENTS"
	check fail 'Unsafe release entitlement'
	/usr/libexec/PlistBuddy -c "Delete :com.apple.security.$entitlement" "$GAZE_TEST_ENTITLEMENTS"
done
/usr/libexec/PlistBuddy -c 'Set :com.apple.security.device.camera false' "$GAZE_TEST_ENTITLEMENTS"
check fail 'Camera entitlement missing'
/usr/libexec/PlistBuddy -c 'Set :com.apple.security.device.camera true' "$GAZE_TEST_ENTITLEMENTS"
printf 'invalid plist' > "$GAZE_TEST_ENTITLEMENTS"
check fail 'Camera entitlement missing'
cp "$ROOT/Resources/Gaze.entitlements" "$GAZE_TEST_ENTITLEMENTS"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier example.invalid.fixture' "$APP/Contents/Info.plist"
check fail 'Unexpected bundle identifier'
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable GazeHelper' "$APP/Contents/Info.plist"
check fail 'Unexpected executable'
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
mv "$APP/Contents/PkgInfo" "$SCRATCH/PkgInfo"
check fail 'Bundle PkgInfo missing'
mv "$SCRATCH/PkgInfo" "$APP/Contents/PkgInfo"
/usr/libexec/PlistBuddy -c 'Delete :NSCameraUsageDescription' "$APP/Contents/Info.plist"
check fail 'Info.plist key NSCameraUsageDescription missing'
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
for model in FaceEmbedding Spoof; do
	mv "$APP/Contents/Resources/$model.mlmodelc" "$SCRATCH/$model.mlmodelc"
	check fail "Required $model model missing"
	mv "$SCRATCH/$model.mlmodelc" "$APP/Contents/Resources/$model.mlmodelc"
done
chmod -x "$APP/Contents/MacOS/Gaze"
check fail 'Gaze executable missing'
chmod +x "$APP/Contents/MacOS/Gaze"
mv "$APP/Contents/Info.plist" "$SCRATCH/Info.plist"
check fail 'Bundle Info.plist missing'
mv "$SCRATCH/Info.plist" "$APP/Contents/Info.plist"
check pass 'Architecture: arm64'
echo "PASS: $COUNT artifact-verifier checks; synthetic bundle, mocked signing/notarization tools, no network or app launch."
