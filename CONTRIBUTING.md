# Working on this

## First run on your machine

```sh
git clone https://github.com/OwenCope/FaceID.git
cd FaceID
./build.sh && open "build/Face ID.app"
```

**You need a code-signing identity.** `build.sh` looks for an *Apple Development* or
*Developer ID Application* certificate in your login keychain and falls back to ad-hoc
signing if it finds neither. Ad-hoc works, but the app's code identity changes on every
build, so macOS challenges it for the keychain password each time you rebuild — tedious
within about ten minutes.

A free Apple ID is enough: open Xcode → Settings → Accounts → add your Apple ID → Manage
Certificates → **+** → Apple Development. No paid membership required. Verify with:

```sh
security find-identity -v -p codesigning
```

**Then, in order:**

1. **Camera** — macOS prompts on first launch. Approve it, or nothing works.
2. **Enrol your face** — the app opens setup automatically when nothing is enrolled.
   Turn your head slowly until the ring fills; it does two passes.
3. **Test Recognition** (menu bar) — confirm your score sits well clear of the threshold
   before trusting it. Get someone else to sit in front of it too; that number matters
   more than yours.
4. **Choose what happens when you're recognised**, in Settings. *Password replay* needs your account password
   stored and Accessibility permission (System Settings → Privacy & Security →
   Accessibility). *Don't unlock* is the safe way to try recognition without wiring it to
   anything.
5. **Open at login**, in Settings, once you're happy — it only watches for the lock while
   running.

**Nothing transfers between machines.** Faceprints are sealed with a Secure Enclave key
that never leaves the Mac that made them, so you enrol fresh. Same for the stored password.
There is no account, no sync, and nothing leaves the device.

**If recognition seems broken**, check `Test Recognition` first — a low score means the
model or the lighting, not the unlock path. The unlock path logs everything:

```sh
log stream --predicate 'subsystem == "app.faceid.FaceID"'
```

## Build and run

```sh
./build.sh && open "build/Face ID.app"
```

Needs the macOS 26 SDK. `build.sh` defaults `DEVELOPER_DIR` to `Xcode-beta.app` and signs
with whatever Apple Development identity is in your keychain.

**Sign with a real identity, not ad-hoc.** The Keychain ACL protecting the vault key is
bound to the app's code identity, and an ad-hoc signature is regenerated every build — so
the app becomes a *different* application each time and macOS challenges it for the
keychain password on every rebuild.

## Licensing — read before pushing anywhere public

`Resources/FaceEmbedding.mlpackage` is Sapphire's `ModernFace`, from a **GPL-3.0**
repository. It is tracked here because this repo is private, and GPL obligations trigger
on distribution.

**Before this repo goes public, either:**

- replace the model with an openly-licensed one (`CoreMLEmbedder` reads the input shape
  from the model, so any ArcFace-family `[1, 3, S, S]` → `[1, N]` network drops straight
  in), or
- license the whole project GPL-3.0.

Changing the model invalidates existing enrolments — the identifier is versioned on
purpose, so prints from different feature spaces are never compared.

## Testing recognition

Menu bar → **Test Recognition**. Watch `low` for the enrolled user and `high` for anyone
else. Thresholds mean nothing in the abstract; they are only valid relative to a measured
distribution on real hardware. Current numbers on the author's Mac: enrolled user 0.85+
across head angles, a different adult 0.23, threshold 0.45.

Lock-screen scores run lower than in-app ones — the display is dark, so the face is lit
less. Measure there too before trusting a threshold.

## Things that cost a day, so you don't repeat them

- **Log your success path, not just your failures.** Code that runs silently is
  indistinguishable from code that never ran, and that ambiguity can burn a day.
- **`sudo` changes identity, not just permission.** Code signing needs the invoking user's
  login keychain; `launchctl bootstrap gui/<uid>` needs their session. Both fail as root.
- **`PlistBuddy -c "Set :key 'value'"` strips embedded quotes.** Use `plutil -replace`.
- **Landmark geometry cannot do face recognition.** Cosine similarity on raw coordinates
  scored a stranger at 1.000 — the shared face template dominates the vector. Pose
  invariance has to be learned, not computed.
- **Never pair launchd `KeepAlive` with `NSApp.activate()`.** That combination produced a
  process that stole focus every few seconds and could not be quit.
- **A test that cannot fail the way production fails proves very little.** When the
  difference between the test environment and the real one is the very thing under test,
  passing is a rehearsal, not evidence.

## The unlock animation we want

Reference frames are in the project owner's screenshots (YouTube Short,
2026-08-12). The sequence, four beats:

1. Green Face ID glyph, glowing, on black.
2. The glyph collapses inward and **rotates in 3D** — it reads as a ring seen
   edge-on, tilting toward the viewer as it spins.
3. It settles flat into a plain green circle.
4. A tick draws itself inside the circle.

Everything stays green throughout; there is no white stage. The whole point is
beat 2: the spin is what makes it read as one object transforming, rather than
two icons swapping places, which is what `.symbolEffect(.replace)` gives you and
why the current version feels flat by comparison.

Implementation note: this cannot be done with SF Symbol transitions. It needs a
hand-built shape with `rotation3DEffect` on the X axis, driven by a keyframe
animation, with the glyph's stroke morphing into the ring as it goes.

Current implementation is in `Sources/LockScreen/NotchCapsule.swift`, and
`--preview-capsule` shows it without locking the screen.
