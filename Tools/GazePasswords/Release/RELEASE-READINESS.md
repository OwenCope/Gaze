# Gaze Passwords release readiness

## Status — September 15, 2026

**Local development artifact checks pass; public distribution remains blocked.**
There is no Developer ID Application identity or notarized distribution artifact.
The lead has audited and integrated Finn, Mira, Odin, Suki and Rex's changes.
This document distinguishes synthetic/component verification, local process/status
checks, and the owner-assisted authentication that is still required.

## Verified local artifact

Built at 22:46 local time and verified September 15, 2026 with the existing development profile
reused as-is (nothing was provisioned, renewed, uploaded or notarized):

- Canonical app: `build/browser-integration/Gaze Passwords.app`.
  This matches the existing BrowserOS registration; no registration rewrite was
  needed. The earlier `build/passwords-release-prep/` candidate is retained as a
  previous test artifact, not the current canonical build.
- Executable SHA-256:
  `335de15c79948a45a9db2e9dcad299ba857b63b200eb9b28e6ec43d43634d2df`
- Team `CAAVJCSL92`, Apple Development authority, hardened runtime on the app
  and the nested `GazeBrowserBridge` helper, exact Keychain group
  `CAAVJCSL92.com.gazeunlock.Passwords`, extension
  `dplcnjngbhocgeidhcgkiidilolbgadl` with the exact
  `activeTab`/`scripting`/`nativeMessaging` permission set.
- `verify.sh --local` passes on this exact bundle. `verify.sh --distribution`
  refuses it at the Developer ID gate, as it must.
- Odin also built a storage-disabled UI-review artifact in his earlier worktree
  (`build-live.sh --ui-review`): identifier
  `com.gazeunlock.Passwords.UIReview`, display name `Gaze Passwords UI
  Review`, and `verify.sh --local` refuses it with `Unexpected bundle
  identifier` — the review app cannot be mistaken for the working vault app.

Reproduce:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
GAZE_PASSWORDS_PROVISIONING_PROFILE="/path/to/matching.provisionprofile" \
GAZE_PASSWORDS_LIVE_OUTPUT="$PWD/build/browser-integration" \
bash Tools/GazePasswords/script/build-live.sh
bash Tools/GazePasswords/Release/verify.sh --local \
  "build/browser-integration/Gaze Passwords.app"
bash Tools/GazePasswords/Release/verify-fixtures.sh
```

`verify-fixtures.sh` runs 56 mocked failure-case checks plus source-wiring
assertions: no network, no launch, no Keychain access. The build itself was
additionally verified end-to-end once against the real profile, identity and
signing tools; the fixtures keep the gates pinned without repeating that.

## Packaging defects fixed in this pass

`script/build-live.sh`, `script/verify-profile.swift`, `Live/Info.plist`:

- The default signing identity matches the verified Gaze bundle's leaf
  certificate, rather than the first identity in the Keychain. An explicit
  `GAZE_SIGNING_IDENTITY` is honored through the shared signing helper and
  still must match the profile and Gaze team.
- The profile check now matches the **signing certificate** against the
  profile's `DeveloperCertificates`, requires the **exact** application
  identifier (wildcard profiles are refused), checks platform and expiration
  with per-failure diagnostics, and warns within 30 days of expiry.
- The Gaze.app team is read only after its own signature verifies; the final
  bundle asserts same-team, non-ad-hoc authority and hardened-runtime flags on
  **both** the app and the nested helper, plus the exact signed Keychain
  entitlements — `codesign --verify --deep --strict` alone proves none of that.
- The staged extension key is re-derived and compared with the bundled
  `BrowserIdentity.json` before signing, so a stale stage cannot ship a helper
  that rejects the bundled extension origin.
- Previous artifacts rotate to unique timestamped names (no same-second
  `mv`-into-directory nesting); staging stays hidden and is always cleaned up.
- `Live/Info.plist` gains `CFBundleDisplayName`; the storage-disabled UI-review
  build rewrites it alongside the identifier and name so the review app is
  clearly identified separately from the working vault app.

## The verifier's contract

`Release/verify.sh [--local|--distribution] [APP]` never launches or installs
the app. Local mode is an offline artifact check; distribution mode additionally
uses the system stapler/Gatekeeper tools. Both modes require an embedded,
unexpired, team/app-matched profile that authorizes the signing leaf certificate.
Distribution also requires a distribution profile, Developer ID authority and
secure timestamps on both app and helper, safe entitlements, a stapled ticket
and Gatekeeper acceptance. A development signature is refused outright. Both modes refuse wrong identities,
wrong entitlements, mismatched extension IDs and missing contents — and a
pass is explicitly **not** proof of working unlock, vault persistence, live
face approval, redistribution rights or clean-install compatibility.

## Integrated verification and lead corrections

- The offline suite passes 1,667 component checks/tests, including 115 extension
  tests, 290 native-bridge checks, 71 native-session checks, 56 browser-save and
  62 browser-fill checks, 24 browser-setup checks, and 41 vault-persistence checks. Tests use synthetic
  archives, socket pairs, mocked Chrome/DOM and dummy credential payloads.
- 56 packaging fixture checks pass. Actual protected compilation and local
  verification also pass with the existing development profile.
- 18 light/dark renders cover locked/empty/populated vault, Settings including its
  lower browser section, Import, password editor and verification-code views.
  The lead inspected the relevant captures and made Import scrollable. Native
  glass and asynchronous discovery are not fully represented offscreen; this is
  not a native UI acceptance test.
- Gaze and protected Passwords launched; signed status probes to both services
  passed with no approval requested and no credential returned. This demonstrates
  signed local service reachability, not real browser registration or a completed
  face-approved fill.
- Final canonical processes: Gaze PID 46045 and Passwords PID 51873. Source
  freshness and executable hashes are recorded in `build/final-candidate-artifacts.json`.
  A final computer-use retry still failed at native-pipe startup; no live visual
  or authenticated-vault acceptance is inferred from the process checks.

The lead corrected Odin's verifier to check signed identifiers and Apple trust
for app/helper, the full Keychain group array, helper vault entitlements, the
leaf certificate specifically, profile validity in distribution mode, helper
Developer ID/timestamp and unsafe-entitlement gates, extension entry points and
unexpected host/optional capabilities. The build runs this verifier before
replacing an output. A fixture temporary-file collision was also fixed.

Mira's timer guard now has a direct controlled-expiry regression: a stale timer
cannot lock a newer vault session, while the current timer can lock its own.
Expiry is also checked from the monotonic clock when reading the lock state or
mutating the vault: a delayed timer cannot extend access past five minutes. Reveal,
copy and editor actions recheck the vault state; stale clipboard timers are bound
to the copy they own. The controlled-clock test covers a suspended timer at the
exact deadline. The persistence-failure fixture throws a system error separately
from a revision conflict. The new vault tests are included in the offline suite.
The signed status tool uses the Gaze certificate by default and supports either
service. No authentication, real vault mutation, camera, locking or form fill
was automated while the owner was away.

Logs (repository `build/`): `passwords-integrated-offline.log`,
`passwords-vault-timer-tests.log`, `passwords-release-fixtures.log`,
`passwords-protected-build.log`, `passwords-layout-check.log`,
`gaze-live-status.log`, `passwords-live-status.log`,
`passwords-distribution-check.log`, `passwords-canonical-build.log`,
`passwords-canonical-setup-tests.log`. The browser-specific inspection and its
limits are recorded in `BROWSER-STATUS-SMOKE-20260915.md`.

## Remaining owner / distribution gates

1. **Provisioning renewal (time-sensitive).** The development profile expires
   2026-09-20 23:51 UTC. Renew through Xcode (`script/provision-live.sh`,
   owner-approved); never remove Keychain entitlements as a workaround. No
   identities were created or renewed in this pass.
2. **Distribution signing.** No Developer ID Application identity exists
   locally — only Apple Development. Provisioning one, timestamped signing,
   notarization and stapling are owner actions; the `--distribution` gates
   above describe exactly what will be required.
3. **Acceptance.** The owner-supervised checklist in `Live/README.md`
   (Keychain save cycle, native-host discovery, synthetic fill, cancellation
   and lock/session boundaries) has not been run on this artifact.
4. **Distribution integration.** Confirm native-host discovery in the intended
   browser, clean install/update behavior, and reviewed extension distribution.
   No browser profile or extension was installed or changed during this pass.
   The sample-data preview remains separate from the protected application.
