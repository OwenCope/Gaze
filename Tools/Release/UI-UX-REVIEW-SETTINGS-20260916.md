# Settings & recovery UX review — 2026-09-16

Fresh product review of the Settings window and its recovery paths, as requested.
Source-only: the app was not launched, no preference was changed, and the camera,
authentication, credentials and installers were not touched. Findings are ordered
by priority. Each proposes the smallest change that fixes the understanding gap —
no new warning banners, no restyled surfaces, and nothing that weakens
authentication. Where the code already matches the copy, that is recorded at the
end rather than inflated into findings.

Scope read: `Sources/App/SettingsView.swift`, `Preferences.swift`,
`NotchSettings.swift`, `GazeSettingsPicker.swift`, `Theme.swift`,
`ReleaseUpdateChecker.swift`, plus the backend/permission paths Settings reports
on (`UnlockBackend.swift`, `BiometricGate.swift`, `LockScreenPasswordSubmission.swift`,
`CameraDevice.swift`, `PresenceWatcher.swift`, `PresenceCheckSchedule.swift`,
`LockWatcher.swift`, `FaceCheck.swift`, `TamperGuard.swift`, `GazeApp.swift` menu bar).

## 1. High — A stored password persists invisibly in recognition-only mode, and Revoke is unreachable there

**User impact.** Someone who steps down to "Just recognise me" reasonably believes
nothing of theirs can release their password any more. In fact the recoverable
copy stays in the vault with no visible trace anywhere in that mode, and the only
way to delete it is to switch back to "Unlock my Mac" first — a step nothing on
screen suggests.

**Evidence.**

- `SettingsView.swift:493-496` — `passwordRow` (Store / Stored / Change / Revoke)
  renders only when `settings.unlockBackend == .keystroke`.
- `SettingsView.swift:530-531` — in `.none` the group footer is just
  `"See recognition working without wiring it to anything."`
  (`UnlockBackendKind.detail`, `UnlockBackend.swift:40-41`). No mention of a
  retained password.
- `SettingsView.swift:613-616` — the one sentence that does say the truth
  ("Switching modes does not delete an existing password…") lives inside the
  `InfoButton` in the hidden row, so it is unreadable exactly when it applies.
- `PasswordReplaySafety` consent and `unlockBackend` are separate stored keys
  (`LockScreenPasswordSubmission.swift:5-15`, `Preferences.swift:277-279`), and
  switching modes never touches the vault — confirmed, not assumed.
- Supporting overstatement in the same mode: hero detail
  `SettingsView.swift:357` says "Recognise your face without entering a
  password," but under a normal launch `UnlockExecutionPolicy.swift:31-33`
  (`permitsScanning`) means the lock-screen loop does not run at all in `.none`
  — recognition happens only in Test Recognition. (The `--scan-only`
  diagnostic excepted.)

**Proposed fix.** When `unlockBackend == .none && PasswordVault.hasPassword`,
show one compact retained-password note inside the existing Unlocking group with
the existing Change / Revoke actions — reuse, don't redesign. Adjust the `.none`
hero detail so it no longer implies lock-screen recognition under a normal
launch. No change to keystroke mode, no new banners.

**Acceptance.**

- Store a password under "Unlock my Mac", switch to "Just recognise me":
  Settings shows the stored state and a working Revoke without re-enabling unlock.
- Revoking there clears the vault (`hasStoredPassword` re-reads false on return).
- Hero in `.none` under normal policy does not claim lock-screen recognition.

## 2. High — Removing a face (and choosing a portrait) is pointer-only; keyboard and VoiceOver users cannot revoke an enrolment

**User impact.** The enrolled-faces row is where access is revoked. A keyboard-only
or VoiceOver user can reach the name field but never the remove control, so they
cannot take away someone's ability to unlock the Mac from Settings.

**Evidence.** `SettingsView.swift` `FaceTile:1469-1570` — both the remove button
(`:1539-1550`) and the portrait-choose button (`:1525-1537`) render only inside
`if hovering`, and `hovering` is set solely by `.onHover` (`:1569`). Portrait
management also has a `contextMenu` (`:1515-1520`); its keyboard/VoiceOver
behavior was not tested and must not be assumed pointer-only. There
is no focus path: focusing the name `TextField` does not reveal either button,
and nothing else in the tile exposes a Remove action to the accessibility tree.

**Proposed fix.** OR keyboard focus into the same reveal condition (a
`@FocusState` on the tile alongside `hovering`) and give the remove button an
explicit label such as "Remove \<name\>". Pointer appearance and behaviour stay
exactly as they are.

**Acceptance.**

- Tabbing to a face tile reveals and reaches Remove; activating it runs the
  existing `BiometricGate.authorize(.removeEnrollment)` path.
- VoiceOver announces a Remove action for each enrolled face with no mouse.
- Pointer hover visuals unchanged.

## 3. Medium — "Require Touch ID for changes here" governs fewer changes than it names

**User impact.** Users calibrate trust from this row: on means "nothing changes
without me", off means "stop asking". Both readings are wrong at the edges. The
most consequential change — enrolling a *new* face that unlocks the Mac — always
prompts regardless of the switch, while removing a face and storing/revoking the
password silently stop prompting when it is off. Macs without a Touch ID sensor cannot change this preference through the
disabled control. The default is enabled, so this does not establish that such
Macs lack password-based protection.

**Evidence.**

- `SettingsView.swift:774-781` binds the row to `touchIDFallback`.
- `BiometricGate.swift:38` — `authorize()` returns `true` immediately when the
  setting is off. Its only call sites are remove-enrolment (`SettingsView:399`)
  and store/revoke password (`SettingsView:1389,1408`).
- `BiometricGate.swift:50-53` — `require()` always prompts. Its call sites are
  adding an enrolment (`FaceEnrollment.swift:200`) and trusting an autofill app
  (`SavedApp.swift:109`).
- `BiometricGate.swift:70-75` — `evaluate` uses `.deviceOwnerAuthentication`
  with a "Use Password…" fallback, so the check is Touch ID *or* password; yet
  the row disables when `!BiometricGate.isAvailable` (`SettingsView:780`), and
  `isAvailable` tests biometrics only (`BiometricGate.swift:25-29`).

**Proposed fix.** Relabel to the actual scope, e.g. "Ask before removing a face
or changing the stored password". Keep the `require()` paths always-on — the
fix is copy, not a weakened gate. Decide explicitly whether no-sensor Macs
should get password-based gating (the evaluation already supports it) or keep the control disabled with accurate explanation. Do not infer an
opt-out from missing Touch ID: the default preference is true.

**Acceptance.**

- With the switch off, adding a face still prompts; the label describes exactly
  the two `authorize()` call sites.
- No-sensor behaviour is a deliberate choice, stated in one place.

## 4. Medium — Settings announces "paused" but offers no way back; Resume lives only in the menu bar

**User impact.** The pause-then-forget trap the `Preferences` docs worry about
(`Preferences.swift:169-175`) resolves, for a Settings reader, into a dead end:
the window names the state and provides no action, so recovery depends on
discovering the menu-bar item.

**Evidence.**

- Hero: `SettingsView.swift:342` ("Gaze is paused"), `:354` ("Face recognition
  is temporarily paused."). No Resume control anywhere in Settings.
- Resume exists only in `MenuBarContent` (`GazeApp.swift:481-482`).
- The state is real, not cosmetic — paused means no camera, no panel, no
  indicator light (`LockWatcher.swift:199-206`) — so the missing action bites
  exactly when the user is trying to understand why nothing happens at lock.

**Proposed fix.** Add a Resume button to the hero row when `isPaused` (the
`@State settings` instance is already in scope; `settings.resume()` clears
`pausedUntil`). No new group, no banner — one button that appears only in the
paused state, mirroring the menu.

**Acceptance.**

- Pause via the menu, open Settings: the hero offers Resume.
- Resuming from Settings re-arms normal behaviour (next lock triggers an
  attempt under normal policy); the menu-bar deadline text and hero agree.

## 5. Medium — "Reject photos" availability reads a model nothing enforces; enforcement reads another

**User impact.** In the common state (neither model installed) the row reads
correctly, so this bites only with a partial install — but then it misreports
capability in both directions: a working protection shown as unavailable, or an
enabled switch that errors at readiness.

**Evidence.**

- Row enablement and footer read `Liveness.isAvailable` (`SettingsView:707`,
  `:811`) — the passive-texture model (`CoreMLLiveness`,
  `Resources/Liveness.mlpackage`, `LivenessDetector.swift:34-39`).
- Everything the switch actually arms reads `SpoofDetector` — the
  object-detection model (`Spoof.mlmodelc`): the unlock gate
  (`LockWatcher.swift:337-339`, `AntiSpoofGate(spoof: SpoofDetector())`),
  browser approval (`GazeBrowserApproval.swift:40`), and backend readiness
  (`UnlockBackend.swift:122`). `Liveness.detector()` has no callers on any
  unlock path.
- Divergent states: Spoof present + Liveness absent → switch disabled with "No
  anti-spoof model is installed" though the enforced model exists. Liveness
  present + Spoof absent → switch enables, then readiness reports
  "Anti-spoof protection is enabled, but its model is unavailable."
  (fails safe, but the row promised otherwise).

**Proposed fix.** Gate `isEnabled` and the footer on `SpoofDetector.isAvailable`
— the model the switch arms — or on either model with per-model copy. A
one-predicate change; no new warnings.

**Acceptance.**

- All four install combinations show consistent enablement and readiness; the
  neither-installed state reads exactly as today.
- Enabling the switch with its model present never produces the
  "model is unavailable" readiness error.

## Checked and not raised

- **One/two movement choice.** Enforced, not decorative: the count is captured
  at attempt start and pinned for the attempt's lifetime
  (`LockWatcher.swift:309,318`); there is deliberately no zero/off option
  (`Preferences.swift:121-146`), and a dedicated regression harness covers the
  contract (`Tools/MovementSettingsRegression/README.md`, not re-run per the
  brief). Row copy ("One is quicker; two asks for another completed response")
  matches the code.
- **Walk-away timing, help and status.** The figures in the row and explainer
  (`SettingsView.swift:737-767`) match the constants: 20 s idle
  (`PresenceCheckSchedule.swift:5`), re-check no more often than every 30 s
  (`:6`), 4 s of fresh no-face evidence (`PresenceWatcher.swift:19`). Missing
  permissions produce a specific notice with direct recovery buttons
  (`SettingsView.swift:830-868`), and the diagnostic-session case says so
  plainly (`:832-835`).
- **Tamper protection.** "Ask for a password before quitting" is enforced in
  `applicationShouldTerminate` via `TamperGuard.authorizeQuit`
  (`TamperGuard.swift:41-52`), and the type's own header states its limits
  honestly (speed bump plus evidence, not proof). Claim matches code.
- **Update failures.** Offline and malformed-feed states are phrased as
  non-alarms with a working retry (`ReleaseUpdateChecker.swift:168-171`,
  `SettingsView.swift:932-941`); a failed background check does not overwrite a
  previously offered update (`ReleaseUpdateChecker.swift:96-102`).

## Live-inspection limits (what this review is not)

- No observed UI: the app was never launched, so text wrapping, focus rings,
  truncation of capped labels (e.g. the `.lineLimit(1)` movement and theme menu
  labels, `SettingsView.swift:724,904`), and compact-window behaviour at the
  660 pt minimum are code inference, not screenshots. `Tools/GazePreview`
  stages notch/companion animation only — there is no Settings snapshot harness
  — so none was produced rather than guessed at.
- VoiceOver/keyboard claims rest on view structure (labels, `labelsHidden`,
  hover-only branches), not on a running VoiceOver session. Finding 2 is
  structural — a control that only exists `if hovering` cannot be in any
  accessibility tree — but exact announcements were not observed.
- Release tooling was not re-audited and no prior head test was repeated; the
  movement regression suite is cited, not re-run.
