#!/bin/bash
# Exercise build.sh's actual iris-model staging branch with synthetic assets.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/gaze-iris-model.XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT
python3 - "$REPO/build.sh" "$FIXTURE/stage-iris.sh" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
start = source.index('if [ -d "$ROOT/Resources/IrisLandmarks.mlmodelc" ]; then')
end = source.index('# The unused legacy Liveness', start)
Path(sys.argv[2]).write_text("set -euo pipefail\n" + source[start:end])
PY
mkdir -p "$FIXTURE/bin"
cat > "$FIXTURE/bin/xcrun" <<'SH'
#!/bin/bash
set -euo pipefail
[ "$1" = coremlc ] && [ "$2" = compile ]
[ -f "$3/Data/com.apple.CoreML/model.mlmodel" ] || exit 42
mkdir -p "$4/IrisLandmarks.mlmodelc"
printf 'compiled fixture\n' > "$4/IrisLandmarks.mlmodelc/model"
SH
chmod +x "$FIXTURE/bin/xcrun"
export PATH="$FIXTURE/bin:$PATH"
export ROOT="$FIXTURE/checkout" STAGE="$FIXTURE/stage"
mkdir -p "$ROOT/Resources" "$STAGE/Contents/Resources"
# No model: use the existing pixel fallback.
bash "$FIXTURE/stage-iris.sh" > "$FIXTURE/missing.log"
grep -q 'falls back to pupil detection by pixel' "$FIXTURE/missing.log"
# A fresh clone contains only Manifest.json, not a compilable Core ML payload.
mkdir -p "$ROOT/Resources/IrisLandmarks.mlpackage"
printf '{}\n' > "$ROOT/Resources/IrisLandmarks.mlpackage/Manifest.json"
bash "$FIXTURE/stage-iris.sh" > "$FIXTURE/stub.log"
grep -q 'falls back to pupil detection by pixel' "$FIXTURE/stub.log"
# A source package with actual model data is still compiled.
mkdir -p "$ROOT/Resources/IrisLandmarks.mlpackage/Data/com.apple.CoreML"
printf 'synthetic model\n' > "$ROOT/Resources/IrisLandmarks.mlpackage/Data/com.apple.CoreML/model.mlmodel"
bash "$FIXTURE/stage-iris.sh" > "$FIXTURE/source.log"
grep -q 'compiled fixture' "$STAGE/Contents/Resources/IrisLandmarks.mlmodelc/model"
# Populated but broken packages still fail instead of silently hiding a bad model.
rm "$ROOT/Resources/IrisLandmarks.mlpackage/Data/com.apple.CoreML/model.mlmodel"
if bash "$FIXTURE/stage-iris.sh" > "$FIXTURE/broken.log"; then
 echo 'FAIL: broken populated package was accepted' >&2
 exit 1
fi
# Prebuilt resources retain priority over the source package.
mkdir -p "$ROOT/Resources/IrisLandmarks.mlmodelc"
printf 'prebuilt fixture\n' > "$ROOT/Resources/IrisLandmarks.mlmodelc/model"
rm -rf "$STAGE/Contents/Resources/IrisLandmarks.mlmodelc"
bash "$FIXTURE/stage-iris.sh" > "$FIXTURE/prebuilt.log"
grep -q 'prebuilt fixture' "$STAGE/Contents/Resources/IrisLandmarks.mlmodelc/model"
echo 'PASS: missing/stub iris package fallback, source compilation and prebuilt priority; synthetic models only.'
