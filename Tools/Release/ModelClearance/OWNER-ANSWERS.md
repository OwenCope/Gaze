# Model clearance — owner answers required

All artifacts remain `unresolved`. No licence, grant or permission below is inferred; every grant cell needs the owner's answer. Cite paths and lines for each evidential claim. `credit-portraits` is under parallel audit and is not questioned here.

## What the repository establishes

| Artifact | Established in-repo | Still missing |
|---|---|---|
| `face-embedding` | Precompiled weight bytes match Sapphire at `ee56de09a0c5ab2cbf442858de36780a0cb151b2`; raw package differs; Shariq permission recorded with app/website attribution condition (`Tools/Release/ModelClearance/SHARIQ-PERMISSION-20260918.md`); redistribution scope empty | Q1, Q2 |
| `spoof-detector` | Training script, dataset identity, licence-string locations (see below) | Q1, Q3, Q4 |
| `setup-art` (30 files) | Generator/manifest per file group (see below); byte identity recorded | Q1, Q5 |
| `credit-portraits` | Untouched; parallel audit owns it | — |
| `app-icon` | Script claim vs current bytes mismatch recorded (see below) | Q1, Q6 |
| `legacy-liveness` | Not in the distributed bundle (`build.sh:108-109`) | Q1, Q7 |

Provenance detail now in `clearance.json`: `spoof-detector` consumes the Roboflow Face Spoof Detection v1 CreateML export via `scripts/train_spoof.swift:1-12`, output metadata author `Gaze` version `1.0` (`scripts/train_spoof.swift:53-57`); consumer `Sources/Recognition/SpoofDetector.swift:6-10`; bundling `build.sh:111-124`; training data git-ignored (`.gitignore:27-28,30-32`). Licence string `CC BY 4.0` appears at `scripts/train_spoof.swift:55` and `Tools/ModelLab/README.md:27` (source `https://universe.roboflow.com/mohammeds-workspace-ft3sn/face-spoof-detection-liika`); `Tools/ModelLab/prepare.py:84-85` repeats the licence as stated-in-export with upstream rights unverified. Nothing in the repo establishes that this dataset licence covers redistribution of the trained weights.

`setup-art` additions: `tour-general/notch/unlock/security.png` are cropped Settings photographs from `Tools/ProductCapture/export-tour-shots.py`, manifest `Tools/ProductCapture/tour-shots.json` (manifest `nativeSHA256` values match the recorded bytes); `tour-how-unlock.png` is rendered from app code plus `lockscreen-base.png` by `Tools/OnboardingArt/render-unlock-tour.sh` (`Tools/OnboardingArt/RenderUnlockTour.swift:58-94,100-101`). Git history: four photographs added in `25477a9`, re-exported in `ccb9da0`; `tour-how-unlock.png` added in `002c00e`.

`app-icon`: `scripts/make_icon_mark.swift:1,81-83` claims to write `Resources/AppIcon.icon/Assets/gaze-mark.png` as a white-on-transparent keyhole, but byte-equality with the current file is unverified (script not run here, no output hash recorded), and `Resources/AppIcon.icon/icon.json` names the layer `Smoked glass face`.

`legacy-liveness`: `Resources/Liveness.mlmodelc` is absent from this checkout; `build.sh:108-109` states the legacy texture model is excluded from bundles and no `build.sh` branch copies any Liveness file (cf. `build.sh:94-106`, `build.sh:114-124`).

## Questions

**Q1 (blocks all six artifacts).** List every distribution channel each artifact is cleared for (Mac app bundle, website download, source archive, other?). One list may cover all artifacts if identical, otherwise per artifact. On answer: fill each entry's `license.redistributionScope` (required: `bundled-app-distribution`).

**Q2 (`face-embedding`).** Confirm the grant covering THESE hashes covers the raw `FaceEmbedding.mlpackage` bytes too, or only the Sapphire-matching precompiled weights — and state the upstream (InsightFace-descended?) rights position for the covered bytes. On answer: set `face-embedding` `license.grant`, `license.evidenceRefs`, scope; `clearance` to `cleared` only when all three columns complete.

**Q3 (`spoof-detector`).** Confirm that the dataset terms at the locations above permit redistribution of the trained `Resources/Spoof.mlmodel` weights (`e4037752…76f`) in the app bundle, and state the required attribution. A yes with a licence pointer is sufficient; a separate consent is not automatically required. On answer: set `spoof-detector` `license.grant`, `license.evidenceRefs`, scope; `clearance` to `cleared` when complete.

**Q4 (`spoof-detector`).** Confirm `Resources/Spoof.mlmodel` was produced by running `scripts/train_spoof.swift` against that Roboflow export — yes or no; if yes, point at the training log or run record. The repo records the script and the output but no log binding the two. On answer: append the log pointer to `spoof-detector` `provenance.evidenceRefs`.

**Q5 (`setup-art`, 30 files).** Confirm you created each of the five `tour-general.png`, `tour-how-unlock.png`, `tour-notch.png`, `tour-security.png`, `tour-unlock.png` assets yourself (screenshots/renders of your own machine and app, no third-party content) — yes or no per file; name the source for any no. Same confirmation is still outstanding for the other 25 files. On answer: set `setup-art` `license.grant` (owner confirms first-party), `license.evidenceRefs`, scope; `clearance` to `cleared` when complete.

**Q6 (`app-icon`).** Confirm you authored `Resources/AppIcon.icon/Assets/gaze-mark.png` and `icon.json` as first-party work — yes or no; if the script output differs from the current bytes, state which file is authoritative. On answer: set `app-icon` `provenance.summary`/`evidenceRefs` to the confirmed source, plus `license.grant`, scope; `clearance` to `cleared` when complete.

**Q7 (`legacy-liveness`).** Confirm `Liveness.mlmodelc` is never distributed and should be removed from the clearance gate: either delete the entry or have the validator stop requiring it. This is an owner/validator decision, not a grant; changing `validate.py` is out of remit. On answer: entry deleted or validator updated by the owner; no `clearance.json` grant involved.

## Could not determine and why

- Whether any dataset or upstream licence covers redistribution of trained weights: the repo states the CC BY 4.0 string and its location but contains no sublicensing analysis; only the owner can conclude (Q3).
- Whether `scripts/train_spoof.swift` produced the exact bundled `Spoof.mlmodel` bytes: no training log or output hash exists in the repo (Q4).
- Whether `scripts/make_icon_mark.swift` output equals the current `gaze-mark.png`: script never run here and no output hash recorded; layer-name mismatch noted but not resolved (Q6).
- Authorship of any `Resources/Art` file: generators and manifests identify process and source images, not who ran them or on whose machine (Q5).
- Distribution scope for any artifact: no channel list exists in the repo (Q1).
- `credit-portraits`: deliberately untouched; parallel audit reports separately.
