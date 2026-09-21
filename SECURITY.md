# Security

How the app handles your account password and your faceprint, and what it does not defend
against. Everything here is checkable against the files named at the bottom.

## September 13, 2026 product separation

**Gaze no longer provides app autofill in the new build.** Its Autofill pane, activation
preference, global shortcut, watcher and saved-app-store initialization are removed.
`Tools/MainAppSources.sh` excludes the retired autofill sources and UI from the main
executable. Gaze retains Mac unlocking, enrollment and the security controls described below.
The retired autofill sources remain in the tree but are excluded from the build by
`Tools/MainAppSources.sh`; they are not wired into the product.

Existing saved-app vault records are **not read, copied, migrated or deleted** by this
separation. The Mac account password used by Gaze's lock-screen backend remains separate.
There is presently no replacement UI for editing retired saved-app records. Do not delete
the shared vault key to clean up those records: it also protects Gaze's other stored data.
An explicit migration/recovery tool must preserve that distinction and require owner consent.

**Gaze Passwords is a separate app whose code is not in this repository, and it is
still a sample-data preview, not a working password manager.** It shares
Gaze's actual console-session lease and app-signature inspection code rather than approximating
them in the UI. The demo starts concealed; app deactivation conceals it and invalidates its
approval. Lock/unlock, sleep and session resignation also close floating guides. App activation
does not reopen the demo or revive requests. This is privacy behavior, not cryptographic
vault locking: only built-in examples exist and remain in process memory.

Companion-app launch confirmations capture the canonical path, designated requirement,
console session and a one-use request ID. Changes, cancellation, invalid signatures, an
unknown session or a used request deny launch. A valid signature is still not a trusted-vendor
allowlist, and launching an app is not an authenticated Gaze connection. No face approval,
profile, vault key or credentials are shared across processes.

Both build scripts enable Hardened Runtime. Passwords retains App Sandbox and user-selected
read-only access, with no network/camera/keychain-sharing privilege added. No camera or
owner-approval prompts are added to a demo that cannot release real credentials.

Verification at separation time: product-source separation, sandbox/build policy,
privacy/session events and launch-confirmation handling were checked without launching
other apps or touching secrets, and the runs passed. Those harnesses are not published
in this repository, so the results cannot be re-run or re-verified from what is here.
What the reader can check directly is the exclusion itself: `Tools/MainAppSources.sh`
lists the retired sources it keeps out of the main executable. Successful compilation,
rendering and simulated event tests do not validate actual Touch ID, camera capture,
system login or a real credential provider.

**Still required for end-to-end use:** a production Passwords vault with OS-enforced key
access and recovery; an authenticated, consent-bound Gaze approval service; a real autofill
provider with verified target identity; migration tests; signed distribution; and controlled
hardware/system-authentication testing. None of these is implied by the demo animation.

## September 12, 2026 hardening checkpoint

This pass reviews the main app's credential-release, camera/recognition, lock-screen,
storage, updater and signing boundaries, plus the companion preview's lack of a real
credential backend. It is not a penetration test, biometric certification, repository-history
secret scan, website audit, or verification of already installed authentication components.
Existing unrelated design changes are preserved.

Behavior changes in this source checkout:

- Autofill requires a new macOS owner-approval prompt (Touch ID or account password) after
  the face check and before any saved password is read. There is no face-only autofill path.
  This approval is application logic, **not an OS-enforced access-control list on the key**.
- Autofill reserves one of five persistent attempts before recognition. Exhaustion requires
  owner approval to reset, then a separate retry; approval to reset does not release a secret.
  Storage errors or failed readback deny further attempts. Lock-screen failures use a separate
  six-failure counter with range validation, saturation and persistence readback.
- A request is bound to its original console-session UUID. Lock, unlock, sleep or session
  resignation irreversibly invalidates pending autofill approval. Exact app path, process
  launch instance, signing requirement, record revision and secure focused field are checked
  again before release. All writes remain targeted Accessibility writes, with no fallback.
- Password-based Mac unlocking now always requires the enrolled built-in camera and a random
  movement challenge, regardless of the older opt-out preferences. When optional object-based
  anti-spoof protection is enabled, a missing model or failed/invalid inference denies unlock.
  Recognition and anti-spoof score thresholds are unchanged.
- Camera start/stop work is serialized. Capture generations invalidate late callbacks;
  sample-age checks reject delayed processing. Repeated frames cannot advance recognition.
  A frame gap, bad-quality frame, missing face or different matched identity resets the hold;
  lock-screen challenge progress is also reset. A stalled camera fails closed, and a lock
  attempt has a 60-second upper bound in addition to absence/failure limits.
- Lock-screen release rechecks the same locked owner session, camera, enrollment, pause and
  policy. The old animation delay before password submission is removed. Backend exceptions
  cannot mark submission successful, and success is broadcast only after a verified unlocked
  session notification following submission. This still cannot prove which OS unlock method
  succeeded if the user also authenticates manually. Within a running watcher, only one
  password submission is allowed until a verified unlock; a refused password cannot be
  replayed repeatedly by wake notifications. This one-submission latch is in memory, not
  a replacement for the persistent lockout counter.
- Release requests are bounded, ephemeral and restricted to the exact HTTPS origin
  `gazeunlock.com`, including redirects. Off-origin downloads fall back to the fixed releases
  page. Gaze no longer executes Git/fetch/merge or inherits Git hooks, helpers and configuration
  for source updates; it only reveals the source folder. No downloaded code is auto-installed.
- `build.sh` enables Hardened Runtime without adding runtime exceptions. This does not provide
  a Developer ID signature, notarization, sandboxing, or real-device runtime compatibility.

Verification: 105 hardening checks, 71 storage/identity checks, 47 password-submission checks
and 27 companion-demo model checks pass with synthetic inputs. An optimized full-source
executable builds and its isolated ad-hoc Hardened Runtime signature verifies. The normal
`build/Gaze.app` executable is unchanged; the review executable was not launched. Existing
Swift concurrency warnings in `DesktopWallpaper` and `GlobalHotKey` remain.
Coverage boundaries are as stated at the top of this section: synthetic inputs only,
with no real passwords, camera, Touch ID, lock/unlock or system authentication.

No real passwords, Keychain records, face enrollment, camera, Touch ID prompts, lock/unlock,
CGEvent posting, import/export, system authentication installation or website changes were
used for this verification. Deployment and controlled end-to-end tests remain outstanding.

## Retained hardening policy

Autofill-specific items below describe the retained source implementation, covered by
checks that are not published in this repository. Since September 13 it is excluded
from Gaze and is not enabled in Gaze Passwords.

- Every new face, including the first, requires fresh macOS owner authentication inside
  `FaceEnrollmentStore.add`. The in-app Touch ID preference cannot bypass it. An unreadable
  vault or an empty filtered face list does not grant an enrollment exception.
- Autofill captures a secure Accessibility element owned by the verified process. It
  rechecks process identity and the exact field after recognition, then sets that element's
  value directly. It never falls back to global keystrokes, plain fields, or Tab navigation.
  Apps that do not expose a writable secure value cannot use this path.
- Known browsers and currently registered HTTP/HTTPS handlers are blocked for both the
  shortcut and automatic filling. This is a denylist, not proof that every other app is
  free of web content. There is no browser origin integration. Do not save website passwords
  against browsers or other applications that display untrusted web content.
- Autofill requires advancing camera frames and resets its matching interval after a frame
  gap. A frozen matching frame cannot complete the hold by being sampled repeatedly.
- Vault reads distinguish a missing item from a Keychain error. Key reconstruction errors
  propagate without replacing the stored key; decryption never creates a replacement key.
  Failed Keychain writes throw, allowing enrollment rollback and lockout failure handling.
- Saved-app changes use an encrypted pending-change record. The intent, secret and list
  are read back before success; deletion also verifies absence. A failure retains the
  displayed list and blocks filling and edits until recovery succeeds. Recovery completes
  the pending change, including after restart; it does not promise to undo it. The pending
  record can contain the replacement secret until recovery removes it.
- App selection retains the canonical URL chosen in the picker or suggestion. The signature
  is checked at selection and before saving, without resolving another app by bundle ID.
  Replacing an existing signing requirement requires fresh owner authentication and another
  signature check after approval. Password-only edits preserve the pin. Record revisions
  reject stale editors and invalidate an autofill request that captured an older password.
- The optional PAM and legacy authorization integrations are disabled. The PAM authenticate
  function returns `PAM_AUTH_ERR`; the XPC compatibility listener returns unavailable and
  does not open the camera. Both installers refuse without changing any files or policies.

These are source changes, not an installation or removal procedure. Old running apps,
installed PAM modules, LaunchAgents, and authorization policies are unchanged until an
administrator separately reviews and deploys or removes them. Do not assume that building
this checkout hardens an already installed integration. See `Plugin/README.md`.

## What is stored

| Item | When |
| --- | --- |
| Faceprint | Once enrolled. Numeric embeddings, not camera photographs. |
| Optional portrait | User-selected PNG files in `~/Library/Application Support/Gaze/Portraits`, outside the encrypted vault. |
| Account password | Only under the **Unlock my Mac** backend. The default, **Just recognise me**, never asks for one. |
| Saved app passwords | Legacy Autofill records only. They remain encrypted and are not migrated or loaded by the new Gaze build. |
| Failed attempt counts | Six lock-screen failures; five independent autofill attempts. Reset rules differ as described above. |

The vault records use the same sealing path. Optional portraits do not.

## Storing the password

1. **Verified before it is kept.** `ODRecord.verifyPassword` checks it against the local
   directory. A wrong password is rejected and never written. The check unlocks nothing and
   is not exercised against a real account by the tests. Account lockout-policy effects must
   be verified separately; an incorrect-password loop is not a safe test method.
2. **A Secure Enclave key is created.** A P-256 key-agreement private key, generated in and
   confined to the Enclave. The Keychain holds a reference blob usable only by this Mac's
   Enclave, never the key itself.
3. **A symmetric key is derived.** The Enclave key agrees with its own public key; the shared
   secret goes through HKDF-SHA256 (salt `app.faceid.vault.v1`) to 32 bytes. Deterministic so
   it reproduces across launches, computable only inside the Enclave holding the private half.
4. **AES-GCM seals it.** Authenticated, so a tampered blob fails to open rather than decoding
   to attacker-chosen data. The sealed box is written to the Keychain as a generic password
   under service `com.gazeunlock.Gaze`, with
   `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and synchronization disabled.

## Using it

`LockWatcher` starts the camera on `com.apple.screenIsLocked` and stops after a bounded search
window. A match must hold for the interval configured in `LockWatcher`. Immediately before any keystroke is
posted, the lock state is re-read from the window server — `CGSSessionScreenIsLocked`, not the
app's cached flag — because the user can unlock with Touch ID while recognition runs,
and keystrokes posted after that land in whatever application is now focused.

The password is then posted as a single Unicode `CGEvent` followed by Return, via the HID event
tap. This requires Accessibility permission, granted explicitly by the user.

The password-submission backend also checks for a locked, logged-in console session owned
by the current user before reading the vault, after reading it, and before each event.
Cancellation, pause/backend changes and event-posting permission are checked at those
boundaries. Events use a private source with cleared modifier/repeat flags. All four
text/Return down/up events are prepared before posting; creation or payload round-trip
failures throw rather than silently sending Return. Empty and control-character passwords
are refused rather than transformed.

These checks are not atomic with global event delivery and do not bind a particular login
field. Posted events do not prove that macOS accepted the password. There is no automatic
password retry or field clearing. A stopped partial submission may leave input in the field.
The backend's readiness check now distinguishes Keychain errors from a missing password;
the older Settings/setup presence helper still needs migration.

September 12, 2026: this backend was exercised with dummy credentials and an in-memory
event sink, using a harness that is not published here. No real input is posted. The later hardening pass
corrects LockWatcher's submission/success accounting and binds it to a session UUID rather
than the console-set key absent on the inspected host. This does not claim that the live
intermittent password failure is resolved; actual lock-screen delivery remains untested.

## Limits

**The face is not a cryptographic factor.** Recognition gates *when the app chooses to type*.
It is not an input to the encryption, and no face is required to derive the key. Anything
running as this user with the app's code identity can call `PasswordVault.password()` and read
plaintext. What the Enclave buys is machine binding, not resistance to a local attacker.

**The password is recoverable by design.** It must be reproduced exactly in order to be typed,
so it is encrypted rather than hashed. "Encrypted at rest, bound to this Mac" is accurate; "we
cannot read your password" is not, and the app does not claim it.

**No biometric ACL on the item.** No `SecAccessControl` with `.userPresence` or
`.biometryCurrentSet`, and `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` rather than something stricter.
This is a convenience choice for hands-free credential replay, not a requirement for all
autofill secrets. A separate, opt-in authentication-protected autofill vault is pending review.

**Not TrueDepth.** Apple's Face ID measures face geometry with a structured-light projector. No
Mac in this design uses one. This app reads a flat camera image. Its optional anti-spoof model
and now-mandatory lock-screen movement challenge are not equivalent to depth sensing.
Autofill instead requires fresh macOS owner approval in addition to its face check. A photograph bypass has not
been established by this review; resistance to photographs and video needs physical testing.

**Presence is not consent.** A face match does not establish that the owner initiated a
particular command. This is why face-only PAM and legacy XPC authorization are disabled.
Re-enabling them needs independently verified caller and account identity, fresh deliberate
owner approval bound to the request, safe cancellation, and reviewed root-owned installation.

**Remaining review work.** Autofill's budget, session cancellation and mandatory owner gate
now have isolated tests, but the real Accessibility/LocalAuthentication interaction still
needs validation. Advancing frames prove processing freshness, not liveness or trusted sensor
capture time. Face-enrollment rename/removal still has silent failure paths, portrait cleanup
can fail silently, and the account-password presence helper still collapses read errors into
absence. The saved-app transaction work does not fix those separate paths. Same-user
tampering, multiple concurrent writers, installer ancestry and ACLs, biometric accuracy,
and real Accessibility behavior need validation. This is not a complete security audit or
a claim that the app resists arbitrary same-user malware.

**Recognition is a similarity threshold, not an identity proof.** Cosine similarity against
enrolled embeddings, above a fixed threshold. Measurably separates the enrolled user from other
people in testing, but it is not equivalent to a biometric assurance level.

## Mitigations that are present

- Credential-release face checks require the enrolled built-in camera. This narrows virtual
  camera exposure but does not attest the driver, physical sensor or frame provenance.
- The lock-screen flow has a six-failure budget; autofill has its own five-attempt budget.
- The vault key can be destroyed, which renders every stored blob permanently unreadable.
- **Just recognise me** does not replay an account password. Selecting it does not delete
  an existing account password or saved autofill secrets; deletion must be requested and confirmed.

## Preserved priorities and release gates

Original priorities from September 11, 2026, updated on September 12. None are deployment-verified.

1. **Storage reliability first.** Maintain the saved-app failure/recovery tests. Extend
   visible error handling to the remaining enrollment, portrait and password-presence paths.
   Verify real Keychain failures separately; the regression suite injects a memory vault.
2. **Exact-app pinning next.** Keep the picker URL and fresh approval on signer replacement.
   The signing requirement, not the path alone, authorizes a running app. Updates satisfying
   the approved requirement remain trusted; this is not a hash pin of every future version.
   Live process-restart and real owner-approval UI tests remain required.
3. **Credential-release safeguards.** The source now has the separate autofill budget,
   session lease, fresh owner gate and frame-stall handling. Validate these together with
   the real target app and macOS prompt on an isolated account. Fresh frames alone must
   never be described as liveness or photo/video resistance.
4. **Optional high-security mode.** Separate autofill keys and secrets from hands-free
   lock-screen credentials. Investigate OS-enforced key access with owner authentication;
   a separate `LAContext` prompt alone is not an access-control policy on the key. Explain
   that Touch ID or account-password prompts reduce hands-free convenience before opt-in.
   Design migration, cancellation, recovery and key invalidation before changing behavior.
5. **Website identity.** Keep browser filling blocked until credentials are bound to a
   verified website identity. Investigate a credential-provider extension rather than
   scraping browser UI. A browser denylist and a signed browser process do not verify origin.
   Do not enable web filling merely because a provider API returns domain suggestions.
6. **Regression tests (not published).** The storage suite covers
failed add/update/delete operations, recovery/restart, exact selection, signer approval,
stale edits and cancellation with dummy credentials. It cannot be run from this repository.
Focus switching, process restarts during release, denied Accessibility writes, lock/session
cancellation and camera stalls are not covered by the storage suite and still need
controlled integration tests.

### Design investigation, not implementation

Apple's installed macOS 26.5 SDK headers were reviewed for the optional designs:

- `Security/SecAccessControl.h` defines user-presence, current-biometry-set and private-key
  usage flags. Current-set biometry can invalidate access after enrollment changes. Validate
  the supported flag combination on target Macs with a disposable key before selecting one.
  Vault migration remains unimplemented. Fresh autofill owner prompts have since been added
  at the application layer, without changing the vault key's ACL.
- `LocalAuthentication/LAContext.h` documents zero reuse duration as disallowing reuse of an
  earlier biometric unlock. The existing replacement gate creates a new context and sets
  zero; automated tests inject the approval decision rather than prompting a real owner.
- `AuthenticationServices/ASCredentialProviderViewController.h` exposes system-provided
  service identifiers and a user-interaction-required error path. Its identifier list can
  be empty or contain multiple domain candidates. Define exact matching, related-domain and
  subdomain policy, IDN handling, cancellation and user selection before releasing secrets.
  Review extension entitlements, signing, key-sharing and browser support separately.

Online documentation could not be checked in this session because the browser was not
connected. SDK inspection is not proof of the latest platform behavior or a working prototype.

### Deployment and open-source release

Source changes and passing tests do not establish that any installed app, PAM module,
authorization plugin, LaunchAgent or authorization policy is updated or safe. Review installed
versions, code signatures, ownership/permissions and password/Touch ID fallback separately.
Do not install, remove or modify system authentication components as part of these tests.

Before opening the repository, review tracked files **and history** for credentials, face
images/templates, logs, private keys, proprietary assets and model/data licensing. Keep dummy
fixtures reproducible and production data out of tests. Resolve the model-license questions
in `CONTRIBUTING.md`/`NOTICE.md` and establish a private vulnerability-reporting route before
release. No repository-history or license audit is claimed by this checkpoint.

The later source hardening also changes camera/LockWatcher lifecycle handling without lowering
thresholds. Camera frames, usable face detection, posted password events and confirmed OS
unlock are separate states. Neither storage tests nor an isolated successful build establish
live lock-screen correctness or the safety of installed components.

## Where to look

| File | Contains |
| --- | --- |
| `Sources/Security/PasswordVault.swift` | Verification and storage. Nothing else touches the password. |
| `Sources/Security/SecureVault.swift` | Enclave key, derivation, sealing. |
| `Sources/Security/Keychain.swift` | What is written, and with which accessibility class. |
| `Sources/Security/LockWatcher.swift` | Lock trigger, sustained-match requirement, pre-keystroke re-check. |
| `Sources/Security/UnlockBackend.swift` | The keystroke replay. |

## Fixed

**Password in `argv`.** Verification used to run `dscl . -authonly <user> <password>`, placing
the password in a subprocess argument vector, readable from the process list by anything running
as the same user for the duration of the call. Replaced with in-process `ODRecord.verifyPassword`,
which is the API `dscl` wraps.

## Reporting

Open an issue. Findings about this document are as welcome as findings
about the code.
