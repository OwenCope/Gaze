# Browser Channel Review — `Sources/Browser/`

Scope: all five files read in full (`BrowserSocket.swift`, `BrowserProtocol.swift`,
`BrowserPeerTrust.swift`, `GazeBrowserApproval.swift`, `BrowserAppLocator.swift`),
plus `Sources/Security/AutofillSecurity.swift`, `PasswordVault.swift`, `SecureVault.swift`,
`Keychain.swift`, everything under `Sources/Autofill/`, `SECURITY.md`, the socket call
sites (`Sources/App/GazeApp.swift:303,357-362`; `Tools/GazePasswords/Live/PasswordBrowserService.swift`;
`Tools/GazePasswords/NativeHost/`), and `Sources/Security/UnlockExecutionPolicy.swift`.

Binding (stated explicitly): **filesystem Unix-domain sockets only — no network binding
anywhere.** `BrowserSocketListener` binds `AF_UNIX`/`SOCK_STREAM` at
`~/.gaze-browser/gaze.sock` (Gaze side) and `~/.gaze-browser/passwords.sock` (Passwords
side, in `Tools/GazePasswords/Live/PasswordBrowserService.swift:58`). No TCP, UDP, IP, or
loopback listener exists in the five files or their call sites.

## Verdict

On the evidence, a hostile local process running as the same user could **not** obtain a
saved password through this channel: `gaze.sock` never emits credentials (only a
single-use face attestation), and both listeners verify the peer's code signature
(identifier plus same-team requirement, from a kernel-supplied audit token) before
reading any message, which a same-user attacker cannot forge without the team's signing
key. Caveat: per `SECURITY.md`, current bundles are ad-hoc signed, under which even
legitimate peers fail the `anchor apple generic` check — fail-closed, but it means the
channel as reviewed has never passed peer verification in a production-signed build.

## High

No high-severity findings. The credential-bearing reply (`filled`, with plaintext
username/password) is constructed only in `Tools/GazePasswords/Live/PasswordBrowserService.swift:200-204`,
after per-request user entry selection, vault-unlocked/app-active checks, and a
request-bound Gaze attestation — never in the five reviewed files.

## Medium

- **The `filled` reply carries a plaintext password to whoever holds the socket.**
  `Tools/GazePasswords/Live/PasswordBrowserService.swift:200-204`,
  `response.password = entry.password`. A process running as the user that passes the
  `passwords.sock` peer check (identifier `com.gazeunlock.Passwords.BrowserBridge` plus
  the Passwords team's signing key) and completes the two human approvals does X
  (a normal fill) and gets Y (the saved username/password for the approved origin) —
  by design, but it means the entire confidentiality of saved passwords rests on the
  peer-signature gate in `BrowserSocket.swift:183`. Severity: MEDIUM (intended flow;
  listed so the weight on that one gate is explicit).

- **`verifyNativeBrowserParent` trusts a recycled pid with only a best-effort re-check.**
  `Sources/Browser/BrowserPeerTrust.swift:37-50`,
  `let parent = getppid()` … `guard getppid() == parent else`. A process running as the
  user that arranges for the bridge's parent pid to be recycled between the signature
  check and use does X (occupies the old parent pid) and gets Y (at most a second look
  at an unchanged pid number, not a re-verification of who holds it). Not exploitable
  on its own — the replacement would still need a browser-team signature — so this is
  defence-in-depth, not a hole. Severity: MEDIUM only in the formal sense; practically LOW.

## Low

- **Unauthenticated peers can hold listener slots and delay (not steal) fills.**
  `Sources/Browser/BrowserSocket.swift:158`, `Darwin.listen(descriptor, 4)`. A process
  running as the user does X (opens many connections to `passwords.sock`) and gets Y
  (immediate rejection at `BrowserSocket.swift:183`, but backlog/accept-loop churn
  that can stall a legitimate bridge past its retry window). No credential exposure;
  availability only. Severity: LOW.

- **Fill/save spam is a prompt-fatigue nudge, contained by origin binding.**
  `Sources/Browser/BrowserSocket.swift:183` (anyone may connect; only signed peers get
  answers) via `Tools/GazePasswords/Live/PasswordBrowserService.swift:88-117`. A process
  running as the user does X (sends `fill`/`save` requests, popping the Passwords vault
  forward via `activateVault()`) and gets Y (repeated approval dialogs — but never a
  credential, because release requires the user to pick an entry whose stored origin
  equals the request origin, plus a fresh face attestation bound to the same
  requestID/origin). Severity: LOW.

- **`status` on `gaze.sock` discloses readiness text, but only to signed peers.**
  `Sources/Browser/GazeBrowserApproval.swift:26-32`,
  `return request.response(operation: "status", error: readinessIssue)`. A process running
  as the user does X (sends `status`) and gets Y (strings like "Gaze is locked out" or
  "Add a face in Gaze") — only if it already passes the `com.gazeunlock.Passwords`
  signature check, so a hostile peer never reaches this. Severity: LOW.

## Checked and clean

- **Peer identity is a code signature, not a pid/bundle-id/path/secret.**
  `Sources/Browser/BrowserPeerTrust.swift:29-35`: `getsockopt(LOCAL_PEERTOKEN)` kernel
  audit token, `token.val.1 == geteuid()`, then `SecCodeCheckValidity` against
  `anchor apple generic and identifier "<fixed>" and certificate leaf[subject.OU] =
  "<own team>"`. Pids are never trusted directly; the identifier strings are fixed
  literals at all call sites (`GazeBrowserApproval.swift:18`,
  `PasswordBrowserService.swift` defaults, `BrowserBridgeMain.swift:30`,
  `GazeStatusProbe.swift:20`), never peer-supplied; the requirement template's
  interpolation is guarded by `^[A-Za-z0-9.-]+$` (`BrowserPeerTrust.swift:22-24`), so no
  requirement-injection. A same-user attacker can neither forge the audit token nor
  mint the team identifier.
- **Message inventory returns nothing hostile-usable on `gaze.sock`.**
  `BrowserProtocol.swift:59-65`: client operations are `status`, `fill`, `save`;
  `GazeBrowserApproval.swift:26,33` answers `status` with readiness text and `verify`
  with a bare `approved: true` attestation (`:127`) — `fill`/`save` addressed to
  `gaze.sock` fail `validateRequest` and get a generic error. No site enumeration, no
  credential bytes, no unlock of the Mac (the keystroke backend is never touched).
- **Approval is per-request, single-use, in-memory, and two-sided.**
  `BrowserProtocol.swift:77-92`: 90-second `BrowserRequestLease`, `consume()` sets a
  one-shot flag, bound to exact `requestID` + `origin`. Gaze side: face hold +
  liveness challenge with a visible panel naming the origin (`GazeBrowserApproval.swift:47-127`).
  Passwords side: user picks the entry, vault must be unlocked, app must be active, and
  the Gaze reply must `lease.consume(reply)` with matching ID/origin
  (`PasswordBrowserService.swift:190-198`). One approval never opens the channel
  generally; nothing is persisted anywhere (restart clears all state). No
  approval-free path to credentials was found.
- **Input parsing is bounded and throwing, with no content-derived indexing.**
  Length prefix capped at 65,536 (`BrowserSocket.swift:7,46,53`);
  `NativeMessageChannel.swift:7` same cap; malformed JSON/length throws and yields a
  generic error reply; no force-unwrap of decoded content, no array subscript from
  message bytes. (`buffer.baseAddress!` in `BrowserSocket.swift:58` and `readExactly`
  applies only to locally allocated non-empty buffers, not to peer bytes.)
- **Socket lifecycle fails closed.** Name allowlist blocks path traversal
  (`BrowserSocket.swift:126`); dir created `0700` and re-checked by `lstat`
  (uid/type/no group-other bits, `:130-133`) — a symlink at the path is not `S_IFSOCK`
  and is rejected (`:137`); stale sockets are unlinked only after an ownership check
  plus a live-connect probe (`:137-145`); fresh sockets get `chmod 0600` (`:158`);
  `unlink` on cancel/deinit (`:203`, `:157`). A pre-planted attacker socket yields
  `unavailable` (DoS), never hijack, because the peer signature is verified after
  `connect` (`BrowserSocket.swift:79`).
- **Listening while locked is fail-closed.** The Gaze listener starts at launch
  (`GazeApp.swift:357-362`) under any policy except `uiReview`
  (`UnlockExecutionPolicy.swift:27-29`) and is never stopped, so it accepts
  connections while the screen is locked — but every request builds an
  `AutofillSessionLease`, which is invalid when `CGSSessionScreenIsLocked`
  (`AutofillSecurity.swift:25-31`), and `verify()` refuses before touching the camera
  (`GazeBrowserApproval.swift:34-45`). Locked-machine callers get errors only.
- **`BrowserAppLocator` (the unused file): intended check is happening, just elsewhere.**
  `Sources/Browser/BrowserAppLocator.swift:4-14`: `open()` verifies a candidate app's
  signature (`verifyApplication`, same-team requirement) before launching it, and
  prefers the on-disk sibling over bundle-ID lookup. It has zero call sites in
  `Sources/` (confirmed by grep — only its own declaration), so no in-app behaviour
  depends on it and its absence removes no check from the Gaze side. Both directions
  that actually launch an app — Passwords→Gaze (`PasswordBrowserService.swift:41-43`)
  and bridge→Passwords (`BrowserBridgeMain.swift:32-34`) — go through it. Nothing
  intended is missing; it is dead code only from the Gaze target's perspective.

## Could not determine

- Whether production distribution will carry a Developer ID/team signature under which
  `anchor apple generic` succeeds for the legitimate peers; current ad-hoc signing
  (per `SECURITY.md`) fail-closes the channel, so end-to-end behaviour is unverified.
- Whether the `~/.gaze-browser` directory could be pre-created with compliant
  permissions by same-user malware before first run — harmless as far as could be
  determined (peer verification still gates everything), but not tested live.
- The contents/strength of the Passwords-side vault (`LocalPasswordStore`, archive
  encryption, lock semantics) — outside the five files; the `filled` reply assumes
  that store resists same-user reads.

## Shipping recommendation

**Disabled by default**: peer authentication, per-request bound approvals, and the
fail-closed lifecycle are sound, but the channel has never run under production
signatures, the Passwords vault is still a sample-data preview per `SECURITY.md`, and a
socket that can emit plaintext passwords should only go live after signed-distribution
and vault-storage review.
