# Unlock path review

## Verdict

Nothing in this path lets an unauthorised person in without the owner's live face: every recognition, session, lockout and submission error I traced refuses to unlock. I did find one HIGH issue where the owner's own password can be typed into the wrong window, plus five LOW issues (dead code from the disabled XPC/PAM path, a misattributed success counter, a vestigial struct field, an ignored parameter, and password `String`s that are never wiped).

## High

- **Password submission never verifies what has focus; the input guard only detects input transitions, not a pre-existing wrong focus.**
  `Sources/Security/LockScreenPasswordSubmission.swift:94` — `func checkPermissionAndSession() throws {` checks enabled state, event-posting permission, session equality (`currentSession() == session`, :98) and verification freshness, then `for event in events { ... post(event) }` (:106–108) with no check of which element receives the keystrokes; `Sources/Security/LockScreenInputGuard.swift:23` — `if current != initial { wasInterrupted = true }` compares only global HID counters.
  Given a lock-screen field other than the password field already focused before the attempt's input snapshot is taken (e.g. a username entry on a user-selection screen), counters stay stable through verification, the owner completes face plus movement verification, and the account password is posted into the plaintext field, which is wrong because every guard in the submission path passes while saying nothing about the target.
  Direction: bind submission to the focused password field (or abort unless it is focused) rather than relying on input-change detection.

## Medium

No medium findings.

## Low

- **Any unlock concurrent with a Gaze submission is counted as Gaze's success and clears the lockout counter.**
  `Sources/Security/LockWatcher.swift:711` — `didSubmitPassword = true` is set immediately after posting events, before macOS confirms anything; `Sources/Security/LockWatcher.swift:272` — `lockout.recordSuccess()` runs on any subsequent unlock notification while the flag is set.
  Given banked failures and a Gaze submission followed within the grace period by a Touch ID or typed-password unlock, the failure counter is wiped by an unlock Gaze did not cause, which is wrong because the counter should reflect Gaze's own rejections.
  Direction: only clear the counter when the submission-unconfirmed watchdog does not fire.
- **If the unlock notification arrives while the session dictionary transiently reads nil, the attempt and camera are never stood down.**
  `Sources/Security/LockWatcher.swift:250` — `guard AutofillConsoleSession.current() != nil else { return }` returns before `attempt?.cancel()`.
  Given a nil session dictionary at the unlock moment (e.g. fast-user-switch churn), the camera keeps running until the 60-second deadline on an unlocked Mac, which is wrong because the attempt's reason to exist is gone.
  Direction: cancel the attempt before the session guard, or re-check on the next tick.
- **The XPC stub keeps dead surface: unused init parameters and an always-on listener whose comment overstates what it can do.**
  `Sources/Security/UnlockService.swift:12` — `init(store _: FaceEnrollmentStore, lockout _: LockoutManager) {}` takes dependencies the stub never touches; `:29` — `xpc_dictionary_set_int64(reply, "verdict", 3)` is the only possible answer (`kGazeVerdictUnavailable = 3`, `Plugin/GazeUnlockProtocol.h:40`); `Sources/App/GazeApp.swift:397` starts the listener on every normal launch with a comment presenting the PAM `sudo` module as a live second client of the same service.
  Given a reader auditing which components can still influence authentication, the live listener plus the comment imply a working authorization channel where none exists, which is wrong because the stub cannot answer anything but unavailable.
  Direction: drop the unused parameters and correct the comment to say the listener only exists for legacy clients that must hear "unavailable".
- **`comparedIdentity` can never be false on the live path, so it adds a check that cannot fire.**
  `Sources/Recognition/UnlockFrameEvaluator.swift:13` — `var comparedIdentity = true`; `:20–22` — the only other construction site is `rejected()`, which already sets `matched: false` with a non-nil `failure`, both of which `permitsMatchHold` (`:16–17`) independently requires.
  Given a future edit that constructs a `Result` with `comparedIdentity: false` and `matched: true`, the gate would silently gain a meaning it has never had, which is wrong because reviewers will read the field as live identity binding that nothing maintains.
  Direction: remove the field or set it at the one place identity is actually compared.
- **`permitsBrowserApproval` ignores its own gating parameter.**
  `Sources/Security/UnlockExecutionPolicy.swift:27` — `func permitsBrowserApproval(passwordReplayEnabled _: Bool) -> Bool`, always true in normal/scan-only/browser-only modes; callers at `Sources/Browser/GazeBrowserApproval.swift:133` and `Sources/App/GazeApp.swift:357` both pass `PasswordReplaySafety.isEnabled` to no effect.
  Given password replay disabled, browser approval still runs, which is wrong only in that the signature promises a coupling the body does not enforce; the browser path itself still requires face, challenge and anti-spoof and releases no Mac password, so impact is nil.
  Direction: either honour the parameter or remove it.
- **The account password lives as an immutable `String` through storage, load and keystroke preparation with no wiping.**
  `Sources/Security/PasswordVault.swift:34` — `static func password() throws -> String?`; `Sources/Security/Keystrokes.swift:42` — `var characters = Array(password.utf16)` copies it again; the parallel autofill path does the same at `Sources/Security/AutofillSecurity.swift:160–166`.
  Given a heap dump or forensic memory read, the password is recoverable long after the unlock, which is wrong because only the in-flight copy needs to exist; severity stays low because anything running as this user can already call `PasswordVault.password()`, as `SECURITY.md` discloses.
  Direction: keep the existing disclosure unless a secure-buffer type is adopted for the whole chain at once.
- **Retired helpers with no production callers remain: `AuthorizationRules.screensaverUsesPlugins()` and the autofill release path.**
  `Sources/Security/UnlockBackend.swift:212` — `static func screensaverUsesPlugins() -> Bool` has no callers in `Sources/`; `AutofillReleaseGate.release`, `AutofillAttemptBudget` and `AutofillOwnerApproval.authorize` (all in `Sources/Security/AutofillSecurity.swift`) are consumed only by the retired `Sources/Autofill/AutofillService.swift`, which `SECURITY.md` says is excluded from the build.
  Given a reader mapping what can release credentials, unreachable release-adjacent code invites wrong conclusions, which is unhelpful but not exploitable.
  Direction: leave alone if the retained-for-tests status is deliberate; otherwise gate or remove.

## Checked and clean

- **Fail-closed recognition.** `UnlockFrameEvaluator.evaluate` returns `rejected()` (matched false, `comparedIdentity` false, failure set) on cancellation, bad threshold config, missing embedding, out-of-range similarity and empty enrollment; `permitsMatchHold` additionally requires the face non-nil and `spoofDecision == .live` whenever anti-spoof is required. No error or unknown state can read as a match.
- **Fail-closed session handling.** Unknown lock state returns unlocked (`LockWatcher.swift:293`, deliberately avoiding typing when unsure); the submission session check requires locked, on-console, login-done, owner-equal and a valid UUID (`LockScreenPasswordSubmission.swift:52–66` via `LockedConsoleSession.validated`), re-read — not cached — before vault read, after vault read, and before every posted event.
- **Fail-closed anti-spoof.** Missing model with the setting on refuses at readiness (`UnlockBackend.swift`), at attempt start (`LockWatcher.swift:341–347`), and on `.unavailable` inference mid-attempt; with the setting off the weaker path is the documented default (`RELEASE_NOTES.md`), not a bypass.
- **Match-hold and challenge binding.** The two-second hold (`LockWatcher.requiredMatchDuration`) runs on camera capture timestamps, resets on frame gaps, quality rejections, face absence, identity change and continuity breaks, and self-resets on face-ID change (`RecognitionFrameGate.swift:13`); challenge responses must be fresh post-presentation frames (`UnlockChallengeGate.admits`: 350 ms presentation delay, advancing frame IDs, 8 s timeout, per-event freshness); submission revalidates session, verification, continuity revision and sample age per keystroke, so a stale verdict cannot be submitted after a camera gap or enrollment change (enrollment IDs, camera pin, liveness and movement-count prefs are all rechecked in `contextIsCurrent`).
- **Lockout cannot be reset or bypassed.** Counter lives in the Secure Enclave-backed vault, saturates, range-validates on load, fails into forced lockout on any read/persist error, and gates both attempt start and the per-tick currency check. The only clear path is `clearAfterPasswordAuth`, reachable only after `PasswordVault.verify` succeeds (`SettingsView.swift:1710–1712`). Relaunching resets only the in-memory one-submission latch and manual-input flag, neither of which skips verification or the persistent counter. Preference toggles and pause touch neither the counter nor the latch's fail-closed direction (a refused password spends the single submission until a verified unlock).
- **No password logging.** Vault, keystroke-preparation and lockout error paths log states and `localizedDescription`s that never contain the password; `Keystrokes.passwordEvents` refuses empty and control-character passwords and verifies the event payload round-trips before anything is posted; `CGEvent.post` failures are silent but leave the screen locked, which records a failure rather than retrying blindly.
- **The stub fails closed end to end.** Verdict 3 is `kGazeVerdictUnavailable` (`Plugin/GazeUnlockProtocol.h:40`); the plugin only proceeds on `kGazeVerdictMatch` (`Plugin/GazePlugin.m:731`) and otherwise falls back to password (`:756`); the PAM function returns `PAM_AUTH_ERR` and both installers refuse without touching the system (`Plugin/README.md:12–17`, confirmed against `SECURITY.md`). The `.authPlugin` backend preference is not dead: it resolves to an explicit unavailable state with user-facing messaging rather than a silent no-op.
- **Broadcast stays one-way.** `StateBroadcast` is posted to, never read for decisions, on both the lock and browser paths.

## Could not determine

- Whether the pinned-camera check (`store.pinnedCameraID` equality, enforced on every tick) actually guarantees a built-in sensor: pinning and device filtering live in camera/store code outside this review's file list.
- Whether Gaze's own posted keystrokes (private event source) can trip the `LockScreenInputGuard` HID counters and self-abort mid-submission: needs runtime observation on the lock screen.
- Whether any real lock-screen configuration presents a plaintext-receiving focus target in the same session (the HIGH finding's precondition): needs observation of the login window with Switch User / accessibility keyboards.
- Live delivery, timing and biometric strength (photo/video resistance with anti-spoof off, TrueDepth limits) need physical testing, as `SECURITY.md` already states; nothing here contradicts its Limits section.
