# Public-release requirements — ShipPass 2026-09-18

Distribution-readiness evidence only. Read-only inventory; no build, sign,
notarize, upload, deploy, or certificate action was performed, and no bundle
was launched. Bundle bytes below were read from the lead checkout
`/Users/owencope/Developer/FaceID/build/` (this worktree's `build/` is
git-ignored and absent). Paths are relative to the repo root unless stated.

## 1. Shippable-claims baseline (what the sources actually promise)

| Claim | Source |
| --- | --- |
| Version `0.1` (build `1`), identifier `com.gazeunlock.Gaze` | `Resources/Info.plist:12,15-18` |
| Minimum macOS `26.0` | `Resources/Info.plist:19-20`; `toolchain.sh` `MIN_SDK_MAJOR=26` |
| Single-architecture binary (build host's arch, not universal) | `build.sh:185-200` (`-target "$(host_target)"`); `Tools/Release/READINESS.md:372-373` |
| Camera entitlement, deliberately not sandboxed | `Resources/Gaze.entitlements` (camera `true`, sandbox comment) |
| Models bundled by default when present: `FaceEmbedding.mlmodelc`, `Spoof.mlmodelc`; landmark-geometry fallback otherwise (weaker) | `build.sh:94-125`; `AGENTS.md:89-92` |
| `verify.sh` release bar: Developer ID Application + secure timestamp + hardened runtime + camera entitlement + no unsafe entitlements + stapled ticket + Gatekeeper acceptance | `Tools/Release/verify.sh:21-39` |
| `DIST=1` release path: clearance gate, `build/release/Gaze.app` output, `--timestamp`, Developer ID check | `build.sh:19-26,202-221` |

## 2. Current candidate evidence (`build/gaze-ship-20260918/Gaze.app`)

Read 2026-09-18 (lead checkout). All commands read-only.

| Requirement | Current evidence | Remaining action | Who |
| --- | --- | --- | --- |
| Version / min OS / arch | `0.1` (build `1`), min OS `26.0`, `arm64`-only (`lipo -archs`, `PlistBuddy`) | None for the claim itself; supported-Mac matrix (Intel? older macOS?) is a product decision still open per `Tools/Release/READINESS.md:367-381` | Owner decides matrix; root can test |
| Models actually in the bundle | `FaceEmbedding.mlmodelc` + `Spoof.mlmodelc` both present in `Contents/Resources/` | None (presence); rights are the blocker (section 3) | — |
| Signature type | `Apple Development` (TeamIdentifier `CAAVJCSL92`); `codesign --verify --deep --strict` passes | Rebuild `DIST=1` with a Developer ID Application identity after rights clear | Owner provisions cert; root runs build |
| Secure timestamp | **Absent**: no `Timestamp=` line in `codesign -dv --verbose=4` (only `Signed Time`, which is not the secure-timestamp evidence `verify.sh:28` greps for) | Comes with the `DIST=1` build (`build.sh:25` adds `--timestamp`) | Root, once cert exists |
| Hardened runtime | Present (`flags=0x10000(runtime)`) | None | — |
| Stapled notarization ticket | **None**: `xcrun stapler validate` → "does not have a ticket stapled to it" (exit 65) | Notarize + staple the future release bundle | Owner authorizes; root runs |
| Gatekeeper acceptance | **Rejected**: `spctl -a -vv` → `rejected`, `origin=Apple Development` (exit 3). Expected for a dev signature, not a release verdict | Re-assess after Developer ID + notarization + stapling | Root |
| Signing-identity inventory | **0** Developer ID Application, **1** Apple Development (type counts only, no names/credentials read) | Provision a Developer ID Application certificate (see `preflight.sh:95-96` next steps) | Owner/external (Apple Developer Program) |
| Local-preview DMG freshness | **Stale**: `build/installers/20260918-tourkit-tipkit/*.dmg.json` records `executableSHA256 1d851eea…`, but the current candidate executable is `d60d756c…`. (`RESULT.md:38-42` also records an older `94cab55e…`.) DMG receipt itself says `distributionReady: false` | Repackage from the final release candidate; root owns packaging later — **do not treat the existing DMG as the candidate** | Root (later) |

## 3. Model/asset rights — the hard blocker (technical readiness ≠ rights)

`python3 Tools/Release/ModelClearance/validate.py --json` in the lead checkout
→ verdict **REFUSE**: all six required artifacts `unresolved`
(`face-embedding`, `spoof-detector`, `setup-art`, `credit-portraits`,
`app-icon`, `legacy-liveness`), each missing licence/grant record and full
`bundled-app-distribution` scope; plus 8 `Resources/Art/tour-*.png` files with
no clearance entry at all. Fixing the *records* is team work
(`Tools/Release/ModelClearance/OWNER-TEMPLATE.md`); the underlying *grants* are
external and cannot be invented. Documented restrictions (nothing fabricated):

- Recognition weights: match Sapphire at `ee56de09…` (repo LICENSE **AGPL-3.0**);
  no grant covers these hashes; possible InsightFace descent unresolved; "redistribution is not cleared" (`NOTICE.md:46-80`).
- FaceIDKit animations: licensed to this app alone, explicitly not for redistribution, kept out of git (`NOTICE.md:82-87`).
- Spoof detector: Roboflow self-stated CC BY 4.0; trained-weight redistribution terms need independent review (`DISTRIBUTION.md` section 3, this directory).
- Setup art (11 files), credit portraits (9 third-party likenesses/icons), app icon: authorship/permission confirmations or removal still open.
- Geometry fallback is **not** an approved substitute for the Mac-unlock model (`NOTICE.md:78-80`). Never lower a threshold to make evaluation pass (`AGENTS.md:100-101`).

## 4. Real-Mac acceptance (still open, owner-supervised)

Per `Tools/Release/READINESS.md:233-320,367-381`: negative/fallback,
wake/relock, clean-install/update checks, supported-Mac install/update matrix,
private lock-screen API behavior per OS version, and deployed update-service
acceptance. Fixture/DMG checks do not close these. Gaze Passwords is a separate
surface; its development provisioning profile expires **2026-09-20 23:51:05 UTC**
(see `DISTRIBUTION.md` section 1, this directory).

## 5. Critical blockers (in order)

1. **Model/asset redistribution rights unresolved** — six groups + eight unlisted art files; `validate.py` REFUSE. No upload until PASS.
2. **No Developer ID Application identity** (0 on this machine) → no release signature, no secure timestamp, no notarization/stapling, Gatekeeper rejects.
3. **Existing local-preview DMG is stale** (packages `1d851eea…`, candidate is `d60d756c…`) and marked `distributionReady: false`.
4. **Live acceptance gaps**: real-Mac install/unlock matrix, clean install/update, revocation/contention/sleep/user-switching fail-closed behavior.

## 6. Final read-only verification (verification only, not publication)

```sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/gaze-ship-20260918/Gaze.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' build/gaze-ship-20260918/Gaze.app/Contents/Info.plist
/usr/bin/lipo -archs build/gaze-ship-20260918/Gaze.app/Contents/MacOS/Gaze
shasum -a 256 build/gaze-ship-20260918/Gaze.app/Contents/MacOS/Gaze
codesign --verify --deep --strict build/gaze-ship-20260918/Gaze.app
codesign -dv --verbose=4 build/gaze-ship-20260918/Gaze.app 2>&1 | grep -E '^(Authority|Timestamp)='
xcrun stapler validate build/gaze-ship-20260918/Gaze.app
spctl -a -vv build/gaze-ship-20260918/Gaze.app
bash Tools/Release/preflight.sh
python3 Tools/Release/ModelClearance/validate.py --json
# Compare any DMG receipt before trusting it:
python3 -c "import json;print(json.load(open('build/installers/<dir>/Gaze-<v>-<arch>-local-preview.dmg.json'))['executableSHA256'])"
```

The release gate itself (`bash Tools/Release/verify.sh build/release/Gaze.app`)
only becomes meaningful after a `DIST=1` Developer ID build, notarization, and
stapling — all of which wait on blockers 1–2 above.
