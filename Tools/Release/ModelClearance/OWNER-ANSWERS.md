# Model clearance — owner answers required

`app-icon` is `cleared`; `legacy-liveness` is removed from the gate; the remaining artifacts stay `unresolved`. No licence, grant or permission below is inferred; every grant cell needs the owner's answer. Cite paths and lines for each evidential claim. `credit-portraits` is under parallel audit and is not questioned here.

## What the repository establishes

| Artifact | Established in-repo | Still missing |
|---|---|---|
| `face-embedding` | Precompiled weight bytes match Sapphire at `ee56de09a0c5ab2cbf442858de36780a0cb151b2`; raw package differs; Shariq permission recorded with app/website attribution condition (`Tools/Release/ModelClearance/SHARIQ-PERMISSION-20260918.md`); scope recorded per owner 2026-09-20 (`bundled-app-distribution`, `website-download`; source archive excluded) | Q2 |
| `spoof-detector` | Training script, dataset identity, licence statement (`Data/spoof-detection/README.dataset.txt`, git-ignored local artifact, quoted into `clearance.json`); owner confirmed 2026-09-20 they trained the model via `scripts/train_spoof.swift` and the CC BY 4.0 terms cover the trained weights with `NOTICE.md` attribution; scope recorded per owner 2026-09-20 (`bundled-app-distribution`, `website-download`; source archive excluded) | — |
| `setup-art` (30 files) | Generator/manifest per file group (see below); byte identity recorded; owner confirmed 2026-09-20 first-party authorship of five tour files (see Q5); scope recorded per owner 2026-09-20 | Q5 (other 25 files) |
| `credit-portraits` | Untouched; parallel audit owns it; scope recorded per owner 2026-09-20 | — |
| `app-icon` | Owner confirmed 2026-09-20 first-party authorship of both files (authoritative); script claim vs current bytes mismatch retained as unverified (see below); scope recorded; `cleared` | — |
| `legacy-liveness` | Removed from the gate per owner 2026-09-20; never distributed (`build.sh:108-109`) | — |

Provenance detail now in `clearance.json`: `spoof-detector` consumes the Roboflow Face Spoof Detection v1 CreateML export via `scripts/train_spoof.swift:1-12`, output metadata author `Gaze` version `1.0` (`scripts/train_spoof.swift:53-57`); consumer `Sources/Recognition/SpoofDetector.swift:6-10`; bundling `build.sh:111-124`; training data git-ignored (`.gitignore:27-28,30-32`). Licence string `CC BY 4.0` appears at `scripts/train_spoof.swift:55` and `Tools/ModelLab/README.md:27` (source `https://universe.roboflow.com/mohammeds-workspace-ft3sn/face-spoof-detection-liika`); `Tools/ModelLab/prepare.py:84-85` repeats the licence as stated-in-export with upstream rights unverified. Nothing in the repo establishes that this dataset licence covers redistribution of the trained weights. The dataset's own licence statement lives in `Data/spoof-detection/README.dataset.txt` — a git-ignored local artifact on the owner's machine (`.gitignore` `/Data/*`), quoted verbatim into `clearance.json` `spoof-detector` `license.evidenceRefs` so the record stands without it.

`setup-art` additions: `tour-general/notch/unlock/security.png` are cropped Settings photographs from `Tools/ProductCapture/export-tour-shots.py`, manifest `Tools/ProductCapture/tour-shots.json` (manifest `nativeSHA256` values match the recorded bytes); `tour-how-unlock.png` is rendered from app code plus `lockscreen-base.png` by `Tools/OnboardingArt/render-unlock-tour.sh` (`Tools/OnboardingArt/RenderUnlockTour.swift:58-94,100-101`). Git history: four photographs added in `25477a9`, re-exported in `ccb9da0`; `tour-how-unlock.png` added in `002c00e`.

`app-icon`: `scripts/make_icon_mark.swift:1,81-83` claims to write `Resources/AppIcon.icon/Assets/gaze-mark.png` as a white-on-transparent keyhole, but byte-equality with the current file is unverified (script not run here, no output hash recorded), and `Resources/AppIcon.icon/icon.json` names the layer `Smoked glass face`.

`legacy-liveness`: `Resources/Liveness.mlmodelc` is absent from this checkout; `build.sh:108-109` states the legacy texture model is excluded from bundles and no `build.sh` branch copies any Liveness file (cf. `build.sh:94-106`, `build.sh:114-124`).

## Questions

**Q1 (blocked all six artifacts) — answered 2026-09-20.** Answer: cleared for the Mac app bundle and for website download from gazeunlock.com; NOT cleared for a source archive. One list covers all artifacts. Recorded in each remaining entry's `license.redistributionScope` as `bundled-app-distribution` plus `website-download`.

**Q2 (`face-embedding`).** Confirm the grant covering THESE hashes covers the raw `FaceEmbedding.mlpackage` bytes too, or only the Sapphire-matching precompiled weights — and state the upstream (InsightFace-descended?) rights position for the covered bytes. On answer: set `face-embedding` `license.grant`, `license.evidenceRefs`, scope; `clearance` to `cleared` only when all three columns complete.

**Q3 (`spoof-detector`) — answered 2026-09-20.** Answer: yes — owner confirms the CC BY 4.0 dataset terms permit redistribution of the trained `Resources/Spoof.mlmodel` weights (`e4037752…76f`) in the app bundle; required attribution is the `NOTICE.md` `The spoof-detection training data` section (dataset name, workspace URL, CC BY 4.0 with licence link). Evidence: `Data/spoof-detection/README.dataset.txt` supplies the licence statement (`# Face Spoof Detection > 2026-03-10 6:12am`, `https://universe.roboflow.com/mohammeds-workspace-ft3sn/face-spoof-detection-liika`, `Provided by a Roboflow user`, `License: CC BY 4.0`) and is git-ignored (`.gitignore` `/Data/*`), so the statement is quoted verbatim into `clearance.json`; `Data/spoof-detection/README.roboflow.txt` records the 19 August 2026 export and 30,351 images. Recorded as `spoof-detector` `license.grant` with scope; `clearance` set to `cleared`.

**Q4 (`spoof-detector`) — answered 2026-09-20.** Answer: yes — owner confirms `Resources/Spoof.mlmodel` was produced by running `scripts/train_spoof.swift` against that Roboflow export; they trained it themselves. No training log or run record exists, so none is pointed at — recorded as such in `spoof-detector` `provenance.evidenceRefs` alongside the owner confirmation, the dataset identity and the script path.

**Q5 (`setup-art`, 30 files) — answered 2026-09-20 (five files; other 25 still open).** Answer: yes for all five — owner confirms they created `tour-general.png`, `tour-how-unlock.png`, `tour-notch.png`, `tour-security.png` and `tour-unlock.png` themselves (screenshots/renders of their own machine and app, no third-party content). Same confirmation is still outstanding for the other 25 files, so the entry stays `unresolved`; the five confirmations are recorded in its provenance.

**Q6 (`app-icon`) — answered 2026-09-20.** Answer: yes — owner confirms `Resources/AppIcon.icon/Assets/gaze-mark.png` and `Resources/AppIcon.icon/icon.json` are their own first-party work; the confirmation is authoritative. The owner did not claim the bytes came from `scripts/make_icon_mark.swift`, so the script-vs-bytes discrepancy stays recorded as unverified. Recorded as `license.grant` with scope; `clearance` set to `cleared`.

**Q7 (`legacy-liveness`) — answered 2026-09-20.** Answer: drop from the gate. Entry removed from `clearance.json` (artifacts and `requiredArtifacts`); `validate.py` untouched. Justification: `build.sh:108-109` excludes the legacy texture model from bundles, no `build.sh` branch copies any Liveness file, and `Resources/Liveness.mlmodelc` is not present.

## Could not determine and why

- Whether `scripts/train_spoof.swift` produced the exact bundled `Spoof.mlmodel` bytes beyond the owner's word: no training log or output hash exists; the owner confirmation of 2026-09-20 is the binding record (Q4).
- Whether `scripts/make_icon_mark.swift` output equals the current `gaze-mark.png`: script never run here and no output hash recorded; layer-name mismatch noted but not resolved (Q6).
- Authorship of 25 of 30 `Resources/Art` files: generators and manifests identify process and source images, not who ran them or on whose machine; five tour files owner-confirmed 2026-09-20 (Q5).
- `credit-portraits`: deliberately untouched; parallel audit reports separately.
