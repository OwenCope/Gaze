# UI/UX Review — Onboarding and Cross-App Setup (2026-09-16)

Product-experience review of first-run setup and the handoff to Gaze Passwords.
Requested after the recent Gaze / Gaze Passwords improvements. Read-only review:
no enrollment, camera, Keychain authentication, real-password import, browser
registration, or live setting change was performed. All evidence below is
**source-quoted** (file:line); no live behavior was exercised and no renders
were generated. Anything marked "source inference" was not observed running.

Scope read: `Sources/Setup/SetupFlow.swift`, `SetupHowStep.swift`,
`SetupMeetGazeStep.swift`, `SetupCaptureStep.swift`, `SetupPasswordStep.swift`,
`SetupPermissionStep.swift`, `SetupDoneStep.swift`, plus `SetupPlan.swift`,
`SetupScaffold.swift`, `SetupControls.swift`, `Tools/GazePasswords/Live/LiveSettingsView.swift`,
`LiveImportView.swift`, `LocalPasswordStore.swift`, supporting `Sources/Security/`
vault code, the `NotchCapsule` return-caption path, and the existing
`Tools/OnboardingRegression/OnboardingTests.swift` harness (plan/expression
assertions and offscreen snapshots — not executed here).

## Findings (5, prioritized)

### 1. Partial setup dead-ends: skipping password/permission leaves no path forward

**Scenario.** A new user presses "Set Up Later" on the password step and again on
the permission step — the exact behavior the buttons invite. They land on
`SetupDoneStep` titled "Your face is saved" with the summary sentence and a
single Done button (`Sources/Setup/SetupDoneStep.swift:72-89`). The window
closes. Nothing tells them *where* Settings is or which pane finishes the job;
they must discover it alone, and the face they just enrolled still cannot unlock
anything.

**Evidence (source).** `SetupFlow.unfinished` is read honestly at display time
(`SetupFlow.swift:283-294`) and the summary copy names what is missing
(`SetupDoneStep.swift:15-29`) — the diagnosis is right, but the actions block
offers only Done when there is no failure (`SetupDoneStep.swift:85-89`). There
is no "Open Settings" / "Finish later in Settings" affordance in either the
partial or complete case.

**Proposal.** When `!unfinished.isComplete` (and not failed, not add-face), add
a secondary button that opens Settings at the pane holding the missing item(s)
(password and/or Accessibility). Keep the single Done button when complete.
Do not auto-route: the user chose "later", so offer the path, don't force it.

**Acceptance.**
- Fresh run, skip password + skip permission → Done screen shows the summary
  *and* a visible control leading to Settings.
- Complete run (face + password + permission) → Done screen unchanged (Done only).
- Add-a-face run → unchanged ("Face added", Done only).

### 2. "Meet Gaze" opens on the idle lesson, burying the movement instruction

**Scenario.** A first-run user reaches Meet Gaze — the one screen that teaches
the one/two-movement challenge. The first thing they see is the `waiting`
lesson: "Ready when you are / Gaze is ready. Its eyes may wander" — the idle
state, not the task (`SetupMeetGazeStep.swift:60,67-71,184-201`). The actual
instruction (`scanning`: "Look toward the camera… two short movements… then
return to your starting position") is one click away, each of the five movement
prompts further still, across 9 lessons. They can press "Continue Setup" without viewing a movement lesson. The always-
visible header already explains the count and return, so the instruction is not
absent; the default demonstration could emphasize it better. The one/two-movement
count itself is handled correctly everywhere once seen (`movementCount`
plumbing in `SetupHowStep.swift:20,26`, `SetupMeetGazeStep.swift:19-30,192`,
harness `how-one`/`meetGaze-one` snapshots) — the problem is purely what is
shown first.

**Evidence (source).** `GazeExpressionGuide` initialises
`_lesson = State(initialValue: lesson)` with default `.waiting`
(`SetupMeetGazeStep.swift:60,67-71`); `SetupMeetGazeStep` does not override it
(`:184-201`).

**Proposal.** Initialise the onboarding instance at `.scanning` (keep `.waiting`
reachable via Previous/menu). One-line change; no copy change.

**Acceptance.**
- Fresh Meet Gaze screen → visible title "Looking for you" with the
  one/two-movement sentence by default (both `movementCount == 1` and `== 2`
  variants, matching the existing harness assertions at
  `OnboardingTests.swift:169-170`).
- All 9 lessons still reachable via Next/menu; reduce-motion and pause behavior
  unchanged.

### 3. The saved login password can go stale, and onboarding never says so

**Scenario.** A user completes setup, then changes their Mac login password a
month later (as IT policies require). Gaze keeps typing the old saved copy at
the lock screen and unlock fails. Nothing in onboarding said the saved copy is
a snapshot that must be re-saved after a Mac password change, or where to
update it. The failure surfaces at the lock screen — the one place it cannot
be fixed.

**Evidence (source).** Password step copy: "Use the password you enter to log in
to this Mac. macOS checks it before Gaze saves an encrypted copy."
(`SetupPasswordStep.swift:33-35`). How-step trust line: "Gaze needs an
encrypted, recoverable copy of your Mac password."
(`SetupHowStep.swift:35-36`). `PasswordVault.store` verifies-then-saves
(`Sources/Security/PasswordVault.swift:24-32`); a repo-wide search finds no
stale/change detection or re-prompt path for the saved copy (source inference —
absence of code, not observed behavior). The existing copy is accurate about
*this moment* (verified before save) and silent about *later*.

**Proposal.** Add one sentence to the password step or the How-step trust block,
e.g. "If you change your Mac password later, save the new one in Gaze
Settings." — plus confirm Settings actually surfaces that update path (if it
does not, that is the companion fix; this review did not redesign Settings).
Avoid any claim about automatic detection; there is none.

**Acceptance.**
- Password or How step visibly states the saved copy must be re-saved after a
  Mac password change and names where (Settings pane).
- No copy implies Gaze tracks password changes automatically.
- Wrong-password vs save-failure distinction in `SetupPasswordStep.swift:91-100`
  unchanged.

### 4. Import review is silently discarded when the vault auto-locks

**Scenario.** In Gaze Passwords, a user picks their Apple Passwords CSV export,
reviews the counts ("Ready to import N / Already saved / Conflicts / Skipped
rows" — `LiveImportView.swift:47-70`), then cmd-tabs to Finder/Safari to
double-check the export file. The vault auto-locks on resign-active
(`LiveImportView.swift:102-107`); `lock()` rotates `sessionID`
(`LocalPasswordStore.swift:221-223`); `onChange(of: store.sessionID)` fires
`clearReview()` (`LiveImportView.swift:101`); the commit guard also clears
silently (`:138`). The user returns to a bare "Choose CSV file…" with no
message — the reviewed file, counts, and context are gone without explanation,
and they must re-pick and re-review to discover whether anything was imported
(nothing was — but the screen does not say that either).

**Evidence (source).** All references above; chain is source inference
(lock → session rotation → review wipe), not observed live.

**Lead decision.** Keep clearing parsed CSV records on lock: they contain
plaintext passwords. Retaining them would change a security lifetime. Instead,
retain only a non-sensitive interrupted-review flag and show a short explanation
that the file must be chosen again. Do not retain the filename or parsed secrets.
Only say no import occurred when the interrupted state establishes that fact.

**Acceptance.**
- Lock (or resign-active) during CSV review → on return, the user sees either
  an explicit interrupted-review notice and a route to choose the file again;
  parsed credentials remain discarded.
- `commit()` still requires live session + active app (guard at `:138` kept).
- Normal choose → review → import flow unchanged when no lock intervenes.

### 5. Browser setup: the three-step distinction is stated once, then undermined by transient status

**Scenario.** A user follows Browser connection: "Connect browser…" (dialog:
"Adds this app's native helper… No extension is installed… Existing helper
registrations are never replaced." — `LiveSettingsView.swift:161-164`) →
"Helper registered — load the extension next" (`:203-204`). They then press
"Find installed browsers" to double-check — and `refreshBrowsers()` clears
`setupStatus/setupDetails/conflictingRegistration` (`:182-188`), wiping the
confirmation and the "another copy" warning. Separately, the entry button says
**Connect** browser while every outcome says **Helper registered** — the two
verbs never meet, so a user cannot tell whether "connected" and "registered"
are the same state. The concluding guidance ("Helper registration, extension
loading and Gaze approval are separate steps… Check app connection inside the
installed extension" — `:139`) is the right mental model, but it sits as small
caption text while the status it explains evaporates.

**Evidence (source).** `LiveSettingsView.swift:107-127` (buttons above, status
below), `:139` (three-step sentence), `:182-188` (refresh clears status),
`:196-213` (register outcomes), `:161-164` (dialog copy).

**Proposal.** (a) Revalidate helper-registration state on browser refresh before displaying
it again. Do not preserve an unqualified cached success or conflict from an older
browser selection or app location.
(b) Align verbs: either the button/dialog adopts "Register helper…" language or
the outcome adopts "Connected". No checklist UI, no new steps.

**Acceptance.**
- Register helper → "Find installed browsers" → the "Helper registered — load
  the extension next" state (or the "connected to another copy" warning with
  its "Show existing helper file" button) survives the refresh.
- The words on the Connect button, the confirmation dialog, and the success
  status use one consistent verb for the helper step.
- Extension-install and Gaze-approval remain presented as separate steps with
  their existing copy.

## Things to keep (design constraints observed in source)

- **Return-caption hiding + return taught in onboarding (owner preference,
  honored).** `NotchCapsule.hidesReturnCaption` suppresses the caption during
  return-to-rest (`Sources/LockScreen/NotchCapsule.swift:457-459`), while
  onboarding teaches the return explicitly (Meet Gaze header
  `SetupMeetGazeStep.swift:192`; turn/nod lessons `:22-25`; scanning `:22`).
  Nothing in this review proposes showing return text at the lock screen.
  Note (minor inconsistency, not a finding): blink/mouth lessons say "then open
  them" / "then relax" rather than "return to start" language — consistent with
  the live `LivenessChallenge.guidancePrompt` ("Open your eyes" / "Relax your
  mouth", `LivenessChallenge.swift:95-102`), so leave as is.
- **No Back into a saved capture.** `SetupFlow.back()` refuses post-save return
  and discards only unsaved progress (`SetupFlow.swift:252-267`); the plan
  enforces it (`SetupPlan.swift:31-38`, asserted in
  `OnboardingTests.swift:116-120`). The password step's missing Back is part of
  the same deliberate asymmetry — do not "fix" it into a re-enrollment trap.
- **Camera-denied recovery.** Denied → "Open Camera Settings" deep link with
  "then return here to continue", refreshed on activate
  (`SetupCaptureStep.swift:148-178`). Cancellation of the system prompt leaves
  the ask in place rather than advancing — correct.
- **Password verified before save; typo vs save-failure distinguished**
  (`PasswordVault.swift:24-32`, `SetupPasswordStep.swift:91-100` with reserved
  error space so buttons don't jump). Genuinely good; keep.
- **Storage claims in live copy are conservative and checkable.** How-step says
  "encrypted, recoverable copy" — consistent with `SecureVault`'s
  enclave-backed key and keychain `ThisDeviceOnly` + non-synchronizable storage
  (`Sources/Security/SecureVault.swift:5`, `Sources/Security/Keychain.swift:54-59`).
  Note: stronger claims ("Secure Enclave", "never synced") currently exist only
  in the **unrendered** `SetupFactArt`/`StoredPasswordRowArt` code in
  `SetupHowStep.swift:66-88,510-564` — `SetupFactCarousel`/`SetupFactArt` are
  referenced nowhere outside that file (the live body renders the `fact(...)`
  rows at `:32-39`). If the carousel is intentionally retired, delete it so a
  future edit cannot "update" trust copy that never ships; if it is the future,
  say so in a comment. Either way, keep exactly one live source for storage
  claims.
- **Browser handoff honesty.** Non-destructive connect (dialog `:161-164`,
  `existingRegistration` guard `:205-208` with "Show existing helper file"),
  "Opening this page does not install anything" (`:176`), vault auto-lock on
  resign-active/sleep/screen-lock (`LiveImportView.swift:102-107`), CSV
  plaintext warning + never-overwrite-existing (`LiveImportView.swift:32-33,51-53`).
  All worth keeping; findings 4–5 build on them rather than replacing them.
- **Harness coverage is real.** `OnboardingTests` asserts plan traversal,
  back-navigation asymmetry, one/two-movement strings, and renders offscreen
  snapshots including `movementCount: 1` variants — findings 1, 2, and 5 each
  have a natural home as an added assertion/snapshot there.

## Out of scope / not verified

- Live rendering, animation choppiness, and the left/right challenge-reset
  investigation (`CHALLENGE-INVESTIGATION.md`) — untouched (launch-infra heads
  own adjacent work; nothing here alters the unlock loop, thresholds, or
  broadcast).
- Whether Settings currently exposes "update saved password" and "Accessibility
  status" panes adequate for findings 1 and 3 to link to — flagged, not
  redesigned.
- The `keyboardEvents` (`CGPreflightPostEventAccess`) half of
  `SetupPermissionStatus` is invisible in the permission row copy (row branches
  only on `accessibility`, `SetupPermissionStep.swift:87-88`): if AX is trusted
  but keystroke posting is not confirmed, the screen reads "Waiting for macOS
  to confirm" indefinitely. Watch item only — rare state, untestable here, and
  the polling + "quit and reopen this copy" recovery is otherwise sound.
