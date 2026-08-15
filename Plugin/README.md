# Authorization plugin

Not built yet. This is what it takes, and what it costs.

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
