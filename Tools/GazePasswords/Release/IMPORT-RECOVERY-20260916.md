# Import recovery notice — 2026-09-16

## Changed file
- `Tools/GazePasswords/Live/LiveImportView.swift` only.

## What changed
- Added `@State private var wasInterruptedByLock = false` next to `review`/`importSession`. Non-sensitive `Boolean`; holds no CSV data, file URL, filename, username, count, password, or entry.
- `.onChange(of: store.sessionID)` now captures `wasInterruptedByLock = wasInterruptedByLock || review != nil || choosingFile` **before** calling the unchanged `clearReview()` and clearing `fileSession`/`choosingFile`. `clearReview()` still discards parsed secrets (`review`, `importSession`, `failure`, `message`) immediately and does not touch the flag, so the notice survives the lock→unlock transition with no credentials retained.
- Secondary notice rendered above the locked/unlocked import controls:
  - Locked: "The vault locked, so the import review was cleared. Choose the CSV again after unlocking."
  - Unlocked: "The vault locked, so the import review was cleared. Choose the CSV again."
  - Style: `.font(.callout).foregroundStyle(.secondary)`.
- Flag cleared on: both explicit file-choice buttons ("Choose CSV file…", "Choose another file"), successful `commit()`, window-will-close ("Import passwords"), and `onDisappear`.
- Untouched: `read(_:)`/`commit()` activity and session guards, all lock notifications (`didResignActive`, `sessionDidResignActive`, `willSleep`, `screenIsLocked`), `store.busy` behavior, and default keyboard actions.

## Compile / layout check
- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash Tools/GazePasswords/test-live-layout.sh /tmp/suki-live-layout` passed (compiles with `-warnings-as-errors`; no real app launch, auth, vault read, or file picker).
- Output: `/tmp/suki-live-layout` (import/settings/vault light/dark PNGs).

## Behavior and limitations
- Verified by code read-back: interruption sets the flag only when a review or file picker was active; idle session changes show no notice.
- Limitation: offscreen captures render `LiveImportView` with default (locked, `wasInterruptedByLock == false`) state, so `import-light/dark.png` do not show the new notice. `review`/`choosingFile`/`wasInterruptedByLock` are private `@State` and were not injected (production APIs not modified for tests), so the lock→unlock notice path and the unlocked wording variant were not exercised by the captures; they were verified by reading the affected flow only.

Lead integration correction: preserve an already-set notice across the next session change (unlock). Reassigning solely from review/choosingFile incorrectly cleared it on unlock, since lock had already discarded both.
