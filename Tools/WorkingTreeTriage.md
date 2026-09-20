# Working-tree triage: untracked `Sources/` files

Ground truth: `git status --porcelain` in `/Users/owencope/Developer/FaceID` (main checkout).
20 untracked `.swift` files under `Sources/`: the 15 named in the brief plus 5 in
`Sources/Browser/` (`BrowserAppLocator.swift`, `BrowserPeerTrust.swift`,
`BrowserProtocol.swift`, `BrowserSocket.swift`, `GazeBrowserApproval.swift`).
Content here is byte-identical to that checkout (`diff -rq Sources/` shows only `.DS_Store`),
so all `file:line` citations below hold for both copies. `ThirdParty/` references nothing below.

## Verdict

No — a clean clone of the committed tree does not compile. Unmodified tracked files
already reference symbols that exist only in untracked files (e.g. `GazeApp.swift:303`
names `GazeBrowserApproval`, `LockWatcher.swift:360` names `UnlockFrameEvaluator`,
`CameraController.swift:59` names `CameraEvidenceContinuity`), so HEAD is missing
declarations it uses. The face-unlock path is additionally non-functional without the
untracked security helpers (see Refactor trace).

**Most serious finding:** unlock logic now lives partly in untracked files.
`LockWatcher.swift:305,313` (tracked, unmodified) calls `LockedConsoleSession.current()`
from untracked `LockScreenPasswordSubmission.swift`, and `LockWatcher.swift:194,315,692`
gates scanning/submission on untracked `UnlockExecutionPolicy`. Committing `LockWatcher`
without those files breaks the build; cloning without them removes the unlock path.

## Must commit

Every file below is referenced by at least one tracked, unmodified file
(HEAD itself is broken without it).

| Path | Primary declared symbol | Referenced by (tracked, unmodified) |
|---|---|---|
| `Sources/App/GazeBrand.swift` | `GazeBrand` | `Sources/App/GazeApp.swift:538` (`GazeBrand.menuBarIcon`) |
| `Sources/App/ReleaseURLPolicy.swift` | `ReleaseURLPolicy`, `ReleaseFeedRedirectPolicy` | `Sources/App/ReleaseUpdateChecker.swift:20` (`ReleaseURLPolicy.feed`) |
| `Sources/Camera/CameraEvidenceContinuity.swift` | `CameraEvidenceContinuity` | `Sources/Camera/CameraController.swift:59` (`evidenceContinuity = CameraEvidenceContinuity()`) |
| `Sources/Camera/CameraFrameLease.swift` | `CameraFrameLease` | `Sources/Camera/CameraController.swift:84` (`lease = CameraFrameLease()`) |
| `Sources/Camera/CameraSessionGate.swift` | `CameraSessionGate` | `Sources/Camera/CameraController.swift:87` (`sessionGate: CameraSessionGate`) |
| `Sources/Companion/GazeCompanionShader.swift` | `GazeCompanionShader` | `Sources/Companion/GazeCompanionRenderer.swift:48` (`GazeCompanionShader.source`) |
| `Sources/LockScreen/NotchPreviewCanvas.swift` | `NotchPreviewCanvas` | `Sources/App/NotchSettings.swift:169` (`NotchPreviewCanvas(model:…)`) |
| `Sources/Recognition/RecognitionFrameGate.swift` | `RecognitionFrameGate`, `RecognitionMatchHold`, `RecognitionRejectionHold` | `Sources/Security/LockWatcher.swift:358` (`RecognitionFrameGate()`) |
| `Sources/Recognition/UnlockFrameEvaluator.swift` | `UnlockFrameEvaluator` | `Sources/Security/LockWatcher.swift:360` (`UnlockFrameEvaluator(embedder:faces:antiSpoof:)`) |
| `Sources/Security/AutofillSecurity.swift` | `AutofillConsoleSession`, `AutofillSessionLease` (+ `AutofillAttemptBudget`, `AutofillOwnerApproval`, `AutofillReleaseGate`) | `Sources/Security/LockWatcher.swift:95` (`AutofillConsoleSession.current()`); `Sources/Security/PresenceWatcher.swift:63` (`AutofillSessionLease()`) |
| `Sources/Security/LockScreenInputGuard.swift` | `LockScreenInputSnapshot`, `LockScreenInputGuard` | `Sources/Security/LockWatcher.swift:228` (`LockScreenInputSnapshot.current()`) |
| `Sources/Security/LockScreenPasswordSubmission.swift` | `PasswordReplaySafety`, `LockedConsoleSession`, `LockScreenSubmissionBudget`, `LockScreenPasswordSubmission` | `Sources/Security/LockWatcher.swift:305` (`LockedConsoleSession.current()`); `Sources/App/GazeApp.swift:408` (`PasswordReplaySafety.isEnabled`) |
| `Sources/Security/UnlockExecutionPolicy.swift` | `UnlockExecutionPolicy` | `Sources/App/GazeApp.swift:285` (`UnlockExecutionPolicy.current`) |
| `Sources/Setup/OnboardingHistory.swift` | `OnboardingHistory` | `Sources/App/GazeApp.swift:63` (`OnboardingHistory.markPresented()`) |
| `Sources/Setup/SetupSessionWork.swift` | `SetupSessionWork` | `Sources/Setup/SetupFlow.swift:60` (`work = SetupSessionWork()`) |
| `Sources/Browser/GazeBrowserApproval.swift` | `GazeBrowserApproval` | `Sources/App/GazeApp.swift:303` (`browserApprovals: GazeBrowserApproval?`) |

Coupling note: several of these are *also* referenced from added (`+`) hunks of
modified tracked files — `FaceCheck.swift:53,54`, `AutofillService.swift:11,143,160,167`,
`AutofillWatcher.swift:88,111`, `BiometricGate.swift:57`,
`UnlockBackend.swift:120,143,145,147,148` are all new references, not pre-existing ones.
The table cites unmodified files only, so each row holds against HEAD, not just the
working tree.

Stage precisely these (plus the cluster below — one invocation, not executed):

```sh
git add Sources/App/GazeBrand.swift Sources/App/ReleaseURLPolicy.swift Sources/Camera/CameraEvidenceContinuity.swift Sources/Camera/CameraFrameLease.swift Sources/Camera/CameraSessionGate.swift Sources/Companion/GazeCompanionShader.swift Sources/LockScreen/NotchPreviewCanvas.swift Sources/Recognition/RecognitionFrameGate.swift Sources/Recognition/UnlockFrameEvaluator.swift Sources/Security/AutofillSecurity.swift Sources/Security/LockScreenInputGuard.swift Sources/Security/LockScreenPasswordSubmission.swift Sources/Security/UnlockExecutionPolicy.swift Sources/Setup/OnboardingHistory.swift Sources/Setup/SetupSessionWork.swift Sources/Browser/GazeBrowserApproval.swift Sources/Browser/BrowserSocket.swift Sources/Browser/BrowserProtocol.swift Sources/Browser/BrowserPeerTrust.swift
```

(`Sources/Browser/BrowserAppLocator.swift` deliberately excluded — see Inert.)

## Inert

One file: `Sources/Browser/BrowserAppLocator.swift` (declares `BrowserAppLocator`,
`open(identifier:name:arguments:preferredURL:)` and `socketPath(_:)`). Establishing greps,
both over `Sources/` and `ThirdParty/`, quoted as required:

- `"BrowserAppLocator"` in `Sources/` → only its own declaration (`BrowserAppLocator.swift:3`); no call site anywhere.
- `"BrowserAppLocator|BrowserPeerTrust|BrowserBridgeError|BrowserOrigin|BrowserMessage|BrowserRequestLease|BrowserSocket|BrowserSocketListener|GazeBrowserApproval"` in `Sources/` → outside `Sources/Browser/`, the only hit is `GazeApp.swift:303,358` (`GazeBrowserApproval`).
- Same three symbol groups in `ThirdParty/` → zero hits each.

Owner decision: commit it (dead code, kept for a planned caller) or delete it. Deleting
changes nothing that compiles today. Not checked: `Tools/`, `Plugin/` (out of scope).

## Clusters

`GazeBrowserApproval.swift` (REQUIRED, see above) cannot compile alone. Three untracked
files are referenced only by untracked files, and must be committed with it:

- `Sources/Browser/BrowserSocket.swift` (`BrowserSocket`, `BrowserSocketListener`) ←
  `GazeBrowserApproval.swift:9` (`listener: BrowserSocketListener?`),
  `GazeBrowserApproval.swift:18` (`BrowserSocketListener(name:peer:handler:)`).
- `Sources/Browser/BrowserProtocol.swift` (`BrowserBridgeError`, `BrowserOrigin`,
  `BrowserMessage`, `BrowserRequestLease`) ← `GazeBrowserApproval.swift:25,47` and
  throughout that file; also used by `BrowserSocket.swift:42,51,69` and
  `BrowserAppLocator.swift:8`, `BrowserPeerTrust.swift` (all untracked).
- `Sources/Browser/BrowserPeerTrust.swift` (`BrowserPeerTrust`) ←
  `BrowserSocket.swift:31` (`BrowserPeerTrust.verify(socket:identifier:)`),
  `BrowserAppLocator.swift:7` (`BrowserPeerTrust.verifyApplication`).

Committing `GazeBrowserApproval.swift` without these three breaks the build; the three
without it are dead. The `git add` above includes all four.

## Refactor trace

`git diff -- Sources/Security/UnlockService.swift`: the removed code went **nowhere** —
it was deleted, not moved. HEAD's `UnlockService` answered the PAM plugin over XPC
(`Verdict` enum, `accept`/`handle`/`authenticate`, `NotchCapsuleController` feedback,
liveness check, `successDwell`/`minimumScanTime`/`searchTimeout`). The working-tree
version is a stub: `init(store _:lockout _:)` takes and ignores its dependencies and
every request gets `verdict 3` (`unavailable`), logging
"Face-only XPC authorization is disabled; requests return unavailable."

- No file in `Sources/` declares `Verdict` anymore except the unrelated
  `PresenceAbsenceGate.Verdict` (`PresenceAbsenceGate.swift:54`); nothing calls
  `authenticate`. No dangling references — the stub compiles standalone.
- The live unlock path is now: `LockWatcher` (tracked) → `UnlockBackend`
  (tracked, modified) → untracked `LockScreenPasswordSubmission.submit`
  (`UnlockBackend.swift:145`), guarded by untracked `UnlockExecutionPolicy`
  (`LockWatcher.swift:194,212,315,692`) and untracked `PasswordReplaySafety`
  (`UnlockBackend.swift:120,143`), with untracked `LockScreenInputGuard` /
  `LockScreenSubmissionBudget` enforcing single-submission and no-interruption
  (`LockWatcher.swift:34,300,310`).
- The `Plugin/pam_gaze.c` (-232), `Plugin/install-pam.sh` (-189),
  `Plugin/install.sh` (-158) deletions are the plugin-side counterpart of the same
  change: the face-only XPC verdict path is disabled end to end.

## Unanswered

- Whether `Sources/Browser/BrowserAppLocator.swift` has a planned caller (nothing in
  `Sources/`/`ThirdParty/` uses it; `Tools/` and `Plugin/` were not searched).
- Whether the disabled face-only XPC path (`UnlockService` stub + PAM C deletions) is
  intended to ship in the upcoming commit or is mid-migration to the keystroke path.
- `PresenceAbsenceGate.swift:24` mentions `CameraEvidenceContinuity` in a comment
  ("Why this does not reuse…") — documentation only, not a dependency; cited here so
  the grep hit is not mistaken for one.

## Modified tracked files

`git diff --stat`: 31 files, +964/−1437. The shape is deliberate refactor, not accident:
`UpdateChecker.swift` (-212) gutted with logic evidently moved to the pre-existing
tracked `ReleaseUpdateChecker.swift` plus untracked `ReleaseURLPolicy.swift`;
`UnlockService.swift` (-178/+37) stubbed as traced above; `SetupRequest.swift` (-80),
`AutofillWatcher.swift` (-53) slimmed; `SavedApp.swift` (+212/−) rewritten. Added lines
contain no TODO/FIXME/XXX/HACK/NSLog/print; the single `as!` in added context
(`AutofillService.swift`, focused-element helper) is pre-existing code that gained a
`CFGetTypeID(focused) == AXUIElementGetTypeID()` guard — hardening, not a new force-cast.
`NOT-FOUND-REPORT.md` (5 lines) deleted. Nothing looks unfinished, but the owner should
confirm the disabled XPC/PAM path is intentional before committing it together with the
rest — that stub is the one change that alters shipped behavior rather than moving code.
