# Gaze app readiness — September 17, 2026

The native app is the current focus. Website and Passwords work are paused.
Public distribution remains blocked; basic unlocking passed on the preceding
candidate by owner report, not by an automated lock-screen test.

## Changes

- Ada 4 fixed wallpaper request races and retry handling in
  `Sources/App/DesktopWallpaper.swift`. Newer selections invalidate older work;
  returning to the cached wallpaper cancels the pending replacement. Failed images
  retry after ten seconds. Core Image processing returns Data from concurrent work,
  while NSImage creation and screen lookup stay on MainActor.
- Root fixed release-version ordering in `Sources/App/ReleaseUpdateChecker.swift`.
  Stable releases outrank their prereleases, build metadata has no precedence, and
  numeric components cannot overflow into zero. Short versions and v/V prefixes
  remain supported. Invalid versions show a failed check rather than “up to date.”
- Root fixed the overlapping-check success timestamp: only a completed successful
  check advances it. An overlapping timer cannot suppress retry after an in-flight
  manual request fails. Successful manual checks also satisfy the daily schedule.
- Otto 4 identified the unused legacy Liveness model and its remaining source
  constant dependency. Root removed the optional copy/compile branches from
  `build.sh` and excluded both legacy model formats from `source-archive.sh`.
  The Swift source, crop constant, local resources, FaceEmbedding, Spoof, and all
  recognition/security thresholds remain unchanged. Clearance stays fail-closed;
  the unresolved legacy inventory entry was not deleted or marked cleared.

## Verification

- The original version probe reproduced three incorrect comparisons: stable
  `1.0.0` was not newer than `1.0.0-beta.1`; beta.2 outranked stable; build metadata
  +2 outranked +1. The new production comparator passes those cases.
- `Tools/AppReadinessRegression/run.sh` passes 13 Swift Testing test functions
  across three suites, including 20 version examples, 18 invalid inputs, the
  standard prerelease sequence, seven wallpaper scenarios, overlapping HTTP
  requests, manual success, and three invalid feed versions.
- The regression package compiles the actual production files in Swift 6 mode.
  URLProtocol supplies all HTTP and a temporary preference suite holds timestamps.
  It never starts Gaze or the wallpaper singleton.
- `Tools/ReleaseRegression/run.sh` passes 23 identity/build checks, 29 artifact
  verifier checks, 12 preflight checks, and the new synthetic archive check.
  Mock signing tools in that suite do not establish a real distribution signature.
- Fresh optimized app build passes with no compiler warnings/errors in its log.
  Deep strict codesign verification passes, with hardened runtime and the same
  Apple Development designated requirement as the preceding candidate.
- All five FaceEmbedding files and all twelve Spoof files match the previous
  bundle byte for byte. Neither legacy Liveness model format is bundled. Source
  hashes stayed stable through the build, and no Swift source is newer than its
  executable. `CHECKPOINT.json` records source and resource fingerprints.

## Candidate

`build/gaze-readiness-20260917/Gaze.app`

Executable SHA-256:
`041b6d864443671babcab54011de3b3f8a76ba449cdc6915add0e4885c4ba747`

Built September 17 at 00:19:11 UTC, using the installed macOS 27 SDK with a
macOS 26 deployment target, arm64. This is not a macOS 26 runtime acceptance test.
The candidate was not launched. The owner-tested `build/Gaze.app` was preserved
with SHA-256 `919e168b1633a0124f019130573ca1d3bb56a15b44d86da3e7ffb16e3f22ab14`;
the existing process still points at that older bundle.

Logs and head evidence: `build/gaze-readiness-20260917/`.
No live lock, camera, credential, enrollment, or authentication trial was performed.

## Remaining launch gates

1. Owner-supervised positive/negative unlock, password fallback, sleep/wake, and
   relock acceptance on the final artifact. Basic unlock on the prior artifact is
   useful evidence but does not cover these cases or automatically transfer here.
2. Clean install and update on supported Macs, including macOS 26 compatibility.
3. Model and artwork distribution rights. All six clearance groups remain open;
   excluding legacy bundle weights does not change the validator's current scope.
   See `Tools/Release/ModelClearance/SAPPHIRE-EVIDENCE-20260916.md` and `clearance.json`.
4. Developer ID signing and notarization, deferred by the owner. This candidate
   keeps the established Apple Development identity.
5. Production update feed/download acceptance when website work resumes. Local
   updater regressions do not prove the deployed service or download is ready.

No deployment, commit, push, source archive publication, or relaunch was performed.
