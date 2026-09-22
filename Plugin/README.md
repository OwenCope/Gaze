# Optional authorization integrations: disabled

Face presence alone must not authorize `sudo`. An unrelated process can request sudo
authentication while the owner happens to be looking at the camera. A signed responder and
a fresh nonce do not establish the owner's intent.

The shared legacy authorization service also lacked caller authorization and request
lifecycle controls. It is disabled rather than retained as a second route to a face verdict.
The normal app's keystroke-unlock and recognition paths are separate and remain available.

## Behavior of this checkout

- `pam_gaze.c` always returns `PAM_AUTH_ERR` from authentication. It does not read a trust
  policy, contact XPC, or report an authentication success.
- `UnlockService` retains the service name for compatibility and replies with verdict 3,
  unavailable. It echoes only correctly sized 32-byte nonces and never opens the camera.
- `install-pam.sh` and `install.sh` print an explanation and exit with status 1 before any
  filesystem, launchd, PAM, or authorization-database changes. This also removes their
  privileged installer attack surface from the supported path.
- `build-pam.sh` builds the disabled compatibility module only. Building it does not replace
  an installed copy. The remaining legacy plugin sources are not approved for deployment.

## Existing installations

Nothing in these source changes removes an installed module, unloads a LaunchAgent, stops an
old process, or edits `/etc/pam.d/sudo_local` or the authorization database. An old installed
module and old running app retain their previous behavior and risks.

The plugin pins the agent by code requirement. Refresh the pin after every rebuild of
`/Applications/Gaze.app`: a fresh signature changes the cdhash, so a stale pin discards
every agent reply as untrusted. Once a Developer ID identity exists, pin the team
identifier instead of the cdhash so rebuilds no longer invalidate the pin.

Copying or installing the agent redistributes the bundled `FaceEmbedding` and `Spoof`
models with it; see NOTICE.md for their redistribution status before distributing the app.

An administrator should first identify which integration is installed and confirm an
independent password-based access path. Then review removal of only the Gaze-specific PAM
entry or legacy authorization mechanisms, preserving unrelated local authentication rules.
Use an isolated test account or machine before deploying authentication-policy changes.
Do not run historical installation or cleanup scripts merely because they remain in git.

Under the former `auth sufficient` configuration, an authentication failure is intended to
fall through to subsequent PAM modules. Actual fallback depends on the complete local stack;
it is not a universal guarantee against lockout.

## Conditions for re-enabling

1. Verify kernel-bound caller identity and bind requests to the correct account and session.
2. Require fresh deliberate owner approval bound to trusted request context. Do not treat a
   camera match or an informational overlay as consent.
3. Bound concurrency, payload sizes, deadlines, disconnect handling, and cancellation. A late
   match must never authorize an expired or different request.
4. Review all privileged file operations, including trusted ancestry, ACLs, symlinks,
   exclusive creation, atomic replacement, and safe per-user LaunchAgent handling.
5. Exercise failure and recovery paths in an isolated environment before enabling a PAM
   success path or modifying a live authorization policy.

The historical fixed-path FIFO claim remains unverified as an exploit. Disabling the old
installer is hardening, not retrospective proof of that claim.

## Archived design notes

The material below describes the old design. It is not a deployment guide for this checkout.

## Why this path

It is the only sanctioned way to put our own UI on the lock screen and to have macOS
perform the unlock. The alternative — `KeystrokeUnlockBackend` — stores your password and
types it into the login window, which works but means a recoverable password on disk and
no custom UI at all.

## The cost, up front

`system.login.screensaver` currently reads:

```
$ security authorizationdb read system.login.screensaver
	<key>rule</key>
	<array>
		<string>use-login-window-ui</string>
	</array>
```

`use-login-window-ui` is Apple's modern lock-screen path. It is what provides Touch ID and
Apple Watch unlock, and **it does not load third-party authorization plugins**. Installing
this plugin means rewriting that rule to `authenticate-session-owner-or-admin`, which drops
the lock screen onto the legacy SecurityAgent path.

So: our blue face animation on the lock screen, or Touch ID on the lock screen. Not both.
This is a macOS constraint, not a limitation of the implementation.

To change it (requires admin), and to put it back:

```sh
# Enable third-party plugins on the lock screen
security authorizationdb write system.login.screensaver authenticate-session-owner-or-admin

# Restore Apple's default
security authorizationdb write system.login.screensaver use-login-window-ui
```

Keep the restore command somewhere you can reach it **from another machine or a recovery
session**. A broken plugin in this path can leave a lock screen that will not authenticate.

## What has to be built

1. **The bundle** — an `SFAuthorizationPluginView` subclass in a `.bundle` installed to
   `/Library/Security/SecurityAgentPlugins/Gaze.bundle`. Objective-C; the API predates
   Swift and is not bridged usefully. It supplies an `NSView` that SecurityAgent hosts, so
   `FaceScanView` has to be re-implemented in AppKit/Core Animation, or rendered by the
   agent and passed across as frames.

2. **Two mechanisms** — the plugin registers a UI mechanism and a privileged one. The UI
   mechanism shows the mark; the privileged mechanism decides the authorization result.

3. **An XPC channel to the session agent.** This is the part that needs care.
   SecurityAgent runs as `_securityagent` and will not have camera TCC approval, and there
   is no way to prompt for it at the lock screen. So the plugin cannot open the camera
   itself. Recognition has to keep running in the logged-in user's session — which does
   retain camera access while the screen is locked — and report a verdict across.

4. **A trustworthy verdict.** The channel is the new attack surface: anything that can
   talk to it can assert "the face matched". The listener must verify the peer's code
   signature (`SecCodeCopyGuestWithAttributes` on the audit token), and the verdict should
   be a short-lived nonce issued by the plugin and signed by the agent, not a boolean.

## Testing

Do not iterate on this by locking your screen. Create a second admin account, test there,
and keep an SSH session open from another machine so you can restore the authorization
rule if the lock screen stops accepting input.
