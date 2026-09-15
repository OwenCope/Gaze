# Walk-away lock — readiness assessment (2026-09-15)

## Integrated result — lead audit

The implementation now builds and passes 99 synthetic absence/scheduling checks,
9 execution-policy checks and production lifecycle wiring checks. The full Gaze
build and all 860 unlock regressions pass. Walk-away locking remains OFF in the
owner's saved settings; no live camera/absence/automatic-lock trial was performed.

Implemented: explicit no-face evidence spanning four seconds of capture time;
per-analysis delivery so a face between 400 ms polls cannot be missed; fresh-frame
checks before the lock request; bounded startup/confirmation; immediate camera
stop on disable; task-generation protection; 30 seconds between idle checks;
independent opt-in lifecycle; diagnostic-policy refusal; permission status and
clearer settings help. Input restarts the normal 20-second idle wait. Any detected
face, including a face whose landmarks fail, cancels the check. No face identity
is required; the enrolled camera pin is used when configured.

Lead corrections to Lena's implementation: invalid/stale repeated observations
now invalidate proof, not only new frames; callback delivery covers every analysis;
stopping a task immediately stops its camera and cannot clear a newer task's state;
permissions, policy, pause and session are checked throughout and before locking.
The original session check required a lock flag that macOS omits while unlocked:
a read-only check here returned `lockFlagPresent=false`, `onConsole=true` and
`loginDone=true`. The implementation now uses the existing owner-console session
lease, which also handles lock/sleep/user switching. ScreenLock logs a posted
shortcut rather than claiming that macOS confirmed a lock.

Kai decoupled lifecycle from password replay/backend selection; Vera added the
permission/status/help UI. The lead checked their integration and shortened the
copy. A 30-second retry interval was chosen instead of the proposed 5–10 minutes,
reducing repeated camera starts without adding minutes of delay after a reader
leaves. It is still a best-effort feature: display-awake assertions suppress it,
and unreliable/unknown camera evidence leaves the Mac unlocked.

Logs: `build/walk-away-presence-tests.log`, `walk-away-lifecycle-tests.log`,
`walk-away-wiring.log`, `walk-away-unlock-regressions.log`, `walk-away-build.log`,
`walk-away-launch.log` (all under `build/`). Owner-run false-lock, wake, media and
camera-timing trials remain required before shipping.

## Original investigation — pre-fix source snapshot

The findings below describe Bo's read-only investigation before the changes above.
References to missing code and old timings are historical, not current blockers.

Screenshot under review: Settings › `Lock when I walk away` /
`Checks the camera once you've been idle for 20 seconds`, toggle off.

## How the feature actually works (confirmed by reading)

- Trigger is idle, confirmation is camera (`Sources/Security/PresenceWatcher.swift:16-27`).
  Loop ticks every 5 s (`tick`), opens the camera only once
  `CGEventSource.secondsSinceLastEventType(.combinedSessionState)` ≥ 20 s (`armIdle`),
  waits about 4 s (`confirmWindow`, 400 ms polls), then requires a fresh
  no-face frame (≤ 500 ms, `CameraFrameLease.maximumAge`). That final spot check
  did not establish valid absence throughout the window.
- Identity is never checked: any single face aborts the lock
  (`PresenceWatcher.swift:142`). Multiple faces read as "missing" during sampling
  but fail the final `absence == .noFace` guard, so the verdict is still "don't lock"
  (`PresenceWatcher.swift:149-152`) — at the cost of holding the camera the full 4 s.
- Mid-check activity aborts early (`idleSeconds() < armIdle` per sample), and the
  lock is re-gated on toggle/pause/lock-state/idle after the 4 s window
  (`PresenceWatcher.swift:110-114`). Camera failure refuses to lock
  (`PresenceWatcher.swift:132-137`). These parts are correct and safe.
- Pause is honored on both sides of the camera window (`PresenceWatcher.swift:82,110-114`),
  and the already-locked guard keeps it from fighting `LockWatcher`
  (`PresenceWatcher.swift:85`).
- Mid-check lock/sleep/user-switch is contained by the foreground `CameraSessionGate` →
  `AutofillSessionLease`, which invalidates on `willSleep` / `screensDidSleep` /
  `sessionDidResignActive` / lock / unlock (`Sources/Security/AutofillSecurity.swift:46-56`,
  `Sources/Camera/CameraSessionGate.swift:16-25`).

## Confirmed issues (code, not hypotheses)

1. **Lifecycle is gated on the wrong thing.** `presenceWatcher` is created only inside
   `case .keystroke` *after* `guard PasswordReplaySafety.isEnabled`
   (`Sources/App/GazeApp.swift:277-300`). Locking needs no password and no backend,
   yet: launching with backend `.none` (or replay off) plus walk-away on = feature
   silently dead; switching keystroke → `.none` tears down `lockWatcher` but never
   stops `presenceWatcher` (no `stop()` call exists anywhere — grep confirms), so
   auto-lock keeps running under "Just recognise me". Creation and teardown are
   asymmetric around a dependency the feature does not functionally have.
2. **Toggle-on cannot start what was never created.** The walk-away toggle uses plain
   `bind()` (`Sources/App/SettingsView.swift:736-743,1299-1303`) and never calls
   `startUnlockTrigger()` (only launch and the backend switch call it —
   `GazeApp.swift:325`, `SettingsView.swift:513`). The "takes effect immediately"
   comment (`GazeApp.swift:290-295`) is true only if the loop already exists.
3. **No execution-policy gate.** `tickOnce` never checks
   `UnlockExecutionPolicy.permitsAutomaticLocking` (`UnlockExecutionPolicy.swift:24`;
   absent from `PresenceWatcher.swift:76-119`). In `--browser-only` with backend
   keystroke + replay on, `startUnlockTrigger` falls through to the backend switch and
   would create the presence watcher, which would then lock the Mac in a mode whose
   contract is "cannot type or lock" (`Tools/GazePasswords/Tests/BrowserCoreTests.swift:193`).
   `--scan-only`/`--ui-review` are safe today only because creation returns early, not
   because the watcher refuses — fragile. (Handoff to Lena.)
4. **No presence cooldown: the LED flash loop while reading is structural.** After a
   "somebody there" verdict there is no snooze — the next 5 s tick re-opens the camera
   (`isConfirming` only prevents overlap, `PresenceWatcher.swift:51,86,104-105`).
   An idle reader gets a camera session roughly every 5–6 s indefinitely (calculation
   from `tick`/`armIdle`, § Frequencies). This is a plausible usability issue,
   not a measured explanation of the owner's general request. The old detail
   string ("Checks the camera once…") obscures the repeated checks.
5. **Locking needs Accessibility, nothing says so.** `ScreenLock.now()` silently does
   nothing without AX (logs only, `Sources/Security/ScreenLock.swift:30-38`), and the
   Permissions section frames Accessibility as "to type your password"
   (`SettingsView.swift:664-676`). Walk-away on + AX revoked = silently never locks.
6. **Display assertion ≠ watching.** `isPlayingMedia` is really "any process holds
   `PreventUserIdleDisplaySleep`/`NoDisplaySleep`" (`PresenceWatcher.swift:182-206`).
   That includes video/calls (intended) but also `caffeinate -d`, presentation apps,
   wake-lock-holding browsers, stay-awake utilities — any of which suppresses locking
   indefinitely. Audio-only correctly still locks (system-sleep assertions ignored).
   Query failure fails open (returns true → never locks, `PresenceWatcher.swift:189`):
   safe direction, but a silent disable. Name and copy over-claim "watching".
7. **Start log line misleads.** `"Watching for you to walk away."`
   (`PresenceWatcher.swift:66`) logs on `start()` even when the toggle is off.
   Last-24 h log shows only this line at launches — no `Nobody there — locking.`, no
   skip lines — consistent with the toggle being off, but the line itself cannot
   distinguish armed from off. Read via `/usr/bin/log`, subsystem `com.gazeunlock.Gaze`,
   category `Presence`; no camera opened, no locks provoked.

## Hypotheses (not confirmed — would need measurement)

- H1: After wake-from-sleep, `idleSeconds()` may already exceed 20 s (no input during
  sleep), causing a camera confirm within ~5 s of every wake. Benign if present
  (flash), desired if absent (lock) — but unmeasured; there are no sleep/wake
  observers on `PresenceWatcher` at all (full-file read: no NotificationCenter).
- H2: Fast-user-switch background-session behavior is unknown: `screenIsLocked()` reads
  only `CGSSessionScreenIsLocked` (`PresenceWatcher.swift:208-214`) with no
  console-user/owner check, unlike `LockedConsoleSession`/`AutofillConsoleSession`.
  Whether a switched-away session's watcher can open the camera or lock is unverified.
- H3: Camera-start latency / first-frame time after idle (hence exact LED-on time per
  reading flash) is unmeasured. Frequencies below are calculations from constants.

## Frequencies — calculations from scheduling constants, NOT measurements

Constants: `tick` 5 s, `armIdle` 20 s, `confirmWindow` 4 s, `sampleInterval` 400 ms
(≤ 10 samples), frame freshness 500 ms.

| Scenario | Camera duty (calculated) |
|---|---|
| Idle reading, face visible, no display assertion | Confirm every ~5 s tick; first face sighting aborts. Camera opens ≈ session-start + first frame per cycle → LED flash roughly every 5–6 s for the whole idle period (~10–12 sessions/min). |
| Idle reading, face out of frame / looking away | Could request a lock after the confirmation despite the owner still being seated; no measured rate available. |
| Media / video call / presentation / `caffeinate -d` | Zero camera (assertion guard first). |
| Truly away | About 20–25 s idle (tick phase), plus unmeasured camera startup and about 4 s confirmation before a lock request. No exact latency established. |
| Camera unavailable | No lock, ever (fail-closed toward not locking). |

## Recommended copy (truthful, opt-in, no owner claim, no guarantees)

- Title: keep `Lock when I walk away`.
- Detail: `If you're idle for 20 seconds, takes a quick camera look. Any face counts as you — this is not owner recognition — and video, calls, presentations, or stay-awake apps pause it. It can take ~30 seconds to lock, and it briefly lights the camera while you read without touching anything.`
- Help/info: `Off unless you turn it on. Needs Accessibility permission to lock, and only runs while Gaze is running and unpaused. Best effort, not a security guarantee.`
- Keep off-by-default (`Preferences.swift:200-207`, `defaults.bool` defaults false — confirmed).

## Prioritized implementation brief

**P0 — lifecycle (lead to triage; PresenceWatcher edits → Lena)**
- P0.1 Decouple presence lifecycle from keystroke/replay: create the watcher
  independent of backend (or call `startUnlockTrigger()` from the walk-away toggle).
  Points: `GazeApp.swift:231-305`, `SettingsView.swift:736-743,1299-1303`.
- P0.2 Gate `tickOnce` (and the post-confirm re-gate) on
  `permitsAutomaticLocking`. Points: `PresenceWatcher.swift:76-119`,
  `UnlockExecutionPolicy.swift:24`.
- P0.3 Decide and document: does "Just recognise me" stop auto-lock? Make creation
  and teardown symmetric (either always stop on backend change or never gate on
  backend). Point: `GazeApp.swift:277-304`.

**P1 — duty cycle and honesty (the owner's complaint)**
- P1.1 Post-present snooze: after seeing a face, don't re-confirm for N minutes
  (fixed, e.g. 5–10 min) unless fresh input arrived first. Kills the reading flash
  loop without touching thresholds. Point: `PresenceWatcher.swift:76-119`.
- P1.2 Ship the copy above; add AX-missing status when walk-away is on but
  `AXIsProcessTrusted()` is false. Points: `SettingsView.swift:736-755,645-677`,
  `ScreenLock.swift:30-38`.
- P1.3 Log armed state (`walkAwayLock` value) in the start line. Point:
  `PresenceWatcher.swift:57-67`.

**P2 — if retained**
- P2.1 Configurable idle delay is justified (cheap, legible: 20 s / 1 min / 5 min,
  default 20 s); retry cooldown should stay fixed, not configurable. Points:
  `Preferences.swift:200-207`, `PresenceWatcher.swift:38`.
- P2.2 Wake debounce + background-session guard (reuse the `AutofillSessionLease`
  pattern); resolve H1/H2 by measurement, not reasoning. Points:
  `PresenceWatcher.swift:208-214`, `AutofillSecurity.swift:29-77`.
- P2.3 Do not promise security while a display assertion is held; consider capping
  indefinite suppression — copy-only for now (P1.2 covers it).

## Rules preserved

Opt-in/off-by-default kept; no owner-recognition claim (any face = present, stated in
copy); no immediacy/guarantee promise (latency table + "best effort" copy).
No thresholds touched. No source files modified.
