# UpdateLifecycleRegression

Stopping the update schedule cancels cleanly instead of reporting a false
offline failure.

`run.sh` compiles the real `Sources/App/ReleaseUpdateChecker.swift` and
`ReleaseURLPolicy.swift` with `Tests.swift` (Xcode-beta toolchain) and runs
six checks. `Tests.swift` is the only test double: a `URLProtocol` stub serves
one canned feed or one canned error, so no production request ever leaves the
process. Persisted state lives in temporary `UserDefaults` suites that are
removed afterwards; the owner's defaults and TipKit are never touched.

Covered:

- start-twice issues one request, and normal success schedules
  `lastReleaseCheck`.
- stop-before-delay issues no request and leaves state idle; stopping twice
  is harmless.
- stop in-flight restores the prior idle state — no false offline failure,
  no success, no timestamp.
- restart after stop checks again.
- two independent instances each check and timestamp without touching
  `.shared` (also asserted on the production source by `run.sh`).
- an ordinary network failure still reports "Couldn't reach gazeunlock.com."
  and advances no timestamp.

Run: `bash Tools/UpdateLifecycleRegression/run.sh`
