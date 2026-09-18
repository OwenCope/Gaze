# Settings-launch handoff regression

Starting the same installed Gaze executable with `--settings` while its `--agent`
was running used to start a second full service stack before showing Settings.
`Sources/App/SettingsLaunchHandoff.swift` fixes the foreground case narrowly: an
eligible launch (bare argv, or exactly `--settings`) whose bundle is already
running activates that instance, reopens its bundle through the normal
`NSWorkspace.shared.open(bundleURL)` reuse path, and exits before any service
starts. Every flagged invocation (`--agent`, `--setup`, `--setup-step`,
`--ui-review`, `--scan-only`, `--browser-only`, anything else) bypasses unchanged.

```sh
bash Tools/SettingsLaunchRegression/run.sh
```

The runner compiles the **production** handoff file into a synthetic AppKit bundle
(`com.gazeunlock.Gaze.SettingsLaunchHandoffTest`, `LSUIElement`), runs a pure-function
self-test (eligibility matrix + no-existing-instance redirect), then a two-process
test: first fixture instance writes a per-PID service marker, the same executable
relaunch with `--settings` must exit 0 with no service marker of its own while the
first records `applicationShouldHandleReopen`.

Scope is same-bundle foreground/settings launches only — not race-free global
singleton election, and not differently located app copies (a candidate must match
both the resolved executable URL and bundle URL). Background (`--agent`) launches
never take the handoff exit, so no KeepAlive loop. All bundle, marker, and log
files live under a fresh `mktemp` directory; only fixture PIDs are ever signalled,
and only after `ps` confirms the executable path. Production Gaze, its LaunchAgent,
camera, credentials, real defaults, and services are never touched.
