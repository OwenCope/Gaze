# UI Leftovers Audit — PRs #50–#60

Range audited: `359b8bc..HEAD` (11 merges). Touched source files: `GazeApp.swift`,
`NotchAnimationPreview.swift`, `SettingsView.swift`, `EnrollmentModel.swift`,
`RecognitionTestPanel.swift`, `RecognitionTestView.swift`, `NotchCapsule.swift`,
`SetupCaptureStep.swift`, `GazeWelcomeTour.swift`, `NotchSettings.swift`, `Theme.swift`,
`SettingsNavigationRow.swift` (new), `ThemePreviewPicker.swift` (new),
`SetupPermissionStep.swift`, `Preferences.swift`, `ReleaseUpdateChecker.swift`,
`SettingsSearch.swift`, `NotchCapsuleController.swift`, plus `ThirdParty/TourKit/TourKit.swift`.
Each was read in full (SettingsView via targeted sections; it is ~1900 lines).
No build, run, test, or lint performed — read-only review.

## Blockers

1. **Caption toggle ignored in lock-screen window sizing.** `build()` always reserves
   30pt of caption room for the attached panel, even when captions are off, so the
   window stays taller than its content after toggling.
   `Sources/LockScreen/NotchCapsuleController.swift:176`:
   ```
   let challengeRoom: CGFloat = isIsland ? 0 : 30
   ```
   with the stale justification at `Sources/LockScreen/NotchCapsuleController.swift:174`:
   ```
   // Every lock-screen scan requires movement guidance. Reserve its caption space
   // when the window is created so prompts and retries cannot clip later.
   ```
   PR #60 ("captions only reserve space when enabled") changed only the in-view
   condition (`showsChallengeCaption`, `NotchCapsule.swift:517-518`) and never touched
   this path. Note the window is built once per lock session, so toggling the
   preference also has no effect until the next lock.

## Leftovers

1. **Unused animation-preview component (the known case: found).**
   `Sources/App/NotchAnimationPreview.swift:4`:
   ```
   struct NotchAnimationPreview: View {
   ```
   Zero references outside its own file. Settings renders the static
   `NotchAppearancePreview` instead (`Sources/App/NotchSettings.swift:14`:
   `NotchAppearancePreview(settings: settings)`; defined at
   `Sources/App/NotchSettings.swift:152`: `private struct NotchAppearancePreview: View {`).
   The dead view carries its own phase picker, playback task, and tip logic
   (`NotchAnimationPreview.swift:93`: `private var phasePicker: some View {`;
   `NotchAnimationPreview.swift:101`: `private var playbackButton: some View {`).

2. **Unused `SliderRow`.** Declared at `Sources/App/Theme.swift:786`:
   ```
   struct SliderRow: View {
   ```
   Zero references in `Sources/` or `Tools/`. All live slider rows use the private
   `NotchAdjustmentRow` (`Sources/App/NotchSettings.swift:216`:
   `private struct NotchAdjustmentRow: View {`).

3. **Knock-on dead tip.** `GazePanelPreviewTip` (`Sources/App/GazeTips.swift:11`:
   `struct GazePanelPreviewTip: Tip {`) is referenced only by the dead preview above
   (`Sources/App/NotchAnimationPreview.swift:14`:
   `@State private var panelTip = GazePanelPreviewTip()`).

4. **Hand-rolled info popovers coexist with extracted `InfoButton`.** The extracted
   component is `Sources/App/Theme.swift:1141` (`struct InfoButton<Content: View>: View {`),
   but two call sites still hand-roll their own:
   `Sources/Setup/SetupMeetGazeStep.swift:130`:
   ```
   Button { showsInfo.toggle() } label: {
       Image(systemName: "info.circle").font(.system(size: 13))
   ```
   with `.buttonStyle(.plain)` at `SetupMeetGazeStep.swift:133`; and
   `Sources/Enrollment/RecognitionTestPanel.swift:40`:
   ```
   Button { showsInformation.toggle() } label: {
       Image(systemName: "info.circle").font(.system(size: 16))
   ```
   styled as a glass button at `RecognitionTestPanel.swift:44`
   (`.gazeButton(.standard, size: .small)`). Same ⓘ role, three treatments, and neither
   has `InfoButton`'s hover-open/pin behaviour.

5. **Stale "three DisclosureGroups" comment.** `Sources/App/Theme.swift:1105`:
   ```
   /// The shared expandable-row treatment for the three native `DisclosureGroup`s.
   ```
   There are four call sites: credits (`SettingsView.swift:321`), release notes
   (`SettingsView.swift:1205`), fine-tune size (`NotchSettings.swift:92`), and
   recognition details (`RecognitionTestPanel.swift:124`). All four do use the shared
   `Theme.disclosureLabel` + `.settingsDisclosureRow()`, so only the count is wrong.

6. **Stale "savedApp" comment.** `Sources/App/SettingsView.swift:142`:
   ```
   // rows in savedApp: the panes are per-subject groups, and a filtered
   ```
   These are Settings panes, not a saved app; the noun looks carried over from the
   Autofill workstream.

7. **Commented-out code: none found.** No `//`-commented Swift blocks, no `#if 0` /
   `#if false` in `Sources/` or `ThirdParty/TourKit`. No `TODO`/`FIXME`/`XXX`/`HACK`
   markers either.

## Inconsistencies

1. **Circular controls: clear-glass vs plain glass.** TourKit uses the decided variant,
   `ThirdParty/TourKit/TourKit.swift:334`:
   ```
   .buttonStyle(.glass(.clear))
   ```
   (with `.buttonBorderShape(.circle)` at `:335`). But the setup chrome and Autofill use
   plain glass on circles: `Sources/Setup/SetupScaffold.swift:82-83`:
   ```
   .buttonStyle(.glass)
   .buttonBorderShape(.circle)
   ```
   and identically `Sources/App/AutofillSettings.swift:366-367` and `:404-405`
   (`.buttonStyle(.glass)` / `.buttonBorderShape(.circle)`).

2. **Tour completion: two blue treatments on one screen.** The circular completion control
   is system glass, `ThirdParty/TourKit/TourKit.swift:276`:
   ```
   .buttonStyle(.glassProminent)
   ```
   with `.tint(.blue)` at `:279`, while the primary CTA on the same screen hand-draws its
   fill, `ThirdParty/TourKit/TourKit.swift:296-321`:
   ```
   private var primaryActionButton: some View {
       Button(action: advance) {
   ...
                   .fill(
                       LinearGradient(
   ...
       .buttonStyle(.plain)
   ```
   Custom gradient capsule beside a real glass control, against the app's
   no-hand-rolled-buttons rule (`Theme.swift:1001-1010`).

3. **"Reset Size" bypasses the app button style.** `Sources/App/NotchSettings.swift:109-111`:
   ```
   .buttonStyle(.glass)
   .buttonBorderShape(.capsule)
   .controlSize(.large)
   ```
   Every button in `SettingsView` goes through `.gazeButton()` (which picks
   `.glass`/`.glassProminent` on macOS 26 with capsule shape); this is the only
   settings button hand-applying the style.

4. **Two control sizes in the same Notch rows.** Segmented pickers use
   `Sources/App/NotchSettings.swift:23-26`:
   ```
   .pickerStyle(.segmented)
   .labelsHidden()
   .controlSize(.regular)
   .frame(width: 330)
   ```
   (repeated at `:51-54` for Material) while the adjacent `SettingsChoiceMenu` rows use
   `.controlSize(.large)` (`Sources/App/Theme.swift:1098`) with intrinsic sizing.

5. **Preview caption uses heading type.** `Sources/App/NotchSettings.swift:183-184`:
   ```
   Text("Appearance preview")
       .font(Typography.groupTitle)
   ```
   A caption set in the group-heading style, next to `Label("Camera off", …)` in
   `Typography.detail` on the same row (`:186-188`).

6. **`SettingsNavigationRow` / `ThemePreviewPicker`: no duplication found.** The only
   `chevron.right` row affordance is the extracted component
   (`SettingsNavigationRow.swift:17`); the setup `chevron` uses are back/forward
   navigation, a different role. `ThemePreviewPicker` has one call site
   (`SettingsView.swift:1177`) and the pre-extraction inline code was removed in
   `1c15c7d`. `SettingsChoiceMenu` has two call sites (Face position, Movements) and no
   hand-rolled copy in Settings; `SetupMeetGazeStep.lessonMenu` (`:150-166`) is a
   grouped-section menu, a different role, though it duplicates the
   `.glass` + capsule + `.large` treatment line-for-line.

## Captions end to end (step 3)

- **Defaults consistent:** opt-in default `true` in
  `Sources/App/Preferences.swift:355-359` (`showNotchCaptions = true`) matches the model
  default `Sources/LockScreen/NotchCapsule.swift:160` (`var showsCaptions = true`).
- **Reads consistent:** controller captures the preference on `show()` and `update()`
  (`NotchCapsuleController.swift:58`, `:100`:
  `model.showsCaptions = Preferences.shared.showNotchCaptions`); both previews sync it
  (`NotchSettings.swift:164,197,212`; `NotchAnimationPreview.swift:84,116` — dead file).
- **All three layouts honour it in-view:** attached via `showsChallengeCaption`
  (`NotchCapsule.swift:517-518`: `model.showsCaptions && model.phase.captionText != nil`),
  which also drives glyph sizing (`:818`, `:828`); island via the same gate inside the
  overlaid `challengeCaption` (`:435-439` overlay is always mounted but renders empty,
  so no space is reserved); ear via the outer gate at `:499`
  (`if isOnEar && showsChallengeCaption {`) plus the opacity check at `:505`.
- **Reduce Motion written cue:** the return-to-rest cue obeys the toggle —
  `NotchCapsule.swift:521-523` (`model.phase.isReturningToRest && !reduceMotion`)
  combined with `:517-518` means captions-off + Reduce Motion shows no return
  instruction at all (no animation either). This matches the encoded test
  (`GuidanceCaptionTests`: `expectsText = enabled && (!phase.isReturningToRest || reduced)`),
  so it is deliberate, but it means the toggle removes the only return guidance users
  with Reduce Motion have.
- **Only gap: the Blocker above** — `challengeRoom` (`NotchCapsuleController.swift:176`)
  is the one layout path that ignores the preference.
