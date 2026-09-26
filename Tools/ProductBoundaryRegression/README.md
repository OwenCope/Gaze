# Product boundary checks

`bash Tools/ProductBoundaryRegression/run.sh` verifies the production Gaze source manifest
leaves out the retired password-autofill feature and its settings, no autofill service or
hotkey is started, the Mac-unlock protections remain included, and the build enables
Hardened Runtime.

These are source/configuration assertions, not a test of installed binaries or OS enforcement.
The build must use `collect_gaze_main_sources` from `Tools/MainAppSources.sh`, as `build.sh`
does; a hand-written `Sources/*/*.swift` compile bypasses those boundaries.

Common hardening tests live under `Tools/HardeningRegression` and lock-screen tests under
`Tools/LockScreenSecurityRegression`.
