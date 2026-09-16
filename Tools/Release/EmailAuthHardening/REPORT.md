# Email sign-in integration — September 16, 2026

Applied locally to `/Users/owencope/Developer/gaze-site`. Nothing deployed;
all mail and storage tests used synthetic credentials and transports.

## Current behavior

Email codes are bound to a random 128-bit challenge and a ten-minute HMAC cookie.
Legacy cookies are refused. Normalization requires string input, trims/lowercases
email, rejects control characters, and accepts exactly six code digits. Expiry
is exclusive: the code is refused at its deadline.

Shared private Blob records limit each challenge to five wrong guesses and one
successful use. Fixed clock-hour buckets allow five sends per exact normalized
email and twenty per source IP. IP accounting is best-effort; it depends on the
hosting proxy's forwarded-address policy and is not a universal abuse bound.
The limits do not imply a rolling-hour quota or prevent abuse across many addresses.

Existing records are updated with a nonempty ETag and `ifMatch`. The first
counter write uses `allowOverwrite: false`; creation races re-read the winner.
Missing ETags, unexpected responses, corrupted counters and outages fail closed.
CAS retries are bounded, so heavy contention can temporarily refuse requests.

Non-development deployments require shared private storage. A private token is
explicit, or a private store ID must be paired with explicit `VERCEL_OIDC_TOKEN`.
Reusing the public token/store is refused. Local development with no Blob flags
uses a process-shared development store; this is not serverless protection.
Email UI also requires AUTH_SECRET, RESEND_API_KEY and SIGNIN_EMAIL_FROM.

The route returns no code or challenge record. Delivery has a ten-second timeout;
a failed delivery clears the challenge and returns an error without a cookie.
The form has named inputs, prevents duplicate submissions, offers a fresh code,
and recovers after network errors. Callback navigation accepts local paths only.
OAuth/admin behavior is otherwise retained.

## Root corrections to the proposal

- Closed first-write counter races; the proposal unconditionally overwrote a
  missing counter, allowing concurrent initial sends to undercount.
- Used the installed SDK's error classes with `instanceof`. These subclasses
  inherit `name: Error`, so matching strings did not recognize CAS conflicts.
- Required a real ETag and valid counter shape; refused non-200/corrupt reads
  instead of treating them as zero/missing.
- Kept a shared development store across send/verify requests and refused memory
  in standalone production, not only on Vercel.
- Matched private OIDC/credential configuration to the metadata policy.
- Added server-only module guards, exclusive expiry, record/email/expiry binding,
  control-character rejection, and removed plaintext code from flow results.
- Minted cookies before sending so missing signing configuration cannot send an
  unusable code; added delivery timeout and explicit route success narrowing.
- Added safe callback paths and fixed form labels, retry, pending and error states.

## Files and verification

`email-auth-hardening.patch` contains the integrated changes to seven site files:
email-code, email-challenge-store, safe-callback, signin-code route, auth,
signin page, and email-sign-in. The `.proposed.*` files now mirror that corrected
implementation; store imports use a relative path for standalone tests.
The patch is an artifact for review; it is already applied locally.

- `node run-tests.mjs --current`: 74 checks on parsing, expiry, policy, state,
  configuration and source wiring. Functional modules use current site code.
- `node test-blob-concurrency.mjs --current`: 21 checks, including simultaneous
  initial sends, shared IP budget, consumed-code races, failed-attempt races,
  bad storage data and configuration. Real installed SDK error classes with an
  in-memory SDK transport; no service calls.
- `node test-route.mjs`: 30 checks executing the actual Next route with real
  NextResponse/cookies and a synthetic mail/storage transport; includes callback
  URL refusal and route-issued-code replay.
- Isolated full production `next build` and HTTP smoke passed after integration.
  Build logs: `build/website-combined-review.log` and `build/website-build-check/`.

Direct Node TypeScript tests can emit a module-type warning because this Next
project does not set package `type: module`; no package mode was changed merely
to suppress that test-runner warning.

## Before any future deployment

Provision/configure the dedicated private store and complete the metadata copy
and comparison described in `../MetadataPrivacy/`. No live store was created,
read, migrated or cleaned by this work. Authentication records use separate
`auth/challenges/` and `auth/sends/` prefixes; Blob has no automatic TTL, so a
reviewed retention job is still needed. Do not delete current-hour counters or
unexpired challenges. Old cookies require requesting a new code after cutover.

Live Resend/Blob configuration and CAS behavior still need a controlled deployment
acceptance test. These fixtures prove the code against the documented SDK contract,
not production service behavior. Email remains phishable mailbox authentication;
these changes bound guessing/replay/sending rather than making it strong identity.

## Browser form verification

A temporary /email-ui-review route rendered the actual EmailSignIn component in
a separate isolated build, with synthetic providers/CSRF/send responses. It never
entered the real site source. The form reached code entry, kept retry controls
after failure, and recovered from an aborted callback. No email or real account
was used. Root additionally holds the send lock through response parsing, adds a
15-second send timeout, and distinguishes credential rejection from service errors.
The extra test server was stopped; the owner preview contains no fixture route.
