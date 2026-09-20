# Pre-publication history scan — Gaze

## Verdict

Do not publish yet. Two categories must be resolved first: permission for the identifiable portraits and app icons bundled under `Resources/Credits/`, and redistribution rights for the tracked model weight files. Both are in the current tree and in history, so removal alone leaves them published via history. Details are under High below.

History coverage was established with `git rev-list --all --count` (1188 commits), `git grep -I --all -n -E <patterns>` for secret/personal-data patterns, `git rev-list --all --objects` combined with `git cat-file --batch-check` for the largest reachable blobs, `git log --all --find-object=<blob>` to attribute large blobs to commits, and `git log --all --oneline -- <path>` plus `git rev-list --all --objects | grep -E <pattern>` for named-file history (FaceIDKit, Frameworks, mlpackage/mlmodelc, jsonl/log, env/key material). Deleted files are covered because every search ran across `--all` commits, not just the working tree.

## High

### H1 — Identifiable portraits and third-party icons bundled without recorded permission

- Type: biometric-adjacent personal data (two identifiable photographs of real people) plus third-party app icons and avatars redistributed in the app bundle.
- Location: `Resources/Credits/` (nine files), tracked since bulk commit `ad7aa83` ("The setup flow, notch panel and recognition work", 2026-09-09). Still tracked at HEAD.
- Evidence already in the repo: `Tools/CreditsAudit.md` viewed all nine as rendered images and records no permission for any of them; the corresponding clearance entry is `unresolved` with provenance `third-party-unrecorded`. The Shariq permission record covers the Sapphire ArcFace model only and explicitly does not extend to unrelated assets, so it does not cover these files.
- Resolution: for each file, either obtain a redistribution grant from the rights holder (portrait subject or icon owner) and record a pointer to it, or delete the file and its clearance row. The app renders a glyph fallback for a missing portrait, so deletion needs no code change. Full purge requires rewriting history, because `ad7aa83` and every descendant carry the files — an owner decision with consequences (rewrites every commit hash, invalidates existing clones).

### H2 — Tracked model weights with unresolved redistribution rights

- Type: model/data licensing blocker for files the public repository would redistribute.
- Locations, both tracked at HEAD and present through history:
  - `Resources/FaceEmbedding.mlpackage/Data/com.apple.CoreML/weights/weight.bin` (about 7.4 MB) — `NOTICE.md` states its provenance is unresolved and that it must not be treated as covered by the Sapphire evidence.
  - `Resources/Spoof.mlmodel` (about 6.8 MB) — author-trained, but trained on a third-party CC BY 4.0 dataset; the dataset terms as applied to redistributing the trained weights still need confirmation per `NOTICE.md` and the clearance template.
- Resolution: resolve provenance and licence/scope for the exact bundled bytes (or replace/remove the files) before publishing. As with H1, the bytes are in history, so keeping them out of the public repo entirely requires a history rewrite; publishing with them requires the rights to be settled first.

## Medium

### M1 — Committed build output lingering in history

- Type: large deleted blobs (practical bloat; a compiled binary in public history).
- Locations (in history, absent from HEAD): `build.noindex/hank/Gaze.app/Contents/MacOS/Gaze` (about 5.2 MB) and `build.noindex/hank/Gaze.app/Contents/Resources/Assets.car` (about 1.8 MB), introduced in Droppy Code checkpoint commits `5a6c11a` / `5ed7b99`, plus roughly two hundred render files under `build.noindex/nova/progress-renders/`. Attributed with `git log --all --find-object` and `git rev-list --all --objects | grep build.noindex`.
- Resolution: harmless if the owner accepts the size; removal from history requires a rewrite. At minimum, confirm no further build output gets committed (the `build/` prefix is git-ignored; `build.noindex/` relied on checkpoints that swept it in).

### M2 — Owner identifiers in tracked files and git history

- Type: personal data (owner's email addresses, a signing team identifier, local-machine username paths), not credentials.
- Locations: the signing identity (email plus team identifier) is written in `Tools/Release/ShipPass20260918/DISTRIBUTION.md` and `Tools/Release/TEAM-LAUNCH-READINESS-20260915.md`; the owner's name is in `LICENSE`; author emails appear across git history (owner addresses alongside `noreply` and `localhost` agent addresses); local checkout paths appear in `SESSION-HANDOFF.md` and release notes. No values are quoted here, per the secrecy rule for this report.
- Resolution: redact the working-tree files (replace with role names or placeholders). Scrubbing history requires a rewrite and is usually disproportionate for an author email; decide deliberately and note that author metadata is standard in open source.

### M3 — Screenshots whose contents were not verified in this scan

- Type: possible exposure of desktop contents, other apps, or faces.
- Locations: `Tools/Release/GalleryPacing/gallery-desktop.png`, `Tools/Release/SecondaryPages/credits-dark-desktop.png`, and large composited art under `Resources/Art/` (e.g. lock-screen and tour images around 0.5–7.8 MB). Filenames only establish what they might show, not what they do show.
- Resolution: the owner should view each tracked screenshot/recording before publishing and remove or crop anything showing a desktop, a password field, a face, or another application's contents. The three `.mp4` files under `Resources/Art/` and the HomeMotion clips fall under the same check.

## Low

### L1 — Operational detail in handoff and release notes

- Local process IDs, build hashes, install paths, preview deployment URLs, and test-session references in `SESSION-HANDOFF.md`, `Tools/Release/ShipPass20260918/SESSION-HANDOFF-1040.md`, `Tools/Release/RESUME-HANDOFF-20260916.md`, and neighbouring release notes. No secret values; tidy-up only, no action required before publishing.

### L2 — Repository weight from legitimate art assets

- Reachable history holds about 74 MB of blobs; the largest reachable objects are art PNGs (`Resources/Art/lockscreen-base.png` about 7.8 MB, `Resources/Art/backdrop.png` about 1.5 MB, tour/how-unlock images about 0.5–1.2 MB each) plus the model files in H2. Clone size is a practical consideration, not a leak. No action required.

### L3 — Benign matches only for credential-adjacent terms

- The words `notarytool`, `stapler`, `security find-identity`, `RESEND_API_KEY`, `AUTH_SECRET`, and `Bearer` appear solely as tool names, environment-variable names, or synthetic test fixtures (e.g. placeholder key strings in `Tools/Release/EmailAuthHardening/` tests). No action required.

## Searched and clean

Each item below was searched across all 1188 commits including deleted files, with the stated method, and nothing was found:

- Private key blocks and certificates (`BEGIN ... PRIVATE KEY`, `BEGIN CERTIFICATE`): `git grep -I --all`.
- Key/token files in any commit (`.p12`, `.pem`, `.key`, `.cer`, `.mobileprovision`, `.pfx`, `.env`, shell history): `git rev-list --all --objects | grep -E` and `git ls-files | grep -E` — no matches.
- Keychain dumps/exports and `security dump` output: `git grep -I --all` — only read-only `security find-identity` invocations in build scripts.
- API tokens, bearer tokens, AWS keys, app-specific passwords, hardcoded password/secret assignments: `git grep -I --all -n -E` over token patterns and quoted secret assignments — only synthetic fixtures and documentation placeholders.
- Notarisation credentials or profile secrets: only tool names (`notarytool`/`stapler` via `xcrun`) and setup instructions with placeholders.
- Enrolment templates, stored face embeddings, captured camera frames, test fixtures built from a real person: `git grep -I --all` over embedding/enrolment/fixture terms plus `git rev-list --all --objects` over fixture/enroll/embedding paths — tests use generated poses and dummy vectors only, and no image/embedding fixture from a real person exists outside `Resources/Credits/` (reported as H1).
- Committed logs, session outputs, crash dumps (`*.jsonl`, `*.log`, `*.ips`): `git rev-list --all --objects | grep -E` — none ever committed. The `session-events.jsonl` and `lockwatcher-live.jsonl` outputs referenced in `SESSION-HANDOFF.md` live under the git-ignored `build/` directory and appear in no commit.
- FaceIDKit claim verified: `NOTICE.md` says the Aviorrok-licensed FaceIDKit framework was kept out of git entirely because history is forever. Verified — `git rev-list --all --objects | grep -Ei 'FaceIDKit|xcframework|Aviorrok'`, `git log --all --oneline -- '*FaceIDKit*'`, `git log --all --oneline -- Frameworks/`, and `git grep -I --all -E 'import FaceIDKit|FaceIDKit\.framework'` all return nothing, and no `.xcframework`/`.framework`/`.dylib` blob exists in any commit. The only FaceIDKit mentions are the `.gitignore` exclusion, the `NOTICE.md` paragraph, and build/archive scripts that explicitly exclude it.
- Other `NOTICE.md` third-party assets: TourKit is vendored MIT with pinned commit, hashes, and licence (`ThirdParty/TourKit/`); Glance is credited as an idea source, not copied code; SkyLight symbols are OS-private APIs, not redistributed assets; the spoof-training image set is git-ignored (`Data/*` except the README, plus named training-data directories) and no training image appears in any commit.
- Compiled Core ML bundles (`*.mlmodelc`): none in any commit, consistent with the `*.mlmodelc/` gitignore rule. Only the raw `Resources/FaceEmbedding.mlpackage` and `Resources/Spoof.mlmodel` are tracked (reported as H2).
- Training data directories and the labelled spoof image set: absent from every commit.

## Private evidence documents

- `Tools/Release/ModelClearance/SHARIQ-PERMISSION-20260918.md` was read in full: it records a hash/pointer to the owner's private chat attachment (naming the attachment file, not reproducing it) plus the weight hash the permission was checked against and its scope limits. It contains the private conversation itself nowhere — the repository's claim of hash-or-pointer-only is accurate.
- `SESSION-HANDOFF.md` was read in full: it records test authorisations, build hashes, process IDs, local paths, and preview URLs. It contains no credential, password, key, face image, or private correspondence content.
- `Tools/Release/ModelClearance/SAPPHIRE-EVIDENCE-20260916.md`, `OWNER-REPORT-20260916.md`, and `OWNER-TEMPLATE.md` were read: pointers, hashes, and process instructions only, no private correspondence or personal data beyond the owner's authorship.
- `Tools/Release/ModelClearance/clearance.json` and `Tools/Release/ModelClearance/OWNER-ANSWERS.md` were deliberately not opened (parallel edit in progress) and are not covered by this scan — see Limits.

## Limits of this scan

- Static text and object search only. It cannot rule out secrets encoded in ways the patterns miss (split across lines, obfuscated, embedded in images or binaries), nor judge whether a pictured screenshot exposes something sensitive — M3 needs human eyes.
- Image contents were not rendered here except via the existing `Tools/CreditsAudit.md` descriptions; the H1 likeness assessment relies on that audit.
- Unreachable/dangling objects (not on any branch) were observed but not treated as publishable history; a `git gc` state or a fresh clone should confirm what `git rev-list --all` reports before release.
- `Tools/Release/ModelClearance/clearance.json` and `Tools/Release/ModelClearance/OWNER-ANSWERS.md` were not reviewed because they are being edited in parallel; their owner-supplied contents must be scanned for private correspondence or personal details before publishing.
- Licence conclusions (Sapphire/AGPL coverage, InsightFace descent, CC BY 4.0 terms for trained weights, credit-portrait rights) are legal questions this scan identifies but does not answer.
- No build, run, test, or lint was performed; no file was modified and no git state was changed in the course of this scan.
