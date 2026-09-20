# Setup flow review

Scope: all 22 files in `Sources/Setup/`, plus `Sources/Enrollment/EnrollmentModel.swift` and `ThirdParty/TourKit/TourKit.swift` for context. No build, run, test or lint performed. No source file modified. Per the brief, nothing about TourKit styling is flagged (see `ThirdParty/TourKit/LOCAL-CHANGES.md`, which was read first).

## Verdict

The worst thing a new user can hit is doing everything right and getting nothing: a user who completes the full run — face enrolled, password saved, Accessibility granted — locks their Mac and Gaze does nothing at the lock screen, because nothing in setup enables the keystroke backend or the password-replay consent it depends on, and the finish screen never names the remaining switch. The tour promises "Automatic unlocking stays off unless you turn it on," setup collects every prerequisite, and then nobody offers to turn it on. There is no force-quit trap anywhere in the flow, and the honesty handling of skipped steps on the done screen is good; the gaps are all about what happens around the edges (window closed mid-step, one-shot auto-prompt, the last switch).

## Flow map

Normal first-run order on a fresh machine is **welcome → capture → password → permission → done**. Note that `SetupHowStep` and `SetupMeetGazeStep` exist as screens but are **not** in a normal run: `SetupPlan` excludes them when `usesWelcomeTour` is true (`SetupPlan.swift:22-23`), and `SetupFlow.makePlan` always passes `usesWelcomeTour: true` (`SetupFlow.swift:268-271`). They are reachable only via `--setup-step=how|meetGaze` or a forced step. The explanatory burden therefore falls entirely on the 4-page welcome tour.

| # | Step (file) | Asks for | Persists | Exit / back |
|---|---|---|---|---|
| 1 | welcome — `SetupWelcomeStep.swift`, content `GazeWelcomeTour.swift` (4 tour pages: Meet Gaze, Stays on your Mac, How unlock works, Unlocking stays your choice) | Nothing; Next/Start setup, tour X = close | `OnboardingHistory.markPresented()` sets `gaze.onboarding.hasBeenPresented` on appear (`SetupFlow.swift:215`) | Tour Back within pages; X closes window |
| 2 | capture — `SetupCaptureStep.swift`, driven by `EnrollmentModel` (positioning → 2 capturing passes → complete/failed) | Camera permission, then head-turn enrolment | Face prints via `store.add` only on `.complete` (`SetupFlow.swift:349-372`); nothing before that | Back to welcome (onboarding only); camera failure always offers Try Again (`SetupFlow.swift:100`); model failure routes to done-with-failure with Try Again |
| 3 | password — `SetupPasswordStep.swift` | Account password, verified against local directory before saving | Keychain record on success (`PasswordVault.store`); typed text is `@State` only, lost on close | Skippable via Set Up Later; **no Back button** when capture is in the plan (`SetupPlan.swift:40`, `SetupFlow.swift:108`) |
| 4 | permission — `SetupPermissionStep.swift` | Accessibility (opens System Settings; polls 1/s + refresh on activate) | Nothing (system state only) | Skippable via Set Up Later; Back goes to password when password is in the plan, else none (`SetupPlan.swift:41`) |
| 5 | done — `SetupDoneStep.swift` | Nothing | Nothing | Single TourKit page: Done / Finish in Settings (partial) / Test Recognition (complete) / Try Again (failure); X just closes (`SetupDoneStep.swift:124-140`) |

Not steps in this flow: `GazeMovementTour.swift` (separate `movement-guide` window, camera-free practice; never referenced by `SetupFlow`), `SetupFactCarousel` / `SetupHowStep.facts` (unreferenced dead UI, see Low), and the helper views (`SetupScaffold`, `SetupControls`, `GlassField`, `SetupBackdrop`, `SetupMark`, `GazeLessonAnimation`, `GazePeekingCompanion`, `GazeTourMovementPage`, `GazeTourSizing`, `SetupRequest`, `SetupSessionWork`).

Abandonment points and consequences:

- **Close during welcome/tour.** `markPresented` already fired on appear, so `needsIntroduction` is false forever after (`OnboardingHistory.swift:6-8`). Next launch does not re-prompt; the user must find Settings or the menu-bar entry themselves. Nothing persisted, coherent empty state, but the auto-invitation is one-shot.
- **Close during capture (before complete).** `commit` runs only on `.complete`; closing cancels work and stops the camera (`SetupFlow.swift:178-181`). Nothing persisted. Combined with the one-shot prompt above, a user who bails mid-capture is never asked again.
- **Close on the password step (window chrome; no in-window close).** Face is already persisted, password is not. Next launch: `isEnrolled` is true so setup never auto-presents (`OnboardingHistory.swift:14-19`), and the app runs enrolled-but-unable-to-unlock. The done screen that would have explained the gap was bypassed. Recovery depends on the user opening Settings.
- **Close on the permission step.** Same shape: face (+ maybe password) saved, Accessibility unknown, no re-prompt, Settings is the only recovery path.
- **Skip password and/or permission via the buttons.** The honest path: `SetupUnfinished` is read at display time (`SetupFlow.swift:328-334`) and done names exactly what is missing (`SetupDoneStep.swift:15-29`). Coherent.
- **Enrolment/model failure.** Routes to done-with-failure, never a false success, with Try Again rebuilding a fresh model (`SetupFlow.swift:379-398`). Coherent.
- **Re-run with everything satisfied.** Plan is empty, welcome goes straight to done-complete. No duplicate face is saved (capture skipped when enrolled, `SetupPlan.swift:24`).

## High

No HIGH findings. No state was found in which the only escape is force-quitting: every screen either carries its own Continue/Skip/Back/Try Again control or can be closed via the window chrome, and closing always cancels cleanly (`SetupFlow.swift:178-181`) and restarts at the beginning on reopen (`SetupFlow.swift:203-216`).

## Medium

**M1 — Setup completes with everything granted but unlocking never engages, and the finish screen never says so.**
`SetupHowStep.swift:26`, `"Gaze enters your saved login password after verification."` — the lock-screen watcher only scans when the keystroke backend is selected and password-replay consent is on (`Sources/Security/UnlockExecutionPolicy.swift:31-33`, `Sources/Security/LockWatcher.swift:194-195`), both of which default off (`Sources/App/Preferences.swift:338-340`, `Sources/Security/LockScreenPasswordSubmission.swift:9-11`), and nothing in `Sources/Setup/` sets either. Meanwhile `SetupDoneStep.swift:26-27` tells a complete setup `"Your face and unlock settings are saved."` when setup changed no unlock setting. User impact: a user who grants everything locks their Mac expecting a face unlock and gets silence; the tour's page 4 ("stays off unless you turn it on," `GazeWelcomeTour.swift:43-48`) discloses the principle but the flow never offers the switch. Suggested direction: the complete-setup done screen should name the one remaining Settings switch instead of implying setup finished the job.

**M2 — Add-a-face with a restricted camera has no in-window control at all.**
`SetupCaptureStep.swift:201-207`, `actionTitle` returns nil for `.restricted` (and unknown statuses), so no action button renders; `SetupFlow.swift:99` passes `onBack: nil` for `.addFace`; and capture never passes `onClose`, so `SetupScaffold.swift:87` renders an empty spacer where Close would be. User impact: a user on a managed Mac (or with a broken camera status) adding a face sees "Ask your Mac's administrator" with literally nothing to press; the only exit is the window's native traffic-light close, which nothing points to. Suggested direction: show Back (or at minimum the scaffold Close) on the camera-access screen whenever there is no primary action.

**M3 — Closing the window on the password or permission step leaves an enrolled-but-mute app with no re-prompt.**
`SetupFlow.swift:174-181` (disappear cancels, state discarded) together with `OnboardingHistory.swift:6-8` (`isEnrolled` true suppresses any future auto-prompt). User impact: the exact user most likely to need guidance — face saved, password and/or Accessibility missing — never sees the done screen built to guide them (`SetupDoneStep.swift:15-29`) and is never asked again; recovery requires discovering Settings unaided. Suggested direction: treat window-close on a post-capture step as an interruption worth resuming (reopen on password/permission), or re-prompt once while the setup is partial.

**M4 — The welcome tour is a one-shot invitation that reads as deferrable.**
`SetupFlow.swift:215`, `OnboardingHistory.markPresented()` fires on appear, so merely opening setup exhausts the only automatic prompt (`OnboardingHistory.swift:6-8`). User impact: closing the tour to "do it later" behaves identically to "never" — next launch is silent. Suggested direction: mark presented on reaching capture (real engagement), not on the welcome screen appearing.

## Low

**L1 — Dead explanation screens still in the flow.** `SetupPlan.swift:22-23` excludes `.how`/`.meetGaze` in normal runs while `SetupFlow.swift:83-92` still hosts them with positions and back wiring. User impact: none today, but anyone editing those screens (or their copy) is working on UI nobody sees, and the "explains before it asks" property silently depends entirely on the tour. Suggested direction: delete them or gate them behind the debug flag explicitly.

**L2 — Dead `SetupHowStep.facts` copy contradicts the product.** `SetupHowStep.swift:66-88`, `"never synced, never logged, never sent anywhere"` and `"No image is stored and nothing is uploaded"` — `SetupFactCarousel` and `facts` have no references anywhere (verified by search). User impact: none while dead, but both claims are stronger than the live copy and the second is false if revived (user-chosen portraits persist on disk via `FaceEnrollmentStore.setPortrait`). Suggested direction: delete the dead array and carousel with the screens in L1.

**L3 — "Nothing is recorded" overstates on the camera screen.** `SetupCaptureStep.swift:219-222`, `"Recognition happens on this Mac. Nothing is recorded."` on the pre-permission screen whose sole purpose is to begin recording faceprints. User impact: trivial, but a literal-minded user enrolled seconds later can fairly ask what the prints are. Suggested direction: scope it — "Nothing is recorded until you enrol."

**L4 — Back out of capture silently discards partial enrolment.** `SetupFlow.swift:293-302` nils the model on back while `SetupCaptureStep.swift:147` reassures `"Your captured progress is kept."` (kept across dropped frames, not across Back). User impact: turning back mid-ring loses real progress with no warning; forward again starts pass 1 from zero. Suggested direction: keep the discard (re-entering capture mid-pass is worse) but drop "kept" from the caption or confirm on back.

**L5 — The password screen doesn't state the cost of skipping.** `SetupPasswordStep.swift:64-69` offers `"Set Up Later"` beside Save with no on-screen consequence; the necessity case lives two surfaces away (tour page 3, `GazeWelcomeTour.swift:37-42`, and the done screen after the fact). User impact: the skip decision is made with the least context in the flow. Suggested direction: one clause under the field, e.g. that skipping means recognition without unlocking until Settings.

**L6 — The password field sets no content type.** `SetupControls.swift:81-130` (`GlassField`): `SecureField` covers autocorrect/spellcheck inherently, but there is no `.textContentType(.password)`, so password managers may not offer to fill. User impact: minor friction typing a long login password blind. Suggested direction: set the content type; change nothing else about the field.

**L7 — A keychain-save failure keeps the typed password in the field.** `SetupPasswordStep.swift:96-100` sets the error but, unlike the wrong-password path (`:93-95`) and the success path (`:89`), does not clear `password`. User impact: negligible (in-memory `@State` only, lost on close), but inconsistent with the screen's own hygiene. Suggested direction: clear it like the other two paths.

## Checked and clean

- **Camera denial and return.** Denied → "Open Camera Settings" opens System Settings (`SetupCaptureStep.swift:180-185`); returning refreshes on activate and auto-starts the camera (`:44-48`, `:161-164`). Back remains available in onboarding. No trap.
- **Permission step.** Skip path, live polling plus activate-refresh, honest pending states ("Waiting for macOS to confirm", quit-and-reopen advice, `SetupPermissionStep.swift:34-46, 97-119`). Handles the must-resolve-in-Settings loop well; do not touch.
- **Partial-setup honesty.** Done names skipped items instead of claiming success (`SetupDoneStep.swift:15-29`); `unfinished` is read at display time so cross-window grants still report truth (`SetupFlow.swift:328-334`). The explicit anti-"You're all set" comments describe a real past bug correctly. Do not touch.
- **Failure honesty.** Same screen for success/failure with the real message (`SetupDoneStep.swift:32-45`); retry builds a fresh model rather than reusing failed material (`SetupFlow.swift:386-398`). Do not touch.
- **No re-enrolment on repeat runs.** Capture skipped when enrolled (`SetupPlan.swift:24`); no back into a completed capture (`SetupFlow.swift:289-292`). Do not touch.
- **Privacy claims that check out.** Tour p1/p2 on-device statements (`GazeWelcomeTour.swift:24-36`) match on-device embedders and non-syncing keychain (`Sources/Security/Keychain.swift:59`, `kSecAttrSynchronizable: false`); "This is not Apple Face ID" plus the recoverable-copy disclosure (`SetupHowStep.swift:33-38`) is the most honest sentence in the flow; the Accessibility explainer correctly scopes what the permission does and does not do (`SetupPermissionStep.swift:90-92`). Do not touch.
- **Password verification design.** Directory check before save, off the main actor, typo vs keychain-failure errors kept distinct (`SetupPasswordStep.swift:72-103`, `Sources/Security/PasswordVault.swift:42-53`); field cleared on success and on wrong password (`:89`, `:94`). Do not touch the mechanism (see L7 for the one inconsistent path).
- **Camera-free guides are camera-free.** "Camera off" claims on the expression guide (`SetupMeetGazeStep.swift:126-131`) and movement tour (`GazeMovementTour.swift:44-45`) hold — neither view touches the camera. "A preview never unlocks anything" (`:130`) holds. Do not touch.
- **Add-face done copy.** "Your new face is saved. Your unlock settings haven't changed." (`SetupDoneStep.swift:95`) is exactly true. Do not touch.
- **Restart safety.** Reopen resets to the start instead of resuming a stale screen (`SetupFlow.swift:203-216`, with the rationale comment at `:167-173`); launch-step flag consumed exactly once (`:218-231`). No "You're all set having done nothing" path. Do not touch.

## Could not determine

- Whether Settings surfaces the partial states from M3 well enough to make them non-issues (Settings is another reviewer's scope; `SettingsView.swift` readiness strings were seen only via search, not read).
- Whether the Test Recognition window offered after complete setup guides the user to the keystroke switch from M1 (the `test` window lives outside `Sources/Setup/`).
- Whether the "save the new one in Gaze Settings" rotation promise (`SetupPasswordStep.swift:35`) holds — the Settings password-update UI was not in scope.
- TourKit internals beyond behaviour relied upon (single-page X never triggers finish; finish checkmark shares the bottom-CTA chain): taken from `LOCAL-CHANGES.md` and the `TourKit.swift` read, no findings, no styling comment per the brief.
