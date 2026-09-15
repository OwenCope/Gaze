# Gaze: left/right challenge resets and choppy animation

## Configurable movement count — September 15, 2026, 21:31

The owner confirmed a choice between one and two movement challenges. Settings now
offers both, with two recommended and retained as the default for existing and new
installations. The lead audited Juno's gate and Ezra's settings changes and completed
the runtime and onboarding integration.

Each Mac unlock/scan-only attempt captures the selected count. Its context checks,
including the final password-submission evidence check, reject a changed selection.
The gate keeps that count through evidence resets; one requires one complete
prompted response, and two requires two. Browser approval retains the default two.
Identity/PAD thresholds, excursion/return requirements, freshness and presentation
timing are unchanged. The setting does not provide a zero-movement mode.

Audit corrections: enabled the picker when Mac unlock is active (the submitted UI
had retained the old toggle's disabled state), removed obsolete caption sizing tied
to `requireChallenge`, rejected Boolean/fractional/string preference values rather
than coercing them to one, and corrected a gate-test return timestamp to avoid a
synthetic 350 ms capture gap. Added isolated persistence/reload tests. Onboarding
and the expression guide reflect the selected count; scan-only copy no longer
assumes two. Normal animated return captions remain hidden.

Validation: 860 unlock/source/gate checks, 34 preference checks, production wiring
checks, and 54 light/dark onboarding renders passed. Inspected the new one-movement
How, Meet Gaze and compact scanning layouts; their instructions fit. These offscreen
renders do not establish native glass appearance or live accessibility behavior.
Live Settings inspection failed at computer-use startup (`native pipe startup
failed`); no retries or live preference changes were made.

`script/build_and_run.sh` built, verified the signature and launched this exact
checkout as PID 24885. Binary mtime: 2026-09-15 21:31:51; SHA-256
`23482f6826b1c44662c554ad0dd12bae6d98c1fd5e7e47be607095de39291b1c`.
Logs: `build/movement-count-{unlock-tests,settings-tests,wiring,onboarding-tests,build-run}.log`.

The owner's positive lock/unlock feedback applies to the preceding build. The new
one-movement option still needs an owner-run lock/unlock and omitted-return check,
followed by a two-movement check after switching back. No lock, credential entry or
camera test was automated. Public-launch gates remain open in `Tools/Release/READINESS.md`.

## Owner feedback and quiet return presentation — September 15

The owner now reports that locking and unlocking work well. The recorded 19:48
attempt on PID 18131 shows Open mouth as movement 1 of 2, a left turn as movement
2 of 2, both outward movements observed, and password events posted at 19:48:19.805.
This corroborates progress through the corrected turn path. The owner's successful
unlock report is real-world evidence; this log excerpt does not independently
record the macOS unlock notification. Broader release validation remains open.

At the owner's request, normal animated return guidance no longer displays a text
caption on the lock screen. An explicit presentation flag distinguishes a genuine
return from a retry, so failure/retry captions remain visible. The caption's layout
space is retained to prevent the companion resizing during the transition; the ear
style also hides the otherwise-empty caption background. Reduce Motion retains the
written return cue, and the face mark retains its accessible label. Practice-window
instructions are unchanged.

Milo updated the How/Meet Gaze onboarding copy to teach two short movements and a
return to the starting position. The lead shortened the header and updated stale
camera/enrollment test doubles. Caption/render tests pass (including hidden normal
return, visible reduced-motion/retry, and stable geometry). The onboarding harness
passes policy checks and renders 48 light/dark screens; inspected Meet Gaze and the
compact scanning lesson fit without clipping. The display-pacing test was explicitly
skipped in this offscreen layout run.

The owner then confirmed that movement count should be selectable. The subsequent
implementation and validation are recorded above; this earlier build still required
two distinct completed movements.

Logs: `build/quiet-return-tests.log`, `build/quiet-return-onboarding-tests.log`,
`build/quiet-return-wiring.log`, and `build/quiet-return-build-run.log`.

The combined build passed and was relaunched. Binary mtime: 2026-09-15 20:03:17;
SHA-256 `9e500999c1ff7fc758345826c05cf52407ef3bed9faa17f0be224c7be6763381`.


## Hydra integration checkpoint — September 15, 2026, 19:42

**Status: local candidate built; NOT approved for public launch.**

The final local executable is `build/Gaze.app/Contents/MacOS/Gaze`, built
2026-09-15 19:42:25, SHA-256
`9c772d9de4ac13f362020eda437b6b91b38061413f016dc266709fe8d6f00742`.
`script/build_and_run.sh` verified the signature and launched PID **18131** with
`--settings`; render diagnostics are off. No Swift source was newer than the
binary at verification. A later native UI inspection was blocked by ScreenCaptureKit
error -3811; process/build verification succeeded, but that is not a live UI or unlock test.

Implemented and integrated:

- Return guidance now says “Return to your starting position,” matching the relative
  baseline instead of asking for absolute frontal zero.
- Per-axis Vision/landmark/unavailable provenance follows camera pose into the
  challenge. The used axis cannot combine a baseline, excursion or return across
  estimators. Both lock-screen and browser approval clear their wider proof on
  source invalidation. Unavailable measurements are NaN, never fabricated zero.
- Missing/degenerate eye geometry cannot report a valid roll. The lead added a pure
  landmark-input seam and 16 checks covering previously untested missing-data paths.
- Recognition work now counts toward the 60 ms poll interval. Slow inference no
  longer adds a second unconditional 60 ms sleep. The 240 ms continuity limit and
  500 ms frame lease remain unchanged; no gap check was removed.
- Practice diagnostics use the actual pose sources and display unavailable axes as
  dashes. Identity/PAD thresholds, two movements, sample counts, direction mapping,
  return tolerances and mismatch resets are unchanged.

Lead audit corrections: fixed a synthetic timing fixture whose consumed capture
was not in its delivered stream; removed a tautological source-label test; corrected
an unsupported “frontal fallback pitch is 0.88” claim (the nose term offsets the
constant); replaced an always-200 NextResponse stub with real NextResponse; corrected
SkyLight, active PAD, geometry-fallback and recorded-video claims in the release notes.

Validation passed:

- 742 unlock/evaluator/continuity/frame/diagnostic/source checks (8 binaries):
  `build/hydra-integrated-unlock-tests.log`.
- 54 enrollment checks plus setup lifecycle: `build/hydra-enrollment-tests.log`.
- Recorded scalar and 8 image/readout pose checks: `build/hydra-head-pose-tests.log`.
- Companion/caption/layout/render lifecycle tests: `build/hydra-guidance-render-tests.log`.
- 58 dummy-credential submission checks, zero events posted:
  `build/hydra-submission-regressions.log`.
- 6 product-boundary checks and 43 release-verifier fixture checks:
  `build/hydra-product-boundaries.log`, `build/hydra-release-regressions.log`.
- Production wiring and build/run: `build/hydra-team-wiring.log`,
  `build/hydra-final-build-run.log`, `build/run-gaze-build.log`.

These are component/synthetic checks plus analysis of previously recorded images.
They do not establish real unlock reliability, FAR/FRR, or PAD attack resistance.
`FrameQuality` still rejects invalid pose measurements before authentication;
pose independence inside the challenge alone does not relax that outer gate.

Update-site preparation:

Vercel reports `gazeunlock.com` on the August 16 production deployment
`dpl_6TnkwQxrfsz5EYqQETNf1VErKMrx`, commit
`4bc8f59d83c9becd7c1a7ecc9b042e924ea1205b`. That commit lacks the local
`src/app/api/latest/route.ts`, explaining the missing feed in that reported build.
The lead applied Iris's privacy patch to the local `gaze-site` route: the public
feed returns `{latest:null}` before fetching records when releases require sign-in,
and all responses use `no-store`. The actual route tests with real NextResponse
and the website typecheck passed. No website commit, push, deploy, release record
change, or artifact upload was performed. See `UPDATE-FEED-INTEGRATION-20260915.md`
and `UPDATE-FEED-PRIVACY.md` in `Tools/Release`.

Still OPEN before distribution:

1. Owner-supervised real lock/wake/turn/return/fallback tests on this exact build,
   followed by qualified held-out recognition and presentation-attack evaluation.
2. Version/hash-specific redistribution permission for both model weights and
   third-party assets. Credit is not permission; provenance remains unresolved.
3. Developer ID Application signing, authorized notarization, stapling and
   Gatekeeper/clean-install/update validation. The local release verifier currently
   stops at **“Developer ID Application signature required.”**
4. Reviewed update-feed deployment, approved production release data, functioning
   download hosting, and signed-out user access as intended.

No head turn was skipped, no match threshold was lowered, no invalidated movement
proof was retained, and no lock or credential entry was automated.

---


## Head-turn direction correction — September 15, 2026, 12:13

**This supersedes the old source comments claiming that a leftward turn in the
mirrored preview lowers raw Vision yaw.** It does not revive the withdrawn
main-thread-inference theory or claim that every mismatch is explained.

The user clarified that head turns fail, with a camera-facing recovery prompt,
and explicitly rejected changing to a different movement as a workaround. No
retry-selection change was made.

### Measured disagreement

Revisited the complete supplied `1D2D7E1F-978D-4620-B71E-DCB906F0FC18.mp4`, rather
than only its numeric strip. At 0.7 seconds the mirrored preview points toward
screen left while the raw readout is **+0.41 rad**. The production left-turn
animation also points toward screen left (covered by the existing rendered-pixel
regression), but the old challenge required **negative** raw yaw.

Extracted ten camera-preview crops at 0, 0.7, 1.183, 1.633, 2.033, 3.283, 3.75,
4.133, 4.633 and 4.983 seconds (crop 855×360 at x=64, y=470). Reran Vision revision 3
on those crops, plus landmark measurements. Representative pairs:

| Clip time | Displayed raw yaw | Vision yaw on mirrored preview | Normalized nose displacement |
| --- | --- | --- | --- |
| 0.700 | +0.41 | -0.4264 | -0.1580 |
| 1.633 | +1.11 | -1.2891 | -0.8068 |
| 3.283 | -0.31 | +0.4126 | +0.1779 |
| 4.133 | -1.15 | +1.0554 | +0.3721 |

All eight nonfrontal samples had opposite preview/readout yaw signs, confirming
mirroring. On the same pixels, nose displacement and Vision yaw had matching
signs. The old landmark fallback negated that displacement, incorrectly reversing
its direction relative to Vision. Exact magnitudes differ because this is a
cropped/compressed, throttled screen recording and the fallback is approximate.

The images and measurements remain under `/tmp/gaze-preview-direction-audit/`.
No enrolled templates, credentials or new camera capture were used. A separate
public dataset image produced an upright production aligned crop; the eye-order
inversion hypothesis was not supported. Face alignment and embedding were not changed.

### Correction

- Left-turn recognition now requires a positive raw-yaw excursion; right requires
  a negative one, matching the mirrored demonstration in this recording.
- The landmark fallback uses the measured horizontal sign that agrees with Vision.
- The enrollment ring mirrors the raw yaw consistently, so its target direction
  agrees with the preview. Existing enrolled templates were not read or replaced.
- Pose math now lives in `Sources/Camera/FacePose.swift`, allowing tests to exercise
  the actual production mapping without opening a camera. Enrollment tests use
  that type instead of a duplicated pose formula.
- Identity cutoff **0.45**, turn excursion **0.30 rad**, return tolerance **0.10 rad**,
  two qualifying excursion samples, two completed actions, frame freshness, PAD,
  mismatch resets and password-submission gates are unchanged.
- Added read-only relative-movement rows in Test Recognition's details. The latest
  failed movement's phase, comparison and relative pose are retained only in the
  attempt's in-memory diagnostics (Unlocking information popover); new attempts
  clear them. Those angles are not written to unified logs.

### Before/after replay and limits

Used scalar readings from the recording with an explicitly prepared baseline:
left baseline [-0.08, -0.11, -0.10], excursion [0.26, 0.41], return -0.02;
right baseline [-0.02, -0.02, -0.02], excursion [-0.54, -0.65], return -0.11.
The excursion readings were still above the identity threshold in the clip.

`build/head-direction-control-20260915.log` records the same replay with the old
and corrected direction checks:

```text
old: turnLeft, returning=false, completed=false
old: turnRight, returning=false, completed=false
fixed: turnLeft, returning=true, completed=true
fixed: turnRight, returning=true, completed=true
```

This is a scalar challenge replay, **not** a full authentication replay. The
recording itself was a score sweep with a completed practice movement displayed;
it does not supply the actual lock-screen baseline or admitted-frame sequence.
The correction explains how following the demonstration could leave movement
unaccepted while turns grow large enough to lose the match. A fresh user-initiated
lock-screen test on this build is still required to confirm real-world reliability.

Validation: 565 unlock/evaluator/continuity/frame/diagnostic checks; 54 enrollment
checks plus setup lifecycle; production wiring; recorded scalar pose regressions;
and eight nonfrontal image/readout comparisons across Vision, fallback, challenge
and ring mapping. Logs are `build/head-turn-direction-tests-20260915.log`,
`build/head-turn-enrollment-tests-20260915.log`,
`build/head-turn-production-wiring-20260915.log` and
`build/head-pose-image-tests-20260915.log`.

The main app built and passed strict signature verification. Binary mtime:
**2026-09-15 12:13:11**, SHA-256:
`6829235ef1e79c673516e51f806a654cdebc9293e715c340a2025f1c2062d54a`.
No Swift source was newer at verification. Launch log:
`build/head-turn-direction-launch-20260915.log`. The exact build is running as
PID **89872** with render diagnostics disabled. Native UI inspection confirmed
Settings is open, automatic unlock and required movements remain on, photo
rejection remains on, and walk-away locking remains off. No lock or camera test
was initiated by the agent.

---


## Guidance and render diagnostics — September 15, 2026

This follow-up resumes the unfinished guidance work from the recovery checkpoint.
It does not establish that real lock-screen resets or choppiness are resolved.

### Implemented

- Test Recognition always displays the current instruction beside the companion,
  including the return cue. It no longer replaces those words with “Follow my lead.”
- The shared prompts now say **“Turn slightly left/right”** and **“Face the camera
  again.”** Only prompt strings changed in `LivenessChallenge`; excursion, baseline,
  sample-count, return and identity requirements are unchanged.
- Test Recognition asks **“Face the camera and hold still.”** and keeps its companion
  at rest until the existing baseline is ready. Previously it demonstrated the turn
  while still collecting that baseline. The real lock loop already prepares its
  baseline before presenting guidance; that loop was not changed.
- The lock panel now keeps the action caption visible with animated guidance, in
  attached, island and ear layouts. **Correction:** it already permitted the return
  caption (`demonstratesAction` is false for `returnToCenter`); it hid the initial action
  caption. Test Recognition hid both. Keeping caption space allocated also avoids
  the former change in glyph sizing when return guidance appears.
- Added optional `RenderTiming` logs to the shared renderer, enabled with
  `./script/build_and_run.sh --render-diagnostics`. The flag affects that launch
  only; omitting it explicitly disables the diagnostics on the next launch.
  Default rendering has no timing samples or timing logs.
- Timing covers callbacks, submissions, busy-frame skips, unavailable resources,
  encode failures, callback p95/max, draw-call max and `currentDrawable` acquisition
  max. It records short segments when they end, plus two-second windows. AppKit
  occlusion state is a report-time snapshot, not proof of lock-screen visibility.
  No face data or credentials are logged. GPU completion and actual displayed
  frames are **not** measured by these counters.

### Fresh evidence from the older running app

PID **78781** was still running the earlier artifact during investigation. At
11:12 it logged four right-turn failures, all `compared=true`, `belowThreshold`,
`returning=false`: scores **0.199080, 0.444739, 0.427117, 0.202308**. These preserve
rather than overturn the earlier conclusion: actual compared mismatches must
invalidate movement proof. No threshold or mismatch-reset change was made.

At 11:15:46 it also reported a first-frame camera timeout (`analyzed=0 expired=0`).
AVCapture had posted `DidStartRunning` at 11:15:42.893. Adjacent system messages
reported **closed clamshell mode** and a display count of zero. That is useful
context for a separate camera-start failure, not proof of a recognition bug or a
reason to extend the timeout. The camera code was not changed.

Evidence files: `build/guidance-baseline-runtime-20260915.log` and
`build/camera-timeout-runtime-20260915.log`. These are local diagnostic artifacts.

### Renderer measurement and limitations

`Tools/GazePreview/probe-render-timing.sh` hosts the production renderer with
synthetic movement and no camera, enrollment, authentication or credentials.
It uses `NSApplication.run()` and waits asynchronously between parent updates.
It measures recognition-sized/active and notch-sized/inactive-scene wrappers,
with steady parents and 30 Hz parent updates. `--reverse` permits an order check.

An initial probe used only `RunLoop.main.run`, did not pump AppKit's complete event
loop and did not have trustworthy occlusion state. It showed a late segment with
115 ms callback gaps and 30 busy-frame skips. **Do not use that flawed host as
proof of production choppiness.** An intermediate run also overlapped GPU regression
work and was stopped; it is not the isolated measurement.

The corrected isolated run, PID **86031**, completed four 30-second segments with
AppKit reporting the window visible. Across 7,204 recorded callbacks, all 7,204
submitted; zero busy, unavailable or failed outcomes. Per-window callback p95
ranged **16.71–18.90 ms**. The maximum callback gap was **45.16 ms** (early in the
run); maximum drawable acquisition was **33.21 ms**. Some sample windows straddle
segment boundaries. This is approximately 60 Hz scheduling with occasional gaps,
not a guarantee of smooth presentation. The last notch/update segment had longer
drawable waits; this ordered run alone does not establish causality.

Files: `build/render-timing-clean-event-loop-20260915.log`,
`build/render-timing-clean-observed-20260915.log`, and
`build/render-timing-clean-summary-20260915.json`.

The actual lock screen still needs a user-supervised reproduction on the new
build, correlated with `RenderTiming` and the existing movement logs. Test
Recognition is not authentication, and a synthetic renderer host excludes camera,
Core ML work and lock-screen composition. The old main-thread-inference explanation
for the lock loop remains withdrawn.

### Verification checkpoint

- 535 unlock/evaluator/continuity/frame/diagnostic checks passed in
  `build/guidance-unlock-tests-20260915.log`.
- Notch regression passed after updating a stale test that expected the old full
  demonstration turn. The replacement checks the already-established 0.30–0.38 rad
  visual excursion. No production animation amplitude was changed in this follow-up.
  Output: `build/guidance-notch-tests-20260915.log`.
- Caption verification checks rendered text in the minimum recognition panel and
  default/minimum adjusted attached, island and ear notches, animated and reduced.
  The size-continuity assertion allows one physical pixel of AppKit rounding;
  an observed 46.5 → 46.0 point width at 2× scale was that rounding, not a jump.
- The companion suite also checks timing accumulation, short-segment flushes,
  lifecycle, actual Metal direction renders, settled expressions and Reduce Motion.
- Main build passed with the installed Xcode-beta SDK. Exact final build/process
  details and final verification results will be recorded below at handoff.


### Guidance handoff and continued turn investigation

The guidance build is now running with diagnostics disabled: binary mtime
2026-09-15 11:41:47, SHA-256
`ed31199519ab1f52cd29dd81a869053cd9e57dcf1d28f6d32a517475b8ba0df1`.
PID **87125** was launched through `script/build_and_run.sh --no-build`.
No Swift source was newer than that binary at verification. Strict signature
verification and the final companion suite passed; see
`build/guidance-final-launch-20260915.log` and
`build/guidance-final-tests-20260915.log`.

The reverse-order, four-minute renderer run (PID 86635) recorded **14,399 callbacks,
all submitted**, with no busy/unavailable/failed outcomes. Window p95 intervals
ranged 16.72–25.73 ms; maximum interval 59.09 ms, maximum drawable wait 40.44 ms.
Longer waits also occurred with a steady parent. This does not isolate parent
updates as the cause. Results are in `build/render-timing-reverse-*.log` and
`build/render-timing-reverse-summary-20260915.json`.

The actual app's camera-free Notch preview emitted `RenderTiming` events under the
diagnostic launcher (PID 86961), verifying the launch flag reaches the real app.
Then a normal launch disabled it again. The main Settings and movement-explanation
preview were inspected through native UI controls; Test Recognition and the actual
lock screen were not exercised by the agent.

The user subsequently asked to investigate scanning and clarified that the
**head-turn movement challenge** fails almost every time and presents a
camera-facing instruction without finishing. They rejected changing to another
random movement as a workaround. **No retry-selection change was implemented.**
Continue investigating the actual turn failure; do not skip turns, lower the
identity cutoff, retain discarded proof, or claim guidance fixes recognition.
`Tools/Release/READINESS.md` explicitly records that the old recovery message reused
“Look back here” after mismatch, so that wording alone did not prove the turn had
been accepted. New logs still need to distinguish the two states.

## Azure new-chat recovery — September 15, 2026

- The user is using their custom **Azure API key**, not ChatGPT sign-in.
  The earlier direct Azure Responses smoke test succeeded; no replacement key,
  plaintext key file, or ChatGPT login was needed.
- Failed new-session metadata selected provider `azure` but still sent model
  `azure/gpt-6-astra`. That router-prefixed model differs from the verified
  Azure deployment `gpt-6-astra`, explaining the deployment-not-found 404.
- Droppy Code retained the old ID in its saved picker and `lastModels.codex`.
  Refreshing Providers exposed the native Codex model catalog. Through the UI,
  added **6 Astra**, opened an unsent FaceID draft, and selected **6 Astra / Low**
  with fast mode off. No prompt was submitted and no other agent was messaged.
- Verified the draft's visible composer label is **6 Astra, Low**. Read-only
  inspection of the persisted preferences confirms `lastModels.codex` is now
  `gpt-6-astra`, and the refreshed Codex catalog includes that bare ID.
  The stale `azure/gpt-6-astra` picker entry was left in place; avoid selecting
  it. Existing conversation histories/model selections were not mass-edited.
- Rechecked the saved configuration: provider `azure`, model `gpt-6-astra`,
  reasoning `low`, context budget **922000**, auto-compaction limit **850000**.
  No credential was changed or printed.
- **Remaining verification:** user must submit their next intended message in
  the corrected draft to confirm an end-to-end Droppy Code response. No new
  inference/full-context test was run during this UI repair. This does not
  establish that the original ongoing chat migrated provider or context.

## Recovery checkpoint — September 15, 2026, 08:33 Asia/Taipei

**Read this first after a context reset or connection failure.** This checkpoint
was requested before changing the assistant's Azure/context configuration.
Earlier sections remain the detailed evidence record; do not revive the
withdrawn main-thread-inference explanation or missing-embedding hypothesis
for the measured below-threshold failures.

### Gaze work completed and what remains

- Fixed Test Recognition's rigid window sizing and pinned score/threshold/
  yaw/pitch above the scrollable content. The exact changes, simulated UI tests,
  signed build and video measurements are recorded below. These fixes did not
  change authentication, thresholds, enrollment or credentials.
- The numeric sweep showed strong scores at modest angles and genuine low
  scores at deep turns, with recovery toward center. It did **not** prove the
  real lock-screen reset problem resolved or explain animation choppiness.
- After the user asked how people know when to stop turning, rechecked
  `Sources/Enrollment/RecognitionTestPanel.swift`: normal animated mode replaces
  `readout.instruction` with `"Follow my lead."`, including when the actual
  instruction is `"Look back here"`. The specific text survives in accessibility/
  help metadata, but is not visibly displayed in that mode.
- **The guidance fix has NOT been implemented.** Next narrow task: show explicit
  slight-turn and return-to-center instructions alongside the animation; inspect
  lock-screen presentation before promising an app-wide fix. Preserve identity
  gates, turn thresholds and reset behavior. The sweep itself was requested by
  the assistant, so do not claim the hidden instruction caused those deep turns.
- Continue to preserve the large existing dirty working tree. No pushing,
  resets, enrollment replacement, credentials changes, screen locking, or
  cross-agent messaging. Test Recognition is not authentication.

### New launcher and Run action

Created executable `script/build_and_run.sh` and
`.codex/environments/environment.toml` (Run action points to that script).
The user can enter the absolute script path in the app's “Add a script…” UI:

```bash
/Users/owencope/Developer/FaceID/script/build_and_run.sh
```

- Default: terminate this user's existing `Gaze.app/Contents/MacOS/Gaze`
  processes with SIGTERM, wait, rebuild using Xcode-beta, verify freshness and
  signature, and launch the exact checkout's `build/Gaze.app --settings`.
- It excludes helpers/PAM/XPC processes, aborts if Gaze remains running or
  respawns, and does not escalate to SIGKILL. It does stop the old app *before*
  building, so a failed build leaves the app stopped rather than launching a
  stale executable.
- `--no-build`: restart the last successful build without compiling.
  `--agent`: menu-bar/background launch. `--dry-run`: no process/build changes.
- Build log: `build/run-gaze-build.log`; script reports binary timestamp,
  SHA-256 and the launched PID.
- Agent validation: `bash -n`, both dry-run paths, help, invalid-option rejection
  and `git diff --check` passed. The agent did not execute a real restart.
- A later read-only check at 08:32 found a newer build/process than the previous
  07:50 artifact: binary mtime **08:27:51**, SHA-256
  `ea4ee5da2341d98a9dd3f1e34c8acfd317251344f7f3f8da3e4669b8059d21fe`;
  PID **78781**, start **08:27:52**, exact FaceID build executable path.
  `build/run-gaze-build.log` ends with successful signing, matching the previous
  signing requirement, and the bundle swap. This is evidence of a subsequent
  build/start, not an agent-observed UI/resize test. Recheck before relying on
  these artifact details again.

### Azure and context-window investigation

The user explicitly clarified that the API key comes from **Azure**, asked to
ditch the router, and authorized changing the context settings. They then
requested this Markdown checkpoint before changes that could break the session.

Before the change, `~/.codex/config.toml` selects `claude-code-router`, with
`model = "gpt-6-astra"`, a custom `ccr-model-catalog.json`, and reasoning effort
`minimal`. The Astra catalog entry is named `azure/gpt-6-astra` and sets both
`context_window` and `max_context_window` to **128000**, with
`effective_context_window_percent = 95`. That explains the reported **121600**
usable context. This was local metadata, not proof of Azure's model maximum.

An existing `[model_providers.azure]` already supplies the user's Azure resource
URL, `wire_api = "responses"` and `env_key = "AZURE_OPENAI_API_KEY"`.
The environment variable is available. **Do not ask the user to paste the key,
print it, or put any credentials in this repository/checkpoint.**

Verified directly, bypassing the router:

- Azure `GET /openai/v1/models` returned HTTP 200 and included `gpt-6-astra`.
  A model-list result alone is not proof of an operational deployment.
- Subsequently, a tiny Azure `POST /openai/v1/responses` using model
  `gpt-6-astra`, reasoning effort `low`, `max_output_tokens: 128` and
  `store: false` returned HTTP 200, status `completed`, text `OK`.
  Usage: **11 input + 5 output = 16 tokens**. This confirms the direct key,
  deployment name and Responses route work. No giant context test was sent.
- Microsoft model documentation lists Astra's **1050000 total context**,
  **922000 max input**, **128000 max output**, and separate long-context pricing.
  OpenAI's model documentation gives the same limits. These are documented
  limits, not an empirical full-context test of this resource.
- Direct Astra documentation lists `low`, `medium`, `high`, `xhigh`, `max`
  reasoning efforts; do not carry router-specific `minimal` into this switch.
- Installed CLI reported `codex-cli 0.154.0`.

Documentation consulted:

- https://learn.microsoft.com/en-us/azure/ai-foundry/openai/concepts/models
- https://developers.openai.com/api/docs/models/gpt-6-astra.md
- https://developers.openai.com/codex/config-reference/

### Configuration change / recovery

**At the moment this checkpoint was written, active settings had NOT changed.**
A private, mode-0600 backup of the original configuration was created at:

```text
/Users/owencope/.codex/backups/config-before-direct-azure-20260915-083307.toml
```

Intended change: select the existing direct Azure provider and `gpt-6-astra`,
remove the router-specific catalog override, use supported reasoning effort
`low`, set a conservative `model_context_window = 922000`, and compact at
`model_auto_compact_token_limit = 850000`. The configured budget deliberately
does not permit one million input tokens. Client safety headroom may make the
displayed usable budget smaller; do not promise that the meter will read 1M.
Do not shut down the router or restart the user's editor as part of this change.
Do not claim the current conversation has adopted new settings until observed.

If new sessions fail after the switch, restore **only the assistant config**:

```bash
cp /Users/owencope/.codex/backups/config-before-direct-azure-20260915-083307.toml \
   /Users/owencope/.codex/config.toml
chmod 600 /Users/owencope/.codex/config.toml
```

Then reopen/reload the client or create a new session as needed. The backup
contains private configuration: never commit or paste its contents. Do not
reset the FaceID working tree. Record actual changes/validation below this
checkpoint after applying them, rather than treating the intended plan as done.

### Applied and checked — September 15, 2026, 08:34 Asia/Taipei

After saving the checkpoint above, updated `~/.codex/config.toml` atomically,
retaining private mode 0600 and all unrelated settings/provider definitions:

```toml
model_provider = "azure"
model = "gpt-6-astra"
model_reasoning_effort = "low"
model_context_window = 922000
model_auto_compact_token_limit = 850000
```

Removed the top-level `model_catalog_json` override pointing to the router's
128K catalog. The catalog file itself was not deleted or edited. Existing Azure
credential configuration was reused; no key was copied into this document or
the project. Router provider definitions/service were left intact for rollback.

`codex features list` exited 0 with the new configuration (configuration parse
check, **not** a new model inference or full agent-session test). Its output is
at `/tmp/gaze-azure-config-validation.log`. Re-read and verified all five saved
settings, the absent catalog override, and mode 0600 at 08:34:17.

The earlier direct-Azure 16-token smoke test succeeded before applying these
settings. No full-context test, new assistant task, editor restart or router
shutdown was performed. **The active conversation's effective provider/context
has not been observed to change.** A newly loaded session may be needed; check
its actual model/context display rather than claiming the change took effect
mid-conversation. The original backup and restoration command above remain the
recovery path if a fresh session cannot connect.

---

## Follow-up — September 15, 2026, 06:52 local time

**The historical investigation below is superseded where noted here.** Reading
`build/gaze-diagnostic-*.log`, `build/gaze-retry-copy-*.log`,
`build/gaze-pacing-tests.log`, `Tools/Release/READINESS.md` and the later unified
logs reveals that diagnostic reproduction had already happened.

### Confirmed: the observed left-turn failures are below-threshold comparisons

Process **66373**, started September 14 at **21:56:55**, emitted:

| September 14 time | Action | Compared | Failure | Score |
| --- | --- | --- | --- | --- |
| 21:58:43.896 | Turn your head left | true | belowThreshold | 0.405143 |
| 21:58:47.500 | Turn your head left | true | belowThreshold | 0.357456 |
| 21:58:51.205 | Turn your head left | true | belowThreshold | 0.274778 |
| 21:58:55.145 | Turn your head left | true | belowThreshold | 0.149604 |

Each immediately precedes `reason=identity mismatch`. The threshold is **0.45**.
These four frames **refute the missing-embedding explanation for this reproduction**.
They do not establish why the scores fall, or explain every historical reset.
In particular, `embeddingUnavailable` alone would not identify missing pupils:
alignment, tensor creation, prediction and output normalization can all fail.

The source correctly discards movement proof on these comparisons. Keeping proof
across a genuine identity mismatch or lowering the cutoff is not the fix.
`Tools/UnlockFlowRegression/EvaluatorTests.swift` now replays these four scalar
scores with PAD configured and unconfigured, checking that they remain compared
mismatches and cannot contribute to a match hold. This is synthetic regression
coverage, not a replay of actual face frames.

### Build versus running process

- `build/Gaze.app/Contents/MacOS/Gaze` was built September 14 at **22:00:33**;
  no current `Sources/**/*.swift` file is newer.
- Its SHA-256 is
  `c5e70a5bd07284a4c54e0e9298b84f6916827566f4a466eaadd6627e337820ce`.
  This differs from the hash recorded in `Tools/Release/READINESS.md`; do not
  treat that report as proof of the exact current artifact.
- The on-disk binary contains evaluator symbols (`nm`), `comparedIdentity` with
  sibling-field controls, and the `Movement identity check failed` log format.
- The running process still predates that 22:00 build. Its emitted diagnostics
  prove it has the comparison diagnostics, **not** that it loaded the latest
  retry-copy/render artifact. No restart was performed in this follow-up.

### Next measurement, not another speculative fix

The enrollment source captures new ring directions once normalized `offCentre`
is at least **0.22**. `FacePose.offCentre` is `hypot(yaw, pitch) / 0.55`
(capped at 1), so capture can begin at a radial pose of **0.121 radians**.
The left/right challenge requires **0.30 radians relative to its baseline**.
Ring completion therefore does not itself guarantee templates at the challenge's
yaw excursion. This is a **coverage hypothesis only**: the owner's enrollment
was not read, its capture poses are not stored in `FaceEnrollment`, and no
camera frames were collected. Alignment and lighting remain other possibilities.

Next, measure score versus yaw/pitch through a frontal → left → frontal and
frontal → right → frontal sweep, using a user-supervised recognition session
before changing enrollment or alignment. Do not replace the user's enrollment
without agreement, and do not infer authentication success from Test Recognition.

The build-folder render tests passed scheduling, GPU-budget and drawable checks,
but they are **not a live lock-screen frame-time trace**. Choppiness remains
unexplained. The latest artifact must be explicitly identified in any supervised
reproduction, with frame timing measured separately from recognition.

No production behavior, thresholds, credentials, enrolled templates, or running
app were changed in this follow-up. No lock was triggered.

Validation with the Xcode-beta toolchain: **535** unlock/evaluator/continuity/
frame/diagnostic checks and **386** recognition-math checks passed. Logs:
`build/challenge-followup-20260915-unlock-tests.log` and
`build/challenge-followup-20260915-math-tests.log`. No main-app rebuild was
needed for these test/documentation-only changes.

---

## User-supplied recognition-test clip

Text recognition on frames sampled at 2 Hz from the supplied 8.4-second clip
(`F83A5CC5-007B-4B83-973D-2F6BA12671CC.mp4`) finds intermittent
`Not recognised` labels between `Recognised` labels in three sampled groups.
This corroborates recognition-status flicker in **Test Recognition**, not a
system-unlock failure. No numeric score or yaw/pitch was recovered from these
samples, so the clip does not establish whether these particular drops are
below-threshold comparisons or unavailable embeddings. Head direction was not
visually verified; inspection here used OCR rather than direct video viewing.

The recording averages approximately 14.9 FPS. That is not a measurement of
the app's render rate and cannot establish the cause of animation choppiness.
Extracted frames remain temporary files outside the repository.

A subsequent full accessibility read of the open test window returned
`Recognised` alongside score `0.000`, only one accumulated sample, and the
earlier pose values. This is not a coherent fresh score-versus-pose sample;
do not infer a new recognition result from it. The next supervised measurement
still needs the visible, updating diagnostic readout.

### Recognition window sizing follow-up

The user could not enlarge Test Recognition to expose the diagnostics. The
panel imposed an exact 480 × 650 frame and the scene used `.contentSize`.
The panel now specifies minimum dimensions with flexible maximums; the scene
uses `.contentMinSize` and a 560 × 820 default. Scroll indicators are no longer
suppressed in this window. No recognition or authentication logic changed.

The signed main-app build succeeded. Its SHA-256 is
`8e37642d6691ab27b2a069b8bc1b53c7bd9baf9d72d997ab2bb49f9c2911f41e`.
The companion integration suite passed, including new simulated-panel checks
for minimum and larger proposed sizes with details expanded and collapsed.
Logs: `build/recognition-window-resize-build.log` and
`build/recognition-window-resize-tests.log`.

Live resize verification remains pending: reconnecting through computer use
timed out for the exact app path; bundle-ID selection is ambiguous because of
backup app bundles. The running FaceID process (74822 at inspection) predates
this build. No process was terminated or restarted by this follow-up.

### Pinned diagnostic readout follow-up

OCR of the user's `521FBD8A-EA2B-4373-B947-2C4D8159FDC0.png`
recovers only the first two detail rows before the footer; numeric score and
pose are not recovered. Resizing support alone did not make those values
accessible in the supplied view.

The test panel now pins status, score, threshold, raw yaw and raw pitch above
the scrollable camera/movement/details section. The preview is 180 points tall
instead of 228. Missing-face/inactive-camera pose values display a dash rather
than presenting the last pose as current. Recognition evaluation, thresholds,
credentials and unlock behavior are unchanged.

The companion integration suite passed with 12 realistic diagnostic rows,
details open and closed, and minimum/default/larger proposed sizes. OCR checks
the top 250 points of the rendered panel for all four labels and numeric
values. Additional offscreen AppKit-mounted checks at 480 × 650 verify the
numeric values, simulated camera label, movement button and reset button.
These are simulated UI tests, not live-camera measurements or proof of
interactive resizing.

Main build and strict code-signature verification passed. Binary filesystem
mtime: `2026-09-15 07:50:33`; SHA-256:
`8751710cf7877f5a71775d5ed5e300d00d0291f85b1688ce3e8db1b03464d37b`.
Logs: `build/recognition-pinned-diagnostics-build.log` and
`build/recognition-pinned-diagnostics-tests.log`.
Running process 74822 still started at `2026-09-15 07:38:13` and has not loaded
this artifact. Exact-path computer-control selection again timed out; bundle
identifier selection reports ambiguity among backup copies. No restart or
lock was performed. Live verification requires reopening the built app.

### Numeric turn-sweep clip — September 15, 2026

The supplied `1D2D7E1F-978D-4620-B71E-DCB906F0FC18.mp4` is 6.85 seconds
long and contains 274 video frames. Local CPU Vision OCR of the pinned
diagnostic region recovered score, threshold, yaw, pitch and recognition
status in all 274 frames, representing **57 distinct displayed readings**,
not 274 independent recognition evaluations. Six key readings were checked
again using enlarged numeric-region crops. No direct visual interpretation
of the person's movement was performed; directions below use signed raw yaw.
Video frames, OCR output and the parsed timeline remain under
`/tmp/gaze-clip-1D2D7E1F`, outside the repository.

| Video time (s) | Score | Raw yaw (rad) | Approx. yaw (degrees) | Display status |
| --- | --- | --- | --- | --- |
| 0.000 | 0.806 | -0.08 | -4.6 | Recognised |
| 0.700 | 0.813 | +0.41 | +23.5 | Recognised |
| 1.183 | 0.516 | +0.80 | +45.8 | Recognised |
| 1.283 | 0.332 | +0.86 | +49.3 | Not recognised |
| 1.633 | 0.102 | +1.11 | +63.6 | Not recognised |
| 2.033 | 0.574 | +0.74 | +42.4 | Recognised |
| 3.283 | 0.813 | -0.31 | -17.8 | Recognised |
| 3.600 | 0.525 | -0.80 | -45.8 | Recognised |
| 3.750 | 0.437 | -0.88 | -50.4 | Not recognised |
| 4.133 | 0.263 | -1.15 | -65.9 | Not recognised |
| 4.633 | 0.716 | -0.73 | -41.8 | Recognised |
| 4.983 | 0.825 | -0.11 | -6.3 | Recognised |

The displayed threshold remains **0.45** throughout. All recovered status
labels agree with the displayed score's threshold comparison. There are no
zero-score or missing-face displays in this recording. The positive failing
scores are consistent with completed below-threshold comparisons, not
`FaceEnrollmentStore.matches`'s zero-score embedding-unavailable result.
This is still a video of the throttled readout, not a per-inference trace.

For 27 distinct readings with absolute yaw at most 0.20 rad, scores range
0.805–0.825. Seven readings between 0.25 and 0.55 rad absolute yaw range
0.774–0.813. The first *displayed* failures on the outward sweeps occur at
+0.86 and -0.88 rad; these are not universal failure boundaries.

**Implication:** this sweep demonstrates recognition loss at large yaw and
recovery on return, while recognition remains strong at smaller turns.
`LivenessChallenge` requires a 0.30-rad (~17.2°) excursion **relative to its
baseline**, two qualifying samples, then a return within 0.10 rad. Raw yaw
alone cannot establish that a particular challenge completed: the recording
does not expose its baseline, selected action, admitted-frame sequence or
lock-screen gate state. This does not confirm the earlier enrollment-coverage
hypothesis at challenge-sized angles, nor prove the original lock-screen
reset is fixed. Prompt/return guidance and timing remain worth checking before
changing enrollment or recognition. No threshold, authentication or enrollment
changes are justified by this clip alone.

Process 77735 started at `2026-09-15 08:14:14`, after the pinned-readout build.
The on-disk binary hash still matches
`8751710cf7877f5a71775d5ed5e300d00d0291f85b1688ce3e8db1b03464d37b`;
the supplied screenshot/video display the new pinned UI. No restart or lock
was triggered during analysis. The recording's average ~39.9 FPS does not
measure the app's rendering FPS or explain the reported choppiness.

---

## Historical investigation (earlier process/build)

**Status:** Investigation only. No behaviour changed, nothing rebuilt, no thresholds
touched, no authentication checks removed, no credentials accessed, the Mac was not
locked. Working tree preserved: 60 modified, 32 untracked, 0 stashes.

**Investigated:** 2026-09-14 against running process 62586 (binary built 21:02), source at
`/Users/owencope/Developer/FaceID`.

**Revised:** 2026-09-15, after review. One conclusion was **withdrawn** and one method was
wrong. Both are recorded below rather than quietly edited out.

---

## Summary

| Claim | Status |
| --- | --- |
| A failed embedding and a low match score take the same `identity mismatch` reset branch | **Confirmed** (source) |
| Missing pupil landmarks during a turn are what actually fails | **Hypothesis only** — not observed |
| The `comparedIdentity` diagnostic is not in the running binary | **Confirmed** (symbol table + control) |
| Main-thread inference causes the choppiness | **Withdrawn — disproved** |

---

## Cause 1 — the reset path cannot tell two failures apart

### Confirmed, from source

`Sources/Recognition/UnlockFrameEvaluator.swift:27`

```swift
let rejected = Result(matched: false, score: 0, face: nil,
                      spoofDecision: nil, comparedIdentity: false)
guard !Task.isCancelled, ..., let candidate = embedder.embed(sample) else { return rejected }
```

`Sources/Security/LockWatcher.swift:537`

```swift
guard result.matched, let face = result.face else {
    matchingHold.reset()
    ...
    resetMovementGuidance(reason: "identity mismatch")
```

A failed embedding (`comparedIdentity: false`, `score: 0`) and a genuine low score both
take this branch and both are labelled `identity mismatch`. In the first case nothing was
compared, so the label is wrong.

### Observed behaviour

```
21:32:06.643  Movement prompt presented; action=Turn your head left
21:32:08.251  Movement guidance withdrawn; reacquiring face. reason=identity mismatch
21:32:10.410  Movement prompt presented; action=Turn your head left
21:32:12.118  Movement guidance withdrawn; reacquiring face. reason=identity mismatch
21:32:14.616  Movement prompt presented; action=Turn your head left
21:32:15.873  Movement guidance withdrawn; reacquiring face. reason=identity mismatch
21:32:22.649  Movement prompt presented; action=Turn your head left
```

Four prompts and three resets in sixteen seconds, always the same action. Similar clusters
at 21:20 and 21:26.

### Hypothesis — NOT confirmed

Both embedding paths require both pupils:

`FaceAligner.swift:22`

```swift
guard let leftEye  = sample.landmarks.leftPupil?.normalizedPoints.first,
      let rightEye = sample.landmarks.rightPupil?.normalizedPoints.first
else { return nil }
```

`FaceEmbedder.swift:113` has the same guard, plus `guard interocular > 0.01`.
`LivenessChallenge.swift:76` sets `turnDelta = 0.30` rad (≈17°).

It is *plausible* that at the yaw the challenge requires, one pupil occludes and the
interocular distance foreshortens, so `embed()` returns nil — meaning the turn that passes
the challenge is the turn that breaks the embedding. Consistent with the fact that `blink`
and `openMouth` keep the head frontal and do not fail this way.

**This was read out of the source. It has not been observed.** The logs from the running
build cannot distinguish it from a genuinely low score, because the field that would
distinguish them is not compiled in — see below. Do not treat it as established.

---

## What is and is not in the running binary

Use `nm` for type and method names; `strings` only sees literals.

```
nm -a build/Gaze.app/Contents/MacOS/Gaze | grep -c UnlockFrameEvaluator   → 38
```

So **`UnlockFrameEvaluator` IS in the running build.** An earlier revision of this report
said otherwise, having used `strings`, which was the wrong tool.

Stored-property names do appear in reflection field descriptors, so `strings -a` is valid
for those — with a control:

| `Result` field | present as an exact string |
| --- | --- |
| `matched` | yes |
| `score` | yes |
| `face` | yes |
| `spoofDecision` | yes |
| **`comparedIdentity`** | **no** |

The siblings are present and `comparedIdentity` is not, so the running build's `Result` has
four fields. The log line `Movement identity check failed` is likewise absent, while
`Movement evidence invalidated`, `Movement guidance withdrawn` and `Movement prompt
presented` are all compiled in.

**Conclusion: the running binary has `UnlockFrameEvaluator` but not the `comparedIdentity`
diagnostic.** It is an intermediate build, neither `HEAD` nor current source.

---

## Cause 2 — WITHDRAWN

An earlier revision claimed the choppiness came from ArcFace inference running
synchronously on the main actor, based on `HEAD` using `store.matches(sample)` on
`@MainActor LockWatcher` while the current source uses an `actor`.

**That reasoning was invalid and the conclusion is disproved.** Comparing against `HEAD`
does not establish what is running, and the running binary is neither. Its evaluator is an
actor:

```
_$s4Gaze20UnlockFrameEvaluatorCScAAAMc                              → Actor conformance
_$s4Gaze20UnlockFrameEvaluatorCScAAAScA15unownedExecutorScevgTW     → unownedExecutor
```

Inference is already off the main actor in the build that is being observed. **There is
currently no explanation for the choppiness, and no measurement of it.** No spindumps or
hang reports exist for Gaze in `~/Library/Logs/DiagnosticReports`.

Two log greps that look like evidence and are not:

- 832 lines matching `hang` — the substring comes from `RunningBoardServices
  didChangeInheritances`.
- 32 lines matching `stalled` — PlugInKit / LaunchServices plugin discovery at 18:20.

---

## Next steps

1. **Build the current source and reproduce.** `compared=false score=0.0` confirms the
   failed-embedding hypothesis; `compared=true score=<n>` refutes it and points at a real
   scoring problem.

   ```bash
   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer ./build.sh
   ```

2. **Measure the choppiness separately.** It needs its own evidence — frame timing or a
   sample of the render path — not an inference from code structure. The current source's
   `Movement evidence invalidated … inferenceMs=` line will at least bound inference cost.

## If the hypothesis holds, the fix is not a lower threshold

A missing embedding is not a weak score; thresholds do not affect it. The shape of a
correct fix is to stop treating "could not compare" as "did not match" — for instance
holding guidance across frames where `comparedIdentity == false` rather than resetting, so
a head turned far enough to satisfy the challenge does not discard the identity evidence
gathered before the turn began.

That is a behaviour change affecting an authentication path. It is not made here, and it
should not be made until step 1 says which failure is actually occurring.
