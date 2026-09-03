# Security

How the app handles your account password and your faceprint, and what it does not defend
against. Everything here is checkable against the files named at the bottom.

## What is stored

| Item | When |
| --- | --- |
| Faceprint | Always, once enrolled. Numeric embeddings, not images — no photographs are kept. |
| Account password | Only under the **Unlock my Mac** backend. The default, **Just recognise me**, never asks for one. |
| Failed attempt count | Always. Six failures disable Gaze until the account password is entered. |

All three go through the same sealing path.

## Storing the password

1. **Verified before it is kept.** `ODRecord.verifyPassword` checks it against the local
   directory. A wrong password is rejected and never written. The check unlocks nothing and
   consumes no system attempt counter, so a typo cannot lock the user out of their Mac.
2. **A Secure Enclave key is created.** A P-256 key-agreement private key is generated in and
   confined to the Enclave. Gaze stores only its opaque representation in the protected vault
   file; the private key never leaves the Enclave.
3. **A symmetric key is derived.** The Enclave key agrees with its own public key; the shared
   secret goes through HKDF-SHA256 (salt `app.faceid.vault.v1`) to 32 bytes. Deterministic so
   it reproduces across launches, computable only inside the Enclave holding the private half.
4. **AES-GCM seals it.** Authenticated, so a tampered blob fails to open rather than decoding
   to attacker-chosen data. The sealed records and the opaque Enclave-key representation are
   written atomically to `~/Library/Application Support/Gaze/vault.bin`, with directory mode
   `0700` and file mode `0600`.

## Migrating older builds

Builds before 0.4 kept the key representation and each sealed record as separate Keychain
items. The first 0.4 launch reads that legacy service in one query, verifies every record,
writes the authenticated vault file, and then removes the old items. After migration, normal
launches do not query Keychain, which prevents the repeated authorization sheet caused by
fetching the same old item for each record. If access is declined, Gaze remembers that failed
decision for the current process so its separate startup readers do not fan out more prompts.

## Using it

`LockWatcher` starts the camera on `com.apple.screenIsLocked` and stops after a bounded search
window. A match must hold continuously for two seconds. Immediately before any keystroke is
posted, the lock state is re-read from the window server — `CGSSessionScreenIsLocked`, not the
app's cached flag — because the user can unlock with Touch ID during the confirmation
animation, and keystrokes posted after that land in whatever application is now focused.

The password is then posted as a single Unicode `CGEvent` followed by Return, via the HID event
tap. This requires Accessibility permission, granted explicitly by the user.

## Limits

**The face is not a cryptographic factor.** Recognition gates *when the app chooses to type*.
It is not an input to the encryption, and no face is required to derive the key. Anything
running as this user with the app's code identity can call `PasswordVault.password()` and read
plaintext. What the Enclave buys is machine binding, not resistance to a local attacker.

**The password is recoverable by design.** It must be reproduced exactly in order to be typed,
so it is encrypted rather than hashed. "Encrypted at rest, bound to this Mac" is accurate; "we
cannot read your password" is not, and the app does not claim it.

**No biometric ACL on the vault.** The Enclave key uses device-only, after-first-unlock access
without `.userPresence` or `.biometryCurrentSet`. The lock screen is precisely when no user is
present to authenticate. The vault's AES-GCM authentication still rejects edits, but it does
not make a local process running as this user disappear.

**Not TrueDepth.** Apple's Face ID measures face geometry with a structured-light projector. No
Mac has one. This reads a flat image from the built-in camera and therefore cannot distinguish a
face from a photograph of one. The optional liveness check is off by default and no anti-spoof
model is bundled.

**Recognition is a similarity threshold, not an identity proof.** Cosine similarity against
enrolled embeddings, above a fixed threshold. Measurably separates the enrolled user from other
people in testing, but it is not equivalent to a biometric assurance level.

## Mitigations that are present

- Only the built-in camera is trusted by default, and it must be the device enrolled on
  (`requireBuiltInCamera`) — this is the defence against frame injection through a virtual camera.
- Six failed attempts disable Gaze until the account password is entered.
- The vault key can be destroyed, which renders every stored blob permanently unreadable.
- Selecting **Just recognise me** removes the password from the design entirely.

## Where to look

| File | Contains |
| --- | --- |
| `Sources/Security/PasswordVault.swift` | Verification and storage. Nothing else touches the password. |
| `Sources/Security/SecureVault.swift` | Enclave key, derivation, sealing. |
| `Sources/Security/Keychain.swift` | One-time compatibility migration for pre-0.4 items. |
| `Sources/Security/LockWatcher.swift` | Lock trigger, sustained-match requirement, pre-keystroke re-check. |
| `Sources/Security/UnlockBackend.swift` | The keystroke replay. |

## Fixed

**Password in `argv`.** Verification used to run `dscl . -authonly <user> <password>`, placing
the password in a subprocess argument vector, readable from the process list by anything running
as the same user for the duration of the call. Replaced with in-process `ODRecord.verifyPassword`,
which is the API `dscl` wraps.

## Reporting

Open an issue, or say so in the Discord. Findings about this document are as welcome as findings
about the code.
