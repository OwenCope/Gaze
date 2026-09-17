# Gaze Model Lab — offline, experimental

This toolchain prepares a separate public-data experiment, trains a supplementary presentation-attack classifier, freezes calibration on validation data, and evaluates untouched test examples. Nothing is installed into Gaze. It does not use the webcam, enrolled faceprints, the password vault, or any network service.

## Reproduce

Run from the FaceID repository with a compatible macOS SDK selected as `SDKROOT`:

```sh
python3 Tools/ModelLab/prepare.py Data/spoof-detection build/my-pad-data --train-per-class 1000
xcrun swiftc -O -parse-as-library -sdk "$SDKROOT" Tools/ModelLab/ModelDataset.swift Tools/ModelLab/Train.swift -o build/train-pad
xcrun swiftc -O -parse-as-library -sdk "$SDKROOT" Tools/ModelLab/ModelDataset.swift Tools/ModelLab/Score.swift -o build/score-pad
build/train-pad build/my-pad-data build/my-pad-candidate
build/score-pad build/my-pad-data build/my-pad-candidate/GazePAD-experimental.mlmodel classifier valid build/my-pad-valid.json
python3 Tools/ModelLab/evaluate.py calibrate build/my-pad-valid.json build/my-pad-data/manifest.json build/my-pad-calibration.json
build/score-pad build/my-pad-data build/my-pad-candidate/GazePAD-experimental.mlmodel classifier test build/my-pad-test.json
python3 Tools/ModelLab/evaluate.py evaluate build/my-pad-test.json build/my-pad-data/manifest.json build/my-pad-report.json --calibration build/my-pad-calibration.json
python3 -m unittest discover -s Tools/ModelLab -p 'test_*.py' -v
```

All output paths must be new. The trainer checks file hashes and subject partitioning before fitting. Training uses Apple's ScenePrint revision 1 with a locally trained logistic-regression head: **transfer learning, not a new facial-recognition foundation model**. Test images are not training or calibration input. Reading their hashes for integrity does not use their predictions to fit the model.

The shipped detector can be scored with `detector` instead of `classifier`, using `Resources/Spoof.mlmodel`, then evaluated at the existing `0.65` cutoff. Its scoring adapter intentionally follows production: the highest top-label detection for class `1`, with zero when no spoof detection exists. This is a negative-cue detector; lack of a detection does not prove liveness.

## Dataset controls and limits

- The existing export identifies itself as Roboflow Face Spoof Detection v1 and states CC BY 4.0. Its source is `https://universe.roboflow.com/mohammeds-workspace-ft3sn/face-spoof-detection-liika`. Upstream consent, class semantics, and sublicensing rights still need independent review before redistribution.
- Only unambiguous live/spoof-labelled records with a source `_id<number>_` subject identifier are eligible. Unknown subject IDs and mixed-label scenes are excluded rather than guessed.
- Source subject identifiers are grouped across the original train/validation/test folders before a deterministic new partition. Equal numeric IDs are conservatively grouped together across sources. Distinct IDs are **not proof of distinct people**. Session, capture-device, and attack-modality annotations are inadequate for certification.
- Selected image bytes are hashed. Duplicated content across splits or labels aborts preparation. Preparation itself is not perceptual near-duplicate detection; the separate audit below checks decoded pixels and visual similarity.
- Validation determines a threshold under a 5% live-rejection budget. If none exists, calibration fails instead of relaxing that budget. The frozen record binds model and manifest hashes and forbids overlapping test IDs or source subjects.
- Evaluations require complete manifest coverage, both classes, finite scores, consistent labels, and independent source-subject partitions. Failed inference aborts the run rather than disappearing from the denominator.
- Reports include error counts, rates, approximate independent-trial Wilson intervals, and deterministic subject-cluster bootstrap intervals. Frames from the same subject/session are correlated. Neither a zero-error bootstrap interval nor a small image count establishes a low security failure rate.

## September 13, 2026 experiments

Local outputs: `build/model-lab-20260913/` (not app resources).

| Experiment | Training | Calibration | Test | Outcome |
| --- | ---: | ---: | ---: | --- |
| Initial ScenePrint head | 500 images | 200 images | Not used | No feasible threshold at 5% live rejection; rejected before test |
| Larger ScenePrint head | 2,000 images, 91 source IDs | 200 images, 18 source IDs | 200 images, 12 source IDs | 5/100 live rejected; 47/100 spoof accepted |
| Shipped detector | Previously trained; provenance overlap possible | Existing cutoff, not retuned | Same 200 selected test images | 6/100 live rejected; 74/100 spoof accepted |

The larger candidate's threshold was frozen at `0.8740573525428773` before its test scores were generated. Model SHA-256: `00b6e286e60c720171d71f57de900f406ed027e34729ed146581fab3d5f7f4c7`. Dataset manifest SHA-256: `a79abb159931dc6dc22fd9e2acb61aadcf61e1f4e04ce9eba039ec508f5baeb6`.

This is a promising **component-level** change, not an acceptable authentication model. Almost half the attack images still pass at the selected cutoff. The shipped model may have seen these images in its earlier training; its row is a diagnostic, not an independent benchmark. Neither row measures the full recognition + movement + unlock pipeline. **No model or threshold was promoted.**

## Follow-up experiments and provenance

The following candidates used the same 200 validation images, with thresholds selected under the same 5% live-rejection budget. These are **validation results, not held-out test results**. Repeated experiments against one validation set can overfit that set. The new candidates have not been scored on the test split and none is approved for release.

| Candidate | Training images | Live rejected on validation | Spoof accepted on validation |
| --- | ---: | ---: | ---: |
| ScenePrint + 64-unit MLP, 60 iterations | 2,000 | 5/100 | 57/100 |
| ScenePrint + 64-unit MLP, 60 iterations | 3,600 | 5/100 | 59/100 |
| ObjectPrint detector, 200 iterations | 3,600 | 5/100 | 41/100 |

The expanded manifest retains the previous validation/test images and source-subject partitions. More training images did not improve the MLP result. The ObjectPrint result is better on this validation set but still admits far too many attacks. Do not adopt it by copying its weights or changing the live threshold.

`Train.swift` accepts an optional final `logistic` (default) or `mlp` argument. `prepare_detection.py` creates a new detection dataset from existing source box annotations, checking labels, geometry, file integrity, complete coverage and both classes in every partition. It keeps the chosen partitions and binds annotation hashes in the new manifest. `TrainDetector.swift` verifies those annotations and trains an experimental ObjectPrint head using train/validation only:

```sh
python3 Tools/ModelLab/prepare_detection.py Data/spoof-detection build/my-pad-data build/my-detection-data
xcrun swiftc -O -parse-as-library -sdk "$SDKROOT" Tools/ModelLab/ModelDataset.swift Tools/ModelLab/TrainDetector.swift -o build/train-detector
build/train-detector build/my-detection-data build/my-detector-candidate
build/score-pad build/my-detection-data build/my-detector-candidate/GazeDetector-experimental.mlmodel detector valid build/my-detector-valid.json
python3 Tools/ModelLab/evaluate.py calibrate build/my-detector-valid.json build/my-detection-data/manifest.json build/my-detector-calibration.json
```

The locally generated detector has SHA-256 `447c5d371719a808ede3260ad2b0ef6584988b8e0a5513dccca7be81aaa639ec`; its manifest is `0d2034b44daf9f86492e7e2f86df9ccabd322ce6776de790ec4d01b010143808` and its binary32 validation cutoff is `0.8786042928695679`. Training records, calibration and metrics are in `build/model-lab-20260913/`. Apple feature extractors are reused: these are not newly trained foundation models.

New score reports bind the inference adapter as `scoringPipeline`. Calibration refuses a different adapter, model, manifest, overlapping subjects, incomplete coverage or altered attack labels. Historical reports without this field are marked `legacy-unspecified`; they cannot be combined with a specifically identified adapter. Reports require proper SHA-256 provenance, not arbitrary nonempty labels.

PAD scores and new cutoffs must be exactly representable as IEEE-754 binary32, matching Swift `Float`. The earlier Python-double `nextafter` cutoffs rounded downward when converted to `Float`: for the expanded MLP and ObjectPrint experiments, that would have changed five live rejects to six. New `*-float32-calibration.json` files preserve the same validation decisions after conversion; they do not modify production cutoffs. Older calibration files remain for historical evidence, but `--calibration` now rejects records without the explicit binary32 contract. Recalibrate the original validation scores into a new file rather than silently rounding an existing record or tuning on test data. The regression suite covers this boundary with 1,000 generated values and actual model-score precision checks.

## Duplicate audit and latency

`audit.py` checks selected file integrity, exact decoded pixels and a bounded 64-bit difference-hash neighborhood. `preview_audit.py` produces a local contact sheet from a hash-verified audit. Neither tool deletes images, changes partitions, identifies people or promotes a model.

```sh
python3 Tools/ModelLab/audit.py build/my-pad-data build/my-pad-audit.json
python3 Tools/ModelLab/preview_audit.py build/my-pad-data build/my-pad-audit.json build/my-pad-audit.png
bash Tools/ModelLab/benchmark.sh build/my-pad-data build/my-pipeline-latency.json
```

The 2,400-image audit found no identical decoded-pixel pair but flagged 1,587 near-similar pairs: eight cross-split and 1,583 with differing live/spoof labels, with overlap between those categories. Visual inspection found difference-hash false positives, so these are review leads, not proven identity leakage. Live/replay pairs of a similar scene are also expected to share appearance. Independently verified subject/session labels are still missing.

The isolated pipeline benchmark reuses production face alignment, embedding and PAD on public still images, without a camera or saved embeddings. On this Mac, 117 of 120 ordered validation images were evaluated; two failed measurement validation and one failed the existing blur gate. Detection + embedding + PAD took median 43.48 ms, p95 61.39 ms and maximum 481.20 ms, including cold-start inference. This is a timing diagnostic, not a balanced accuracy study or live lock-screen latency: it excludes camera delivery, event queues and competing UI load. The report lists those limits and remains `releaseApproved: false`.

## Recognition evaluation

The metrics tool also accepts `kind: recognition`, `scoreDirection: higher_is_match`, and `genuine`/`impostor` trial labels, with a predeclared threshold such as the current `0.45`. Supply a manifest of the same trials and split/subject metadata. It reports false accepts and false rejects separately. This is a scorer, not an image/embedding exporter or a camera collector.

No genuine recognition accuracy number was measured in this pass: there is no verified consented multi-person recognition benchmark available here. Build one with enrollment/probe separation, independently verified identities, separate sessions/devices, glasses/lighting/head poses, and targeted lookalikes. Calibration identities must not overlap evaluation identities. A qualified review should pre-register operating-point and sample-size requirements before collecting results.

## Promotion requirements

Keep candidates outside `Resources`. Verify data and weight licensing; evaluate photo and video replay, injected cameras, masks, domain shift and capture failures; measure the complete unlock system using consenting testers; review fairness and reliability by relevant conditions; independently audit password release and input races. Only then consider a separately reviewed signed model update with embedding-version migration where applicable. MIT application code does not automatically license third-party model weights.
