# Gaze release gates

September 18 update: [ShipPass20260918/RESULT.md](ShipPass20260918/RESULT.md)
records the current TourKit/TipKit app candidate, local DMG, backend/admin fixes,
SEO checks, and remaining acceptance gates. The candidate builds and verifies;
the latest full-window tour includes movement demonstrations and was installed
and relaunched at `build/Gaze.app` at the owner's request. The earlier DMG predates
this unified tour; see the report for the current executable hash. The website production
build and 82 backend/SEO tests pass. No deployment command was run. The older
checkpoints below are historical and do not describe this candidate's hash.

Latest app + website UX pass: [UXReview20260917/RESULT.md](UXReview20260917/RESULT.md).
The new app is now installed and running from the normal `build/Gaze.app` path;
the previous owner-tested bundle is backed up as `Gaze.before-full-ux-20260917.app`.
Seven website source files were updated and a sample-data preview is available at
http://127.0.0.1:55524. Build, signature, type/lint, route and component checks pass.
Final live visual acceptance was blocked by window-capture errors; the production
website was not deployed. See that report for remaining UX and release gates.

Previous checkpoint:

Latest native app checkpoint: [AppReadiness/20260917/HOUR-REPORT.md](AppReadiness/20260917/HOUR-REPORT.md).
The candidate at `build/gaze-hour-20260917/Gaze.app` adds camera-failure retry,
readable release notes, background lesson pausing and truthful login-item recovery
to the earlier wallpaper/updater fixes. The SDK 26.5 build, signature/resource checks,
onboarding/enrollment suites and isolated UI checks pass. A later direct launch
opened Settings successfully and displayed Gaze is ready; the owner-tested
`build/Gaze.app` file remains unchanged. Public release still needs
owner acceptance, supported-Mac installation/update checks, distribution rights,
Developer ID/notarization and deployed update-service acceptance. Website work is paused.

Latest website checkpoint: Morning20260917/REPORT.md. The morning fixes and their
synthetic tests passed; the preview process stopped in a later Droppy crash.
Public launch is still not approved, and crash cause remains unconfirmed.

## Current local checkpoint — September 16, 2026

Latest UI follow-up: lossless native-detail imagery, a fixed-stage segmented gallery
and 0.6-speed hero preview are integrated. Current local build logs are
build/website-gallery-pacing-final. WholeSiteReview/REPORT.md records newly found OPEN
editor publication/draft-recovery and contrast issues; this is not website launch
sign-off. See GalleryPacing/REPORT.md and PreviewImageQuality/REPORT.md.

Website update: public and private page layouts are now unified, old gallery media
is replaced with current labelled setup previews, and Credits is revised after
owner feedback. Production build, TypeScript, scoped lint and synthetic local
page checks pass. Preview remains http://127.0.0.1:55523; logs are under
build/website-whole-site-final. See SecondaryPages/REPORT.md and SOURCES.json.
Admin reliability source/report packaging is now complete in AdminReliability/.


Local development builds are available. Public release is not approved. The owner
requested localhost only and deferred Developer ID signing; nothing was deployed
or uploaded.

- Gaze: `build/Gaze.app`, executable SHA-256
  `919e168b1633a0124f019130573ca1d3bb56a15b44d86da3e7ffb16e3f22ab14`.
  Running process 36107 was verified after the Gaze-only usability pass. This
  Apple Development build includes truthful readiness, setup/Settings improvements,
  companion-preview changes and the corrected error shake. See
  GazeUsability/20260916/REPORT.md for the exact scope and checks.
- Gaze Passwords: `build/browser-integration/Gaze Passwords.app`, executable SHA-256
  `cc1751f3406e31f5b4e87e433544557c4a26aab484a6666a044655c9385b0e92`.
  Local protected build and verification passed. The real browser action popup
  reached the native service using the status-only path; no credentials accessed.
- Website: the requested homepage revision is integrated and running at
  `http://127.0.0.1:55523` with synthetic data and no production secrets. The full
  production build, TypeScript, scoped lint and all five HTTP assertions pass.
  The switcher is below the laptop, hover tilt is removed, FAQ/mobile navigation
  animate, and current Solid/Semi media use the corrected scale and clean background.
  The old Liquid Glass clip was removed; a faithful current capture remains pending.

The integrated website includes private metadata configuration, conditional catalog
mutations, atomic release renames, version-checked tester notes, bounded email-code
attempts/replay protection, sanitized Markdown and validated download destinations.
Current notes, concurrency and privacy suites pass against synthetic SDK/filesystem
fixtures. Notes browser tests passed draft retention, acknowledgement advancement,
conflict/cancel recovery, duplicate submission and scoped shortcuts. Full-site
TypeScript and lint of the latest integrated files pass. These are not production
service or live administrator acceptance results.

The homepage revision passed desktop/mobile interaction checks, including rapid
FAQ reversal, immediate keyboard/reduced-motion changes, closed-content inertness,
Escape focus restoration and automatic preview pausing. Earlier native-glass capture evidence is historical; that old flat-face media is
no longer selected by the website. See HomeMotion/ReferenceCorrection/REPORT.md
for the current media and capture limitations.

Additional homepage polish is integrated: a compact demo layout, pointer-only
theme-icon motion, scoped feature-rail keyboard controls and larger footer links.
The combined production build and focused desktop/mobile browser checks pass.
See HomeMotion/SmallPolish/REPORT.md.

The owner now reports a successful basic unlock on the current Gaze candidate.
That smoke check is passed by owner report; broader negative/fallback, wake/relock
and clean-install/update acceptance are still pending. The owner supplied Sapphire’s source. The precompiled recognition weights match
the pinned Sapphire weight blob, whose repository LICENSE is AGPL-3.0 (not the
reported GPL-3.0). Upstream/model coverage and distribution obligations remain
unresolved. See ModelClearance/SAPPHIRE-EVIDENCE-20260916.md.

Remaining public-release requirements: model/asset redistribution clearance (six
groups unresolved), Developer ID/notarization when supplied, owner-supervised live
acceptance and clean install/update checks, private Blob migration and production
OAuth/email wiring. The development Passwords profile expires September 20, 2026
at 23:51 UTC. No model or recognition threshold was changed; the experimental
ObjectPrint candidate was not promoted (47/100 test spoof accepts).

Details: `RESUME-HANDOFF-20260916.md`, `NotesVersioning/BROWSER-RESULT.md`,
`../GazePasswords/Release/BROWSER-STATUS-SMOKE-20260916.md`,
`MetadataPrivacy/METADATA-PRIVACY-HANDOFF.md`, `ModelClearance/README.md`.

## Previous local candidate — September 15, 2026, 21:53

**NOT launch-ready.** The Hydra investigation and integration are complete locally;
owner validation, model/asset permissions, release signing and the deployed update
flow remain open. The controlling current checkpoint is at the top of
`CHALLENGE-INVESTIGATION.md`; historical September 14 evidence below is retained.

Local binary SHA-256:
`f75675d3f58213ab4128884b7f7274153d008937141b42e8b656dc8904ee289c`.
Built 21:53:01, strict signature verified, relaunched as PID 46045. This is an Apple
Development candidate, not a notarized distribution build. Release verification
fails at the Developer ID requirement.

The movement-count change adds one/two selection for Mac unlock and its scan-only
diagnostic. Two remains the default. Attempts capture the choice and reject policy
changes before accepting further proof or releasing a password; browser approval
still requires two. 860 unlock/source/gate checks, 34 isolated preference checks,
production wiring checks and 54 onboarding renders passed for that change.

Walk-away locking now uses per-analysis sustained absence evidence, checks session,
permissions/policy and input throughout, stops its camera on cancellation, and
waits 30 seconds between checks during uninterrupted idle. Its lifecycle is
independent of password replay. 99 presence/scheduling checks, 9 policy checks,
lifecycle wiring and a fresh run of all 860 unlock regressions pass. The feature
remains OFF in the owner's preferences. No unattended camera or lock trial was run.
See `WALK-AWAY-READINESS-20260915.md` for the lead's corrections and limits.

The current Gaze and protected Gaze Passwords builds both launched. Signed status
probes reported available services with no approval or credentials requested.
This verifies local service reachability, not a real browser-to-vault face-approved
fill. Passwords artifact/test evidence and its separate distribution gates are in
`../GazePasswords/Release/RELEASE-READINESS.md`.

Earlier integration also passed 54 enrollment checks plus setup lifecycle, 58
submission checks, 6 product-boundary checks, 43 release-verifier fixture checks,
and pose-image/caption/render suites. These were not all rerun for the count option.
They do not replace the real-world gates below. Native Settings inspection of this
build was blocked by computer-use startup failure.

The owner reports good lock/unlock behavior on the preceding build. Before release,
validate the new option on this exact artifact: one complete movement unlocks only
after returning to the starting pose; an omitted return fails; switching back to
two requires both movements. Also complete the broader negative/wake/fallback and
recognition/PAD evaluation below. No live lock test was automated.
The local website feed now respects the release privacy setting and passes its
route tests/typecheck; the live deployment still lacks that route. No upload or
production deployment occurred.


## Latest diagnostic build — September 14

The owner reproduced the turn failure at 21:58 on this diagnostic build. The
left-turn failures were successful comparisons below the unchanged 0.45 cutoff:
0.405143, 0.357456, 0.274778 and 0.149604. They were not missing embeddings in these
observed frames. The preceding nod completed, then left-turn mismatches discarded
all movement proof. Recovery reused “Look back here,” incorrectly resembling the
return phase of a successful movement. The follow-up changes recovery copy to
“Face the camera to retry”; it does not fix or relax identity matching.

Executable SHA-256:
`fad6a7afd63ee97089022a4a9a9445fe7dfa7ab5f1fc08d27657f18a4165f683`.
Built, signature-verified and relaunched while the owner console was unlocked.
Settings confirmed automatic unlock on, both movements and photo rejection on,
and walk-away locking off. No agent-initiated lock or credential entry occurred.

This build installs the pending render-timer stability and two-frame GPU budget
changes, and uses centered recovery guidance after a discarded movement attempt.
The discard still clears all movement proof. Identity/PAD thresholds, enrollment
alignment, required movements and password-submission rules are unchanged.

Movement failure diagnostics now distinguish `embeddingUnavailable` from
`belowThreshold`, invalid configuration/scores, cancellation and missing enrollment.
An unavailable embedding does not by itself establish missing pupil landmarks;
that still needs investigation if observed. The prior installed binary already
contained the evaluator actor; this is not a newly introduced actor migration.

527 unlock/evaluator/continuity/frame/diagnostic checks, 127 hardening checks,
58 submission checks, production-wiring checks and companion integration/rendering
tests passed. These do not measure live lock-screen frame rate or prove turn
recognition fixed. One owner-initiated reproduction on this exact build is pending.

Status: **not ready to distribute**, September 14, 2026. Gaze Passwords is outside
this checklist. A local build, Test Recognition, or the animation preview is not
evidence that the Mac can actually unlock.

## Current evidence

- Real lock-screen logs from the earlier build show a first-fresh-frame timeout
  roughly one second after search began. They do not establish password delivery
  or a successful Gaze unlock.
- The new frame gate gives camera startup four seconds before its first accepted
  frame; the established-stream timeout remains one second. Frame age (500 ms),
  evidence continuity, identity, PAD and two-movement requirements are unchanged.
- Required PAD model loading now precedes camera startup, followed by a fresh
  session/input check. This avoids loading the model while capture is starting.
- Foreground capture (including Test Recognition and enrollment) now holds an
  unlocked-console lease. Lock, sleep and user switching stop it; a late frame or
  delayed permission result cannot restart it. LockWatcher explicitly uses the
  separate lock-screen scope and retains its existing locked-session checks.
  Reopen a practice window after unlocking rather than auto-restarting its camera.
- Walk-away checks now refuse stopped capture and require a recent, explicit
  no-face result before concluding absence. The owner's walk-away setting remains
  off; automatic locking has not been exercised by the agent.
- Last-attempt diagnostics are in the existing Unlocking information popover.
  They are memory-only, attempt-bound and contain no passwords or camera images.
  A sent password is not reported as a confirmed unlock.
- Automatic unlocking requires explicit local consent. It does not become enabled
  merely because an older install selected the keystroke backend. The owner's
  current installation was explicitly enabled at their request.
- A submission budget permits at most one password submission per lock cycle.
  Permission, session, manual input, consent and evidence are rechecked before
  password access and posting. No field-clearing or password retries were added.
- Local regression tests cover these decisions with synthetic inputs. They do
  not establish real-world false-accept rates or prove loginwindow transport.

## Owner-supervised lock-screen test — OPEN

Earlier local build checked on September 14:

- Executable SHA-256:
  `4a694a484a637c16cee3d3c8fe24d347105626b0ecb42e97662036584dfe2333`.
- Full build and strict signature verification passed using the existing local
  signing requirement. This is not a Developer ID distribution build.
- 322 unlock/evaluator/continuity/frame/diagnostic checks, 127 hardening checks,
  58 password-submission checks, 386 recognition-math checks, 54 enrollment checks
  plus setup-lifecycle checks, and production-wiring checks passed with synthetic
  data. No password events were posted by those tests.
- 23 release-identity/build checks and 20 artifact-verifier fixture checks passed.
  The actual local app correctly fails release verification at Developer ID.
- The relaunched UI shows automatic unlock enabled, camera/Accessibility allowed,
  PAD and two movements enabled, and walk-away locking off.
- A live, unlocked Test Recognition session advanced from waiting for frames to
  **242 analyzed frames / 0 expired**, with no face and zero recognition samples.
  The test window was then closed. This demonstrates desktop capture delivery,
  not a recognized owner or working lock-screen unlock.
- The owner subsequently reported one successful unlock, but repeated failed or
  misleading movement guidance. Logs show fresh lock-screen capture in 298–658 ms,
  resets on identity mismatch/invalidated inference, one PAD rejection, and a
  password submission at 20:42:15 on September 14. This is evidence that delivery
  can work, not that unlocking is reliable or that fallback tests are complete.

The follow-up fix separates sustained identity mismatch from total face-presence
time. A matching frame clears the rejection timer; low scores still invalidate
the match and all movement proof. The four-second rejection hold, identity cutoff,
PAD threshold and both required movements remain unchanged. Added diagnostics
identify the actual requested movement and distinguish expired inference from
capture-continuity invalidation. This follow-up needs another real-device test.

The production Metal renderer also inverted the horizontal guidance rotation:
the left-turn animation moved its face toward screen right. An offscreen pixel
regression reproduced this before the fix. Correcting only the body rotation
sign passes 18 left/right/down rendering checks across three materials and two
sizes, plus the existing companion integration tests. Recognition yaw/pitch
conventions and thresholds are unchanged. This fixes the demonstrated rendering
error; agreement with the owner's real movements still needs a live retry.

Both follow-ups were rebuilt and relaunched on September 14 with executable
SHA-256 `85d8c63623aac10bda8ab063de15466a6c8b2132eb5e1b6f6ef86c3c3b1534a5`.
Strict signature verification, 488 unlock/evaluator/continuity/frame/diagnostic
checks and production-hold wiring checks passed. The relaunched Settings window
shows automatic unlock on, camera and Accessibility allowed, photo rejection and
two movements on, and walk-away locking off. The owner reported a successful
unlock on this build. Logs show a blink/open-mouth sequence followed by one
submission at 20:56:53. A subsequent left-turn attempt repeatedly lost the
identity match and restarted its first movement until the search ended. This
remains a reliability blocker; launch preparation is paused in favor of it.

The next guidance revision adds an explicit return-to-rest phase after the
existing movement detector observes enough valid movement. The blob eases back
to center instead of continuing to demonstrate the outward motion; completion
still requires the user's return, two actions, matching identity and the existing
PAD/evidence checks. The demonstrated turn is smaller, but the measured movement
threshold is unchanged. This addresses missing guidance, not proven recognition
robustness at turned poses. A real left/right retest remains necessary.

This guidance revision was rebuilt, signature-verified and relaunched with
SHA-256 `04ef563b468b3bd442956b8f8d425286627befff63b7d0437c40305135326100`.
516 unlock/evaluator/continuity/frame/diagnostic checks, submission regressions,
production wiring and companion rendering/integration checks passed. The actual
lock-screen flow has not yet been retested on this revision.

Do not automate locking, enter credentials, record the password field, or create
a deliberately incorrect saved password. Keep password and Touch ID available.
The owner starts each lock and performs any manual authentication privately.

Record the exact app executable hash, macOS version, camera and outcome for:

1. Cold launch, then owner-initiated lock: fresh frames, face detection and both
   movement prompts appear. No password input before all verification completes.
2. Normal face verification: exactly one submission, then actual macOS unlock.
   Recheck Settings → Unlocking → information for the recorded outcome.
3. Wake after display sleep: same flow, with no duplicate attempt or premature
   password input. Repeat enough times to expose intermittent capture startup.
4. Cover camera / move out of frame / omit a movement: no password input. Manual
   password and Touch ID fallback remain usable where macOS offers them.
5. Begin manual input during scanning: Gaze yields without clearing the field or
   continuing password entry during that lock.
6. Pause or disable automatic unlocking: no subsequent Gaze submission. Re-enable
   only at the owner's request; Test Recognition alone must not enter a password.
7. If a real submission fails, record only the non-secret diagnostic and time.
   Confirm there is no repeat during that lock, then unlock manually. A failure
   remains a release blocker until attributed and corrected.

## Recognition and anti-spoof evidence — OPEN

- Evaluate consented, held-out enrolled and non-enrolled users on supported Macs,
  including dim lock-screen lighting, glasses, pose changes and multiple faces.
- Evaluate held photos, phone/tablet replay and other relevant presentation
  attacks. Keep attack sessions separate from training and threshold selection.
- Record false accepts/rejects and PAD errors per condition, with sample sizes
  and uncertainty, against the exact distributed model hashes and thresholds.
- Agree on release acceptance criteria before evaluating; do not lower thresholds
  to make a demo pass. Existing weak experimental models remain uninstalled.
- Do not advertise Touch ID-equivalent security or claim that passing movement
  challenges makes an RGB-camera system spoof-proof.

## Model and asset redistribution evidence — OPEN

The repository's historical README and NOTICE disagree on the recognition model's
license. Owner-reported permission has not yet been attached to a specific model
version and distribution scope. Record the actual permission/license for each
bundled model, its provenance/hash, attribution and any redistribution terms.
Do the same for third-party assets and training/evaluation data. This checklist
does not determine or grant legal rights.

## Signed release artifact — OPEN

Local certificate inventory currently has Apple Development, not Developer ID
Application. The release build now refuses ad-hoc or development-only signing
before building or replacing output. Local builds preserve their existing signing
requirement. Release output defaults to a separate `build/release/Gaze.app`.

```sh
DIST=1 GAZE_SIGNING_IDENTITY="Developer ID Application: …" bash build.sh
```

The owner must provision an appropriate certificate and authorize notarization.
Do not place signing credentials in source, logs or command history. Do not upload
an artifact until its included assets are cleared for that distribution. After
notarization and stapling, validate the exact bundle:

```sh
bash Tools/Release/verify.sh build/release/Gaze.app
```

This checks the bundle, required models, Developer ID, secure timestamp, hardened
runtime, entitlements, stapled ticket and Gatekeeper acceptance. It does not
perform notarization or launch the app. Record the final archive checksum too.

## Clean installation and update — OPEN

- Use a separate test Mac/account with no development permissions. Test the
  quarantined downloaded artifact, first-run camera and Accessibility prompts,
  enrollment, explicit unlock consent, normal launch and login item.
- Verify all claimed OS/architecture combinations. The build script produces the
  build host's architecture, not a universal binary. Private lock-screen window
  APIs need real testing on every supported OS version.
- Verify permission revocation, camera contention, sleep/wake and fast user
  switching fail closed without trapping the user at the lock screen.
- Verify update/replacement keeps access to existing enrollment and protected
  password storage with the intended signing identity. Never bypass Keychain or
  TCC checks to make migration pass.
- Verify uninstall leaves ordinary macOS password/Touch ID authentication intact.
  Do not install, remove or modify authentication plugins as part of this test.

Only close these gates with recorded evidence. Passing `verify.sh` alone is not a
ship decision.
