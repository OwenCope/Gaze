# Gaze for macOS

Unlock your Mac by looking at it. Built as an alternative to
[Sapphire](https://github.com/cshariq/Sapphire)'s Gaze feature — its approach informed
this one, but no code was copied (it is GPL-3.0; see *Licensing* below).

## Install

```sh
git clone https://github.com/OwenCope/Gaze.git

cd Gaze && ./build.sh && open "build/Gaze.app"
```

To create a distributable disk image:

```sh
./package-dmg.sh
open "build/Gaze-0.2.dmg"
```


Requires the macOS 26 SDK. No Xcode project — `build.sh` drives `swiftc` and assembles the
bundle by hand.

---

## What it does

Lock the screen, look at the camera, and it types you in. A panel drops out of the notch
while it looks, morphs to a green tick on success, and retracts.

Measured on the author's Mac: enrolled user **0.85+** across every head angle, a different
adult **0.23**, threshold **0.45**.

---

## How it fits together

```
screen locks
   └─ LockWatcher              notices the lock, opens the camera
        ├─ CameraController    AVCapture + Vision → FaceSample (landmarks, pose, quality)
        ├─ FaceEnrollmentStore embeds the sample, compares to enrolled prints
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

### Unlocking

The app watches for the screen lock, recognises you, and types your stored password into
the login window. Touch ID keeps working, and the login window is Apple's own — so if
recognition fails there is always a real password field waiting. That property is what
makes it safe: a recognition failure costs you a password, never your way in.

The cost is that your password is stored on this Mac in recoverable form. Anything running
as you can extract it.

### Three decisions worth knowing

**Recognition is a neural model, not geometry.** The geometry version *looked* fine and was
useless: cosine similarity on raw landmark coordinates scored a different person at 1.000,
because the shared face template dominates the vector. Switching to Euclidean distance
fixed that but it still collapsed from 0.77 to 0.33 when the head tilted. Pose invariance
has to be learned.

**Liveness is off by default, and camera pinning is on.** Anti-spoof models score *capture*
artefacts — moiré, paper grain, print edges — so they catch a photo held to the lens. They
do nothing against frame injection: a virtual camera feeding a recording has no capture
artefacts at all. `CameraDevice` refuses anything but the built-in camera, which is the
defence that actually matters.

**The lock-screen panel uses private SkyLight SPI.** Window level is irrelevant — every
level fails, including above `CGShieldingWindowLevel`. The lock screen is a separate
*space*, so the panel gets its own space pinned to absolute level 400. Unsupported, and
written so that if it breaks you lose the panel and unlocking still works.

---

## Where to start

1. `./build.sh && open "build/Gaze.app"` — it opens setup on first run
2. Enrol, then menu bar → **Test Recognition** to see live scores
3. Read `Sources/Security/LockWatcher.swift` — the whole unlock flow is one file

`--preview-capsule` shows the lock-screen panel without locking, which makes iterating on
it much faster.

---

## Current state

**Working:** enrolment, recognition, Secure Enclave storage, 6-attempt lockout, camera
pinning, screen-lock trigger, keystroke unlock, notch panel, Touch ID for in-app changes,
tamper protection, login item.

**Not done:**

- The notch panel stacks below DynamicLake Pro's lock icon rather than replacing it.
- Tamper protection only covers graceful quit; `kill -9` bypasses it entirely.
- No liveness model is bundled, so that toggle is disabled.

---

## Licensing

`Resources/FaceEmbedding.mlpackage` is Sapphire's `ModernFace` model, from a **GPL-3.0**
repository. This repo is private, and GPL obligations trigger on distribution.

**Before it goes public**, either replace the model with an openly-licensed one or license
the whole project GPL-3.0. `CoreMLEmbedder` reads the input shape from the model, so any
ArcFace-family `[1, 3, S, S]` → `[1, N]` network drops in — but changing it invalidates
existing enrolments by design.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for build details and a list of the mistakes that
cost the most time.
