# Model clearance — owner completion template

The gate in `Tools/Release/READINESS.md` ("Model and asset redistribution
evidence") stays OPEN until every row below is filled. Copy this template's
answers into `Tools/Release/ModelClearance/clearance.json` (set the entry's
`clearance` to `"cleared"` only when all three columns are filled), then run
the validator. Do NOT paste private grant documents or credentials into
source — record where the evidence lives (e.g. "licence email, owner's
archive, 2026-…") instead.

| Artifact (hash-bound) | Provenance to confirm | Licence/grant + evidence pointer | Redistribution scope |
|---|---|---|---|
| `face-embedding` — model `b8992d79…f494`, weights `f9145f91…c00da9` | Where did these exact weights come from (Sapphire? InsightFace-derived? other)? Version? | The actual permission/licence for THESE hashes (not the source repo's code licence). If InsightFace-descended: commercial/redistribution licence or contact `recognition-oss-pack@insightface.ai`. If GPL-covered: licence analysis, not a credit line. | e.g. `bundled-app-distribution` (Mac app bundle, website download, source archive?) — list each channel covered |
| `spoof-detector` — `e4037752…76f` (6,831,170 bytes) | Confirm: trained in-repo via `scripts/train_spoof.swift` from the Roboflow Face Spoof Detection v1 export | Dataset terms covering redistribution of the TRAINED weights in the bundle (stated CC BY 4.0 needs upstream consent/sublicensing review — record the conclusion + pointer) | Same: list each distribution channel covered |
| `setup-art` — 11 files in `Resources/Art` (hashes in clearance.json) | Confirm authorship (own screenshots?) per file, or name the third-party source | Grant for each file (own work = owner confirms; third-party = permission pointer) | `bundled-app-distribution` at minimum |
| `credit-portraits` — 9 files in `Resources/Credits` | Third-party likenesses/app icons — confirm subject per file | Permission pointer per portrait/icon, or delete the file and its row | `bundled-app-distribution` at minimum |
| `app-icon` — glyph + `icon.json` (hashes in clearance.json) | Confirm authorship (`scripts/make_icon_mark.swift`) | Owner confirms first-party + scope | `bundled-app-distribution` at minimum |

Done = `python3 Tools/Release/ModelClearance/validate.py` prints
`PASS: model clearance` (exit 0). Anything else names exactly what is
still missing.
