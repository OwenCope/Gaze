# Gaze app readiness regressions

Run `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash Tools/AppReadinessRegression/run.sh`.

The runner copies the current production `ReleaseUpdateChecker.swift`,
`ReleaseURLPolicy.swift`, and `DesktopWallpaper.swift` into a temporary Swift package.
Swift Testing compiles those files in Swift 6 mode. The only UI stand-in is
`Theme.background`; no wallpaper singleton or app lifecycle is started.

Coverage:

- Stable, prerelease, and build-metadata precedence; short versions and v prefixes;
  invalid tags and numeric components larger than Int.
- Overlapping manual/scheduled checks with delayed HTTP success/failure; only
  completed successful checks advance the daily schedule. Malformed versions keep
  the check retryable and show an error instead of claiming the app is up to date.
- Wallpaper request coalescing, stale completion rejection, cached-image return,
  retry cooldowns, and reset invalidation.

All HTTP is intercepted by a test URLProtocol. Preferences use a temporary suite
removed after each case. No camera, enrollment, credentials, live update server,
wallpaper file, or running Gaze process is accessed. These tests do not establish
live recognition accuracy, Liquid Glass appearance, or public distribution readiness.

The separate `Tools/ReleaseRegression/run.sh` checks packaging and release gates,
including a synthetic source archive with legacy weights deliberately marked as tracked.
