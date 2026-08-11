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

## The authorization plugin — do not install it

`Plugin/` builds a SecurityAgent authorization plugin. It is no longer selectable in the
app, and `install.sh` should not be run: doing so locked a Mac out.

It passed everything — loaded, matched in 115ms, drew its own panel, PAM fallback verified
both ways, `build-paneltest.sh` returned GRANTED. All of that drew the panel over an
ordinary desktop. At a real lock screen SecurityAgent owns the display, our panel never
became usable, and with our mechanism alone in the rule there was nothing behind it.

Before touching it again it needs `mechanisms: [ FaceID:unlock, builtin:authenticate ]`, so
Apple's password prompt is always the backstop, and a second machine to SSH from.

**Test with `Plugin/test-plugin.sh`, never by editing `system.login.screensaver`** — and
know that the throwaway right is a *weaker* test than the real lock screen, not an
equivalent one.

Rollback, worth keeping somewhere reachable from another machine:

```sh
sudo security authorizationdb write system.login.screensaver use-login-window-ui
```

## Things that cost a day, so you don't repeat them

- **The `dlopen` "library validation failed" error is misleading.** The host logs it, then
  clears library validation and loads the plugin anyway. Log on your *success* path — a
  plugin that loads silently is indistinguishable from one that never loaded.
- **`sudo` changes identity, not just permission.** Code signing needs the invoking user's
  login keychain; `launchctl bootstrap gui/<uid>` needs their session. Both fail as root.
- **Never `dispatch_sync` to the main queue from a mechanism.** SecurityAgent invokes them
  on the main thread; it deadlocks instantly and looks like a load failure.
- **`PlistBuddy -c "Set :key 'value'"` strips embedded quotes.** Use `plutil -replace`.
  A mangled code requirement fails to parse and every reply is rejected as untrusted.
- **Landmark geometry cannot do face recognition.** Cosine similarity on raw coordinates
  scored a stranger at 1.000 — the shared face template dominates the vector. Pose
  invariance has to be learned, not computed.
- **Never pair launchd `KeepAlive` with `NSApp.activate()`.** That combination produced a
  process that stole focus every few seconds and could not be quit.
- **A test that cannot fail the way production fails proves very little.** The plugin passed
  a full end-to-end test over an ordinary desktop, then locked the machine out at a real
  lock screen — because SecurityAgent owns the display there and our panel did not. When
  the difference between test and production is the very thing under test, it is a
  rehearsal, not evidence.
