# Distribution prerequisites — ShipPass 2026-09-18

Lead checkout follow-up, September 18: `python3 Tools/Release/ModelClearance/validate.py`
was run in `/Users/owencope/Developer/FaceID`. It exits 1 for unresolved clearance
and missing grant/scope evidence across all six groups, with no missing-file
errors. The worktree's missing model paths below are not missing artifacts in
the lead checkout.

Inventory taken 2026-09-18 ~00:49 UTC. Read-only: no build, sign, upload,
notarize, deploy, or certificate action was performed, and neither bundle was
launched. Old reports under `Tools/Release/` are historical context only and
were not edited; historical SHA/version values below are superseded by the
fresh values in this file.

Commands actually run (all read-only):
- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash Tools/Release/preflight.sh` → exit 1 (this worktree copy)
- `python3 Tools/Release/ModelClearance/validate.py` → exit 1 (same refusal as preflight's clearance step)
- Per bundle: `PlistBuddy` reads of `Contents/Info.plist`, `lipo -archs`, `shasum -a 256`, `codesign -dv --verbose=4`, `codesign --verify --deep --strict`, `xcrun stapler validate`
- `spctl -a -vv` on `build/Gaze.app` (assessment only)
- `security cms -D -i ".../Gaze Passwords.app/Contents/embedded.provisionprofile"` decoded to a temp plist, parsed for expiration/identifier only, temp file deleted

Note on paths: this inventory ran from a worktree copy whose `build/` is
git-ignored and absent. Bundle metadata below was read from the actual bundles
in `/Users/owencope/Developer/FaceID/build/` (not from historical reports).
The preflight and validator runs above used the worktree's `Resources/`, which
unlike the lead checkout has no `FaceEmbedding.mlmodelc` or `Liveness.mlmodelc`
dirs — hence the 10 `file missing on disk` lines apply to this copy, not
necessarily to the lead checkout.

## 1. Available prerequisites (present, verified)

- Toolchain: `codesign`, `security`, `xcrun`, `spctl`, `python3`, plus
  `notarytool` and `stapler` via `xcrun`, all found by preflight.
- Source bundle metadata (`Resources/Info.plist`): identifier
  `com.gazeunlock.Gaze`; keys `CFBundleExecutable`, `CFBundleName`,
  `CFBundleShortVersionString`, `CFBundleVersion`,
  `LSMinimumSystemVersion`, `NSCameraUsageDescription` all present.
- Camera entitlement: `com.apple.security.device.camera=true` in
  `Resources/Gaze.entitlements`.
- Model sources in worktree `Resources/`: `FaceEmbedding` (via
  `FaceEmbedding.mlpackage`) and `Spoof` (`Spoof.mlmodel`) both found.
- `build/Gaze.app` (mtime 2026-09-17T17:15:14+08:00): version 0.1 (build 1),
  min OS 26.0, `arm64`-only, hardened runtime (`flags=0x10000(runtime)`),
  signed `Apple Development: owen.o.cope@gmail.com (Y6LG3Q6HV4)`,
  TeamIdentifier `CAAVJCSL92`, executable SHA-256
  `84c1015c041ddea1c570c218f9f333773169695f9b7e04b1b68e6907201871b5`,
  `codesign --verify --deep --strict` passes, no embedded provisioning
  profile, no stapled ticket (`stapler validate`: "does not have a ticket
  stapled to it", exit 65).
- `build/gaze-ux-tightening-20260917/Gaze.app` (mtime
  2026-09-17T18:02:11+08:00): version 0.1 (build 1), min OS 26.0,
  `arm64`-only, hardened runtime, same Apple Development authority/team,
  executable SHA-256
  `311a8b47e8be0352cefe1f308adeb856a9bc8b1dc0d9571ee57bbdced08687a5`,
  strict verify passes, no stapled ticket (exit 65).
- `build/browser-integration/Gaze Passwords.app` (mtime
  2026-09-16T08:48:07+08:00): `com.gazeunlock.Passwords` 0.1.0 (build 1),
  min OS 26.0, `arm64`-only, hardened runtime, same Apple Development
  authority/team, executable SHA-256
  `cc1751f3406e31f5b4e87e433544557c4a26aab484a6666a044655c9385b0e92`
  (matches the historical value in `Tools/Release/READINESS.md`), no stapled
  ticket (exit 65). Embedded provisioning profile: application-identifier
  `CAAVJCSL92.com.gazeunlock.Passwords` — compatible with the bundle
  identifier; expiration 2026-09-20 23:51:05 UTC — not yet expired, but
  expires within seven days of this inventory (~2.9 days). No certificates,
  keys, tokens, or device lists were exported.
- Gatekeeper spot-check: `spctl -a -vv build/Gaze.app` → `rejected`,
  `origin=Apple Development: ...` (exit 3). Expected for a local Development
  signature; not a release verdict.

## 2. Code/tooling problems the team can fix

- Preflight in this copy reports 2 missing prerequisites (exit 1): (a) no
  Developer ID Application identity — see section 3, not a code fix; (b)
  model/asset clearance REFUSE — six artifacts `unresolved`
  (`face-embedding`, `spoof-detector`, `setup-art`, `credit-portraits`,
  `app-icon`, `legacy-liveness`), each missing licence/grant record and full
  `bundled-app-distribution` scope (`spoof-detector`, `setup-art`,
  `credit-portraits`, `app-icon`, `legacy-liveness` also missing licence
  evidence refs). Recording the evidence pointers in
  `Tools/Release/ModelClearance/clearance.json` per `OWNER-TEMPLATE.md` and
  re-running `validate.py` to `PASS` is team work, but the underlying grants
  themselves are external (section 3).
- The 10 `file missing on disk` validator lines (all
  `FaceEmbedding.mlmodelc/*` and `Liveness.mlmodelc/*` payload files) are an
  artifact of this worktree copy lacking the precompiled dirs present in the
  lead checkout. Re-run `validate.py` in the lead checkout before treating
  them as real gaps; do not "fix" by inventing fingerprints.
- No stapled ticket on any of the three bundles, and no `build/release/`
  signed artifact exists. Stapling follows a real Developer ID build +
  notarization (section 3); there is nothing to staple yet.

## 3. External requirements (owner or third party only)

- Developer ID Application certificate: none on this machine (preflight:
  "this machine can only make local Apple Development builds"). Owner must
  provision it; then `DIST=1 GAZE_SIGNING_IDENTITY="Developer ID
  Application: ..." bash build.sh`, notarize, staple, and verify with
  `bash Tools/Release/verify.sh build/release/Gaze.app`. All current bundles
  are Apple Development local builds — not distributable.
- Exact model/asset permissions, per `Tools/Release/ModelClearance/README.md`,
  `OWNER-TEMPLATE.md`, and `NOTICE.md` (nothing invented here):
  - `face-embedding`: precompiled weights match Sapphire at
    `ee56de09…` (repo LICENSE AGPL-3.0, correcting the earlier GPL-3.0
    report); no grant covers THESE hashes, and possible InsightFace descent
    needs separate resolution. Requires the actual permission/licence for the
    bundled bytes plus redistribution scope.
  - `spoof-detector`: Roboflow Face Spoof Detection v1 export (self-stated
    CC BY 4.0); dataset terms covering redistribution of the *trained* weights
    need independent review and a recorded grant pointer.
  - `legacy-liveness`: compiled-weights source and licence entirely unrecorded.
  - `setup-art` (11 files), `credit-portraits` (9 third-party
    likenesses/icons), `app-icon`: authorship/permission confirmations or
    removal of the files. Do not paste private grant documents into source —
    record pointers. No thresholds were touched and no substitute model is
    approved.
- Owner-supervised acceptance still open per `Tools/Release/READINESS.md`:
  live install/unlock acceptance (basic unlock smoke-reported 2026-09-16;
  negative/fallback, wake/relock, clean-install/update checks pending),
  supported-Mac install/update checks, and deployed update-service acceptance.
- Time-sensitive: the Gaze Passwords development provisioning profile expires
  2026-09-20 23:51:05 UTC. Any Passwords testing past that date needs a fresh
  profile; distribution needs its own release provisioning path.

Skill notes: the `no-agent-messaging` skill was read (delegation coordination
rules retained; no messaging was needed). The packaging-notarization skill was
not found under the searched skill paths, so notarization steps above are quoted
from `preflight.sh`'s own next-steps output, not from that skill.
