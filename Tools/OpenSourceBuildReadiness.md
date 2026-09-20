# Open-source build readiness (clean-clone projection)

Method: tracked set from `git ls-files` (913 files, worktree tree clean at `ffbd1df`); ignored set from `git check-ignore -v`; sizes from `ls -l` / `du -sh`. Nothing was built or run.

## Verdict

No — `./build.sh` does not succeed on a clean clone on a clean Mac. It exits 1 at the signing-identity lookup (`build.sh:12-16`) before anything compiles, because a fresh Mac has no Apple Development or Developer ID Application certificate for `gaze_signing_identity` (`Tools/Release/Signing.sh:3-26`) to select. Everything else the script reads is tracked and sufficient: once the contributor creates a free Apple Development certificate (`CONTRIBUTING.md:11-21`) and has full Xcode with the macOS 26 SDK, the same script compiles and signs a complete, non-degraded app — both ML models build from tracked sources.

## Excluded by .gitignore

| Rule | What it excludes | Build needs it? | Regenerated from tracked source? |
|---|---|---|---|
| `build/` (`.gitignore:2`) | App bundle output | No — created by `build.sh:49-57` | n/a (output) |
| `*.dSYM/` (`.gitignore:3`) | Debug-symbol bundles | No | n/a |
| `*.mlmodelc/` (`.gitignore:5-6`) | Compiled Core ML models | Yes at bundle time, but optional-degrading, never fatal (`build.sh:94-125` prints `!` and continues) | Yes — `FaceEmbedding.mlpackage` (3 files, tracked per `git ls-files`) compiles via `xcrun coremlc compile` (`build.sh:100-103`); `Spoof.mlmodel` (tracked, 6,831,170 bytes) compiles via `build.sh:118-121`. `git check-ignore -v` confirms `Resources/FaceEmbedding.mlmodelc/` and `Resources/Spoof.mlmodelc/` match this rule |
| `Plugin/build/` (`.gitignore:9`) | Plugin build output | No — `./build.sh` never references `Plugin/` (grep over `build.sh` shows only `Tools/` inputs) | Yes — `Plugin/build-*.sh` (all tracked) |
| `.DS_Store` (`.gitignore:12`) | macOS noise | No | n/a |
| `__pycache__/`, `*.py[cod]` (`.gitignore:15-16`) | Python caches | No | Regenerated on run |
| `Frameworks/` (`.gitignore:18-22`) | FaceIDKit, proprietary, app-licensed-only | No — zero build-time references: no `import FaceIDKit` anywhere in `Sources/` or `Plugin/`; only the comment at `build.sh:170` and the historical note at `Sources/App/GazeApp.swift:689-695` | Nothing to regenerate — absent by design; runtime substitution is real (see § FaceIDKit) |
| `Face Spoof Detection.v1i.createml/` (`.gitignore:27`), `dataset-subset/` (`.gitignore:28`) | Spoof training data + subset | No for build; yes for retraining | Re-obtainable, not regenerable: Roboflow export (`NOTICE.md:91-94`), `scripts/train_spoof.swift` tracked |
| `/Data/*` except `!/Data/README.md` (`.gitignore:31-32`) | Local datasets (`spoof-detection/`, `spoof-subset/`, `evaluation/`) | No — `Data/README.md:7` states "building Gaze does not need this data". Present here as 4.0K (`du -sh Data`): README only; the gigabytes live on the author's machine | n/a — retraining/evaluation only |
| `.claude/` (`.gitignore:35`) | Per-session agent scratch | No | n/a |
| `Tools/Release/AdminReliability/fixture/app.js` (`.gitignore:38`; enforced by `Tools/Release/AdminReliability/fixture/.gitignore:1`) | Generated browser fixture bundle (absent: `git ls-files` shows no `app.js` under `fixture/`) | No for `./build.sh` | Yes — `Tools/Release/AdminReliability/fixture/build.sh` (tracked), but it needs a gaze-site checkout (`SITE=${GAZE_SITE_DIR:-/Users/owencope/Developer/gaze-site}`) plus npm/esbuild |

Face-embedding model status, explicitly: **present, not absent.** `Resources/FaceEmbedding.mlpackage` (7.2M total; `weight.bin` 7,408,704 bytes) is fully tracked — `git ls-files Resources/` lists `model.mlmodel`, `weights/weight.bin`, `Manifest.json` — and `build.sh:100-103` compiles it with `xcrun coremlc`. The `*.mlmodelc/` exclusion therefore costs a clone nothing at build time. The open question about the model is legal, not mechanical: `NOTICE.md:57-66,81-84` leaves the raw package's provenance unresolved (the AGPL-3.0 Sapphire match documented at `NOTICE.md:50-55` concerns the 87MB precompiled variant, whose fingerprint differs from this package's).

## First failure

On a clean Mac (Xcode installed, no certificates created), the build stops here:

```bash
# build.sh:12-16
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null)" || {
	echo "Unable to inspect valid signing identities. The existing app was not replaced." >&2
	exit 1
}
IDENTITY="$(gaze_signing_identity "${DIST:-0}" "${GAZE_SIGNING_IDENTITY:-}" "$IDENTITIES")" || exit 1
```

`gaze_signing_identity` (`Tools/Release/Signing.sh:3-26`) only accepts `Developer ID Application:` or, for local builds, `Apple Development:` identities; with neither present it prints "Local builds require a valid stable Apple Development or Developer ID Application identity…" (`Tools/Release/Signing.sh:20-21`) and returns 1, and `set -euo pipefail` (`build.sh:4`) ends the run. This check sits before every compile (compilation `build.sh:189-231`, signing `build.sh:239-241`), so no partial bundle is left behind. The remedy is already documented: `CONTRIBUTING.md:11-21` (free Apple ID → Apple Development certificate → verify with `security find-identity -v -p codesigning`).

Second gate, not reached on the stipulated machine but load-bearing for strangers: `require_toolchain` (`toolchain.sh:64-85`) rejects anything without the macOS 26 SDK *and* `coremlc`, i.e. Command Line Tools alone always fails — by design, since without `coremlc` the tracked `.mlpackage`/`.mlmodel` could not compile and the app would silently fall back to landmark geometry (`toolchain.sh:11-15`). Every other input `build.sh` reads is tracked: `toolchain.sh`, `Tools/MainAppSources.sh`, `Tools/Release/Signing.sh`, `Tools/Release/check-build-space.py`, `Resources/Info.plist`, `Resources/Gaze.entitlements`, `Resources/AppIcon.icon/` (icon.json + gaze-mark.png tracked), `Resources/Art/`, `Resources/Credits/`, `ThirdParty/TourKit/TourKit.swift` + `LICENSE` (wired in at `Tools/MainAppSources.sh:13-15`, licensed into the bundle at `build.sh:166-167`), and all `Sources/*/*.swift`.

## Degraded capabilities

Assuming the contributor passes the two gates above (full Xcode, free signing certificate):

| Capability | Status | Reason |
|---|---|---|
| Face enrollment + recognition unlock | Available | Model tracked and compiled (`build.sh:100-103`); `UnlockGuard` allow-lists `coreml:` identifiers (`Sources/Security/UnlockBackend.swift:74-86`); threshold 0.45 (`Sources/Recognition/FaceEmbedder.swift:186`) |
| Spoof object-detector gate | Available (weak, as shipped) | `Spoof.mlmodel` tracked, compiled (`build.sh:118-122`); gate active when bundled (`Sources/Recognition/SpoofDetector.swift:28-39`, `Sources/Recognition/AntiSpoofGate.swift:72-73`). Strength limits are measured and documented in-code (`AntiSpoofGate.swift:36-70`), not a clone artifact |
| Setup flow without FaceIDKit | Available, plainer | No build- or source-level reference (only `build.sh:170` comment); `Sources/Setup/SetupMark.swift:1-52` contains no framework branch — it always renders `GazeLessonAnimation`/`GazeCompanionView`. `Sources/App/GazeApp.swift:689-695` confirms the old framework branch was removed so contributors see the same flow. Contributor sees system-drawn mark instead of Aviorrok animations (`NOTICE.md:101-106`) |
| Retraining the spoof model | Impossible from clone | Dataset absent by design (`/Data/*`, `Face Spoof Detection.v1i.createml/`, `dataset-subset/`); re-export from Roboflow per `NOTICE.md:91-94`, retrain with tracked `scripts/train_spoof.swift` |
| `Plugin/` (PAM module, auth plugin, panel test) | Available as source; not built by `./build.sh` | All `Plugin/*.sh`/sources tracked; `build.sh` never invokes them; install (`Plugin/install.sh`, `Plugin/install-pam.sh`) is privileged and manual |
| `Tools/` regression suites | Available except one fixture | Tracked suites drive `swiftc`/python directly; `Tools/Release/AdminReliability` fixture needs a gaze-site checkout + npm (see table) |
| Local signing | Impossible until certificated | First-failure gate above; free-Apple-ID route in `CONTRIBUTING.md:17-18` |
| `DIST=1` release signing/notarization | Impossible without membership + clearance | Requires Developer ID (`Tools/Release/Signing.sh:17-19`) and `validate.py` PASS (`build.sh:20-23`); clearance inputs under parallel edit — see Unanswered |

## Fix list

1. **Signing hard-fail on fresh machines** — Document (already done in `CONTRIBUTING.md:11-21` and `README.md:21`); keep refusing ad-hoc fallback. Rationale: `build.sh:34-42` pins the new bundle to the existing app's signing requirement, which ad-hoc cannot satisfy — an ad-hoc "fix" would break upgrades. Optional small improvement: point the `Signing.sh:21` error at `CONTRIBUTING.md`.
2. **`FaceEmbedding.mlpackage` tracked with unresolved provenance** (7.2M; `weight.bin` 7,408,704 bytes; `NOTICE.md:63-66,81-84`) — Options: (a) resolve rights and keep tracking; (b) untrack and add a download/release-asset fetch step to `build.sh` (falling back to the landmark embedder with the existing `build.sh:105` message); (c) document the limitation in the README. Do **not** leave it silently tracked in a public repo — redistribution without resolved rights is the obvious-but-wrong default. Note the geometry fallback is explicitly "not an approved substitute for the Mac-unlock recognition model" (`NOTICE.md:83-84`) and `UnlockGuard` refuses it for real unlocks, so option (b) degrades unlock to recognition-only by design.
3. **`Spoof.mlmodel` tracked** (6,831,170 bytes) — Keep tracking (recommended): author's own trained weights (`NOTICE.md:88-99`), training data attributed CC BY 4.0 (`NOTICE.md:91-95`), small enough for git. Alternative only if repo size becomes a concern: Git LFS or release-asset download with a `build.sh` fetch step.
4. **Training data absent** — Accept + already documented (`Data/README.md`, `NOTICE.md:91-94` re-export path). No action unless `Tools/ModelLab` tests need vendored fixtures, which was not established here.
5. **FaceIDKit absent** — Accept (by design; substitution verified real, not aspirational). Optional: one README line that contributors see the system-drawn setup mark.
6. **AdminReliability `fixture/app.js` absent** — Accept (regenerable) + document the gaze-site prerequisite where that suite is described; do not vendor a prebuilt bundle (generated file, would rot).
7. **Full-Xcode requirement** — Accept + already documented (`toolchain.sh:71-84` error text, `CONTRIBUTING.md:58-66`). No change.
8. **README still shows an author-local toolchain path** (`README.md:16`: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer ./build.sh`) while `toolchain.sh:31-61` auto-detects any new-enough Xcode — Update README to plain `./build.sh` (as `CONTRIBUTING.md:8` already shows); the beta path is exactly the machine-specific assumption `toolchain.sh:3-9` was written to eliminate.

## Unanswered

- `DIST=1` clearance state: `Tools/Release/ModelClearance/clearance.json` and `OWNER-ANSWERS.md` are being edited in parallel and were deliberately not read; whether `validate.py` currently passes is unknown.
- Whether the `FaceEmbedding.mlpackage` weights' provenance/rights resolve (open per `NOTICE.md:63-66,81-84`).
- Exact size of the author-local training data (multi-GB per `.gitignore:25`); this copy's `Data/` holds only the README (4.0K), so no measurement was possible.
- Post-gate behavior (actual compile, model compile output, signature) — no build was run, per the brief.
