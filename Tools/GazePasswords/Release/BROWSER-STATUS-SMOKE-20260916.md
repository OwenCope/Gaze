# Browser native-host status check — September 16, 2026

The actual BrowserOS neo extension action popup reported:

> Connected to Gaze Passwords. No credentials accessed.

This closes the previously unverified local status path: extension worker →
registered native bridge → signed running Passwords service → validated reply.
It does not prove vault persistence, Fill/Save or face approval.

## Scope and method

- BrowserOS neo's installed executable, launched through agent-browser with a
  disposable /tmp profile and the current staged extension. No real browser
  profile, account or registration was modified.
- Copied the existing approved native-host manifest into that disposable profile;
  its original bytes still match after the check. The helper path was unchanged.
- Extension ID: dplcnjngbhocgeidhcgkiidilolbgadl.
- Current registered helper SHA256:
  ee0775a2aaa9f6a98696343b0eda60f0f171e215b0842a264be47bcb0f919c57.
- Opening popup.html as a normal tab was correctly refused by the sender.tab
  guard. No guard was changed. Opened the actual action popup through Chrome's
  action.openPopup API, then used its own DOM controls to expand About and press
  Check app connection. Read the resulting status from that popup's DOM through
  extension.getViews({type:'popup'}).
- The real helper process ran (PID14859 observed in system security logs).
  The existing Passwords service, PID51873, was left running; this check must not
  be represented as a test of a freshly relaunched Passwords executable.
- The normal-tab screenshot shows the deliberate refusal, not the successful
  action-popup result. The latter was read as text, not captured as a screenshot.

Only status was invoked. No page credentials, real vault data, Keychain unlock,
Fill, Save, camera test, face approval, screen lock or browser form submission.
The status handler creates an owner-session lease and updates last contact; it
returns no credential fields. Popup validation refuses replies carrying secrets.

No extension was installed into the owner's normal browser profile. A real
owner-assisted Fill/Save acceptance pass remains separate. Current source/build
readiness and distribution limitations remain in RELEASE-READINESS.md.
