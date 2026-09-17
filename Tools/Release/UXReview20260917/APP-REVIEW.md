# Gaze native UX review — 2026-09-17 (Finn 4)

Scope: current FaceID worktree source only. No app launch, camera, lock, credentials,
enrollment, preferences, or permission-prompt testing. No production edits.

Baseline: the owner screenshot
(`/Users/owencope/Library/Application Support/Droppy Code Dev/attachments/92121F9D-49CE-462D-AB5A-C2F19BF2DD77.png`)
is the **older running layout** — toolbar capsule with icon tabs + "Find a setting"
search, "Gaze is ready" card with right-side "Add a Face" / "Test Recognition"
buttons, and Unlocking / Permissions / Hardening groups. Current source already
moves enrolled faces below readiness and removes the duplicate enrolled-header
"Add a Face" button; root owns loading and visually verifying that newer build.
Everything below about the newer layout is **source inference**, not rendered evidence.

Already-completed work (not re-examined, not restated as findings): camera retry,
login-item error/approval recovery, release notes, readiness labels, wallpaper
retry, lesson pause handling, face-section reordering, segmented appearance selectors.

Skills read: `.agents/skills/swiftui-pro/SKILL.md` (full),
`.agents/skills/apple-design/SKILL.md` (full). Relevant swiftui-pro references
applied from the skill body: system text styles over fixed sizes, native controls
over hand-drawn ones, Dynamic Type / VoiceOver / Reduce Motion, hierarchy by
weight+size+leading. No threshold, challenge-enforcement, or unlock-algorithm
judgement — out of scope for this review.

Reopening behaviour: treated as hypothesis per brief. The safeguards in
`GazeApp.swift` (`AppActivation.bringToFront` visible-window-only loop,
deferred `returnToBackgroundIfIdle`, `restorationBehavior(.disabled)` on the
enrollment window, `SetupRequest.isDeliberateOpen` launch-flag gating) were read
but not touched and are not findings.

## Coverage

| Area | Source | Covered |
|---|---|---|
| App lifecycle, windows, activation/focus guards | `Sources/App/GazeApp.swift` | Yes — read fully |
| Settings shell: toolbar, search, hero, face/unlock/permissions/hardening, general, updates, about, credits, face tiles | `Sources/App/SettingsView.swift` | Yes — read fully |
| Tokens, glass, rows, buttons, fields, InfoButton, StatusLine | `Sources/App/Theme.swift` | Yes — read fully |
| Toolbar pane switcher (gaze-following segmented control) | `Sources/App/GazeSettingsPicker.swift` | Yes — read fully |
| Notch appearance / size / expressions guide | `Sources/App/NotchSettings.swift` | Yes — read fully |
| Notch animation preview (Play/Stop phase cycler) | `Sources/App/NotchAnimationPreview.swift` | Yes — read fully |
| Menu-bar status, Pause menu, Lock Screen Now, Add/Set Up, Test, Settings, Quit | `MenuBarContent` in `GazeApp.swift:449-540` | Yes — read |
| Setup flow: plan, progress, back rules, restart-on-appear, camera ownership | `Sources/Setup/SetupFlow.swift` | Yes — read fully |
| Setup chrome: title/message type, nav buttons, progress row | `Sources/Setup/SetupScaffold.swift` | Yes — read |
| Capture incl. camera-permission denied/restricted states | `Sources/Setup/SetupCaptureStep.swift` | Yes — read fully |
| Accessibility-permission step incl. pending state | `Sources/Setup/SetupPermissionStep.swift` | Yes — read fully |
| Done step: success / partial / failure, Settings + Test second actions | `Sources/Setup/SetupDoneStep.swift` | Yes — read fully |
| Recognition test vs camera-free distinction | `Sources/Enrollment/RecognitionTestView.swift`, `Sources/Enrollment/RecognitionTestPanel.swift` | Yes — read fully |
| Welcome / how / meet-Gaze / password lesson steps | `Sources/Setup/SetupWelcomeStep.swift` etc. | Partial — scaffold + flow contracts read; individual copy not line-audited |
| Rendered newer build | — | Not covered — root owns visual verification |

## Findings (new, prioritized, max eight)

### 1. Setup titles ignore Dynamic Type — the first screen a user sees (high)
- Anchor: `Sources/Setup/SetupScaffold.swift:24-25` —
  `.font(.system(size: isHero ? 38 : 30, weight: .semibold))`.
- User problem: every setup screen's title is a fixed point size, so a user who
  raised the system text size gets body copy that scales (`Typography.setupBody`)
  under a title that does not. First-run is exactly where this reads as broken.
- Recommendation (mechanical): use the scaled styles that already exist —
  `Typography.setupHero` for `isHero`, `Typography.setupTitle` otherwise.
  Source inference, not screenshot evidence.

### 2. Hero action column is a fixed 132pt — labels crowd on the daily screen (high)
- Anchor: `Sources/App/SettingsView.swift:449` (`.frame(width: 132)`) with the
  button stack at `SettingsView.swift:410-447` ("Resume Gaze" / "Review
  Permissions" / "Review Setup" / "Set Up Gaze" + "Test Recognition").
- User problem: two stacked large buttons with different label lengths in a
  132pt column either truncate ("Review Permissions") or wrap, on the row the
  user reads every day. The older-layout screenshot shows this same right-side
  stack already tight; the newer conditional stack ("Review Setup" /
  "Review Permissions") makes it worse.
- Recommendation (mechanical): widen the column to ~168pt and keep the existing
  equal-width pairing. Partly screenshot evidence (crowded right-side stack in
  the older layout), partly source inference (newer labels are longer).

### 3. Notch pickers and menus use fixed widths and a fixed 13pt label (high)
- Anchor: `Sources/App/NotchSettings.swift:13-17` (`NotchChoiceMenu` label
  `.font(.system(size: 13)).frame(width: 140)`) and `NotchSettings.swift:42-52`,
  `69-80` (Panel/Material segmented pickers `.frame(width: 330)`).
- User problem: fixed widths clip localized strings and force horizontal
  pressure in a 620pt column; the 13pt label also bypasses the app's own
  `Typography.control` scale, so it will not follow text-size settings while
  everything around it does.
- Recommendation (mechanical): drop the fixed widths to `minWidth` + flexible
  (`frame(minWidth: 140)` / remove the 330 caps) and set the menu label to
  `Typography.control`. Source inference.

### 4. Notch size rows are sliders-only with fixed label/value widths (medium)
- Anchor: `NotchAdjustmentRow` in `Sources/App/NotchSettings.swift:237-263`
  (104pt label, 48pt value, slider-only, no stepper/entry); the sibling
  "Reset Size" button at `:125-131` uses `.buttonStyle(.glass)` directly
  instead of `.gazeButton()`.
- User problem: keyboard-only and VoiceOver users get a slider with a spoken
  value but no way to type or step an exact offset; the fixed 48pt value field
  also clips "+" values at large text sizes. The reset button renders in a
  different shape from every other button in the window.
- Recommendation (mechanical): put `.gazeButton()` on "Reset Size" and add a
  `Stepper` (or an editable value field) bound to the same value next to the
  slider. Prefer this over new animation or features. Source inference.

### 5. Test Recognition "Try another movement" is a lone underlined link (medium)
- Anchor: `Sources/Enrollment/RecognitionTestPanel.swift:97-99`; nearby info
  button at `:36-40` (`.buttonStyle(.plain).padding(6)`).
- User problem: the movement action looks like web text, not a Mac control —
  low-contrast secondary color, underline-only affordance, small hit area — and
  sits next to a 6pt-padded info glyph with a ~28pt target. Both are used
  mid-task while the user is looking at the camera, so weak affordances cost
  the most here.
- Recommendation (mechanical): make "Try another movement" a
  `.gazeButton(.standard, size: .small)` button and give the info glyph a
  22pt minimum frame with the same bordered treatment as `linkGlyph`. Source
  inference.

### 6. Search-result rows are invisible to keyboard focus (medium)
- Anchor: `SettingsView.searchResults` in `Sources/App/SettingsView.swift:319-363`
  (`Button { selectSearchResult }` + `.buttonStyle(.plain)`, navigation only).
- User problem: search is keyboard-first (Cmd-F, type, Return works via
  `onSubmit`), but arrowing through results shows no selection or focus ring —
  a plain full-width button gives no visible current row, so keyboard users
  cannot tell which result Return will take.
- Recommendation (mechanical): keep the plain row shape but add a visible
  focused/hover state (e.g. `.focusable()` + `Theme.selection` fill on focus)
  rather than inventing a new control. Source inference.

### 7. "Finish in Settings" leaves both windows open (medium)
- Anchor: `SetupFlow.swift:117-120` (`onOpenSettings` opens Settings;
  Done still just closes via `onDone`) + `SetupDoneStep.swift:122-124`.
- User problem: after a partial first-run setup, pressing "Finish in Settings"
  opens Settings but leaves setup open too — two windows, neither clearly
  primary, and the unfinished password/permission state now lives in a window
  behind the one the user was just dismissed from.
- Recommendation (mechanical): after `openWindow(id: "settings")`, also call
  `onFinish` to close setup (hypothesis — inferred from source, not reproduced;
  do not change the closed-setup-window safeguards to do it). Source inference.

### 8. Menu-bar Settings has no standard shortcut; Lock shortcut is bare (low)
- Anchor: `MenuBarContent` in `Sources/App/GazeApp.swift:509-534` —
  `Button("Lock Screen Now") { } .keyboardShortcut("l")`, `Button("Settings…")`
  with no shortcut.
- User problem: macOS users expect Settings at Cmd-,; its absence makes the
  app's most-opened window reachable only by click, while a bare "l" shortcut
  is discoverable only with the menu open and reads as unfinished next to it.
- Recommendation (mechanical): add `.keyboardShortcut(",")` to "Settings…" and
  leave "Lock Screen Now" as is or scope it explicitly. Source inference.

## What would most visibly improve the first screen and daily use in the hour

1. **Finding 1 (scaffold titles → scaled type).** One-line change, fixes the
   first-run screen at large text sizes with zero layout risk.
2. **Finding 2 (hero column 132 → ~168pt).** The readiness row is the daily
   screen; un-crowding its buttons is visible in every state.
3. **Findings 3 + 4 (notch widths + reset/stepper).** The Notch pane is the
   most control-dense pane and the one where fixed widths clip first; normal
   native controls there pay off across Panel / Material / Face-position /
   size rows at once.

Files changed: `Tools/Release/UXReview20260917/APP-REVIEW.md` only (this report).
Checked by: re-reading the created file; no production code touched, no build
run (report-only task, and builds belong to root's integration step).
