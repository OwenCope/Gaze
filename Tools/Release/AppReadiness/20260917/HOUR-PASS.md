# Native app follow-up work window

Started 2026-09-17 at 01:20:33 UTC; requested duration about one hour.

Scope: native Gaze. Website and Passwords remain paused. Preserve existing edits,
the owner-tested app, signing identity, model weights, thresholds and authentication.
No agent-initiated live camera, lock-screen, credential or enrollment test.

Current integration work:

- Iris added direct capture retry; Milo improved the Updates panel.
- Juno added inactive-scene pausing. The existing display-driven lesson regression
  explicitly requires visible NSHostingView lessons to animate with scenePhase
  inactive. Root must resolve the lifecycle signal before accepting this build;
  do not merely remove the assertion or report the suite as passing.
- A new Open at login issue is confirmed in the source: Settings discards the
  registration result and reads non-observable service state in the toggle binding.
  Delegate presentation refresh and failure feedback without altering registration.

Root owns the lifecycle decision, new failure-path fixture coverage, combined build,
signature validation, and final checkpoint. The candidate last accepted before this
round is build/gaze-readiness-20260917/Gaze.app, SHA-256
58e9d70675bd2f2b8eddca4ca21a2a1be512720fdad3e81f3d1217584b544f7b.

Public shipping still requires owner-supervised acceptance, clean install/update
on supported Macs, distribution rights, and Developer ID/notarization. These are
not closed by the time budget or by offline test success.

## Mid-pass checkpoint — 01:51 UTC

- Root corrected the lesson gate to stop background scenes while allowing visible
  inactive NSHostingView lessons. The existing display-driven regressions pass;
  a new mounted-view test covers freeze/resume, selection while paused, explicit
  pause, Reduce Motion and detach. The 54-screen onboarding fixture also passes.
- New Settings/capture fixture exercises actual extracted Settings members and
  the actual capture view with simulated services/authorization. First interactive
  run passed 50 checks, including native light/dark release-note disclosure clicks
  through CUA. No real service was contacted or configured.
- A further test reproduced stale login-item failure feedback after external
  repair. Root records the failed requested state and clears the message only
  when the actual service state reaches that request. The expanded automated
  fixture now passes 56 checks, including both enable/disable external repairs.
- Both ordinary SDK 27 and SDK 26.5 app builds passed before the final stale-error
  fix. SDK 26.5 output records minos 26.0 / sdk 26.5 in LC_BUILD_VERSION; both
  signatures pass. They need a final rebuild after the latest Settings edit.
- Cached offscreen capture images omit compositor-backed glass buttons; do not
  mistake that limitation for the live UI. A native capture-retry inspection is
  next, followed by the final builds and report.

Logs and fixture artifacts: build/gaze-hour-20260917/. The owner-tested
build/Gaze.app remains unchanged and has not been relaunched.

## Completed local pass

Completed 02:15:29 UTC after 54.9 minutes.
Final candidate: build/gaze-hour-20260917/Gaze.app. The final build, signature,
model equality, Settings/capture checks, onboarding and enrollment checks passed.
See HOUR-REPORT.md and HOUR-CHECKPOINT.json for scope, evidence and remaining
owner/distribution gates. All native fixture processes were closed; production
Gaze was not relaunched. The real-window minimize/restore result remains unverified.
