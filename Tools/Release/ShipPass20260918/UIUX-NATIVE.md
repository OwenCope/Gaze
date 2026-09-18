# Gaze native UI/UX review — 2026-09-18

Scope: first-run setup flow (`Sources/Setup/`), Settings (`Sources/App/SettingsView.swift`), recognition test (`Sources/Enrollment/RecognitionTestView.swift`, `RecognitionTestPanel.swift`). Read against the restrained Apple-style direction: native controls, clear hierarchy, compact spacing, plain copy, no decorative grids or unnecessary motion. No P0 found; nothing below blocks setup or unlock on its own.

Preview screenshots: none exist for setup, Settings, or the recognition test. The only PNGs in the tree are website/marketing posters (`Tools/Release/GalleryPacing/`, `Tools/Release/HomeMotion/`, `Tools/Release/SecondaryPages/`) and in-app art cards (`Resources/Art/how-*.png`, credit portraits). All carry the checkout timestamp (2026-09-18), so no age signal is available. No live window was inspected and no app instance was launched for this review.

## Findings

### P1 — Reopening setup mid-flow discards progress and re-runs capture
- **User action/state:** user closes the setup window halfway (e.g. to fetch a login password), then reopens it.
- **File/symbol:** `Sources/Setup/SetupFlow.swift` — `restart()` (lines 185–197), `makePlan(including:)` (lines 246–250).
- **Evidence:** `restart()` runs on every appear: it nils the enrollment model, bumps `captureSession`, and resets to `.welcome`. `makePlan` always includes `.capture` for onboarding and never consults whether a face was already saved this run, so a completed capture must be repeated and can add a duplicate face (up to `maximumFaces`).
- **Impact:** completed work reads as lost; repeated enrollments consume the limited face slots.
- **Proposed fix:** thread the completed-capture state into the plan — skip `.capture` in `makePlan` when `store.isEnrolled` already reflects this run's save, and resume at the step after it.

### P1 — Password step has no way back
- **User action/state:** user on "Your login password" wants to re-check the enrolled face or movement lesson before handing over a password.
- **File/symbol:** `Sources/Setup/SetupFlow.swift` lines 94–99 (constructs `SetupPasswordStep` without `onBack`); `Sources/Setup/SetupPasswordStep.swift` lines 17–20 (`onBack` exists but is never wired); `Sources/Setup/SetupPlan.swift` lines 31–37 (`previous(before:)` returns nil for `.password`).
- **Evidence:** every neighbouring step offers Back; the password screen — the one asking for the most sensitive input — offers only Save or Set Up Later.
- **Impact:** users who hesitate at the password prompt cannot revisit what they are trusting; skipping feels like the only way to look back.
- **Proposed fix:** pass `onBack: back` into `SetupPasswordStep` in `SetupFlow` and return `.capture` for `.password` in `SetupPlan.previous(before:)`.

### P1 — Recognition test is a dead end when nothing is enrolled
- **User action/state:** user opens Test Recognition before enrolling (hero offers it alongside setup; Settings search can land there).
- **File/symbol:** `Sources/Enrollment/RecognitionTestView.swift` line 146 (`"Enroll your face to try this."`); `Sources/Enrollment/RecognitionTestPanel.swift` lines 98–99 (`"Try another movement"` disabled when `!canChallenge`).
- **Evidence:** the only guidance is a status sentence; the panel offers no enroll/setup action, so the window has nothing usable in it.
- **Impact:** a new user who opens the test first has no path forward and must discover setup elsewhere.
- **Proposed fix:** when `!store.isEnrolled`, show a "Set Up Gaze" button in the panel that opens the enrollment window (same `SetupRequest.beginOnboarding` + `openWindow(id: "enrollment")` path the hero uses).

### P1 — Test read-outs speak in radians and frame counters
- **User action/state:** ordinary user runs Test Recognition and tries to judge whether recognition is good enough.
- **File/symbol:** `Sources/Enrollment/RecognitionTestView.swift` lines 119–143 (`readout` diagnostic rows); `Sources/Enrollment/RecognitionTestPanel.swift` lines 140–147 (`summaryRows`).
- **Evidence:** the always-visible summary shows `Yaw (raw)`, `Pitch (raw)` in radians and a bare `Match score` vs `Threshold` decimal pair; the details list adds `Analyzed / expired frames`, `Detector score / threshold`, `Eye openness 0.3xx · open/shut`. Nothing says what is good or what to do about a bad value.
- **Impact:** users compare decimals without knowing the margin that matters; the numbers raise questions the window does not answer.
- **Proposed fix:** keep raw values inside the "Recognition details" disclosure only, and rewrite the summary row in plain language (match verdict against threshold, movement result), with one sentence on what to try next when the verdict is poor.

### P2 — Wrong lockout password fails silently
- **User action/state:** locked-out user types an incorrect account password and presses Unlock in Settings → Unlock → Locked out.
- **File/symbol:** `Sources/App/SettingsView.swift` lines 1667–1674 (`clearLockout()`).
- **Evidence:** the mismatch branch only clears the field; no error is set and `lockoutSection` (lines 581–599) has no error line, unlike the adjacent password rows which show `passwordError` via `StatusLine`.
- **Impact:** a typo is indistinguishable from the control doing nothing; users may retry blindly or conclude unlock is broken.
- **Proposed fix:** add a `lockoutError` state shown as a `StatusLine` under the row, set to a plain "That password didn't match." on mismatch and cleared on success.

### P2 — Secondary setup buttons ignore the Escape convention
- **User action/state:** keyboard user tries to dismiss or defer with Escape on welcome ("Not Now"), password ("Set Up Later"), permission ("Set Up Later"), or done ("Close").
- **File/symbol:** `Sources/Setup/SetupControls.swift` lines 30–43 (`SetupSecondaryButton`); contrast line 18 (`SetupButton` binds `.keyboardShortcut(.defaultAction)`).
- **Evidence:** the primary action answers Return; no secondary answers `.cancelAction`, so Escape does nothing despite these being the flow's cancel/defer affordances.
- **Impact:** keyboard-only users must Tab to the defer control on every skippable screen.
- **Proposed fix:** add `.keyboardShortcut(.cancelAction)` to `SetupSecondaryButton`.

### P2 — "Unlock my Mac" toggle misreports the legacy plugin state
- **User action/state:** user with the legacy authorization-plugin backend reads the Unlocking section.
- **File/symbol:** `Sources/App/SettingsView.swift` lines 626–632 (toggle detail falls through to `"Off — your Mac stays locked"` for `.authPlugin`); lines 678–684 (`unlockFooter` confirms the plugin path still exists for installed setups).
- **Evidence:** the toggle binds only the keystroke backend, so a working legacy-plugin install reads as "Off", contradicting the footer's "existing installations are unchanged".
- **Impact:** misleading readiness text; users may "fix" a setup that works.
- **Proposed fix:** branch the detail for `.authPlugin` (e.g. "Legacy authorization plugin — managed outside this switch") instead of reusing the Off copy.

### P2 — "Finish in Settings" / "Test Recognition" leave a stale Done screen behind
- **User action/state:** user finishes partial setup, presses "Finish in Settings" (or completes setup and presses "Test Recognition") on the Done screen.
- **File/symbol:** `Sources/Setup/SetupFlow.swift` lines 114–124 (`onOpenSettings` / `onTestRecognition` open a window but never finish); `Sources/Setup/SetupDoneStep.swift` lines 122–126 (secondary actions).
- **Evidence:** the Done-screen comment says Done "still just closes", but neither secondary action calls `onFinish`, so setup stays open on a screen whose work has moved elsewhere; reopening later restarts per Finding 1 anyway.
- **Impact:** two windows for one task and a stale screen to return to.
- **Proposed fix:** call `onFinish()` after opening Settings / the recognition test so setup closes and the destination owns the next step.

## Coverage and limitations
- Read, not run: no build, no launch, no permission prompt, no biometric prompt, no enrollment, no camera. `GazeApp.swift`, `FaceEmbedder.swift`, `FaceEnrollment.swift` untouched per brief.
- No live window inspected; window-resize, Dynamic Type at large sizes, and VoiceOver traversal were assessed from source (system-scaled `Typography` fonts, resizable window floors, focus-aware `FaceTile` controls) but not exercised. Clipped-content risk from fixed action heights (`SetupScaffold` 80pt action well) and fixed detail widths is source-supported only, and no clipping instance met the bar for a finding.
- "Visually observed" issues: none — there were no preview screenshots of these surfaces to observe. All findings above are source-supported; none rely on an untested runtime state except where noted.

## Recommended batches (disjoint file ownership)
1. **Setup flow continuity** — `Sources/Setup/SetupFlow.swift`, `Sources/Setup/SetupPlan.swift`, `Sources/Setup/SetupDoneStep.swift` (Findings 1, 2, 8: resume, Back, close-after-handoff).
2. **Settings truthfulness** — `Sources/App/SettingsView.swift` (Findings 5, 7: lockout error, plugin copy).
3. **Test-window clarity and keyboard parity** — `Sources/Enrollment/RecognitionTestView.swift`, `Sources/Enrollment/RecognitionTestPanel.swift`, `Sources/Setup/SetupControls.swift` (Findings 3, 4, 6: enroll path, plain-language summary, Escape).
