# Working on this

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

## The authorization plugin

`Plugin/` builds a SecurityAgent authorization plugin. It works, on a stock SIP-enabled
Mac with ordinary Development signing.

**Always test with `Plugin/test-plugin.sh`, never by editing `system.login.screensaver`.**
It registers a throwaway right pointing at the same mechanism, so a broken plugin costs
you a failed test instead of a Mac you cannot log into. Our mechanism is the only one in
its rule, so if it fails to resolve there is no password prompt behind it.

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
