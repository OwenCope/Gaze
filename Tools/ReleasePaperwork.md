# Release paperwork check — Gaze 0.1

Read-only review. No file was changed except this new report. `RELEASE_NOTES.md` is unmodified; corrected wording below is proposed text only.

## Hard blockers

Ordered most severe first. Each cites a file.

1. **No Developer ID identity, so no distributable signature exists.** Local inventory has Apple Development only; `DIST=1` refuses to build without Developer ID Application (`Tools/Release/Signing.sh:17-19`, `Tools/Release/READINESS.md:348-359`, `SESSION-HANDOFF.md:32`). A DMG downloaded from a website carrying an Apple Development (or ad-hoc) signature fails Gatekeeper: `Tools/Release/verify.sh:38-39` requires a stapled notarization ticket plus `spctl --assess --type execute`, and neither can exist without the Developer ID + notarize + staple path that `Tools/Release/DMG/package.py:92-100,138-149` implements but that has never been run for a release (every recorded DMG is a `-local-preview` with `distributionReady=false`, e.g. `SESSION-HANDOFF.md:42,326`). On a user's Mac, a quarantined app without a Developer ID signature and notarization ticket is refused at open ("developer cannot be verified" / damaged-app handling) — this is standard Gatekeeper behavior for quarantined software; the repo itself only encodes the requirement side (`Tools/Release/verify.sh:24,28,38-39`), not the user-visible dialog text.
2. **Model/asset redistribution clearance is unresolved on all six tracked artifacts.** `Tools/Release/ModelClearance/clearance.json` records `clearance: unresolved` for face-embedding (`:95`), spoof-detector (`:131`), setup-art (`:313`), credit-portraits (`:387`), app-icon (`:427`) and legacy-liveness (`:480`). `Tools/Release/ModelClearance/validate.py:63-78` therefore returns REFUSE, and `build.sh:20-23` exits 1 on `DIST=1` before replacing any output. Public release is mechanically blocked until each artifact has a recorded grant, evidence refs and redistribution scope covering `bundled-app-distribution`.
3. **Functional release gates recorded elsewhere are still open.** Recognition/PAD evidence, signed-artifact validation, clean-install/update testing and live-Mac acceptance are all OPEN per `Tools/Release/READINESS.md:326-388` and `SESSION-HANDOFF.md:17-20,45,328-331`. Paperwork alone cannot clear the release.
4. **Release notes misdescribe current behavior (details in step 2).** Fixable in docs, but the Settings About pane links users to versioned release notes (`Sources/App/SettingsView.swift:1441-1445`), so shipping stale notes ships a wrong in-app promise.

Not blockers: camera usage description exists with substantive wording (`Resources/Info.plist:37-38`); the sole entitlement is the camera device entitlement with sandbox deliberately omitted and documented (`Resources/Gaze.entitlements:1-12`); version and bundle-identifier values agree across release artifacts (step 1).

## 1. Version and identity consistency

Release version is `0.1`, build `1`, bundle identifier `com.gazeunlock.Gaze`. Every release-artifact location agrees; no disagreement found.

| Location | Value |
|---|---|
| `Resources/Info.plist:12` CFBundleIdentifier | `com.gazeunlock.Gaze` |
| `Resources/Info.plist:16` CFBundleShortVersionString | `0.1` |
| `Resources/Info.plist:18` CFBundleVersion | `1` |
| `Resources/Info.plist:20` LSMinimumSystemVersion | `26.0` (matches `RELEASE_NOTES.md:53` "macOS 26") |
| `Plugin/Info.plist:10` CFBundleIdentifier | `com.gazeunlock.Gaze.plugin` (distinct plugin id, by design) |
| `Plugin/Info.plist:14` CFBundleShortVersionString | `0.1` |
| `Plugin/Info.plist:16` CFBundleVersion | `1` |
| `RELEASE_NOTES.md:1` title | `0.1` |
| `build.sh:210` codesign `--identifier` | `com.gazeunlock.Gaze` |
| `Tools/Release/preflight.sh:24` BUNDLE_ID | `com.gazeunlock.Gaze` |
| `Tools/Release/verify.sh:5` BUNDLE_ID | `com.gazeunlock.Gaze` |
| `Tools/Release/DMG/package.py:82-83` | rejects any input whose identifier is not `com.gazeunlock.Gaze`; DMG filename embeds `CFBundleShortVersionString` (`Tools/Release/DMG/package.py:87-89,104-105`) |
| `source-archive.sh:14` | reads version from `Resources/Info.plist`, single source, no duplicate |
| `Sources/App/ReleaseUpdateChecker.swift:51-53`, `Sources/App/UpdateChecker.swift:22` | read version from bundle at runtime, no hardcoded string |
| `Sources/App/SettingsView.swift:1396-1400` | About pane shows `updates.currentVersion` from the bundle, no hardcoded string |

No Swift file contains a hardcoded release version string (grep over `Sources/` for version literals found only runtime bundle reads and unrelated numerics).

Different-but-not-disagreeing identifiers (all separate bundles/services, all consistently spelled):
- `Tools/GazePreview/Info.plist:12-13` is `1.0` / `1` — a preview helper, not the release app.
- `Plugin/build-paneltest.sh:23,44` uses `com.gazeunlock.Gaze.paneltest` / version `1.0` — a test harness, not shipped.
- LaunchAgent `com.gazeunlock.Gaze.agent` (`Plugin/com.gazeunlock.Gaze.agent.plist:6`), Mach service `com.gazeunlock.Gaze.unlock` (`Sources/Security/UnlockService.swift:7`, `Plugin/GazeUnlockProtocol.h:20`), test right `com.gazeunlock.Gaze.testunlock` (`Plugin/PanelTest/main.swift:21`), capture helper `com.gazeunlock.ProductCapture` (`Tools/ProductCapture/build.py:35`), isolated test suites (`com.gazeunlock.Tests…`, `com.gazeunlock.MovementSettingsTests…`).
- Logging subsystems are `com.gazeunlock.Gaze` everywhere in app code (e.g. `Sources/Security/LockWatcher.swift:18`, `Sources/Security/Keychain.swift:11` service string), with the plugin using the hierarchical `com.gazeunlock.Gaze.plugin` (`Plugin/GazePlugin.m:37`). Broadcast name `com.gazeunlock.Gaze.state` matches in code and docs (`Sources/App/StateBroadcast.swift:52`, `INTEGRATION.md:9`).
- `Keychain.swift:11` stores under service `com.gazeunlock.Gaze`, matching the bundle id.

`script/build_and_run.sh` and `scripts/` contain no version or bundle-identifier strings (only hit is `scripts/train_spoof.swift:56`, a model metadata `version: "1.0"` for the locally trained spoof model, unrelated to app versioning).

## 2. Release notes accuracy

Range `359b8bc..HEAD` contains merges #50–#60 (eleven) plus one head commit. Non-merge commits: search highlighting, glass tour controls, settings-component refactors, disclosure/info-button refactors, navigation-row/theme-picker refactors, theme-aware group styling, semi-glass transparency + theme picker UI, captions toggle, captions space reservation. Of these, the user-visible behavior changes are:

- Settings search result highlighting (`0dde6fe`, `7754895`, PRs #50–#51): cosmetic; notes never describe Settings search, nothing to correct.
- Tour/controls glass styling, completion circle, reusable rows, theme-aware group styling, transparency slider (`002c00e`, `33b1495`, `0847c87`, `3693748`, `1c15c7d`, `1967e5d`, `747910e`, PRs #52–#58): visual refinements of already-documented surfaces. The notes say "Three styles and size sliders, because notches and taste both vary" (`RELEASE_NOTES.md:26-27`) and "Follows your system appearance" (`RELEASE_NOTES.md:63`); the appearance theme picker itself predates this range (`enum AppTheme` introduced in `0138d27`, an ancestor of `359b8bc`), so these commits change no documented behavior.
- Notch captions toggle (`955cf84`, PR #59) and captions reserve space only when enabled (`841a5a1`, PR #60): **not described in the notes — wrong/incomplete.**

Current behavior (code): Settings has an "Expressions" section with a "Show captions" toggle, "Shows movement guidance and status text under Gaze" (`Sources/App/NotchSettings.swift:71-75`), defaulting to on (`Sources/App/Preferences.swift:355-360`). It is display-only: it hides caption words and their symbols, never the mark itself, and changes nothing about what is checked or when unlock happens (`Sources/App/Preferences.swift:305-311`). With captions off, the lock-screen panel still expands and the companion mark still demonstrates each movement (`challengeHint` is independent of caption text, `Sources/LockScreen/NotchCapsule.swift:121-131`); only the words/symbols and their reserved space disappear (`Sources/LockScreen/NotchCapsule.swift:517-519,525-546`; `Sources/LockScreen/NotchCapsuleController.swift:58,100`).

Two notes paragraphs are now wrong or incomplete:

Quote 1 (`RELEASE_NOTES.md:20-23`):
> Choose one or two movement challenges in Settings under “Movements to unlock this
> Mac.” Two is the default. Follow each prompt and return to your starting position;
> onboarding shows how. The normal return animation keeps its text caption hidden,
> while Reduce Motion retains the written cue.

This is incomplete: it never mentions the captions preference, and the return-caption sentence no longer covers all cases — with "Show captions" off there are no written cues at all, including under Reduce Motion (the off switch gates every caption, `Sources/LockScreen/NotchCapsule.swift:541-542`).

Proposed replacement, in the document's voice:
> Choose one or two movement challenges in Settings under “Movements to unlock this
> Mac.” Two is the default. Follow each prompt and return to your starting position;
> onboarding shows how. The normal return animation keeps its text caption hidden,
> while Reduce Motion retains the written cue. If you turn off “Show captions” under
> Expressions in Settings, the panel stops showing movement guidance and status text
> entirely and keeps only the mark itself; the companion still demonstrates each
> movement, and what Gaze checks before unlocking stays exactly the same.

Quote 2 (`RELEASE_NOTES.md:25-27`):
> A panel in the notch: a padlock while it's resting, the Gaze mark while it's looking, a
> green tick when it's you, a shake when it isn't. Three styles and size sliders, because
> notches and taste both vary.

This is incomplete: a reader cannot learn the captions toggle exists or where to find it.

Proposed replacement, in the document's voice:
> A panel in the notch: a padlock while it's resting, the Gaze mark while it's looking, a
> green tick when it's you, a shake when it isn't. Three styles and size sliders, because
> notches and taste both vary. Under Expressions in Settings you can turn the written
> guidance and status text off; the mark and its movements stay, only the words go away.

Uncertainty, not a verdict: `RELEASE_NOTES.md:68-69` says "Anti-spoof checking is a switch with nothing behind it yet. No model is bundled, so it stays off and says so," while `Resources/` on disk contains `Resources/Spoof.mlmodel` and `build.sh:114-125` compiles it into the bundle, and `Tools/Release/ModelClearance/clearance.json:99-101` describes it as the active lock-screen spoof gate. That paragraph predates the reviewed range, so it is outside the step-2 brief; I could not determine from read-only review whether the notes or the on-disk model state is the stale side. Owner should confirm before release.

## 3. Signing and distribution

- What the build signs with today: `build.sh:12-16` resolves an identity via `Tools/Release/Signing.sh`, which accepts Developer ID Application always, or Apple Development for non-`DIST` builds (`Tools/Release/Signing.sh:10`). `SESSION-HANDOFF.md:32` records "Signing remains Apple Development; no Developer ID identity available." Non-release builds sign with `--options runtime` but no secure timestamp (`build.sh:18,26,208-210`).
- What a public release requires: a Developer ID Application signature with secure timestamp and Hardened Runtime, plus notarization and stapling, for a DMG distributed outside the App Store. The repo enforces exactly this: `build.sh:202-221` signs release with `--timestamp` and then refuses to continue unless the authority is `Developer ID Application` with a `Timestamp`; `Tools/Release/verify.sh:24-39` requires Developer ID authority, valid team id, timestamp, Hardened Runtime flags, camera entitlement without unsafe entitlements, a stapled ticket (`stapler validate`) and Gatekeeper acceptance (`spctl --assess`).
- Tooling present: release signing path (`build.sh:19-26,177-221`), clearance gate (`build.sh:20-23`, `Tools/Release/ModelClearance/validate.py`), DMG creation with Developer ID signing + notarytool submit + stapler staple + spctl assess (`Tools/Release/DMG/package.py:92-100,138-149`, `Tools/Release/DMG/README.md:22-33`), read-only preflight (`Tools/Release/preflight.sh`) and artifact verification (`Tools/Release/verify.sh`).
- Tooling absent: the certificate itself (no Developer ID identity on the machine per `SESSION-HANDOFF.md:32` and `Tools/Release/READINESS.md:350-353`); a notarization credential profile (a `--notary-profile` is required input, `Tools/Release/DMG/package.py:94-96`); and any completed release run — all recorded DMGs are `--local-preview` with `distributionReady=false` (`Tools/Release/DMG/package.py:160`, `SESSION-HANDOFF.md:326`).
- What happens on a user's Mac with an Apple Development-signed download: the quarantine bit is set on download; Gatekeeper does not trust Apple Development (or ad-hoc) signatures for quarantined software, so the app is refused at open and no notarization ticket can exist for it. Concretely, `Tools/Release/verify.sh:38-39` (stapler + spctl) cannot pass for such an artifact. The exact user-visible dialog wording is platform behavior not stated anywhere in the repo, so it is not quoted here.

## 4. Licence and attribution clearance

No overall clearance is declared here. Per-asset status, all from `Tools/Release/ModelClearance/clearance.json` unless noted:

| Bundled asset | Stated licence / permission basis | Settled for public distribution? |
|---|---|---|
| Face-embedding model (`FaceEmbedding.mlmodelc`, weight SHA-256 `c28620…c1545`) | Pinned Sapphire repo licence is AGPL-3.0 (`NOTICE.md:57-61`); owner-supplied screenshot records Shariq agreeing to use of the Sapphire ArcFace model with credit (`Tools/Release/ModelClearance/SHARIQ-PERMISSION-20260918.md:1-23`, noted in `NOTICE.md:78-82`, `SESSION-HANDOFF.md:34-38`) | No. Permission covers the Sapphire-matched precompiled weights with attribution only; it does not cover the different raw `FaceEmbedding.mlpackage` (weight SHA-256 `f9145f…c00da9`, `NOTICE.md:63-66`), upstream training/weight rights (possible InsightFace descent, `NOTICE.md:68-71`), or AGPL source/notice obligations (`NOTICE.md:71-74`). Clearance status `permission-recorded-upstream-and-alternate-package-unresolved` (`clearance.json:87`). Evidence that would settle: a grant covering the exact bundled bytes plus upstream/training rights, or a replaced model with clean provenance; plus an AGPL-obligations analysis for the intended distribution. |
| Raw package `FaceEmbedding.mlpackage` | None stated; provenance unresolved (`NOTICE.md:63-66`) | No. Evidence that would settle: provenance + redistribution grant for those exact bytes, or removal from the distributed artifact if `build.sh` never bundles it. |
| Spoof detector (`Spoof.mlmodel` → `Spoof.mlmodelc`) | Trained locally from a Roboflow "Face Spoof Detection v1" CreateML export that self-identifies as CC BY 4.0 (`clearance.json:115-122`); no redistribution grant recorded (`clearance.json:124-130`) | No. Evidence that would settle: dataset licence terms confirming trained-weight redistribution, recorded with grant pointer and scope (see `Tools/ModelLab/README.md:27` per `clearance.json:132`). |
| Setup art (`Resources/Art`) | Sources identified in manifests; no authorship/grant statement (`clearance.json:296-314`) | No. Evidence that would settle: per-file authorship and redistribution grants, or replacement with first-party art. |
| Credit portraits/icons (`Resources/Credits`) | Third-party likenesses and app icons; no per-file permission record (`clearance.json:373-388`) | No. Evidence that would settle: permission for each portrait/icon, or removal of the file and its Settings row. |
| App icon (`Resources/AppIcon.icon`) | Authorship unrecorded; old generator script does not evidence current bytes (`clearance.json:412-427`) | No. Evidence that would settle: owner confirmation of first-party authorship and scope. |
| Legacy liveness model (`Liveness.mlmodelc`) | No redistribution evidence (`clearance.json:466-481`) | No. Evidence that would settle: provenance + grant, or confirmed exclusion from the bundle. |
| TourKit (`ThirdParty/TourKit`) | MIT, © 2026 Ram Patra, pinned commit `4f2b109…`, verbatim source + licence with hashes, licence shipped in bundle (`NOTICE.md:33-44`) | Documented as well as vendored code gets; no open item recorded against it. |
| Glance notch-flare idea | MIT, © 2026 Jonathan Zhou; implementation described as composed primitive, not a copy (`NOTICE.md:8-29`) | Documented; idea-level attribution, no code copied per the record. |
| FaceIDKit animations | Licensed to this app alone, explicitly not for redistribution; kept out of git (`NOTICE.md:86-91`) | Settled by exclusion, provided it stays out of the bundle and history. |
| SkyLight private API use | Undocumented symbols used for panel placement only, no authentication role (`NOTICE.md:93-103`) | Legal/platform-risk question, not a licence grant; App Review does not apply (no App Store distribution) but symbols can break per-release. |

`LICENSE` is MIT, © 2026 Owen Cope (`LICENSE:1-3`). `SECURITY.md` is a security design document, not a licence source; its only distribution-relevant statements are that `build.sh` enables Hardened Runtime without conferring Developer ID/notarization/sandboxing (`SECURITY.md:107-108`) and that opening the repository requires resolving the model-licence questions first (`SECURITY.md:331-335`). `README.md:130-138` agrees the model licence records are inconsistent and must be documented per exact bundled model.

## 5. Privacy and entitlements

- Camera usage description exists and is not a placeholder (`Resources/Info.plist:36-38`): "Gaze uses the camera to enroll your face and to recognize you when your Mac is locked. Images are matched on-device and never leave this Mac." It covers enrollment and lock-screen recognition; no other privacy-sensitive usage strings (microphone, location, contacts, etc.) are declared anywhere under `Resources/` — grep for usage-description keys finds only `NSCameraUsageDescription`.
- Entitlements (`Resources/Gaze.entitlements:1-12`): exactly one, `com.apple.security.device.camera = true`. The app is deliberately not sandboxed, with the reason documented in the file (unlock backends need helper communication / CGEvent posting, neither survives the sandbox). No entitlement looks broader than a face-unlock utility needs; nothing resembling network, JIT, DYLD-environment or library-validation exceptions is requested, and `Tools/Release/verify.sh:34-37` explicitly fails the release on those unsafe entitlements. Accessibility and login-item access are requested at runtime through macOS prompts, not via entitlements — correct as far as this review could determine.
- Separate preview entitlements under `Tools/GazePasswords/` (`Preview.entitlements`, `Signing/Passwords.entitlements`) belong to the Passwords preview product, not the Gaze release bundle, and were not assessed here beyond noting their location.

## Material limits

- Read-only by brief: nothing was built, run, signed, notarized, or inspected outside the checkout, so live signature state, keychain contents and on-machine identities are taken from `SESSION-HANDOFF.md` and `Tools/Release/READINESS.md`, not re-verified.
- Git history reads were limited to the step-2 range plus two provenance checks (`0138d27` predates `359b8bc`; captions preference introduced in `955cf84`); full-history auditing (secrets, asset provenance) is explicitly out of scope and still open per `SECURITY.md:331-335`.
- Gatekeeper's user-visible wording for an Apple Development-signed download is stated as general platform behavior; the repo pins only the requirement side.
