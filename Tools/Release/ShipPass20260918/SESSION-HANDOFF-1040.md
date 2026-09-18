# Gaze session handoff — 2026-09-18

Final local checkpoint prepared around 10:40 UTC. The extended work session is
complete; public-release requirements and the Liquid Glass choice remain open.
Read `Tools/Release/ShipPass20260918/FINAL-LOCAL-RESULT.md` first. It supersedes
earlier installed/build/preview facts retained below as session history.
The user explicitly requested this handoff and persistence through the memory MCP.
Read the memory node `Gaze Ship Handoff 2026-09-18` and this file in the next session.
The older `TOUR-HANDOFF.md` and older nine-page reports are superseded where they conflict.

## User intent and constraints

- Improve Gaze and its website toward shipping. Fix both behavior and presentation.
- Work a full40 minutes, then the user added another hour. Recorded start08:42:53 UTC;
  original end09:22:53; extended earliest finish10:22:53 UTC. See
  `Tools/Release/ShipPass20260918/FORTY-MINUTE-SESSION.json`, now records119.5 minutes
  and `local_work_completed_external_requirements_open`.
  Do not count an idle gap between sessions as completed work or claim the session finished.
- Keep TourKit's original layout/navigation; no replacement TabView, custom dots,
  duplicate Skip/header/footer, title bar, traffic lights, or visible nested host window.
  Scale the whole stock panel so buttons, text and fitted artwork grow together.
- Latest design: main onboarding includes the truthful completion screen AFTER real setup;
  movement guidance is a separate TourKit guide reachable from Settings.
- Replace obsolete Settings screenshots and inconsistent website image sizing.
- User complained the buttons are not Liquid Glass. An async question is pending:
  allow ONLY a button-style change to TourKit, or keep upstream completely unchanged?
  **No answer has been received. Do not assume permission.** Stock source remains unchanged.
- User said no more Hydra heads for this request; do remaining work locally.
- No git status/diff/commit/branch/push/PR/merge operations. Hydra handles landing.
  Preserve all existing work and other-agent changes; no reconciliation/reset/stash.
- Keep recognition thresholds, consent and one-way state broadcasts intact. No real
  camera, lock, password replay, authentication-plugin, email or account-mutation tests.

## Projects and toolchain

- Native: `/Users/owencope/Developer/FaceID`.
- Website: `/Users/owencope/Developer/gaze-site` (authorized direct workspace).
- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` is required for modern Swift.
- Native build: `DEVELOPER_DIR=... GAZE_BUILD_OUTPUT=/Users/owencope/Developer/FaceID/build/gaze-ship-20260918/Gaze.app bash build.sh`.
- Use `/usr/bin/log`, since bare `log` is a zsh builtin. Use `nm` for compiled Swift symbols.
- Read `/Users/owencope/.codex/skills/no-agent-messaging/SKILL.md` before coordination.

## Source state: native UI

- `ThirdParty/TourKit/TourKit.swift` matches pinned upstream exactly, SHA256
  `4d67d1f9eaa13dd63d5dc72044b5a9d28cb707117e0a39ef6070ca6187a76207`.
  Some vendor metadata/historical LOCAL-CHANGES notes still describe earlier forks;
  they are not proof that those patches remain in the current source.
- `GazeTourSizing.swift`: baseWidth660, panelWidth720, panelHeight680, scale720/660.
  Callers frame the stock view at660x623.33, scale uniformly, then frame720x680.
- `GazeWelcomeTour.swift`: FOUR introductory pages, using fresh illustrations:
  Meet Gaze, Stays on your Mac, How unlock works, Unlocking stays your choice.
  Next / Start setup. No live custom media. `SetupWelcomeStep` is a thin host with
  an invisible10pt top drag strip. `tourRevision` resets introduction on reopening.
- `SetupDoneStep.swift`: one stock TourKit page driven by actual completion state.
  Failure -> Try Again/onRetry; partial with opener -> Finish in Settings;
  complete ordinary setup with opener -> Test Recognition; otherwise -> Done.
  Built-in close always calls onDone, so testing remains optional. Existing failure,
  partial, addFace and truthful state helpers/callbacks are preserved.
- `GazeMovementTour.swift`: separate SIX-page camera-free guide (intro plus left,
  right, nod, blink, mouth), stock Next/Done/close. It uses static instructional
  storyboards from real renderer poses, not camera evaluation or live animation.
- `GazeApp.swift`: enrollment and movement-guide scenes are `.plain`, transparent,
 760x680; movement guide suppressed at launch. Settings General and Notch Expressions
  open the guide; the old inline expression guide was replaced. SetupFlow suppresses
  its outer backdrop for welcome/done, retaining rounded backdrop for functional stages.

## Fresh artwork

- Vera's generator: `Tools/OnboardingArt/Generate.swift`, `run.sh`, README and manifest.
  Eleven1440x900 RGBA PNGs in `Resources/Art`: onboarding-recognition/local/unlock/
  choice/success/failure and movement-left/right/nod/blink/mouth.
- Uses the real SoftFaceGPU/companion renderer, charcoal material and familiar SF
  Symbols. No old screenshots, baked text/buttons/windows, personal data or fake checks.
  Movement middle poses sample real guidance peaks because stillPose is neutral.
- Original worker contact sheet was only in its ignored build. Root made
  `build/gaze-ship-20260918/new-art-contact-sheet.jpg` and inspected the actual PNGs.
- Website copies now EXIST: `public/product/gaze-recognition.webp`, gaze-local,
  gaze-unlock, gaze-choice, gaze-movement-left. All1440x900, lossless.
  Root translated artwork down140px (no resampling/clipping visible contents),
  composited onto #1a1a1a for white-symbol contrast, added24px rounded alpha corners.
  Provenance/hashes: `gaze-site/public/product/gaze-art-sources.json`.

## Reliability work already landed

- Remy: SetupPlan Back cannot repeat saved capture. Password Back is nil if capture
  was in the plan; permission goes to password when present, otherwise nil after
  capture / welcome without capture. `Tools/SetupBackRegression`:128 combinations pass.
- Iris: ReleaseUpdateChecker schedule is tracked, idempotent, cancellable, instance-owned;
  stop cancels pending work/timer, cancellation restores prior state without false offline
  messages or timestamps. URLProtocol-only lifecycle harness passed16 checks.
- Suki's future-clock fix is in source: skip only when elapsed>=0 and <interval;
  a future lastReleaseCheck no longer suppresses checks. Its final report confirms
  the full lifecycle regression passed, including future timestamp recovery,
  recent-timestamp skipping and preserving an available update despite a future timestamp.
- Juno: `SettingsLaunchHandoff.swift`, called BEFORE services in GazeApp.init.
  Bare or exact --settings same-bundle foreground launches reopen oldest matching
  running executable/bundle and exit. --agent, --setup and diagnostics bypass.
  Synthetic AppKit two-process test passed;20 eligibility checks. This is narrow
  reuse, not race-free global singleton election or cross-location deduplication.
- Root added --agent to `Plugin/com.gazeunlock.Gaze.agent.plist`; plutil passed.
  No installed authentication plugin or system plist was changed.
- Milo: cached/known-miss favicon lookups no longer wait behind4 downloads.
  `Tools/GazePasswords/test-icons.sh`:698 checks, no network/vault. Gaze Passwords
  itself has NOT been rebuilt/installed during this latest pass.
- Root enrollment regression:54 generated-pose checks plus setup task cancellation,
  stale completion, reopen isolation and teardown passed without camera/credentials.

## Installed versus built — do not confuse them

FINAL: the latest candidate is now installed and packaged. Both executables hash
`bbbd3c98d02c5037d2f479b7d3ad2253de1a2405f66616bafc1223d44d7f97b8`.
Installed PID38071 was verified at10:32 UTC. Receipt: `final-guides-install-result.json`.
Fresh DMG: `build/installers/20260918-final-guides/Gaze-0.1-arm64-local-preview.dmg`,
SHA256 `50cf708c3db4c20c3bb632df56af000c0343387665423538a3db16d72f413c14`.

Earlier checkpoint:

Last checked installed `build/Gaze.app` executable SHA256:
`d60d756c8b167fed9cacd10275803e029b6269c44407217308d742a016f98b60`.
It is the EARLIER five-page stock tour with old rounded screenshot assets.
User requested a quick relaunch: launchctl kickstart then plain `open` succeeded;
one matching PID25558 was confirmed. Refresh PIDs before acting.

Latest candidate `build/gaze-ship-20260918/Gaze.app` executable SHA256:
`bbbd3c98d02c5037d2f479b7d3ad2253de1a2405f66616bafc1223d44d7f97b8`.
Full build succeeded (`illustrated-guides-build.log`), and no Swift source was newer
than this candidate at the checkpoint. It contains the new illustrations/guides and
reliability code. **This candidate has NOT been installed or packaged yet.**

KeepAlive installation procedure:

1. Stage with ditto; verify deep/strict signature and installed designated requirement.
2. Boot out `gui/<uid>/com.gazeunlock.Gaze.agent`; plain SIGTERM just respawns it.
3. Confirm the installed-path process stopped; archive old bundle, rename staged bundle.
4. Verify hash/signature. Restore the UNCHANGED user's LaunchAgent in finally.
5. Confirm exactly one new PID at `build/Gaze.app` and its loaded executable via lsof.

Helpers under `build/gaze-ship-20260918`: prepare-stock-tour.py/install-stock-tour.py
and earlier rounded/compact variants. Use a fresh plan/receipt prefix and update
their build-result prerequisite to actual final evidence; do not reuse a stale plan.
User plist is `~/Library/LaunchAgents/com.gazeunlock.Gaze.agent.plist`, currently
`[.../build/Gaze.app/Contents/MacOS/Gaze, --agent]`, KeepAlive=true.
Avoid `open ... --args --settings` on an old installed build; it caused duplicates.
Plain `open build/Gaze.app` after the quick relaunch reused one instance successfully.

## Current native verification

`Tools/Release/ShipPass20260918/check-tour.py` now tests actual FOUR-page intro,
separate SIX-page movement guide and EIGHT completion/action scenarios using inert
callbacks and a borderless760x680 host. PASS in `guided-setup-fixture.log`.
Captures/geometry: `build/gaze-ship-20260918/guided-setup-interaction/`.
Root inspected intro-1.png, movement-2.png and completion-complete-test.png.
Checks include one navigation system, no clipping, Back/Next/finish/close, partial/
failure/addFace action precedence, and Close never invoking test/retry.
They do NOT establish dragging, Escape, live camera/unlock, or restoration acceptance.
OnboardingRegression/run.sh includes GazeTourSizing, GazeMovementTour and new assets.
The older full54-screen rendering suite has not been rerun after every latest UI change.

## Website implementation and checks

FINAL: user rejected the Apple-like layout and formulaic copy after this checkpoint.
Homepage now uses plain left-aligned copy and `gaze-story.tsx` with4 scroll-linked
illustrations; no homepage MacBook mockup, screenshot gallery or feature carousel.
Those reusable components remain for other uses. LiveDemo, FAQs, SEO description
and CTA copy were rewritten. Full build, lint, types and82 tests passed. Desktop
story behavior, keyboard no-motion, and320/390/768 responsive document widths passed.
Both55524/55525 serve the revised site. Evidence is in `browser-final/`.

Earlier component work (retained):

- Shared ProductMediaFrame:16:10, responsive, object-contain, consistent padding/radius.
  Gallery/lightbox/ProductTour/SetupWalkthrough/FeaturesCarousel now use it.
  Per-source width/2 caps removed, lightbox960px responsive cap, paired card media aligned.
- Old screenshot references replaced by the five fresh artwork WebPs above, with
  correct1440x900 metadata and truthful illustration alt/captions. Real panel video
  and900x560 poster remain. Movement copy describes a separate camera-free guide.
- Root removed the inappropriate 'TourKit-free' footer sentence; changed gallery
  tablist label from 'Choose a screenshot' to 'Choose a preview'.
- During this pass: scoped ESLint and tsc passed,82 backend tests passed, production
  build passed. Logs `site-ship-tests.log` and `site-ship-build.log`. Final source/art
  edits after some checks still need the final appropriately scoped verification.
- Latest desktop browser check: all4 gallery tabs have exactly710x443.75 frames,
 1440x900 natural images, object-fit contain, no document overflow. Results saved
  in Aside artifacts/gallery-layout.json; screenshot gallery-new-art.png exists but
  has NOT yet been inspected. Lightbox, other routes and narrow layouts remain to check.

## Local websites and browser session

- Actual checkout dev server: http://127.0.0.1:55525/ (PID25072 at check), exec session88689.
  Uses actual project's .env.local; public-page inspection only, no mutations.
- User's older http://127.0.0.1:55524/features was DOWN (no listener), explaining their
  report. Root restarted its existing isolated preview in
  `build/gaze-full-ux-20260917/site-preview`, detached PID32685, using Next dev --webpack.
  Auth, write-blocking proxy, fake email, signin and layout override hashes were preserved.
  Only6 public UI components were synced; public/node_modules remain original symlinks.
  Log `restored-preview-55524.log`. Restored `/features` confirmed HTTP200 at09:58 UTC.
  Do not rerun preview-site.py wholesale: it would overwrite later safe preview fixes.
- BrowserOS neo tools were unavailable. Aside CLI is installed; read `aside guide`
  and `aside guide repl` before use. No service-specific skill for localhost.
- Persistent Aside REPL exec session83321, `sizingPage` points to55525.
  Session dir `/Users/owencope/.aside/u/0/sessions/2026-09-18_Qe2IUCF4GSFesFhD`.
  Use fresh snapshot refs. `page.goto`, locator click, evaluate, screenshot work.
  `setViewportSize` is NOT exposed (TypeError), so mobile viewport proof is unfinished.
  Deferred Chrome DevTools tools are also present; inspect their metadata/connection
  if useful for real viewport emulation. Do not claim mobile device testing from desktop.
  Session IDs may not survive a new chat; reconnect rather than assuming validity.

## Real public-release blockers

See `SHIP-REQUIREMENTS.md` and `Tools/Release/ModelClearance/`.
- No Developer ID Application identity; Apple Development only. No secure timestamp,
  notarization/staple; Gatekeeper rejection is expected for this dev build.
- Clearance validator REFUSE: model/asset rights unresolved. Source licence does not
  establish weight redistribution rights. New art also needs inventory/provenance
  records; do not invent grants or mark cleared based only on generated hashes.
- Real-Mac negative/fallback, sleep/relock, install/update and supported-OS acceptance open.
- Separate Gaze Passwords development profile expires2026-09-20 23:51 UTC.
- Existing DMG packages much older `1d851eea...` executable, explicitly local-preview,
  distributionReady=false. Do not distribute it as current or as a public release.
- No deployment, publication, notarization or messages to third parties were authorized/run.

## Remaining work, in practical order

1. Review FINAL-LOCAL-RESULT.md and the user's feedback on the new website/app.
2. Resolve the Liquid Glass choice if the user responds; no vendor changes without it.
3. Obtain real model/asset rights evidence and Developer ID/notarization prerequisites.
4. Perform owner-supervised live-Mac acceptance and real-device/Safari web acceptance.
5. If further changes are made, rebuild/recheck/repackage the exact new artifact;
   never label the current development DMG as a cleared public release.
