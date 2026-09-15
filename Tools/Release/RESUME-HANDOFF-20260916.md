# Resume handoff — September 16, 2026

The owner warned that the connection may drop. This records the active task and
remaining integration work; it is not a launch approval.

## Owner intent and constraints

- Finish Gaze launch preparation, then improve UI/UX. Gaze Passwords was also
  prepared in the preceding pass; preserve that work.
- Use Hydra for authorized delegation, through the fenced hydra JSON block in a
  final reply. Do not use built-in collaboration spawning. Workers use OpenCode
  Muse Spark 1.3; no Claude Code. The owner explicitly reiterated Hydra usage.
- Study `https://gitlab.com/droppyformac1/droppy-code` selectively for design ideas,
  preserving Gaze's identity. Its code is AGPLv3 with additional attribution terms;
  do not copy code/assets/branding into the MIT project by assumption.
- The owner explicitly authorized fixes in `/Users/owencope/Developer/gaze-site`.
  Read that checkout's AGENTS.md and installed Next.js documentation before editing.
  Deployment/publication is still a separate final step after concrete review.
- Never use git status/diff, reset, stash, reconcile or revert others' work.
  Do not commit, push, make branches or merge; Droppy handles landing.
- Preserve hidden normal animated return captions. Teach return-to-start in setup;
  retain Reduce Motion and VoiceOver cues. One/two movements are selectable, default two.
- No lowering recognition/PAD thresholds or weakening gates. No unsupervised lock,
  camera, credential-entry or enrollment test. Walk-away was left off.
- Read `/Users/owencope/.codex/skills/no-agent-messaging/SKILL.md` before coordination.
  Use `/usr/bin/log` explicitly. Builds need Xcode-beta via DEVELOPER_DIR.

## Current heads and recovery

Hank, Walter, Ada, Otto, Pip, Ivo, Lux, Tova, Gus and Hank 2 reported completed work
in the current launch/UI wave. The initial Nova failed with a provider error:
`reasoning encrypted_content was not issued to this caller`. No initial Nova changes
landed; its saved copy is `/Users/owencope/.droppy-code/worktrees/faceid-nova-8b02fc46`.
A fresh Hydra recovery task was sent. The owner has now confirmed **Nova 2 is done,
six files landed**. The root observes the pending/progress implementation in the
checkout, but has not yet received/audited the detailed recovery report or verified
its test results. Do not restart or duplicate it.

Observed recovery files: `Sources/Security/LockWatcher.swift`,
`Sources/LockScreen/NotchCapsule.swift`, `Sources/LockScreen/GazeFaceMark.swift`,
`Tools/GazePreview/Tests/MovementProgressTests.swift`,
`Tools/GazePreview/Tests/GuidanceCaptionTests.swift`, and the preview integration runner.
Confirm the exact list from the forthcoming report rather than assuming.

## Landed work requiring the lead's final audit/integration

1. **Pip — release checks.** `Tools/Release/preflight.sh`, `verify.sh`,
   `Tools/ReleaseRegression/preflight-checks.sh`, `run.sh`, `verify-artifact.sh`.
   Reports 23 identity/wiring + 29 verifier + 11 preflight checks passed.
   Check and integrate with the clearance validator; do not call preflight a legal
   or complete launch verdict. Check real tool discovery and failure behavior.
2. **Lux — clearance evidence.** All five files under `Tools/Release/ModelClearance/`:
   `clearance.json`, `validate.py`, `test_validate.py`, `README.md`, `OWNER-TEMPLATE.md`.
   Reports seven synthetic tests and real inventory refusal (all unresolved).
   Audit model AND asset coverage, including compiled-only models/new files; validate
   recorded bytes. No licence/grant has been established by this tooling.
3. **Ivo — website download patch.** Three files under `Tools/Release/UpdateDeployment/`:
   patch, test harness and deployment note. Patch is NOT yet applied to gaze-site.
   The current proposal redirects eligible public release filenames to stored URLs
   and maps the feed to same-origin `/dl/<name>`. Audit HTTPS/host restrictions,
   filename handling, privacy, ambiguity, missing real artifacts and fallback behavior
   before applying. The drafted code currently accepts stored HTTP(S) targets;
   do not assume this is an adequate release-download policy.
4. **Ada — Settings.** `Sources/App/SettingsView.swift` and
   `Tools/SettingsUXRegression/run.sh`. Retained-password controls in recognition-only
   mode, more accurate mode/auth copy, keyboard-focus-aware face controls. Reports
   parse + 19 source assertions only. Full typecheck/build and practical focus/layout
   checks remain; do not treat conditional focus controls as proven accessible.
5. **Otto — onboarding.** `SetupDoneStep.swift`, `SetupFlow.swift`,
   `SetupMeetGazeStep.swift`, `SetupPasswordStep.swift`, and
   `Tools/OnboardingRegression/OnboardingTests.swift`. Secondary Finish in Settings
   for partial setup, scanning lesson first, saved-password-change explanation.
   Reports 54 offscreen renders/checks. Verify AppActivation routing and final layout.
6. **Nova 2 — guidance.** Recovering outward `1 of 2`/`2 of 2` and a neutral
   `.pending` / `Waiting for macOS` state. Closed lock until real confirmation;
   no success tick before macOS confirms. Check all exhaustive phase switches,
   one/two counts, resets, accessible labels, return hiding, preview and app builds.

The lead must read each head's changed files, correct problems itself, and run the
narrowest relevant checks. Never delegate the mandatory integration audit.

## Reviews already read and qualified by the lead

- `UI-UX-REVIEW-ONBOARDING-20260916.md`: keep clearing parsed CSV secrets on lock;
  only a non-sensitive interruption notice is appropriate. The setup header already
  teaches count/return, so the idle-first lesson is not absence of instructions.
  Revalidate browser status on refresh; do not preserve stale unqualified success.
- `UI-UX-REVIEW-SETTINGS-20260916.md`: contextual menus are not automatically
  pointer-only; missing Touch ID does not imply no password-based protection
  (the preference defaults true). Remaining findings include Resume in Settings and
  photo-rejection availability using Liveness rather than the enforced Spoof model.
- `UI-UX-REVIEW-GUIDANCE-20260916.md`: neutral pending, not success tick; 11pt
  readability concerns are not proof of macOS Dynamic Type clipping. Zero *extra*
  island caption allocation does not establish missing caption space.
- `DROPPY-DESIGN-REFERENCE-20260916.md`: source-based, no observed pixels.
  Potential original implementations: settings search, contextual destructive
  confirmations with precise consequences, arrow navigation in Passwords search.
  Check claims against current code before adopting (vault search already has an
  onSubmit handler in LiveVaultView). No Droppy implementation has been copied.
- `Tools/Release/Signing.sh`: Hank added certificate instructions; root clarified
  that local builds still need/use Apple Development, not “no certificate needed.”
  Syntax check passed. Only Apple Development is currently available, no Developer ID.

## Earlier verified baseline (not proof that newer UI changes are built)

Gaze: `build/Gaze.app`, last verified executable SHA-256
`f75675d3f58213ab4128884b7f7274153d008937141b42e8b656dc8904ee289c`, built
September 15 21:53, launched PID 46045. The newer September 16 UI edits need rebuilding.
Earlier checks: 860 unlock, 99 presence/scheduling, nine presence policy, 34 movement
preference, 54 onboarding renders. Walk-away uses per-analysis absence evidence,
four-second proof, 20-second idle arming, 30-second retry spacing, active-session
lease and immediate cancellation cleanup. It remains opt-in/off in the saved state
at the last check. Recheck runtime identity rather than trusting an old PID.

Passwords canonical app: `build/browser-integration/Gaze Passwords.app`, SHA-256
`335de15c79948a45a9db2e9dcad299ba857b63b200eb9b28e6ec43d43634d2df`, built
September 15 22:46, launched PID 51873. Earlier protected candidate remains under
`build/passwords-release-prep/`; do not confuse it with canonical.
Passed 1,667 offline checks/tests, 56 packaging fixtures and 18 layout renders.
Both signed direct status probes passed without approval or credentials. The
BrowserOS registration was NOT rewritten; rebuilding the canonical path refreshed
its helper. No Gaze extension entry was found in the inspected Default profile's
Preferences/Secure Preferences; actual browser installation/status remains unverified.

Native CUA repeatedly fails with `Sky Computer Use native pipe startup failed`.
BrowserOS MCP tools are not exposed in the current environment. Do not fabricate
visual/live-browser verification or repeatedly debug these routes.

## Website and launch blockers

The prior privacy patch IS applied locally at
`gaze-site/src/app/api/latest/route.ts`: restricted releases return latest:null
before storage reads, all branches no-store. Its harness is
`Tools/Release/test-update-feed-privacy.cjs --current`.
The prior verified Vercel production commit lacked this route; no deployment has
been made. The download patch still needs audit/application and there is no cleared
real shipping artifact behind the seed download record. Do not publish placeholder
releases or unlicensed model bytes.

Remaining public-launch gates: exact model/asset redistribution evidence;
Developer ID signing + notarization/stapling; real owner-assisted lock/wake/failure
and browser/Keychain/face acceptance; clean installation/update and deployed feed.
The Passwords development profile expires 2026-09-20 23:51 UTC (September 21 Taipei).
No certificate purchase/provisioning, notarization, uploads or public release was done.

## Next work after resuming

Finish the release/clearance/download and UI integration audits above, apply only
reviewed website fixes, run focused tests plus the combined app build, and refresh
artifact hashes. The owner is back and may help with a short supervised live test
when the exact candidate is ready. Keep progress updates concise. When reporting
heads, start each part with the head's name and a plain statement of its user impact.
