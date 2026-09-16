# Release editor browser result

The fixture imports the actual current ReleaseComposer, with stub router/upload
and deferred POST responses. It performs no real upload, save or authentication.

- Rename 1.0 → 1.1 sends one POST containing previousTag 1.0. Inputs are disabled
  while saving. A 409 keeps version 1.1 in the editor and performs no navigation.
- A completed synthetic build attachment survives a subsequent upload failure.
- During that second pending upload, Save is disabled and no POST is added.
- Retrying the rename sends the retained attachment and one POST. A confirmed
  tag 1.1 response navigates to /releases/1.1; no DELETE is ever issued.

Independent combined tests execute current storage, store and API with real SDK
precondition error classes: concurrent rename/add preserves both, colliding
renames have one winner, delete-before-rename cannot resurrect, malformed input
is rejected before storage, and non-admin writes cannot reach the catalog.
The SDK transport is in memory; production credentials/Blob were not exercised.
