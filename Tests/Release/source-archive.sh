#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/gaze-source-archive.XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/bin" "$FIXTURE/Resources" "$FIXTURE/Sources/Recognition" "$FIXTURE/Tools/Scripts"
cp "$ROOT/Tools/Scripts/source-archive.sh" "$FIXTURE/Tools/Scripts/source-archive.sh"
cp "$ROOT/Resources/Info.plist" "$FIXTURE/Resources/Info.plist"
printf 'Synthetic notice\n' > "$FIXTURE/NOTICE.md"
printf '// Required crop constant stays in source\n' > "$FIXTURE/Sources/Recognition/LivenessDetector.swift"
for model in FaceEmbedding.mlpackage Liveness.mlmodelc Liveness.mlpackage; do
    mkdir -p "$FIXTURE/Resources/$model/weights"
    printf 'fixture weights, not a model\n' > "$FIXTURE/Resources/$model/weights/test.bin"
done
cat > "$FIXTURE/bin/git" <<'SH'
#!/bin/bash
test "$1" = -C && test "$3" = ls-files || exit 1
printf '%s\n' 'NOTICE.md' 'Resources/Info.plist' 'Sources/Recognition/LivenessDetector.swift' \
    'Resources/FaceEmbedding.mlpackage/weights/test.bin' \
    'Resources/Liveness.mlmodelc/weights/test.bin' 'Resources/Liveness.mlpackage/weights/test.bin'
SH
chmod +x "$FIXTURE/bin/git"
PATH="$FIXTURE/bin:$PATH" bash "$FIXTURE/Tools/Scripts/source-archive.sh" > "$FIXTURE/output.log"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$FIXTURE/Resources/Info.plist")"
unzip -Z1 "$FIXTURE/build/Gaze-$VERSION-source.zip" > "$FIXTURE/contents.txt"
grep -qx 'Sources/Recognition/LivenessDetector.swift' "$FIXTURE/contents.txt"
if grep -Eq 'Resources/(FaceEmbedding\.mlpackage|Liveness\.mlmodelc|Liveness\.mlpackage)/' "$FIXTURE/contents.txt"; then
    echo 'FAIL: excluded model payload entered the source archive' >&2
    exit 1
fi
echo 'PASS: source archive excludes raw/compiled legacy weights and retains the Swift source; synthetic files only.'
