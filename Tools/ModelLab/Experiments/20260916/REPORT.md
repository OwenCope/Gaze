# Experiment 20260916 — report

## Outcome: one declared test evaluation, no training run

No new model was trained (justification pre-recorded in
`PREREGISTRATION.md`: 121/121 source subject IDs already partitioned, no
independent split possible; 2,000→3,600 train scaling already failed;
same valid set already used for 4 calibrations). The bounded experiment was
the deferred single test scoring of the frozen ObjectPrint detector with its
frozen validation calibration. No tuning on test; `evaluate.py` re-verified
hashes, pipeline, coverage and calibration/test disjointness.

## Test result (200 images, 100 live / 100 spoof, 12 subjects, cutoff `0.8786042928695679`)

| Candidate | Live rejected (false rejects) | Spoof accepted (false accepts) |
| --- | ---: | ---: |
| ObjectPrint detector 200-iter (this run, **test**) | **8/100** (8.0%, Wilson95 4.1–15.0, cluster 0.0–21.7) | **47/100** (47.0%, Wilson95 37.5–56.7, cluster 26.0–68.3) |
| ScenePrint logistic head, prior (test) | 5/100 (5.0%) | 47/100 (47.0%) |
| Shipped `Spoof.mlmodel` diagnostic (test) | 6/100 (6.0%) | 74/100 (74.0%) |
| ObjectPrint detector (validation, frozen cutoff source) | 5/100 | 41/100 |

Score sanity: non-degenerate — live median 0.0 (84 zeros: no spoof box
found, expected of a negative-cue detector), spoof median 0.91.

## Verdict: unproven, not better — not promoted

The validation edge (41 vs 47–59 spoof-accepts) did **not** generalize:
identical 47/100 attack-accept on test with a numerically worse live-reject
(8 vs 5/100; intervals overlap, so not a proven regression either). All
candidates admit roughly half of attacks at a ~5% live-reject operating
point. **No model or threshold promoted; `releaseApproved: false`;
production `Resources`, thresholds and partitions untouched.**

## Measured size / latency

- Model file: 6,831,190 bytes (~6.5 MiB `.mlmodel`, uncompiled source form),
  SHA-256 `447c5d37…aaa639ec`.
- Scoring: ~3 s wall for 200 images (~15 ms/image mean, 1-s clock
  resolution) on M4 with `computeUnits .all`, run `nice -n 15`. Timing
  diagnostic only — excludes camera, alignment/embedding path, queues and UI
  load; not a lock-screen latency claim.

## Artifacts / provenance

- Inputs (read-only, lead checkout): `build/model-lab-20260913/
  candidate-objectprint/GazeDetector-experimental.mlmodel`,
  `detection-dataset/manifest.json` (`0d2034b4…b010143808`),
  `objectprint-float32-calibration.json`; training record declares
  `testUsedForTraining: false`.
- New (this worktree): `Tools/ModelLab/Experiments/20260916/
  PREREGISTRATION.md`, `run-objectprint-test.sh` (guardrailed single-eval
  runner: hash checks, refuses overwrite, pins calibration — reusable);
  ignored `build/model-lab-20260916/{score-pad,objectprint-test.json,
  objectprint-test-report.json}`.
- Full metric JSON (intervals, limitations, hashes) is in
  `build/model-lab-20260916/objectprint-test-report.json`.

## Limitations (do not re-cite test numbers without these)

Shared twice-examined 200-image test split; 12 unverified source-subject IDs;
frames correlated; dHash audit flags cross-split near-similar pairs
including valid↔test and one train-spoof↔test-spoof (review leads, weaken
held-out claims); attack labels `unspecified`; replay/mask/injection,
lighting, glasses, camera domains untested. Component scores, not system
accept rates. Live-reject point estimate (8%) exceeded the 5% validation
budget — expected selection slippage, and a further reason the frozen cutoff
must not be re-tuned on this split.

Lead tooling corrections: fixed the abbreviated hash, made input paths checkout-relative, created a fresh output directory before compiling, and pinned the frozen calibration SHA-256 (`51bfe97274f2cc861fd4f14daf1b94c8799000487f55c05a44bc02302da32a52`). Syntax/guard checks only; the test split was not scored again.
