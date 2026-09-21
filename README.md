# Gaze for macOS

Unlock your Mac by looking at it. Built as an alternative to
[Sapphire](https://github.com/cshariq/Sapphire)'s Gaze feature — its approach informed
this one, but no code was copied (it is GPL-3.0; see *Licensing* below).

## Install

**Development build, not a release recommendation.** Real lock-screen unlocking,
recognition/PAD evaluation, redistribution evidence and clean-install testing are
still release gates.

```sh
git clone https://github.com/OwenCope/Gaze.git
cd Gaze
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer ./build.sh
open "build/Gaze.app"
```


Requires the macOS 26 SDK and a valid stable signing identity. No Xcode project —
`build.sh` drives `swiftc` and assembles the bundle by hand. `DIST=1` requires a
Developer ID Application identity; it no longer produces ad-hoc distribution builds.

**The recognition model is not in this repository.** Its redistribution rights are
unresolved (see `NOTICE.md`), so it is not published here. A clone still builds and
runs: `build.sh` reports `no FaceEmbedding model — using landmark-geometry fallback`
and the app works end to end. Recognition is materially weaker on that path, and it is
explicitly not an approved substitute for unlocking a Mac — treat a fallback build as
a development build, not as Gaze. Supply your own `Resources/FaceEmbedding.mlpackage`
(or a prebuilt `Resources/FaceEmbedding.mlmodelc`) to get the real one.

---

## What it does

After explicit setup and consent, Gaze attempts face verification and two movement
challenges when the screen locks. Its notch companion guides the movements. Only
complete, current verification can authorize password submission; macOS must then
confirm an actual unlock. A stalled camera or failed check must leave manual
authentication available, not trigger password retries.

Historical scores from individual users are not a validation study. Current
lock-screen reliability and false-accept/PAD performance still need independent
release evaluation.

---

## How it fits together

The working folder is organized as follows:

| Location | Contents |
| --- | --- |
| `Sources/`, `Resources/`, `Plugin/` | App code, bundled resources and authentication plugin |
| `Tools/` | Preview app, release signing and model-clearance tooling |
| `build/Gaze.app` | Normal local app build |
| `build/release/Gaze.app` | Distribution build (`DIST=1`), separate from the local app |
| `script/`, `scripts/` | App launcher and model/icon generation scripts |

```
screen locks
   └─ LockWatcher              notices the lock, opens the camera
        ├─ CameraController    AVCapture + Vision → FaceSample (landmarks, pose, quality)
        ├─ UnlockFrameEvaluator evaluates identity and configured anti-spoof off the main actor
        ├─ NotchCapsule        the panel, in a SkyLight space above the lock screen
        └─ KeystrokeUnlock     types the stored password into the login window
```

| Directory | What lives there |
| --- | --- |
| `Sources/Camera` | Capture session, device trust, Vision pipeline |
| `Sources/Recognition` | Embedders, face alignment, enrolment records, liveness |
| `Sources/Enrollment` | Coverage-ring setup UI and the recognition test screen |
| `Sources/Security` | Vault, lockout, unlock backends, Touch ID, tamper guard |
| `Sources/LockScreen` | The notch panel and the SkyLight space that hosts it |
| `Sources/App` | App entry, settings, design tokens |

Two sources do not ship in this app. `Sources/Autofill/` and
`Sources/App/AutofillSettings.swift` belong to the Gaze Passwords direction;
`Tools/MainAppSources.sh` excludes them from the Gaze build, and they are kept
here for shared code and a future migration.

### Unlocking

The app watches for the screen lock, recognises you, and types your stored password into
the login window. Touch ID keeps working, and the login window is Apple's own — so if
recognition fails, manual authentication remains the intended fallback. Release
still needs testing of that fallback through cancellation, failures, and updates.

Your password is stored on this Mac in a form Gaze can recover. Face verification controls
when Gaze chooses to use it; it is not a cryptographic factor required to decrypt it.
See `SECURITY.md` for the storage and local-code-execution threat model.

### Three decisions worth knowing

**Recognition is a neural model, not geometry.** The geometry version *looked* fine and was
useless: cosine similarity on raw landmark coordinates scored a different person at 1.000,
because the shared face template dominates the vector. Switching to Euclidean distance
fixed that but it still collapsed from 0.77 to 0.33 when the head tilted. Pose invariance
has to be learned.

**Camera pinning and movement verification are required for unlocking.** Anti-spoof models score *capture*
artefacts such as print edges and visible devices, but those signals do not guarantee
rejection of a photo or replay. `CameraDevice` restricts unlock capture to the enrolled
built-in camera. Pinning, identity checks, movement verification and the configured
photo detector are distinct checks; their combined resistance still needs evaluation.

**The lock-screen panel uses private SkyLight SPI.** Window level is irrelevant — every
level fails, including above `CGShieldingWindowLevel`. The lock screen is a separate
*space*, so the panel gets its own space pinned to absolute level 400. Unsupported, and
the unlock loop requires the guidance panel to be available. If the private APIs
break, password submission is refused and the user must unlock manually.

---

## Where to start

1. `./build.sh && open "build/Gaze.app"` — it opens setup on first run
2. Enrol, then menu bar → **Test Recognition** to see live scores
3. Read `Sources/Security/LockWatcher.swift` — the whole unlock flow is one file

The standalone preview in `Tools/GazePreview/` stages the lock-screen panel
without locking, which makes iterating on it much faster.

---

## Current state

**Implemented, not a shipping sign-off:** enrollment, recognition, protected storage,
lockout, camera pinning, lock/wake handling, guarded password submission, notch UI,
Touch ID for in-app changes and login item.

**Unverified release gates:** actual lock-screen unlock/fallback reliability,
independent recognition/PAD evidence, model/asset distribution permissions,
Developer ID/notarization and clean installation/update. The earlier rejected-password
report is not resolved merely because the synthetic tests or build pass.

---

## Licensing

The face model is described historically as Sapphire's `ModernFace`, but the
repository's license records are inconsistent. Owner-reported permission must be
documented for the exact bundled model and intended distribution. Do not infer a
model's redistribution rights from the source repository's license alone.
That permission is still an open gate, alongside other model and asset
permissions. Changing the embedding model requires compatible enrollment handling
and a new recognition evaluation; it is not a packaging-only replacement.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for build details and a list of the mistakes that
cost the most time.
