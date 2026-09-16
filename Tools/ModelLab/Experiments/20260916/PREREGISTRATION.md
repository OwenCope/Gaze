# Experiment 20260916 — pre-registration (written before any test scoring)

## Decision: no new training run

A further bounded transfer-learning run is **not justified** by available
data/provenance. Reasons, all checked read-only against existing inputs:

1. **Subject pool exhausted.** The source export contains 121 distinct
   unambiguous `_id<N>_` subject IDs; all 121 are already partitioned
   (91 train / 18 valid / 12 test). Any new split must reuse subjects, so no
   independent train/valid/test partition can be built from this pool.
2. **Data scaling already tested, no gain.** ScenePrint MLP 2,000 → 3,600
   train images (same subjects): validation spoof-accept 57/100 → 59/100
   at 5/100 live-reject. More frames of the same subjects did not help.
3. **Validation set peeked 4x.** The same 200-image valid split selected the
   larger-logistic, mlp-2000, mlp-3600 and objectprint cutoffs. A fifth
   calibration on it would be selection-overfitting, not evidence.
4. **Capacity direction tested.** 64-unit MLP was worse than logistic on the
   same 2,000 images (57 vs ~equivalent-or-better logistic behaviour class);
   no untried head in scope has a provenance basis.
5. **Remaining variants are thrash.** ObjectPrint iteration-count tweaks or
   logistic-on-3600 change no independent variable the data can resolve.

No new face scraping, licence acceptance, camera, enrollment, Keychain,
upload or paid-compute input is used. CC BY 4.0 local experimental use only;
nothing is redistributed and no model lands in tracked source.

## Bounded experiment instead: deferred declared test evaluation

The frozen ObjectPrint detector candidate (best validation result, never
test-scored) gets its **single declared test evaluation** with its frozen
calibration. No parameter changes on any outcome.

- Candidate: `GazeDetector-experimental.mlmodel` (Apple ObjectPrint rev 1,
  200 iterations; train 3,600 / valid 200; `testUsedForTraining: false`)
  - modelSHA256 `447c5d371719a808ede3260ad2b0ef6584988b8e0a5513dccca7be81aaa639ec`
- Dataset: detection-dataset `manifest.json`
  - manifestSHA256 `0d2034b44daf9f86492e7e2f86df9ccabd322ce6776de790ec4d01b010143808`
  - test split: 200 images (100 live / 100 spoof), 12 source subjects,
    zero ID and zero subject overlap with the 200 calibration IDs / 18
    calibration subjects (verified 2026-09-16 before scoring)
- Calibration (frozen, valid only, 5% live-reject budget):
  `objectprint-float32-calibration.json`,
  threshold `0.8786042928695679` (IEEE-754 binary32),
  pipeline `vision_detector_fullframe_scaleFill_up_v1`
- Procedure: one `score-pad … detector test` run → `evaluate.py evaluate
  --calibration`. `evaluate.py` independently re-verifies hashes, pipeline,
  coverage and calibration/test disjointness, and refuses overwrite.
- Pre-declared reporting: bonaFideRejected (false rejects) and
  attacksAccepted (false accepts) with intervals, plus measured model size
  and scoring wall-time. Verdict scale only: worse / unproven / needs-more-evidence.
  No promotion, no threshold change, no spoof-resistance claim.

## Known limitations (carried into the report)

- Shared, twice-examined test split (larger candidate + shipped diagnostic);
  12 source subjects; frames correlated.
- Duplicate audit (routine dHash, known false positives) flags 8 cross-split
  near-similar pairs, several valid↔test and one train-spoof↔test-spoof;
  review leads, not proven leakage — but they weaken held-out claims.
- Source subject IDs unverified as distinct people; attack labels
  `unspecified`; photo/video replay, masks, injection, lighting, glasses and
  camera domains untested. Offline component scores, not system accept rates.
