# Face ID for macOS

Unlock your Mac by looking at it. Built as an alternative to
[Sapphire](https://github.com/cshariq/Sapphire)'s Face ID feature — its approach informed
this one, but no code was copied (it is GPL-3.0; see *Licensing* below).

## Install

```sh
git clone https://github.com/OwenCope/FaceID.git

cd FaceID && ./build.sh && open "build/Face ID.app"
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
| `Plugin/` | SecurityAgent authorization plugin (Objective-C) |

### Unlocking

The app watches for the screen lock, recognises you, and types your stored password into
the login window. Touch ID keeps working, and the login window is Apple's own — so if
recognition fails there is always a real password field waiting. That property is what
makes this the shipping path; the plugin section below is what happens without it.

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

1. `./build.sh && open "build/Face ID.app"` — it opens setup on first run
2. Enrol, then menu bar → **Test Recognition** to see live scores
3. Read `Sources/Security/LockWatcher.swift` — the whole unlock flow is one file

`--preview-capsule` shows the lock-screen panel without locking, which makes iterating on
it much faster.

---

## The authorization plugin — do not install it

`Plugin/` builds a SecurityAgent authorization plugin. It is no longer selectable in the
app, because installing it **locked a Mac out** and cost a reboot to recover.

It passed every test available short of the real thing: it loaded on a stock SIP-enabled
Mac with an ordinary Development signature, matched a face in 115ms with no password
stored, drew its own panel, and its PAM password fallback accepted a correct password and
rejected a wrong one. `Plugin/build-paneltest.sh` walked that whole path and returned
GRANTED.

Every one of those tests drew the panel **over an ordinary desktop**. At a real lock screen
SecurityAgent owns the display, our panel never became usable, and because our mechanism
was the only entry in `system.login.screensaver` there was nothing behind it — face
reported success, the password field was unreachable, and Touch ID had been disabled by the
install.

The lesson is not that the plugin is impossible. It is that **the test could not fail the
way production fails**, which made it a rehearsal rather than evidence.

### What it would need

```
mechanisms: [ FaceID:unlock, builtin:authenticate ]
```

With Apple's own password prompt chained behind ours, a failure in our UI costs an extra
prompt instead of the machine. That, plus a second device to SSH from — this cannot be
validated safely from the machine being locked.

If your lock screen is currently routed through it:

```sh
sudo security authorizationdb write system.login.screensaver use-login-window-ui
```

## Current state

**Working:** enrolment, recognition, Secure Enclave storage, 6-attempt lockout, camera
pinning, screen-lock trigger, keystroke unlock, notch panel, Touch ID for in-app changes,
tamper protection, login item.

**Not done:**

- The authorization plugin needs a chained `builtin:authenticate` rule and a second device
  to test from before it is safe to install again. See above.
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
