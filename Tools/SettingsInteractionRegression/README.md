# Settings and setup recovery checks

Run the automatic checks:

    DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash Tools/SettingsInteractionRegression/run.sh

This compiles and opens an isolated native fixture. It does not launch production
Gaze, contact the update server, register a login item, access enrollment data, or
request the camera. Its service implementations only change in-memory test values.

`generate.py` copies the selected Settings view members, state declarations, and
handlers verbatim from the current source. The capture fixture is the current
`SetupCaptureStep.swift`, with its four `AVCaptureDevice` permission calls redirected
to an authorized test stand-in. A permission request traps. Camera preview and
enrollment values come from the existing onboarding test doubles. Generated source
and source hashes are saved beside the results so the scope is reviewable.

The automatic run checks:

- Opening Settings does not register Gaze; failed registration stays off and shows
  an error; retry can request approval; pending registration can be cancelled.
- Returning after external changes updates the switch. A failure remains visible
  until the requested enable/disable state is reached, then its message clears.
- Installed apps omit the source-folder action; source builds retain it. Check and
  Download invoke their existing handlers, and a pending check disables the button.
- Empty release notes produce no disclosure.
- Camera failure exposes Try Again in onboarding and Add a Face. The callback runs
  once, resumed capture removes the action, and completed enrollment suppresses it.

The fixture uses native accessibility actions inside its own process. SwiftUI's
accessibility tree requires the AppKit compatibility API for enhanced UI mode;
the resulting deprecation warnings are confined to this test harness.

## Interactive checks

    DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash Tools/SettingsInteractionRegression/run.sh /tmp/gaze-ui-review --inspect-notes --inspect-capture

When the log says `READY`, use the native UI (or CUA) to open the Release Notes
arrow, first in light mode and then dark mode. The fixture verifies the revealed
literal text. Later, activate Try Again in onboarding and Add a Face; Return is
the primary action's keyboard shortcut. Each checkpoint waits up to three minutes.
The default automatic run explicitly skips disclosure expansion; it never reports
that interaction as tested. `results.json` records which interactive modes ran.

Images from AppKit's offscreen cache can omit compositor-backed glass buttons.
Use the interactive window to assess those controls. These fixtures cover isolated
presentation and callback wiring, not real camera recovery, SMAppService behavior,
VoiceOver narration, production downloads, or full-app startup.
