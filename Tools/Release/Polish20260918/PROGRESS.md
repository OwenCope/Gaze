# September 18 polish pass

The user rejected the editorial redesign. The previous centered homepage has
been restored; this pass makes scoped additions to that layout.

Implemented:

- TourKit's navigation and page layout remain. Its surface and buttons now use
  native Liquid Glass. The specific vendor patch and source hash are recorded
  in ThirdParty/TourKit/LOCAL-CHANGES.md and SOURCE.json.
- The separate movement guide mounts the actual live renderer for the current
  page. It is centered and has Pause/Play; reduced motion, backgrounding and
  detaching stop rendering. No camera or authentication flow is entered.
- The homepage movement tab and product tour play all five real renderer
  animations at 60 fps. This is explicitly an animation export, not a screen
  recording. Captions name each movement. The underlying clip pauses while its
  enlarged dialog is open; closing restores focus and prior pause intent.
- Repetitive homepage copy and misleading wording about a simulated macOS
  response were corrected without changing the restored layout.

Validation so far:

- Native build and signature checks pass. Installed app SHA256:
  b494a3750305abe5a16cfe9b863764c1de56625889a251e3e9601225341dbd1f
- Installed process was verified as PID 43397. The LaunchAgent plist is unchanged.
- Four-page intro, six-page guide, eight completion/action cases, Back/Next,
  close, one active renderer, horizontal centering, Pause/Play checks pass.
- Onboarding suite passes; display callbacks measured roughly 60 fps.
  A stale 18-second idle-loop assertion was corrected for the existing
  13.2-second loop. Production idle motion was not changed.
- Website lint, TypeScript, production build and 82 existing tests pass.
- Desktop playback, caption timing, pause, enlargement and focus restoration
  were checked in Aside. Static CSS viewport checks at 320/390/768px showed no overflow and exact centering. They are not device/Safari acceptance.

Screenshot blocker:

- Computer-use capture fails with ScreenCaptureKit error -3811.
- The standalone own-window capture returns error -3801: capture permission
  denied. The system screencapture command also cannot create the window image.
- Cached AppKit images omit native glass; these will not be published as app
  screenshots. The new Tools/ProductCapture app compiles the actual UI with
  empty enrollment, a stub Keychain, isolated preferences and no service startup.
- The user was asked to enable Screen Recording. No response yet. Current
  screenshot replacement remains unfinished; do not label illustration assets
  as screenshots or claim this blocker is solved.

Build/check logs and installation receipts are in build/polish-20260918.
The minimum finish time in SESSION.json is 11:53:39 UTC.

Final asset update: native intro/completion illustrations and the corresponding
website copies now have visible bounds centered at (720,450). Existing dark
website backgrounds and rounded corners were retained for white-symbol contrast.
The static notch feature-card poster now plays its existing panel video.

Final app is installed and running (verified PID 43397); the final local DMG
is in build/installers/20260918-centered-glass-final. Build, signature,
mounted executable/asset hashes and packaging checks pass. The capture helper
also builds with the final sources and assets; its interim window was closed.

The generated-art inventory fingerprints were refreshed. Clearance still refuses
the same six unresolved rights groups, with no missing/hash/coverage defects.
No grants, release approvals or policy changes were added.

The installed executable also imports SwiftUI native glass APIs; symbol evidence
is saved in build/polish-20260918/native-glass-symbols.txt. This corroborates the
build contents, but is not a substitute for blocked native visual capture.

Work window ended 2026-09-18T11:54:34.266805+00:00. Elapsed 60.92 minutes, including waiting for capture permission. Local implementation is ready; real app screenshots remain unfinished.
