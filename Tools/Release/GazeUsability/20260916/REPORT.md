# Gaze usability pass — September 16, 2026

Scope: Gaze only. The owner deferred website work and Passwords. The forty-minute
work window began at 07:21 UTC and ends at 08:01 UTC. No git operation, deployment,
model change or security-threshold change was performed.

## What changed

- The menu now reports camera permission, unlocking-off, recognition-only and
  backend-attention states instead of calling every enrolled configuration ready.
  Review, scan-only and browser-only launch modes are identified explicitly.
  Menu actions and security behavior are unchanged. Finn 3 and Suki 3 did not land
  this change; root implemented it after checking the unchanged source.
- Settings shows the scheduled resume time and refreshes once a pause expires.
  Missing access/setup gets a direct navigation button to its existing section.
  Its Accessibility indicator now uses the same two-part permission readiness as
  setup and the unlock backend. No permission request runs from the navigation.
- Add a Face is disabled at the existing face limit, with an explanation. Escape
  cancels a name edit; each name field has a specific accessibility label and
  exposes the full name in its tooltip. Existing removal authorization remains.
- Mira 3 added an optional Test Recognition action after complete first-run setup.
  It is absent after failure, partial setup and add-face flows. Root centered the
  action and moved its explanation into the content: it uses the camera only when
  chosen and does not lock or unlock the Mac. Completion copy confirms saved data
  instead of promising readiness solely from password/permission completion.
- Odin 3 added the Waiting for macOS phase to the simulated appearance preview.
  Automatic playback follows the successful sequence; rejection stays available
  manually. Playback stops when the scene becomes inactive. Camera-off help remains.
- Rex 3 resets the decorative setup companion's clock when playback resumes and
  adds a 180ms visibility fade, disabled under either Reduce Motion preference.
- Root fixed a real password-error animation bug: integer rounding discarded every
  fractional frame, so the shake never moved. Its progress is now CGFloat, with
  immediate suppression under Reduce Motion. Password handling is unchanged.

## Evidence

- Combined optimized app build and strict signature verification passed; local
  Apple Development identity matches the previous build's signing requirement.
- Onboarding policy checks and 54 light/dark offscreen screens passed. The real
  completion view was rendered with the new callback present, including partial
  and failure configurations. The completed screen was visually inspected.
- New regression exercises the actual ShakeEffect: fractional progress survives,
  both directions move, integer endpoints settle at zero, and disabling motion
  suppresses an in-flight offset.
- Existing Settings UX invariants passed, including retained-password wording,
  accessible face actions, Touch ID scope and unchanged security settings.
- Six synthetic face-control layouts were rendered from the current FaceTile and
  AddFaceTile declarations at 580pt content width. One, four and five faces fit in
  light/dark themes, so no gratuitous grid redesign was made. Names and callbacks
  were synthetic; no enrollment store was opened by this fixture.
- Binary SHA-256:
  919e168b1633a0124f019130573ca1d3bb56a15b44d86da3e7ffb16e3f22ab14
  No Sources/*.swift file was newer at verification. CHECKPOINT.json records exact
  source hashes. The local run script launched the new build as PID 36107 with
  --settings after an unlocked-owner-console check and walk-away setting read (off).

Logs: build/gaze-usability-final-build.log, gaze-usability-final-onboarding.log,
gaze-usability-settings-check.log, gaze-usability-face-review.log,
gaze-usability-launch.log and gaze-usability-runtime.json.
Images: build/gaze-usability-final-onboarding/ and gaze-usability-face-renders/.

## Limits and next owner check

Offscreen renders establish layout, not native Liquid Glass fidelity, VoiceOver,
physical display cadence, live recognition accuracy or a successful Mac unlock.
No live lock/camera/credential trial was performed. The pre-existing
DesktopWallpaper Sendable warning remains outside this change.

When the owner returns, inspect Settings readiness and repair navigation, check
Pause/Resume presentation, try Escape while editing a face name, and play the
camera-off notch preview. An actual recognition/unlock trial is a separate
owner-supervised acceptance step. Public release still requires model/asset rights,
Developer ID/notarization and clean install/update acceptance; local success does
not close those gates.

Startup follow-up: PID 36107 was still running after more than three minutes. The
filtered startup-log query returned no entries; that is not evidence of logging
failure or a substitute for interactive acceptance.
