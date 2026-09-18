# Instance startup and service ownership — evidence (2026-09-18)

Scope: read-only trace of launch paths and duplicate-process protection.
No process launched, stopped, or signalled. No source edited, nothing built,
camera never activated, screen never locked, no credentials touched.
`com.gazeunlock.Gaze.state` untouched; no new broadcast proposed.
Skill `/Users/owencope/.codex/skills/no-agent-messaging/SKILL.md` could not be
read from this worktree (outside allowed directories); no agent messaging was
used. Production sources below are anchors only.

Known observed problem (per brief, not re-verified here): opening a second
`Gaze.app` with `--settings` while the launchd `--agent` instance was running
produced two Gaze processes; root closed only the extra instance.

## 1. Ordered startup operations (`Sources/App/GazeApp.swift`)

All on the main actor / main thread unless noted.

**Phase A — store construction (inside `GazeApp.init`, line 53):**

1. `AppServices.shared.store.isEnrolled` (line 55) — constructs
   `AppServices` (line 231): `FaceEnrollmentStore()` → Keychain reads via
   `SecureVault.load` (up to 3 reads) + synchronous Core ML model load via
   `Embedders.best()` → `CoreMLEmbedder()` → `MLModel(contentsOf:)`; then
   `LockoutManager()` → one more Keychain read (`lockout-state`).
2. `OnboardingHistory.markPresented()` / `presentsSetup(isEnrolled:arguments:)`
   (`Sources/Setup/OnboardingHistory.swift:6-19`) — UserDefaults read + one
   write. Suppressed by `--agent` / `--settings`.
3. `AppActivation.isBackgroundLaunch` (line 163) = argv contains `--agent`.
   Sets `presentsSettingsAtLaunch` (line 51): settings scene
   `.defaultLaunchBehavior(.presented/.suppressed)` (line 88); enrollment scene
   suppressed when background or settings-will-present (line 139).

No camera, window, socket, XPC, observer, or timer starts in Phase A.

**Phase B — actual service startup (`AppDelegate.applicationDidFinishLaunching`, line 382):**

4. `TamperGuard.shared.start()` — UserDefaults-gated bundle watch only.
5. `AppServices.shared.startUnlockTrigger()` (line 299):
   `syncPresenceWatcher()` → `PresenceWatcher.start()` (5 s tick; no camera
   until idle+absence proven) → `GazeBrowserApproval.start()` (binds Unix
   socket `gaze.sock`; models/camera only on request) → `LockScreenSpace.shared`
   (SkyLight space, no window) → `UnlockService.start()`
   (`Sources/Security/UnlockService.swift:15` — idle XPC mach-service listener
   `com.gazeunlock.Gaze.unlock`) → `LockWatcher.start()`
   (`Sources/Security/LockWatcher.swift:88-110` — DistributedNotificationCenter
   lock/wake observers; camera only on lock).
6. `ReleaseUpdateChecker.shared.startScheduledChecks()` — first check deferred
   8 s; no network at launch instant.
7. `AppServices.shared.runLockScreenShootIfRequested()` — `--shoot-lockscreen`
   only, skipped in review modes.
8. `startInvisibleWindowSweep()` (line ~418) — immediate window-server query +
   repeating 1 s `Timer` for process lifetime.
9. `GazeTips.configure()` — only when `executionPolicy == .normal`.
10. `--settings` handoff runs later, in `EnrollmentWindow.task`
    (lines 647-657): 200 ms sleep → `AppActivation.bringToFront()` (line 167;
    no-op on `--agent` launch unless `userInitiated`) → `openWindow(id:
    "settings")` → `dismissWindow(id: "enrollment")`.

**Settings-opening bridge (all in-process only):** `AppActivation.openSettings`
closure (line 154) is assigned in `GazeStatusItemLabel.onAppear` (line 489) as
`bringToFront(userInitiated: true)` + `openWindow(id: "settings")`.
`applicationShouldHandleReopen` (line 374) calls it on Dock reopen. Menu
`Settings…` button does the same (line ~579). Nothing here crosses processes.

## 2. Launch-mode paths

Policy: `UnlockExecutionPolicy.current` (`Sources/Security/UnlockExecutionPolicy.swift:9`);
`AppServices.executionPolicy` (line 232); `isUIReview` = anything non-`.normal`.

| Mode | Window behaviour | Services started |
| --- | --- | --- |
| normal (no flags) | settings iff `presentsSetup` (first run); else menu-bar only | presence (if setting on) + browser approval + XPC listener + LockWatcher per backend (`keystroke`+replay on) / plugin listener only (`authPlugin`) / none (`none`) |
| `--agent` | all windows `.suppressed`; `bringToFront` gated (line 168) | same as normal — **a `--settings` instance starts the identical service set** |
| `--settings` | enrollment task opens settings, dismisses enrollment (lines 647-657) | same as normal; `presentsSetup` forced false |
| `--setup` / `--capture-dataset` / `--setup-step=` | enrollment window held open (`presentsSetup` true) | same as normal |
| `--scan-only` | normal windows | LockWatcher only (scan, no submit); presence off; browser approval on |
| `--ui-review` | normal windows + safety banner | presence off; LockWatcher/XPC/browser-service start skipped (`guard !isUIReview`) |
| `--browser-only` | normal windows + banner | browser approval on; LockWatcher/presence off |

Existing launch regression coverage (all synthetic, none exercise two live
processes): `Tools/OnboardingRegression/OnboardingTests.swift:checkFirstUse`
(`presentsSetup` under `--agent`/`--settings`/`--setup`/`--capture-dataset`/`--setup-step=`);
`Tools/PresenceLifecycleRegression/LifecycleTests.swift` (+`test-wiring.sh`:
no second presence watcher in-process); `Tools/LockScreenSecurityRegression/test-production-hold.sh`
(duplicate-wake guard); `Tools/UnlockFlowRegression/*` (duplicate timestamps,
frame-gate holds); `Tools/GazePasswords/test-gaze-status.sh` +
`Live/README.md` (probe already-running signed service before launching).

## 3. Process-ownership / IPC guards: absent

- No file lock (`flock`/`fcntl` lockfile), no `NSRunningApplication` self-check,
  no `exit()`-on-second-instance, no `LSMultipleInstancesProhibited`, no
  cross-process "open settings in primary" IPC anywhere in `Sources/App` or
  `Sources/Security` (grep 2026-09-18). The only `fcntl` use is non-blocking
  flag handling on browser sockets (`Sources/Browser/BrowserSocket.swift:11-12,159`).
- `UnlockService.start()` (`UnlockService.swift:15`) has `guard listener == nil`
  (in-process only); a second process binding the same mach service gets no
  exclusivity error handling — both listeners coexist.
- `GazeBrowserApproval.start()` swallows bind failure into a log
  (`Browser approval listener unavailable`) — second instance degrades silently.
- `Resources/Info.plist`: `LSUIElement=true` (line 41), no multiple-instance key.
- Launch persistence is split: `LoginItem` (`Sources/Security/LoginItem.swift`)
  uses `SMAppService.mainApp` (register once, no `KeepAlive` — see its header
  comment lines 7-14); the legacy `Plugin/com.gazeunlock.Gaze.agent.plist`
  still declares `KeepAlive=true` + `RunAtLoad` with `MachServices`
  `com.gazeunlock.Gaze.unlock`, and its `ProgramArguments` contain only
  `/Applications/Gaze.app/Contents/MacOS/Gaze` — **no `--agent` flag**, so a
  launchd-spawned instance takes the non-background path (windows eligible,
  `bringToFront` ungated).

## 4. Entrypoint → first side effect → duplicate protection

| Entrypoint | First side effect | Current duplicate protection |
| --- | --- | --- |
| `GazeApp.init` (GazeApp.swift:53) | Keychain reads + Core ML model map + UserDefaults write (`markPresented`) | **None** |
| `AppDelegate.applicationDidFinishLaunching` (line 382) | bundle watch; presence tick; `gaze.sock` bind; XPC listener; lock observers; update timer; window-sweep timer | **None cross-process** (in-process `nil` guards only) |
| `--agent` launch | identical side effects, windows suppressed | None — full service stack runs |
| `--settings` second launch | identical side effects, then settings window opens | None — this is the observed two-process case |
| review-mode launch (`--scan-only`/`--ui-review`/`--browser-only`) | reduced service set per §2 | None at process level |
| Dock reopen on running app | `applicationShouldHandleReopen` → in-process `openSettings` | N/A (single process) |
| `BrowserAppLocator.open` (`Sources/Browser/BrowserAppLocator.swift:4-14`) | `NSWorkspace.openApplication` (normally reuses running instance) | Relies on AppKit reuse; bypassed by `open --args`, which spawns anew |

## 5. Earliest practical integration point for root's decision

`GazeApp.init` top (before `AppServices.shared` is touched, GazeApp.swift:53)
or the head of `applicationDidFinishLaunching` (line 382, before
`TamperGuard`/`startUnlockTrigger`) — both precede every side effect in §1
except argv inspection. A check there runs before any Keychain/model/socket/XPC
work. Recorded as the location only; no singleton behaviour implemented here.

**KeepAlive restart-loop constraint:** with the legacy plist's `KeepAlive=true`,
terminating the launchd-owned primary causes launchd to relaunch it; past
history (`AppActivation` comment lines 159-162; `LoginItem.swift:7-14`;
`CONTRIBUTING.md:119`) shows `KeepAlive` + unconditional `activate()` made a
focus-stealing unquittable loop. So any "close the extra" action must identify
the non-primary PID first — killing the primary re-creates it, and a guard
that unconditionally exits would kill-then-relaunch-loop the agent while
leaving the manual `--settings` copy running.

**Routing a user back to the primary without a new channel:** the existing
in-process callbacks already do the right thing once the user is in the primary
process — `AppActivation.openSettings` (line 489: `bringToFront(userInitiated:
true)` + `openWindow(id: "settings")`), `applicationShouldHandleReopen` (line
374), and the menu `Settings…` button. A second process that detects the
primary only needs to activate it (e.g. via `NSWorkspace`, the same mechanism
`BrowserAppLocator.open` already uses to reuse a running instance) and exit
before Phase A side effects — no unlock-triggering broadcast, no use of
`com.gazeunlock.Gaze.state`.
