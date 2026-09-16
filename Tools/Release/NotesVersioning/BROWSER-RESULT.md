# Notes versioning: browser result, September 16, 2026

Root exercised the corrected staged editor in BrowserOS neo through agent-browser,
using the local fixture at 127.0.0.1:18473. The fixture imports the edited component;
router, button styling, responses and note content are synthetic. No production
account, email, Blob store or notes were accessed.

Passed:

- Save A, type B before acknowledgement: B remains visible and unsaved. The next
  B request carries A's acknowledged version, then reports Saved after acceptance.
- A 409 keeps draft C and the reload affordance. Cancelling its confirmation keeps
  draft, error and version, with no navigation or refresh.
- A subsequent network failure keeps the known conflict and recovery affordance.
- HTTP 200 with version `missing` is refused: no Saved, no version advancement,
  no refresh. Successful acknowledgements require 64 lowercase hex characters.
- Two synchronous Save clicks produce one pending request.
- Textarea Ctrl+S sends one request with the newest acknowledged version.
  The same key event on the document body is not intercepted and sends nothing.
- Successful retry clears the conflict. The browser error log was empty.

Reload acceptance was not driven; the native confirmation was exercised with cancel.
The production component's types and lint pass. The current route harness has 18
passing cases with a stubbed document service; the notes-versioning and existing
metadata/privacy suites execute real source against a synthetic SDK and real local
filesystem. These results do not verify production Blob or real administrator access.
