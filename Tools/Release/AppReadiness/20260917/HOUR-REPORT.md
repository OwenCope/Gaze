# Gaze native app follow-up — September 17, 2026

The new local candidate is `build/gaze-hour-20260917/Gaze.app`. It is ready for
owner-supervised testing, not public distribution. The running, owner-tested
`build/Gaze.app` was preserved and was not relaunched.

## What changed

- Iris added a direct **Try Again** action when the camera fails during capture.
  Both onboarding and Add a Face use the existing retry/cancellation path. The
  action is absent once enrollment is complete and being saved.
- Milo made the Updates panel useful in an installed app: the disabled source-folder
  control is absent, nonempty release notes have a disclosure, and the copy explains
  that Gaze opens downloads rather than installing them automatically.
- Juno added lesson clock pausing across visibility and Reduce Motion changes.
  Root corrected the gate from `scenePhase == .active` to `scenePhase != .background`:
  visible macOS hosting windows can legitimately be inactive. This preserves the
  existing teaching animations while freezing background playback.
- Ezra added truthful Open at login state, registration-failure feedback, and a
  direct path to Login Items when approval or repair is needed. Root added a further
  recovery fix: once an external change reaches the failed request's intended
  enable/disable state, the old error clears. Unresolved errors remain visible.

Registration, authentication, recognition thresholds, enrolled data and update URL
policy were not changed. Earlier wallpaper and updater fixes are included in this
candidate; their original evidence remains in `REPORT.md`.

## Verification

| Check | Result and scope |
| --- | --- |
| Final optimized app build | Pass, no compiler warnings/errors. Built with macOS 26.5 SDK, deployment target 26.0, arm64. |
| Actual signature | Deep strict verification passes. Apple Development identity matches the owner-tested build; hardened runtime and expected entitlements remain intact. |
| Model payloads | All five FaceEmbedding files and all twelve Spoof files exactly match the owner-tested bundle. Neither legacy Liveness model format is bundled. |
| Settings/capture fixture | 56 automatic checks pass against actual extracted Settings members and the actual capture view with test service/permission substitutions. |
| Native release-note interaction | Opened the light/dark disclosure arrows through CUA. Literal notes remained text; Download and source-folder callbacks were counted against fake services. The earlier interactive fixture run passed 50 overlapping checks. |
| Native camera-retry interaction | Inspected the visible glass button in onboarding and Add a Face. Return invoked the retry callback once in both. The interactive keyboard run passed 54 overlapping checks. No real camera ran. |
| Lesson lifecycle | New mounted-view checks pass for background freeze/resume, selection while paused, explicit pause, Reduce Motion and detach. Existing visible-inactive-window motion checks still pass. |
| Actual SwiftUI scene | Hiding a separate scene probe produced background state, a paused Metal view and a frozen clock. Minimize/restore was not established because CUA could not capture the hidden window. |
| Onboarding | Existing policy checks and 54 light/dark offscreen screens pass. Display-driven lesson checks produced changing frames for waiting, turn, success and retry. |
| Enrollment lifecycle | 54 generated-pose/dummy-vector checks plus cancellation, stale completion, reopen isolation and teardown checks pass. No store, camera or owner authentication was used. |
| Settings UX regressions | Existing checks pass after the final Settings change. |

The fixture counts overlap; they are not additive. SDK compilation is not a macOS 26
runtime or clean-install test. Native fixtures exercise presentation and callbacks,
not live SMAppService registration or real camera recovery. Offscreen image caching
omits some compositor-backed glass controls, so those controls were inspected live.

## Exact artifact

- Path: `build/gaze-hour-20260917/Gaze.app`
- Executable SHA-256: `70b892078b03824b867b045dfee3a662c6731b89e7afac2e2886f4dc1f38f761`
- Executable built: September 17, 2026, 02:07:51 UTC
- Architecture / deployment / SDK: arm64 / macOS 26.0 / macOS 26.5
- Signature: Apple Development; not a Developer ID/notarized release
- Fingerprints and validation metadata: `HOUR-CHECKPOINT.json`

The owner-tested executable remains:
`919e168b1633a0124f019130573ca1d3bb56a15b44d86da3e7ffb16e3f22ab14`.

## Evidence and repeatable checks

Logs and generated fixtures are under `build/gaze-hour-20260917/`:

- `final-build.log`, `final-build-version.txt`, `final-build-inputs.json`
- `onboarding.log`, `onboarding/motion-cadence.json`, and rendered onboarding screens
- `enrollment.log`, `settings-ux.log`
- `settings-automated.log`, `settings-automated-results.json`, `settings-automated-source.json`
- `settings-interactive.log`, `settings-interactive-source.json`, `capture-interactive.log`
- `settings/` source extracts, manifests, screenshots and latest result JSON
- `settings-stale-error-before.log` records the reproduced external-repair failure
- `scene-probe/scene-events.json` records actual app/window/renderer state

`Tools/SettingsInteractionRegression/README.md` explains automatic and interactive
modes and their boundaries. `Tools/OnboardingRegression/scene-probe.sh` builds a
camera-free scene probe; it is not production Gaze. All fixture processes were closed.

## Next owner test

1. Quit the currently running Gaze through its menu, then open the exact candidate
   above with `--settings`. Avoid running two copies together. The older
   `build/Gaze.app` remains available to return to.
2. Check actual Open at login enable/disable and approval behavior; review the
   Updates and companion panels. The service itself was simulated in these tests.
3. Complete supervised setup, positive/negative unlock, password fallback and
   sleep/wake/relock acceptance on this exact artifact. A prior basic-unlock pass
   does not automatically establish these cases for a rebuilt candidate.
4. Complete clean install/update and supported-Mac runtime checks.

Public release still needs model/artwork distribution rights, Developer ID signing
and notarization, plus deployed update-feed/download acceptance when website work
resumes. The six asset-clearance groups remain unresolved. Nothing was published,
committed or pushed, and no production camera, lock or credential trial was run.
