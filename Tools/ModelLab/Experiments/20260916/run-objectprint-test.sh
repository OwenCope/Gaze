#!/bin/bash
# Single declared test evaluation for one frozen PAD candidate.
# Guardrails: refuses to overwrite outputs, re-verifies model/manifest hashes
# against PREREGISTRATION.md before scoring, pins the frozen calibration, and
# performs no tuning on test. Reusable for future candidates by overriding env.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
INPUTS="${MODELLAB_INPUTS:-$REPO_ROOT/build/model-lab-20260913}"
OUT="${MODELLAB_OUT:-$REPO_ROOT/build/model-lab-20260916}"
EXPECTED_MODEL="${EXPECTED_MODEL_SHA:-447c5d371719a808ede3260ad2b0ef6584988b8e0a5513dccca7be81aaa639ec}"
EXPECTED_MANIFEST="${EXPECTED_MANIFEST_SHA:-0d2034b44daf9f86492e7e2f86df9ccabd322ce6776de790ec4d01b010143808}"

MODEL="$INPUTS/candidate-objectprint/GazeDetector-experimental.mlmodel"
DATASET="$INPUTS/detection-dataset"
CALIBRATION="$INPUTS/objectprint-float32-calibration.json"
EXPECTED_CALIBRATION="51bfe97274f2cc861fd4f14daf1b94c8799000487f55c05a44bc02302da32a52"

for path in "$MODEL" "$DATASET/manifest.json" "$CALIBRATION"; do
  [ -e "$path" ] || { echo "missing input: $path" >&2; exit 1; }
done

actual_model="$(shasum -a 256 "$MODEL" | cut -d' ' -f1)"
actual_manifest="$(shasum -a 256 "$DATASET/manifest.json" | cut -d' ' -f1)"
[ "$actual_model" = "$EXPECTED_MODEL" ] || { echo "model hash mismatch" >&2; exit 1; }
[ "$actual_manifest" = "$EXPECTED_MANIFEST" ] || { echo "manifest hash mismatch" >&2; exit 1; }
actual_calibration="$(shasum -a 256 "$CALIBRATION" | cut -d' ' -f1)"
[ "$actual_calibration" = "$EXPECTED_CALIBRATION" ] || { echo "calibration hash mismatch" >&2; exit 1; }
echo "provenance OK: model ${actual_model:0:12} manifest ${actual_manifest:0:12}"

[ -e "$OUT/objectprint-test.json" ] && { echo "refusing: test output exists (one declared evaluation only)" >&2; exit 1; }
[ -e "$OUT/objectprint-test-report.json" ] && { echo "refusing: test report exists" >&2; exit 1; }

mkdir -p "$OUT"

: "${DEVELOPER_DIR:=/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR
SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path --sdk macosx)}"
if [ ! -x "$OUT/score-pad" ]; then
  xcrun swiftc -O -parse-as-library -sdk "$SDKROOT" \
    "$REPO_ROOT/Tools/ModelLab/ModelDataset.swift" "$REPO_ROOT/Tools/ModelLab/Score.swift" \
    -o "$OUT/score-pad"
fi

start="$(date +%s)"
nice -n 15 "$OUT/score-pad" "$DATASET" "$MODEL" detector test "$OUT/objectprint-test.json"
end="$(date +%s)"
echo "scoring wall time: $((end - start))s for 200 test images"

python3 "$REPO_ROOT/Tools/ModelLab/evaluate.py" evaluate \
  "$OUT/objectprint-test.json" "$DATASET/manifest.json" "$OUT/objectprint-test-report.json" \
  --calibration "$CALIBRATION"
echo "saved $OUT/objectprint-test-report.json"
