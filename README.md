# Face ID

Face recognition unlock for macOS. Built as an alternative to [Sapphire](https://github.com/cshariq/Sapphire),
whose approach informed this one but whose code is not used — it is GPL-3.0 and nothing
was copied from it.

Build and run:

```sh
./build.sh && open "build/Face ID.app"
```

Requires the macOS 26 SDK. `build.sh` defaults `DEVELOPER_DIR` to `Xcode-beta.app`.

## What works today

- **Enrolment** — the two-pass ring flow. A live circular preview inside 48 radial ticks
  that fill as you turn your head, driven by Vision's yaw/pitch. Captures one faceprint
  per newly covered direction.
- **Recognition** — a 512-d ArcFace-family embedding, L2-normalised, cosine-matched
  against the enrolled set.

  Worth recording why this is a neural model rather than landmark geometry, because the
  geometry version *looked* like it worked. It scored a different person at 1.000 (cosine
  on raw coordinates is dominated by the shared face template, so every face comes out
  parallel), and after switching to Euclidean distance it still collapsed from 0.77 to
  0.33 when the head tilted up. Pose invariance cannot be computed from a single 2D image
  — it has to be learned. Measured with the bundled model: same person 0.85+ across every
  head angle.
- **Storage** — faceprints and lockout state are AES-GCM sealed under a Secure Enclave
  key. The ciphertext is bound to this Mac; copying the Keychain items elsewhere yields
  nothing.
- **Lockout** — face unlock is refused after 6 consecutive failures until the account
  password is entered. The counter is in the sealed vault, not a plist, and fails closed
  if the record will not open.
- **Camera pinning** — only the built-in camera is trusted, and the exact device is pinned
  at enrolment.
- **Tamper protection** — administrator authentication to quit, plus a watch on the app
  bundle.
- **Touch ID** — guards in-app changes (un-enrolling, editing settings, storing a password).

- **Unlocking** — the screen lock triggers a face search, and on a match the stored
  password is typed into the login window. Working end to end.

## The authorization plugin works

Proven end to end, on a stock SIP-enabled Mac with an ordinary Apple Development
signature:

```
AuthorizationPluginCreate entered — the plugin IS loaded
MechanismInvoke entered
Asking the agent in session uid 501
Recognised (score 0.835686)
Face recognised; allowing unlock
```

115ms, and **no password is stored or typed** — the system authenticates.

Installed but *not* routed: `system.login.screensaver` is still `use-login-window-ui`.
`sudo Plugin/install.sh` switches over, `sudo Plugin/uninstall.sh` reverts, and the single
line that matters for rollback is:

```sh
sudo security authorizationdb write system.login.screensaver use-login-window-ui
```

**Before routing your real lock screen through it, exercise the password fallback.** Every
successful run so far took the face-match path; `buttonPressed:` → PAM has never executed.
That is the path you depend on when your face isn't recognised, and an untested fallback
is worse than none.

### The bugs, none of which were about code signing

The `dlopen` "library validation failed" error in the log is **misleading** — Apple's DTS
engineer confirms the host logs it, clears library validation, then loads the plugin
anyway. Chasing it cost most of a day. The real failures were:

1. `,privileged` on the mechanism — privileged mechanisms run in authd with no window
   server, so a UI mechanism can never work there
2. `dispatch_sync` to the main queue *from* the main queue — instant deadlock, and it
   looks exactly like the plugin never loading
3. Backend left on `keystroke`, so the agent never opened its XPC listener
4. Cross-domain XPC — the agent's mach service lives in `gui/<uid>`; the plugin runs as
   `_securityagent` and needs `xpc_connection_set_target_uid`
5. `PlistBuddy -c "Set :key 'value'"` stripping the quotes from the pinned code
   requirement, making it unparseable so every reply was discarded as untrusted
6. `SetResult` inside a completion block on a nil object — silently dropped, mechanism
   hangs forever

**Log on the success path, not just the failure path.** A plugin that loads silently is
indistinguishable from one that never loaded, and that single missing `os_log` is what
made all six of these look like one unsolvable signing problem.

## Superseded: what I first thought blocked it

It is written, it compiles, and it installs. macOS will not load it:

```
dlopen(/Library/Security/SecurityAgentPlugins/FaceID.bundle/...):
  code signature not valid for use in process:
  mapping process is a platform binary, but mapped file is not
```

The loader is **`SecurityAgentHelper-arm64`**, and it already carries
`com.apple.private.security.clear-library-validation` — the entitlement that exists
specifically so it can load third-party plugins. So library validation is *not* the
blocker.

What rejects the bundle is a separate kernel check: platform-binary status, which comes
from Apple's own signing infrastructure. **No third-party certificate can satisfy it** —
not Apple Development, not Developer ID, not notarized. Paying for the Developer Program
would not help.

This is not specific to this project. OpenAI's Codex team hit the identical error, same
process and same message, on macOS 26.5
([codex#24013](https://github.com/openai/codex/issues/24013)); the issue closed with no
fix and no workaround. Disabling SIP is the only lever anyone has found, which is not a
reasonable trade.

Gatekeeper *allows* the bundle — `AppleSystemPolicy` logs `library, allowed`. The kernel
then refuses to map it. Everything on our side is correct.

The consequence, stated plainly: **there is no lock-screen animation.** The capsule only
renders when SecurityAgent hosts our view, and it will not host it. The login window sits
above ordinary app windows, so the keystroke backend cannot draw there either.

Everything for that path is kept — `Plugin/`, the XPC listener, the installer — in case
Apple changes this. It is not waiting on a certificate or on work; it is waiting on macOS.

**Test with `Plugin/test-plugin.sh`, never by editing the lock screen rule.** It registers
a throwaway right instead, so a plugin that cannot load costs you a failed test rather
than a Mac you cannot log into. That is how the signing wall was found.
- **The bundled model is GPL-3.0.** `Resources/FaceEmbedding.mlpackage` is Sapphire's
  `ModernFace` — an ArcFace-family network taking `[1, 3, 112, 112]` planar RGB and
  returning a 512-d embedding. Fine for personal use, since GPL obligations trigger on
  distribution. **Before publishing this app anywhere, either license it GPL-3.0 or swap
  in an openly-licensed model.** `CoreMLEmbedder` reads the input shape from the model, so
  a replacement of the same family drops straight in.
- **No liveness model ships**, so the anti-spoof toggle is disabled. This is deliberate —
  see below.

## Security notes

**There is no depth camera.** Real Face ID resists spoofing because the TrueDepth
projector builds a depth map. A MacBook Air has a plain RGB sensor, so nothing here can
reproduce that. Treat this as convenience-grade.

**Liveness models do not stop the attack that matters.** MiniFASNet and relatives score
*capture artefacts* — moiré off a phone screen, paper grain, print edges. They catch
someone holding up a photo. They do not catch frame injection: a virtual camera feeding a
recording produces no capture artefacts, and the model calls it genuine. That is why
camera pinning is on by default and liveness is off.

**The two unlock backends are not equally safe.** The authorization plugin has the *system*
perform the unlock and never stores a password. Password replay stores your account
password in recoverable form and types it into the login window. The second keeps Touch ID
working; the first does not, because macOS will not run its modern lock-screen path and
third-party plugins at the same time.

**Tamper protection is tamper evidence, not tamper proofing.** An administrator can delete
this app. SIP protects Apple's software, not ours. What the feature buys is that removal
requires an authentication prompt and leaves a log entry.

It also only covers the *graceful* quit path. `applicationShouldTerminate` is where the
admin prompt lives, and `kill -9` never reaches it — a SIGKILL stops the app with no
prompt at all. Closing that would need a separate watchdog process (a `KeepAlive` launch
agent that relaunches the app), which is not built. Assume any local process running as
you can end this app at will.

## Layout

| Path | What lives there |
| --- | --- |
| `Sources/Camera` | Capture session, device trust, Vision pipeline |
| `Sources/Recognition` | Embedders, alignment, enrolment records, liveness |
| `Sources/Enrollment` | Ring coverage model and setup UI |
| `Sources/Security` | Vault, lockout, unlock backends, Touch ID, tamper guard |
| `Sources/LockScreen` | The animated Face ID mark |
| `Plugin` | Authorization plugin (not yet built) |
