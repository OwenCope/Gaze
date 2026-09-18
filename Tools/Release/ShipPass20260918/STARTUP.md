# Gaze startup and resource use — measured 2026-09-18 (CST, UTC+8)

Scope: fresh evidence only. No process was launched, quit, restarted, or
signalled. No source edited, nothing built, camera never activated, screen
never locked, no credentials entered. Skill read:
`/Users/owencope/.codex/skills/no-agent-messaging/SKILL.md`. No
build-run-debug skill exists under `~/.codex/skills/` or the worktree
`.agents/skills/` (checked 2026-09-18); that lookup is recorded as unavailable.

## 1. Running process identity

One Gaze process, found with `pgrep -fl "Gaze.app"`:

| Fact | Value |
| --- | --- |
| PID / args | 1158, `--agent` (menu-bar watcher) |
| Executable | `/Users/owencope/Developer/FaceID/build/Gaze.app/Contents/MacOS/Gaze` |
| Executable mtime | 2026-09-17T17:16:56+0800, 4849248 bytes |
| SHA-256 | `84c1015c041ddea1c570c218f9f333773169695f9b7e04b1b68e6907201871b5` |
| Launch time | 2026-09-17 19:31:59 +0800 (from `/usr/bin/sample` report header) |
| macOS | 27.0, build 26A5425a (`sw_vers`) |
| Architecture | arm64 (`uname -m`) |
| Free disk (/) | 29 Gi available of 228 Gi (`df -h /`, 2026-09-18 08:47) |

Note: the binary lives in the owner's `/Users/owencope/Developer/FaceID`
checkout, not in this worktree. Source symbols below are mapped against this
worktree's files as they are; no freshness comparison between the two
checkouts was performed.

## 2. Runtime observations (PID 1158)

Five `ps` observations ~2 s apart, 2026-09-18 08:46–08:47 CST:

| # | %CPU | RSS (KiB) | Elapsed |
| --- | --- | --- | --- |
| 1 | 0.0 | 26432 | 13:14:52 |
| 2 | 0.0 | 26432 | 13:14:54 |
| 3 | 0.0 | 24512 | 13:14:56 |
| 4 | 0.0 | 24512 | 13:14:58 |
| 5 | 0.0 | 24544 | 13:15:00 |

One 5-second `/usr/bin/sample` (4298 samples, 1 ms interval) written to the
temporary artifact `/tmp/GazeSampleAda5.txt` (kept outside the repo; dominant
stacks summarized here, no private data copied):

- Main thread (4298/4298 samples): idle in `NSApplication run` →
  `__CFRunLoopRun` → `mach_msg`. The only Gaze code on the main thread was a
  5-sample timer firing: `AppDelegate.startInvisibleWindowSweep()` →
  `AppDelegate.clearInvisibleWindows()` → `SLWindowListCopyWindowInfo`
  (SkyLight). I.e. the 1-second invisible-window sweep fires as designed and
  each firing reaches the window server.
- Six `ANEServicesThread` threads and `com.apple.NSEventThread`: all parked in
  `mach_msg` (idle, 4298 samples each).
- Remaining worker threads: parked in `__workq_kernreturn`.
- Physical footprint 172.6M, peak 466.6M (sample header).
- Sort-by-top: `mach_msg2_trap` 34383, `__workq_kernreturn` 11529 — an idle
  agent, not a busy one, at sample time.

GPU load was **not measured**. No GPU inference is drawn from the CPU numbers
above.

## 3. Startup operation map (source, this worktree)

Anchors read: `GazeApp.init` (`Sources/App/GazeApp.swift:15`), `AppServices`
stored properties (`GazeApp.swift:190-211`), `AppServices.startUnlockTrigger`
(`GazeApp.swift:258`), `AppDelegate.applicationDidFinishLaunching`
(`GazeApp.swift:341`). `CHALLENGE-INVESTIGATION.md` was read before touching
any unlock-loop source. Only synchronous initializers directly reached from
those anchors are listed. All of this runs on the main actor / main thread
unless noted.

| # | Operation (exact symbol) | Executor | Disk I/O | Keychain | Model load | Window |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `GazeApp.init` → `AppServices.shared.store.isEnrolled`, `OnboardingHistory.markPresented()` / `presentsSetup(isEnrolled:arguments:)` (`Sources/Setup/OnboardingHistory.swift:6-19`), `AppActivation.isBackgroundLaunch` | Main thread (SwiftUI App init) | UserDefaults read + one write (`gaze.onboarding.hasBeenPresented`) | Indirect via #2 | Indirect via #2 | None |
| 2 | `AppServices.shared` init → `FaceEnrollmentStore()` → `init()` → `load()` (`Sources/Recognition/FaceEnrollment.swift:140-173`) → `SecureVault.load` (`Sources/Security/SecureVault.swift:91`) → `Keychain.load` + Secure Enclave key agreement + AES-GCM open + JSON decode; fallback tries list shape then single shape, each a Keychain read | Main actor, synchronous | No (Keychain, not file) | **Yes, up to 3 reads** (list, single, single-after-failure) | Indirect via #3 | None |
| 3 | `FaceEnrollmentStore.embedder` → `Embedders.best()` → `CoreMLEmbedder()` (`Sources/Recognition/FaceEmbedder.swift:65-67,195-216`) → `MLModel(contentsOf:)` for `FaceEmbedding.mlmodelc` | Main actor, synchronous, inside #2 | **Yes** (model file read) | No | **Yes** | None |
| 4 | `AppServices.lockout` → `LockoutManager.init` → `load()` (`Sources/Security/LockoutManager.swift:43-62`) → `SecureVault.load(State.self, from: "lockout-state")` | Main actor, synchronous | No | **Yes** | No | None |
| 5 | `AppServices.executionPolicy` → `UnlockExecutionPolicy.current` (`Sources/Security/UnlockExecutionPolicy.swift:9`) | Main thread | No | No | No | None |
| 6 | `Preferences.shared` first touch → `init(defaults:)` (`Sources/App/Preferences.swift:318-348`): ~15 UserDefaults reads. First touched at startup from `TamperGuard.start` (`tamperProtection`) or `startUnlockTrigger` (`walkAwayLock`, `unlockBackend`) | Main actor, synchronous | **Yes** (plist-backed, cached by system) | No | No | None |
| 7 | `TamperGuard.shared.start()` (`Sources/Security/TamperGuard.swift:27`): UserDefaults-gated; `watchBundle()` (DispatchSourceFileSystemObject on own bundle) only if enabled | Main actor | No | No | No | None (no auth prompt at startup) |
| 8 | `startUnlockTrigger` → `syncPresenceWatcher()`: `PresenceWatcher(store:)` + `start()` (`Sources/Security/PresenceWatcher.swift:30-46`) spawns a 5 s tick `Task`; no camera until idle+absence proven | Main actor | No | No | No | None |
| 9 | `startUnlockTrigger` → `GazeBrowserApproval(store:lockout:)` + `start()` (`Sources/Browser/GazeBrowserApproval.swift:13-23`): binds `BrowserSocketListener(name: "gaze.sock", …)`; models/panels/camera only on request | Main actor | No (Unix socket bind) | No | No | None |
| 10 | `startUnlockTrigger` → `LockScreenSpace.shared` → `setUp()` (`Sources/LockScreen/LockScreenSpace.swift:48-80`): `dlopen` SkyLight + 6 `dlsym` + `SLSMainConnectionID` / `SLSSpaceCreate` window-server roundtrip | Main actor, synchronous | No | No | No | None (space only, no window) |
| 11 | `startUnlockTrigger` → `UnlockService(store:lockout:)` + `start()` (`Sources/Security/UnlockService.swift:12-37`): creates/resumes idle XPC mach-service listener `com.gazeunlock.Gaze.unlock` | Main actor (listener queue for events) | No | No | No | None |
| 12 | `startUnlockTrigger` → `LockWatcher(store:lockout:)` + `start()` (`Sources/Security/LockWatcher.swift:88-110`): init stores refs and builds `NotchCapsuleController()` (field init only — `Sources/LockScreen/NotchCapsuleController.swift:26-42`, no window until `show()`); `start()` registers `com.apple.screenIsLocked` / wake observers on `DistributedNotificationCenter` | Main actor | No | No | No | None |
| 13 | `ReleaseUpdateChecker.shared.startScheduledChecks()` (`Sources/App/ReleaseUpdateChecker.swift:83-93`): UserDefaults read; first check deferred 8 s via `Task.sleep`, then hourly `Timer`; **no network at startup instant** | Main actor | UserDefaults read | No | No | None |
| 14 | `AppDelegate.startInvisibleWindowSweep()` (`GazeApp.swift:373-387`) → `clearInvisibleWindows()` (`GazeApp.swift:402-422`): immediate `CGWindowListCopyWindowInfo` window-server query + repeating 1.0 s `Timer` on `RunLoop.main` common modes for process lifetime | Main thread, synchronous, then every second forever | No | No | No | None (mutates `ignoresMouseEvents` only) |
| 15 | Window creation on `--agent` launch: none. Settings/enrollment/test/dataset scenes are `.suppressed` (`GazeApp.swift:48,98`); only the `MenuBarExtra(.menu)` exists. `MenuBarContent.menuStatus` reads `AVCaptureDevice.authorizationStatus` (no activation), `PasswordReplaySafety.isEnabled` (UserDefaults read, `Sources/Security/LockScreenPasswordSubmission.swift:9`), backend `readiness()` | Main thread | UserDefaults reads | Not traced (readiness internals not followed) | No | Menu-bar menu only |

Bundled-model confirmation (running app, read-only `ls`): the running
bundle's `Contents/Resources/` contains compiled `FaceEmbedding.mlmodelc` and
`Spoof.mlmodelc`, so path #3 takes the Core ML branch at startup
(`embedder=coreml:112x112:arcface-2.73` in logs corroborates).

## 4. Subsystem logs (`/usr/bin/log`, never the builtin)

- Errors/faults, `subsystem == "com.gazeunlock.Gaze"`, last 24 h: exactly 3,
  all identical lock-loop camera timeouts, no startup/lifecycle errors:
  - 2026-09-17 23:40:59, PID 1158 — `Camera timed out at first frame; analyzed=0 expired=0. No password submitted.`
  - 2026-09-18 07:02:38, PID 1158 — same text.
  - 2026-09-18 07:50:47, PID 1158 — same text.
- Startup categories (`TamperGuard`, `Releases`, `Enrollment`, `Windows`,
  `UnlockService`, `BrowserApproval`, `Presence`) over the last 2 d: **no
  entries** — no `Tamper protection active`, no release-check outcome, no
  `Enrolment failed to open`, no `Made an invisible window click-through`.
  (Absence of evidence, not evidence of absence: `notice`-level persistence
  and the `tamperProtection` setting were not independently verified.)
- Routine lock-loop evidence (sanitized config, no biometric/credential data):
  every search logs `embedder=coreml:112x112:arcface-2.73 threshold=0.450000
  faces=1`; first fresh camera frame typically ready ~500–650 ms after wake
  (2728 ms once, at 2026-09-17 23:41:11).

## 5. Unavailable measurements

- **Launch duration cannot be measured without restarting the owner's process**
  (PID 1158 has been up since 2026-09-17 19:31:59; relaunching it to time
  startup is explicitly out of scope). Stated explicitly per brief.
- No per-phase startup timing exists in the code (no startup timestamps are
  logged between `GazeApp.init` and `applicationDidFinishLaunching`).
- GPU load not measured; no GPU conclusion is offered.
- Cold-start (post-reboot, uncached Keychain/model pages) vs warm-start not
  distinguished — the observed process is long past launch.

## 6. Bottlenecks (at most three, evidence-supported)

1. **Synchronous Core ML model load on the main actor during launch.**
   `AppServices.shared` → `FaceEnrollmentStore.init` → `Embedders.best()` →
   `CoreMLEmbedder.init()` → `MLModel(contentsOf:)` reads and maps the full
   embedding model before `applicationDidFinishLaunching` runs anything. The
   sample's 466.6M peak footprint is consistent with model pages entering at
   launch. Deferring this off the main actor (or lazily to first use) removes
   file I/O plus model compilation from the critical launch path.
2. **Serial Keychain + Secure Enclave roundtrips on the main actor at launch.**
   `FaceEnrollmentStore.load()` performs up to three `SecureVault.load`
   calls (list shape, single shape, single-after-failure), each doing a
   Keychain read plus an Enclave key agreement and AES-GCM open; then
   `LockoutManager.init` adds a fourth (`lockout-state`). Each is an IPC
   stall on the launch path with no concurrency.
3. **A perpetual per-second window-server query.** `AppDelegate`
   `.startInvisibleWindowSweep()` fires `CGWindowListCopyWindowInfo` every
   second for the life of the process; the 5-second sample caught it firing
   on the main thread (5/4298 samples reaching SkyLight). Individually cheap,
   but it is the only Gaze code observed running on the main thread at idle
   and it never backs off.

## 7. Exact symbols for a proposed next patch

A startup-only patch (no recognition-behavior change) would touch, in order
of §6: `CoreMLEmbedder.init()` (`Sources/Recognition/FaceEmbedder.swift:195`)
and its call site `Embedders.best()` (`FaceEmbedder.swift:65`) to load
asynchronously off the main actor; `FaceEnrollmentStore.init`/`load()`
(`Sources/Recognition/FaceEnrollment.swift:140-173`) and
`LockoutManager.init`/`load()` (`Sources/Security/LockoutManager.swift:43-62`)
to coalesce/parallelize the `SecureVault.load` Keychain roundtrips;
`AppDelegate.startInvisibleWindowSweep()`/`clearInvisibleWindows()`
(`Sources/App/GazeApp.swift:373-422`) to back off or stop after steady state;
startup timing anchors `GazeApp.init` (`GazeApp.swift:15`) and
`AppDelegate.applicationDidFinishLaunching` (`GazeApp.swift:341`) to bracket
with log timestamps so the next pass can measure rather than infer. Model
file: `Resources/FaceEmbedding.mlpackage` (compiled to `FaceEmbedding.mlmodelc`
by `build.sh`; distribution rights per `NOTICE.md`).
