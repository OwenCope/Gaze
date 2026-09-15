# Droppy Code design reference — selective study (2026-09-16)

Owner-approved reference: https://gitlab.com/droppyformac1/droppy-code ("they love it;
borrowing some ideas permitted, not copying the whole interface").
This is a new design-reference study, not a follow-up to any previous head's audit.

## Source identity and method

- Local `/Users/owencope/Developer/Droppy` is **empty** (0 entries) — it is not a checkout
  of the reference repository and was not used.
- All reference evidence comes from the **public GitLab repository** `droppyformac1/droppy-code`,
  read-only via the project page and the repository-tree / raw-file REST API. No reference
  code was cloned, executed, or copied into this worktree.
- Bounded set reviewed (actual UI sources, `main` branch):
  - `DroppyCode/Views/Settings/SettingsView.swift` (settings shell: search-filtered sidebar,
    chrome overlays, per-page controls, provider status rows, archive delete, About/credits)
  - `DroppyCode/Views/Sidebar/SidebarView.swift` (thread list: search + arrow-key navigation,
    row-anchored delete popover, settled folding, project/activity layouts)
  - `DroppyCode/Views/Tour/TourPages.swift` (six-page welcome tour of real captures)
  - `README.md` (raw), `LICENSE` (raw), project page (licence badge: GNU AGPLv3)
- Compared against Gaze: `Sources/App/SettingsView.swift`, `Sources/App/Theme.swift`,
  `Sources/Setup/SetupScaffold.swift`, `Sources/App/NotchSettings.swift`,
  `Tools/GazePasswords/Live/LiveVaultView.swift`,
  `Tools/GazePasswords/Live/LiveSettingsView.swift`,
  `Tools/GazePasswords/Live/VaultSearchField.swift`.
- **Observed visuals vs source inference:** no rendered screenshots or running app were
  inspected — `docs/` captures and the website were not reviewed. Everything below about
  Droppy Code's look is inferred from SwiftUI source (layout, spacing constants, control
  choices, comments stating intent), not from observed pixels. Treat visual claims accordingly.

## Licence / attribution — can we reuse code?

- Droppy Code is **GNU AGPLv3 with §7 additional terms** (read `LICENSE` raw in full):
  (a) every copy/modified/covered work must preserve the attribution
  *"Droppy Code by Jordy Spruit (Droppy), https://getdroppycode.app"* in its About screen
  (or equivalent), README, and source-file copyright notices, and preserve
  `THIRD_PARTY_NOTICES.md`; (b) modified versions must be marked modified and must not
  present as Droppy Code; (c) **no rights to the names "Droppy"/"Droppy Code", the icon,
  or other marks** (see `TRADEMARK.md`). README "Credit" section repeats the ask.
- So: studying ideas is fine; **lifting source files or UI copy into Gaze would attach
  AGPLv3 copyleft plus a mandatory About/README/header credit line** — a lead-level
  licensing decision, not a head-level one. Default taken here: **original implementations
  of design ideas only; no copied code, copy, branding, icons, or assets.**
- Note for the lead: Droppy Code itself descends in part from T3 Code (MIT) and ports
  Zeron's working indicators (MIT) and TourKit (MIT) — even its own About lists these.
  Any future code-level reuse would need the full `THIRD_PARTY_NOTICES.md` chain, not
  just the AGPL header.

## What was deliberately NOT taken

- The tinted per-page icon palette (`SettingsPage.tint`: blue/purple/teal/orange…).
  Gaze's `Theme.swift` documents the opposite, considered decision (monochrome tiles;
  colour reserved for state/recognition). Droppy's palette serves a fixed 8-page sidebar;
  importing it would undo a Gaze rule for no gain.
- The 780×580 sidebar+detail settings shell. Gaze's toolbar-centred pane picker
  (`GazeSettingsPicker`, `SettingsView.swift:119-123`) with a 620pt centred column is
  the right shape for 4 panes; Droppy's shell solves an 8-page problem Gaze doesn't have.
- Live-preview settings cards (`ChatTextSizeCard` chat sample; `NotchAppearancePreview`
  already exists in Gaze `Sources/App/NotchSettings.swift:166`) — Gaze already does this
  where it matters. No recommendation.
- Welcome-tour mechanics: Droppy's six real-capture tour (`TourPages.swift`, re-openable
  via About › "Show") overlaps Gaze's re-openable onboarding
  (`SettingsView.swift:326-337` "Open Onboarding"). Gaze's flow is functional setup, not a
  slideshow; converting it is out of scope for this study.

## Recommendation 1 — Settings search with a keyword index (adopt when panes grow)

**Reference evidence (observed source):** `DroppyCode/Views/Settings/SettingsView.swift` —
`SettingsPage.keywords` per page (e.g. providers page indexes "codex, claude, … api key,
quota, credits"); `visiblePages` filters sidebar rows on the trimmed query; `.onChange(of:
visiblePages)` auto-selects the first match so the detail pane never sits on an
unlisted page; empty result renders "No results" + "Try a setting or a provider name."
Search submits to the first match (`SidebarSearchField … { if let first … }`).

**Where it fits Gaze:** `Sources/App/SettingsView.swift` — the toolbar picker currently
switches 4 panes with no way to find a buried row (walk-away lock, password-storage
explanation, movement count). As panes/rows grow, add a search field (toolbar-adjacent
or atop the detail column) indexing pane titles plus per-row keywords
("walk away", "absence", "password storage", "enclave", "spoof", "login items").
Mirror the two behaviours that make Droppy's version work: auto-select first match, and
a "No results / try …" empty state rather than a blank pane.

**User problem solved:** findability — a user who revokes camera access in System Settings
and opens Gaze Settings looking for "camera" currently has to know it lives under Unlock ›
Permissions. Search meets them where they are.

**Remains distinct:** keep Gaze's centred toolbar picker, 620pt column, monochrome tiles,
and sentence-case groups. Borrow the *mechanism* (keyword index + first-match select +
empty state), none of the chrome.

## Recommendation 2 — Destructive confirmations as row-anchored popovers that say what stays

**Reference evidence (observed source):** `DroppyCode/Views/Sidebar/SidebarView.swift` —
`deletePopover(for:on:)` asks the delete question in a popover on the row itself, never a
window sheet ("Clicking away or pressing Escape keeps the thread"); `DeleteThreadPopover`
names the thread and states what survives ("…and its history will be removed. Files in
your project stay as they are."); the confirmed delete runs only after the popover closes
(`confirmDeletion`/`carryOutConfirmedDeletion`, with a comment explaining the crash this
ordering avoids). Same pattern in Settings: `ArchiveDeleteAllButton` confirms via popover
hanging off the button, honouring the "Confirm before deleting" setting.

**Where it fits Gaze:** two destructive actions currently fire on one click behind only a
biometric gate, with no confirmation and no "what stays" copy —
"Revoke" stored password (`SettingsView.swift:581`, `revokePassword()` at `:1406`) and
FaceTile removal (`SettingsView.swift:397-402`, `FaceTile` at `:1436`, whose comment
already says removal "appears on approach rather than sitting there as a permanent
invitation"). Adopt the popover shape for both, with Droppy-style survival copy:
Revoke → "Your Mac account password is unchanged; only Gaze's stored copy is removed."
Remove face → "Your other enrolled faces keep working." (single-face case: "You will need
to enrol again to use face unlock.")

**User problem solved:** irreversible-action anxiety at the exact moment of highest stakes
(password handling, biometric enrolment). A sheet would yank context away from the row the
user is reasoning about; the popover keeps the question where the answer's consequences
are visible. Error recovery: clicking away cancels — the safe default.

**Remains distinct:** keep `BiometricGate` as the authorisation step (Droppy has no
equivalent); keep Gaze's capsule glass buttons and `StatusLine` error reporting
(`passwordError` stays inline under the row). Borrow placement + survival-copy, not styling.

## Recommendation 3 — Arrow-key-navigable vault search (Gaze Passwords)

**Reference evidence (observed source):** `DroppyCode/Views/Sidebar/SidebarView.swift` —
`SidebarSearchField(text:prompt:onSubmit:onMove:)`; `moveSearchSelection(by:helpers:)`
walks Up/Down through results with the row highlighting "exactly as a clicked one does",
Enter selects (`onSubmit` picks the first result). Search results are cached per query so
keystrokes, submit, and arrows share one lookup.

**Where it fits Gaze:** `Tools/GazePasswords/Live/VaultSearchField.swift` is a plain
`TextField` with a clear button — no arrow handling, no Enter-to-select (confirmed by grep:
no `onMoveCommand`/arrow handling anywhere under `Tools/GazePasswords`). The vault list in
`LiveVaultView.swift:27-38` already selects entries (`store.selected`) and already has
thoughtful `ContentUnavailableView` empty states with recovery actions (`:98-120` — "Clear
search", "Search all passwords", "Add a password"), so the missing piece is specifically
keyboard traversal: Up/Down moves selection through filtered entries, Enter opens the
detail, highlighting matches a clicked row.

**User problem solved:** a password manager is used mid-flow (filling a login elsewhere);
forcing pointer use for every lookup breaks that flow. Keyboard search-to-select is the
difference between a vault that assists and one that interrupts.

**Remains distinct:** keep the capsule glass search field, the `PasswordSectionPicker`
toolbar switcher, and the existing empty-state copy. Borrow only the key handling and the
"highlight like a click" selection contract.

## Constraints honoured

- No edits to Gaze UI sources or the reference repo; this study owns only this file.
- No git inspection/operations, no builds, no live preferences/camera/credentials, no app
  restarts, no external messages, no publication.
- Verification: re-read the cited Gaze regions after drafting (`SettingsView.swift`
  hero/picker at `:113-123`, password row at `:553-624`, `revokePassword` at `:1406-1418`,
  `FaceTile` at `:1430+`; `NotchAppearancePreview` at `NotchSettings.swift:166-218`;
  `VaultSearchField.swift` full file; `LiveVaultView.swift:23-120`) to confirm each
  recommendation targets a real gap and not already-implemented behaviour
  (live preview and empty-state recovery were checked and explicitly excluded).
