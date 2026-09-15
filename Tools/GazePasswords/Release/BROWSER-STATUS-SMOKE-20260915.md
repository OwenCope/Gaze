# Browser native-host status smoke — 2026-09-15

Scope: BrowserOS (BrowserClaw) native-host discovery/status for Gaze Passwords.

## Lead audit and follow-up

The original findings below describe the files at Zola's check time. The lead
verified that BrowserOS MCP tools are also unavailable in the lead environment.
A further read-only check found no entry for the expected extension ID in either
`Default/Preferences` or `Default/Secure Preferences`. This is evidence about the
inspected profile only; a cache-directory absence alone cannot establish that an
unpacked extension is absent from every possible browser profile.

The stale helper was resolved without changing the registration: the verified
current protected app was rebuilt at the already-registered canonical path,
`build/browser-integration/Gaze Passwords.app`. That build passes local release
verification. Its helper SHA-256 is now
`e3fa05cb14b89f7de0305045435f91191322b0c578271f04b40958685ddbd8d8`.
The existing registration still names this exact path and the expected extension
allowlist. Earlier app/extension artifacts were preserved by the build script.

Settings now identifies a conflicting helper registration and can reveal the
exact file for review; it still never silently replaces a conflicting registration.
A new path regression passes with the existing setup fixtures (24 checks total).

The canonical app launched locked and its signed direct status probe passed.
The real BrowserOS -> native host path remains NOT verified: no extension was
installed or driven, and no vault authentication, camera, form fill or profile
rewrite was performed. Use the canonical build and its bundled/staged extension
for the owner-assisted browser test.

## Original head snapshot

## Method (read-only)

- Read the existing registration at
  `/Users/owencope/Library/Application Support/BrowserClaw/NativeMessagingHosts/com.gazeunlock.passwords.json`
  without modifying it. Recorded name, helper path, allowlist and type only.
- Verified helper/app paths exist, compared SHA-256 digests, checked `codesign -dv`
  identity/team/runtime fields and `codesign --verify --deep --strict` (pass/fail only).
  No secrets printed; no key material reproduced.
- Compared the two staged extension manifests and the two bundled
  `BrowserIdentity.json` files by extension ID and version only.
- Listed `BrowserClaw/Default/Extensions/`, walked `Default/Preferences` and
  `Local State` for the expected extension ID string only, and checked for a
  running BrowserClaw process.
- Did NOT click Fill or Save, approve anything, unlock the vault, invoke Keychain
  authentication, open the camera, lock the screen, change settings/profiles/data,
  install/reload/replace any extension, enable developer mode, rewrite the
  registration, move apps, or kill/restart processes.
- Live popup check was not run: the BrowserOS neo MCP tools are not present in
  this environment (only file/shell tools), and no BrowserClaw process was running
  at check time. Fallback was limited to signatures/manifest/path checks below.

## Exact artifacts exercised

All paths are absolute under the root checkout `/Users/owencope/Developer/FaceID/build/`.
This worktree has no `build/` directory, so nothing was exercised from the worktree.

- Registration: `.../BrowserClaw/NativeMessagingHosts/com.gazeunlock.passwords.json`,
  mtime 2026-09-14 14:17:42.
  - name `com.gazeunlock.passwords`, type `stdio`
  - path `/Users/owencope/Developer/FaceID/build/browser-integration/Gaze Passwords.app/Contents/Helpers/GazeBrowserBridge`
  - allowlist: exactly `chrome-extension://dplcnjngbhocgeidhcgkiidilolbgadl/` (matches expected bundled ID)
- Registered helper (browser-integration), mtime 2026-09-14 14:48:50:
  - SHA-256 `37da91ce147ec3b061ab3340628cb004a677f09d75e4d34356a4765cae889b70`
  - identifier `com.gazeunlock.Passwords.BrowserBridge`, team `CAAVJCSL92`,
    Apple Development authority, hardened runtime, `codesign --verify` pass
- Protected-candidate helper (passwords-release-prep), mtime 2026-09-15 22:31:
  - SHA-256 `4bfca7fc5508b4cc16487d12db291ad98ed21382b694a533426556c1e180733f`
  - same identifier/team/authority/runtime shape, `codesign --verify` pass
  - helper digests differ: registration does NOT point at the protected candidate
- Apps (running at check time):
  - `build/Gaze.app`, executable SHA-256 `f75675d3f58213ab4128884b7f7274153d008937141b42e8b656dc8904ee289c`,
    signed 2026-09-15 21:53, team `CAAVJCSL92`, identifier `com.gazeunlock.Gaze`,
    running PID 46045 as `.../Gaze.app/Contents/MacOS/Gaze --settings`
  - `build/passwords-release-prep/Gaze Passwords.app`, executable SHA-256
    `6f12bcc56bcb33acff12b1f4612182099024dfa2624925a7e3aaff43a3a71adf`,
    signed 2026-09-15 22:31, team `CAAVJCSL92`, identifier `com.gazeunlock.Passwords`,
    exact Keychain group `CAAVJCSL92.com.gazeunlock.Passwords`, running PID 49925,
    launched locked, not authenticated (per handoff; not re-tested here)
- Staged extensions:
  - `build/browser-integration/browser-extension/manifest.json` and
    `build/passwords-release-prep/browser-extension/manifest.json`: both name
    `Gaze Passwords`, version `0.2.0`, permissions `activeTab`/`scripting`/`nativeMessaging`.
    Staged signing key present in both (not reproduced); both bundled
    `BrowserIdentity.json` files record extension ID `dplcnjngbhocgeidhcgkiidilolbgadl`.
- Installed extensions in `BrowserClaw/Default/Extensions/`: only
  `adlpneommgkgeanpaekgoaolcpncohkf` (BrowserOS Feedback),
  `bgnkhhnnamicmpeenaelnjfhikgbkllg`, and `pjimfkbpehlcllblajnpfamdfjhhlgkc`
  (BrowserOS neo 0.2.17.0). `dplcnjngbhocgeidhcgkiidilolbgadl/` is absent.
  String walk of `Default/Preferences` and `Local State` found no reference to the
  expected ID. No BrowserClaw process matched at check time (config on disk reports
  browseros 0.49.5.0 / chromium 148.0.7988.97, but that is not a running instance).
- Safe status action confirmed present in source (not clicked):
  `BrowserExtension/popup.html` button `#connection` ("Check app connection") and
  `popup.js` handler sending `{operation:"status"}` and writing `#connection-status`.
  It does not unlock, fill, save, or read the page.

## Result

Live BrowserOS -> native host -> signed Passwords status NOT verified.

- The registration file exists, resolves to an existing signed helper, and its
  allowlist matches the expected extension ID — but that helper belongs to the
  `browser-integration` build (Sep 14), not the protected `passwords-release-prep`
  candidate (Sep 15, different helper digest).
- The expected extension ID was not found in the inspected Default extension
  cache, Preferences or Local State. Installation state in a running browser was
  not verified; do not generalize this file inspection to every possible profile.
- Prior signed direct status probes passing does not prove this path; nothing here
  proves filling, Keychain persistence, face recognition, or readiness to distribute.

## Limitations

- No browser tab was opened; no extension popup was driven. The live
  "Check app connection" step could not run here (no BrowserOS neo MCP tools in
  this environment; no running BrowserClaw instance observed).
- All digest/signature/manifest evidence is offline and read-only. It proves which
  files exist and that their signatures verify, not that the browser can reach them.

## Integration defect and concrete next step

At check time, the registration selected an older helper and the expected
extension was not found in the inspected profile. The lead resolved the stale
helper as recorded above; actual browser installation/status still needs validation.

Next step (owner/lead action, not taken here): decide the canonical artifact, load
the `dplcnjng...` extension from that artifact's staged `browser-extension`
directory without disturbing other profiles, point/verify the registration at that
artifact's helper, relaunch the browser, open only the extension popup created for
this check, press ONLY "Check app connection", and record the exact
`#connection-status` text plus which app/helper digests were running. Do not press
Fill/Save, approve, unlock, or visit real login pages.
