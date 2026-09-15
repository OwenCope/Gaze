# Gaze launch readiness — team assessment (Walter), September 15, 2026

Lead integration update: see the 19:42 checkpoint in `CHALLENGE-INVESTIGATION.md`
and the current candidate in `Tools/Release/READINESS.md`. The local implementation
and checks are complete; the public-launch verdict remains blocked. The artifact
inventory in section 1 below records Walter's isolated copy at audit time.

Scope: launch-readiness assessment only. No production source changed for this
report. No build, no camera, no lock, no credentials, no enrollment, no
notarization, no install performed. This does not authorize shipping.

Lead audit: corrected model/gate distinctions, pose-angle claims, validation classifications, and the SkyLight dependency. The original worktree inventory below is historical; it is not the lead checkout inventory.

Upstream inputs built on: `Tools/Release/READINESS.md` (Sept 14 gates, still
the controlling checklist), `CHALLENGE-INVESTIGATION.md` (direction-sign
correction Sept 15, real-world confirmation still pending), `SECURITY.md`
(Sept 12–13 hardening + product separation), `NOTICE.md` (one factual
correction applied — SkyLight — see below).

## Verdict: NOT launch-ready

Nothing below is fixed by "it builds" or "synthetic tests pass." Every gate
in `Tools/Release/READINESS.md` that was OPEN on Sept 14 is still OPEN:
owner-supervised lock-screen validation on the current source, recognition /
anti-spoof evidence with real users and attacks, model and asset
redistribution rights, signed release artifact, clean install and update.
This report adds specificity and ordering; it closes no gate.

## 1. Exact available artifact — none verifiable in this copy

- This worktree (`faceid-walter-7f1ed0fc`) contains **no `build/` directory at
  all**: no `build/Gaze.app`, no `build/release/Gaze.app`, no log artifacts.
  There is no app artifact here to hash, verify, or ship.
- The hashes recorded in `CHALLENGE-INVESTIGATION.md` (most recent: binary
  mtime 2026-09-15 12:13:11, SHA-256
  `6829235e…2d54a`, PID 89872) refer to builds in the lead checkout, not to
  anything present in this copy. They cannot be re-verified from here and
  must be re-established by the lead against the exact binary that ships.
- Any launch candidate must be rebuilt from a frozen source revision via
  `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer ./build.sh`
  (Command Line Tools toolchain alone fails on Swift macros — see AGENTS.md),
  then identified by executable SHA-256 and binary mtime before any
  validation counts. A failed build leaves the previous binary in place, so
  mtime is the relink check.

## 2. Signing / notarization prerequisites — blocker

- Local certificate inventory (read-only `security find-identity`): exactly
  one identity, `Apple Development: owen.o.cope@gmail.com (Y6LG3Q6HV4)`.
  **No `Developer ID Application` identity exists on this machine.**
- Consequences (`build.sh`, `Tools/Release/Signing.sh`,
  `Tools/Release/verify.sh`):
  - `DIST=1` release builds **cannot be signed here** — `Signing.sh`
    refuses ad-hoc and Apple Development for release mode.
  - `verify.sh` requires Developer ID authority, secure timestamp, Hardened
    Runtime, camera entitlement, no unsafe entitlements, stapled notarization
    ticket, and Gatekeeper acceptance. None of this has been produced for any
    current-source build.
  - Local builds sign ad-hoc/Development and correctly **fail** release
    verification by design (`Tools/ReleaseRegression` covers this with
    fixtures — 23 identity/wiring + 20 artifact-verifier checks, synthetic
    only).
- Owner decisions required: provision a Developer ID Application certificate
  on a release machine, authorize notarization (credentials never in source,
  logs, or history), then run `DIST=1 GAZE_SIGNING_IDENTITY="Developer ID
  Application: …" bash build.sh` followed by `bash Tools/Release/verify.sh
  build/release/Gaze.app` after notarization + stapling, and record the final
  archive checksum. Passing `verify.sh` is artifact validation only, not a
  ship decision.

## 3. Model and asset redistribution rights — blocker

- `Resources/FaceEmbedding.mlpackage` **is present in this working copy**
  (184 KB `model.mlmodel` + 7.4 MB `weight.bin`, Manifest author
  `com.apple.CoreML`). Presence here is not a license.
- Provenance accounts disagree, and neither grants redistribution:
  - `NOTICE.md`: model "comes from Sapphire, by cshariq, and its licence is
    unknown, so it is not included in published source archives."
  - `Sources/Recognition/FaceEmbedder.swift:61-64`: "Sapphire ships a 512-d
    `ModernFace` model, but its repository is GPL-3.0 and we are not copying
    from it, so no weights are vendored here."
  - The working copy *does* contain weights while the source comment says
    none are vendored — so the file's provenance, version, hash, and how it
    arrived here are all unattributed. `Tools/Release/READINESS.md` already
    flags the README/NOTICE disagreement and owner-reported permission not
    attached to a specific model version and distribution scope. Still open.
- Thresholds are fixed in source and must not be moved to make a demo pass:
  `CoreMLEmbedder.matchThreshold = 0.45`
  (`Sources/Recognition/FaceEmbedder.swift:183`), `LandmarkEmbedder = 0.55`
  (`:81`). Without the model the app falls back to landmark geometry, which
  the source itself calls convenience-grade ("can tell you from a stranger,
  and not much more" — `NOTICE.md`; "struggle with siblings" —
  `FaceEmbedder.swift:72-78`).
- Anti-spoof models: Walter's isolated copy lacked `Resources/Liveness.*`,
  but that does not make the current lock-screen photo check unavailable.
  `AntiSpoofGate` uses `SpoofDetector` alone, with a rejection cutoff of **0.65**.
  The detector's own **0.5** property is used by the practice readout; it is not
  the lock-screen gate cutoff. The texture `Liveness` model is deliberately
  excluded from this gate. The lead checkout contains prebuilt Liveness weights,
  and its last built app contains `FaceEmbedding.mlmodelc`, `Spoof.mlmodelc`, and
  `Liveness.mlmodelc`. Model presence is not proof of operational accuracy or
  redistribution rights. The misleading build warning tying missing Liveness
  directly to a photograph passing has been corrected by the lead.
  `Tools/Release/verify.sh` requires FaceEmbedding and Spoof, not Liveness.
  Rights and qualified validation remain open for the exact distributed models.
- Other assets: setup card art (`Resources/Art/`), credit portraits
  (`Resources/Credits/`), app icon (Icon Composer `.icon`) are bundled from
  this tree — confirm redistribution rights for each before publishing.
  FaceIDKit/Aviorrok animations already removed from the build
  (`build.sh:175-177`, `NOTICE.md` — framework kept out of git).
- Owner decisions required: record per-model permission/license, provenance,
  hash, attribution, and redistribution terms for each bundled model; same
  for third-party assets and any training/evaluation data. This checklist
  determines no legal rights.

## 4. Installer / update readiness — not validated

- Privileged installers are **disabled by design**: `Plugin/install.sh` and
  `install-pam.sh` print an explanation and exit 1 before any filesystem,
  launchd, PAM, or authorization-database change (`Plugin/README.md`). PAM
  authenticate always returns `PAM_AUTH_ERR`; the XPC compatibility listener
  returns unavailable without opening the camera (`SECURITY.md:152-154`).
  This disables the privileged PAM installation path. It does not by itself
  prevent normal application-bundle installation. Old installed modules,
  agents and policies are untouched by building this checkout; their presence
  and removal need an isolated-machine audit. Normal app installation and
  login-item behavior still need validation.
- LaunchAgent plist (`Plugin/com.gazeunlock.Gaze.agent.plist`) points at
  `/Applications/Gaze.app` with a MachServices declaration for the retired
  plugin channel — review before any distribution; do not ship a service
  registration for a disabled service without a decision.
- Updater (`Sources/App/ReleaseUpdateChecker.swift`): offer-only, opens the
  download in the browser, never auto-installs; feed restricted to the
  `gazeunlock.com` origin with redirect policy (`Sources/App/ReleaseURLPolicy.swift`).
  Sound design, but no live update flow has been exercised end to end.
- Bundle facts constraining release notes: version `0.1` (build `1`),
  `LSMinimumSystemVersion 26.0`, not sandboxed (deliberate — keystroke backend
  needs HID/Accessibility), camera entitlement only, host-architecture-only
  binary (no universal slice — `build.sh` targets `host_target`), private
  lock-screen window APIs need per-OS-version testing (`READINESS.md`:
  clean-install gate).
- Missing entirely: quarantined-download test on a separate Mac/account,
  first-run TCC prompts, enrollment + explicit unlock consent, login-item
  behavior, permission revocation, camera contention, sleep/wake, fast user
  switching, update migration preserving enrollment/vault access under the
  release identity, and uninstall leaving password/Touch ID intact. None
  covered by this assessment. The owner must perform lock and credential
  interactions; authorized artifact and installer checks can be prepared separately.

## 5. Security claims — what may and may not be said

Per `SECURITY.md` (still accurate, no change proposed): recognition gates
*when the app chooses to type*; it is not a cryptographic factor, not an
input to the vault key, and anything running as the user with the app's code
identity can call `PasswordVault.password()`. No biometric ACL on the item
(`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, no `.biometryCurrentSet`).
Do not advertise Touch ID-equivalent security. Do not claim movement
challenges make an RGB-camera system spoof-proof — the Sept 15 clip analysis
shows score collapse at large raw yaw (first displayed failures at +0.86 /
−0.88 rad) with recovery on return. Those values are substantially larger than
its 0.30-rad relative excursion and cannot establish a failure boundary at the
challenge-sized angle. The baseline and actual admitted-frame sequence matter. "Encrypted at rest, bound to this
Mac" is accurate; "we cannot read your password" is false. The broadcast
channel (`com.gazeunlock.Gaze.state`) stays one-way; any integration that can
*cause* an unlock is a vulnerability, not a feature.

## 6. Missing real-world validation — the release blocker

From `CHALLENGE-INVESTIGATION.md`, current as of Sept 15 12:13:

- **Head-turn direction sign was corrected in source** (left now requires
  positive raw-yaw excursion, right negative; landmark fallback sign fixed;
  pose math centralized in `Sources/Camera/FacePose.swift`; scalar replay
  passes both directions). This is a **scalar replay, not an authentication
  replay** — the clip was a score sweep, not the lock-screen baseline or
  admitted-frame sequence. **No owner-supervised lock-screen test on the
  corrected build has occurred.** Real-world reliability unconfirmed.
- **Below-threshold comparisons at turned poses are the measured failure**,
  not missing embeddings: Sept 14 reproduction scored 0.405/0.357/0.275/0.150
  against the 0.45 cutoff with `compared=true`; Sept 15 11:12 runtime showed
  0.199/0.445/0.427/0.202, all `belowThreshold`, `returning=false`. Proof is
  correctly discarded on mismatch — do not retain it, do not lower the
  cutoff.
- **Choppiness unexplained.** The main-thread-inference theory was withdrawn
  (evaluator actor confirmed in binary via `nm`). Synthetic renderer probes
  (≈60 Hz scheduling, p95 16.7–25.7 ms, max gap 59 ms, no dropped submits)
  are not a live lock-screen frame-time trace; GPU completion and displayed
  frames unmeasured. `RenderTiming` diagnostics exist behind
  `--render-diagnostics` but have not been correlated with a supervised lock
  session.
- The supplied recognition videos are real camera/readout observations. The
  scalar replays and regression fixtures are synthetic. Neither substitutes
  for an observed complete lock-screen authentication flow.

## 7. Prioritized launch checklist (all OPEN)

1. **P0 — Supervised unlock validation on the exact corrected build.**
   Rebuild from frozen source, record SHA-256/mtime/macOS version, run the
   §8 plan with the owner. Any failure is a release blocker until attributed
   and corrected. (Validates §6.)
2. **P0 — Model redistribution rights.** Resolve §3 per model + assets before
   any artifact leaves this machine. No upload until cleared.
3. **P0 — Release signing + notarization.** Provision Developer ID, build
   `DIST=1`, notarize, staple, `verify.sh`, record archive checksum. (§2.)
4. **P1 — Recognition / anti-spoof evidence.** Held-out enrolled vs
   non-enrolled users, dim lock-screen light, glasses, pose, multiple faces;
   held-photo and replay attacks kept separate from threshold selection;
   FAR/FRR + PAD errors with sample sizes and uncertainty against exact model
   hashes; acceptance criteria agreed *before* evaluating. No Touch
   ID-equivalence or spoof-proof claims. (`READINESS.md` §Recognition.)
5. **P1 — Clean install + update on isolated hardware.** Quarantined
   download, TCC prompts, enrollment, consent, login item, revocation,
   contention, sleep/wake, user switching, migration under release identity,
   uninstall safety. Never bypass Keychain/TCC to make migration pass.
6. **P2 — Installer/component audit.** Decide the fate of the disabled PAM /
   XPC path, the agent plist MachServices entry, and legacy installed
   components; document removal without breaking password/Touch ID fallback.
7. **P2 — Versioning + support matrix.** Real version/build numbers, claimed
   OS/arch combinations actually tested (arm64-only today; private SkyLight
   SPI risk per release — see NOTICE.md correction), vulnerability-reporting
   route, history scan for secrets/templates/keys before any source
   publication (`SECURITY.md:331-335`).

## 8. Minimal owner-supervised unlock validation plan

Owner runs everything; agent never triggers locks, enters credentials, or
touches the password field. Keep password + Touch ID available. Record app
SHA-256, macOS version, and camera for each step (`READINESS.md` items 1–7,
condensed to the minimum that gates launch):

1. Cold launch → owner locks → fresh frames, face detection, both movement
   prompts appear; no password input before all verification completes.
2. Normal verification → exactly one submission → actual macOS unlock; recheck
   Settings → Unlocking → information for the recorded outcome (a sent
   password is not a confirmed unlock).
3. Wake after display sleep → same flow, no duplicate attempt or premature
   input; repeat to expose intermittent capture startup (prior first-frame
   timeout + closed-clamshell context noted Sept 15 — not a recognition bug,
   but record display state if capture stalls).
4. Negative cases: covered camera / out of frame / omitted movement → **no**
   password input; manual password and Touch ID fallback usable.
5. Manual input during scanning → Gaze yields without clearing the field or
   continuing entry during that lock.
6. Pause/disable automatic unlocking → no further submission; re-enable only
   at owner request.
7. Any real submission failure → record only non-secret diagnostics + time,
   confirm no repeat that lock, unlock manually; failure stays a blocker.

## Work completed (this report)

- Read `AGENTS.md`, `CHALLENGE-INVESTIGATION.md`,
  `Tools/Release/READINESS.md`, `NOTICE.md`, `SECURITY.md`; confirmed no
  existing `TEAM-LAUNCH-READINESS-20260915.md` in this copy.
- Source inspection (read-only): `Sources/LockScreen/LockScreenSpace.swift`
  (SkyLight `dlopen` + 6 `dlsym` symbols), `NotchCapsuleController.swift`
  (space adoption), `Sources/Security/ScreenLock.swift` (public-shortcut
  locking — no private lock symbol), `FaceEmbedder.swift` (thresholds 0.45 /
  0.55, Sapphire/GPL comment), `LivenessDetector.swift` (nil-by-default),
  `SpoofDetector.swift` (0.5 object threshold), `build.sh` / `Signing.sh` /
  `verify.sh` / `ReleaseRegression/*` (signing gates), `Plugin/README.md` +
  installer stubs (disabled), agent plist, `Info.plist` (0.1/1, minOS 26.0),
  entitlements (camera only, unsandboxed), `ReleaseUpdateChecker.swift`
  (offer-only updater).
- Factual checks (no build, no launch, no camera): `ls` (no `build/` in this
  copy; `FaceEmbedding.mlpackage` weights present; `Spoof.mlmodel` present
  uncompiled; no `Liveness` model), `plutil` (model manifest), `security
  find-identity` (Apple Development only — 1 identity), `sw_vers` (macOS
  27.0), `uname -m` (arm64).
- Applied one narrow `NOTICE.md` correction (SkyLight statement contradicted
  by `LockScreenSpace.swift`); wrote this file. No other files touched.

## Owner decisions still required

- Authorize + witness the §8 supervised validation on a recorded exact build.
- Attach per-model versioned redistribution permission or select and validate
  a redistributable model. The landmark fallback is not an approved substitute
  for the required Core ML model in the current Mac-unlock release.
- Provision Developer ID + authorize notarization; approve version number and
  supported OS/arch list.
- Agree FAR/FRR + PAD acceptance criteria before evaluation begins.
- Approve installer/component removal plan and isolated-hardware test window.
- Launch preparation does not authorize shipping. No gate is closed by this
  report.
