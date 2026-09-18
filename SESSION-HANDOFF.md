# Gaze handoff, September 18

Read this file and `Tools/Release/Polish20260918/PROGRESS.md` before continuing.
They supersede the 10:40 UTC checkpoint, which is preserved in
`Tools/Release/ShipPass20260918/SESSION-HANDOFF-1040.md`.
The user explicitly requested persistence through the memory MCP.

## Latest request

The user rejected the editorial website redesign and asked to revert it.
Keep the previous centered Apple-like homepage; add targeted improvements.
They also want native Liquid Glass, centered live movement animations instead
of three-frame illustrations, current app screenshots, and a full hour of work.

This hour started at 10:53:39 UTC and its work window has now ended after 11:53:39 UTC.
`Tools/Release/Polish20260918/SESSION.json` records the session.
Local changes and checks are ready. Real app screenshot replacement remains pending macOS capture permission.

The user's repeated explicit requests for Liquid Glass and live animations
supersede the earlier unresolved button-style questionnaire. No checkbox answer
was received, and none is being claimed. The implementation is a narrow TourKit
styling/media extension; its layout and navigation remain.

## Constraints

- No more heads. Work locally in the real checkouts.
- Native: `/Users/owencope/Developer/FaceID`.
- Website: `/Users/owencope/Developer/gaze-site`.
- No git status/diff/reset/stash/commit/push/branch/PR/merge operations. Hydra
  handles landing. Preserve other work.
- No real camera, lock/unlock, password replay, plugin-installation, account or
  email mutation tests. No threshold or broadcast-policy changes.
- Prefix native builds with
  `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`.
- Use `/usr/bin/log`, not the zsh `log` builtin; use `nm` for compiled symbols.

## Current changes

Website:

- `src/app/page.tsx` again uses the centered HomeHeroMotion hero, the headline
  “Your face. Your Mac. Unlocked.”, MacScreen, gallery, feature carousel and
  earlier privacy/community layout. The rejected GazeStory component was
  archived in `FaceID/build/polish-20260918/rejected-gaze-story.tsx` and removed.
- `live-demo.tsx` and `faqs.tsx` restore their prior headings. Targeted copy
  edits remove repeated claims and clarify that the panel video is simulated.
- New `product-animation.tsx` plays the actual renderer's five guidance cycles
  with captions, Pause/Play, offscreen/hidden-tab pause and reduced-motion
  handling. Used in `screenshot-gallery.tsx` and `product-tour.tsx`; the notch feature card also now plays its existing panel clip.
- `public/previews/gaze-movements.mp4` is 900×560, 60 fps, 16 seconds, 165302 bytes.
  Its poster and WebVTT captions accompany it. This is an animation export,
  not an app screenshot or real unlock recording.
- Existing illustration compositions have been centered at (720,450) on their
  1440×900 canvases. They remain labeled as illustrations. They are still
  awaiting replacement by real screenshots; do not claim that part is finished.

Native:

- `ThirdParty/TourKit/TourKit.swift` uses native `.glass`, `.glassProminent` and
  `.glassEffect(.regular, in:)`; painted buttons/blur circles/dark scrim removed.
- Optional `pageMedia` mounts the current page's live content in the original
  media region. Existing TourPage model, navigation and callbacks remain.
- Reduced Motion disables page fades. Initial hidden Back is disabled and
  hidden from accessibility. Close keeps the checkmark, labeled `Close tour`
  with identifier `tour-close`.
- `GazeMovementTour` uses `GazeTourMovementPage` and the real GazeLessonAnimation.
  The guide has six pages and remains camera-free. Media is centered; Pause/Play
  works. Only the active page owns a renderer after its short cross-fade.
- `Tools/OnboardingArt/Generate.swift` centers the six intro/completion images
  vertically and corrects the visible horizontal bounds of composite images.
  Legacy movement strips are preserved but no longer used by the live guide.
- Vendor provenance is accurate in SOURCE.json and LOCAL-CHANGES.md.

## Validation

- Native build passes. Read the latest final build log and installation receipt
  in `build/polish-20260918`; the final asset-inclusive build is installed.
- `Tools/Release/ShipPass20260918/check-tour.py` checks four intro pages, six
  movement pages, eight completion/action states, Back/Next/close, one renderer,
  centering and Pause/Play. It also measures the new glass guide itself.
- All six glass-guide pages submitted 360–361 frames in six seconds, p95 roughly
  18.4–18.7ms. Results:
  `build/gaze-ship-20260918/guided-setup-interaction/glass-movement-performance.json`.
- Onboarding regression passes, including background/reduced-motion/detach
  behavior and 54 offscreen layouts. One stale test assumed an 18-second idle
  loop; corrected for the existing 13.2-second loop without changing the motion.
- Website lint, TypeScript, production build and 82 existing tests pass.
- Aside browser checks passed playback, captions, Pause/Play, enlargement,
  underlying-video pause, close/focus restoration and offscreen pause.
- Simulated MediaQueryList changes in the actual browser verified reduced-motion
  autoplay suppression, explicit Play and pause when Reduce Motion is enabled.
  The test override was removed. No OS preference was changed.
- Static CSS viewport fixtures at 320/390/768px had no horizontal overflow;
  gallery centers were exactly 160/195/384px. These are layout checks, not
  iPhone/Safari acceptance. Temporary iframe removed.

## Screenshot blocker

macOS capture access remains unavailable. CUA fails with ScreenCaptureKit -3811;
a standalone own-window capture returns -3801 (“The user declined … capture”);
`/usr/sbin/screencapture` also cannot create the own-window image.
AppKit cached images omit native glass and are not suitable website screenshots.
Do not substitute them or label illustrations as current app screenshots.

An asynchronous question asked the user to enable Screen & System Audio Recording
for the app running this chat. No reply has arrived. The dedicated capture helper
may be listed separately as **Gaze Product Capture**.

`Tools/ProductCapture` is ready:

- `build.py` compiles real current app views, with the normal app entry point
  disabled, stub Keychain/empty enrollment, in-memory lockout and separate
  bundle preferences. No production service startup, camera or credentials.
- `CaptureApp.swift` mirrors native Settings and plain tour window styles.
- `--inspect` keeps its window open and writes its ID to window.json.
- `export-shots.py` requires four real screenshots, then centers them on
  transparent 1440×900 canvases without cropping or retouching. It refuses to
  invent missing inputs. Read Tools/ProductCapture/README.md for commands.
- No real captures have been exported to the website yet. The interim capture helper process was closed; build it/relaunch when capture permission is available.

## Previews and tools

- User preview: http://127.0.0.1:55524/
  Existing isolated directory: `build/gaze-full-ux-20260917/site-preview`.
  Fake auth/email and write-blocking proxy must remain. Sync only changed
  public UI source files. Public/node_modules link to canonical website.
- Canonical dev server: http://127.0.0.1:55525/ (real local environment; public
  page inspection only).
- Both servers were running during this pass.
- Aside CLI works. Read `aside guide` and `aside guide repl` before use.
  Latest persistent REPL session 27410, page variable `polishPage`.
  Session artifacts:
  `/Users/owencope/.aside/u/0/sessions/2026-09-18_EpmesM2kXzeSZABi/artifacts`.
- BrowserOS neo tools are unavailable. Chrome DevTools cannot start because
  Google Chrome is absent. Aside does not implement setViewportSize/emulateMedia.

## Installation and release

The installed app has already been updated once in this pass. The final build with centered art is installed and verified as PID 43397.
Executable SHA256: b494a3750305abe5a16cfe9b863764c1de56625889a251e3e9601225341dbd1f.
Use the staged, signature-checked installer scripts in `build/polish-20260918`.
They boot out the existing KeepAlive LaunchAgent, preserve its plist, archive
and swap the app, bootstrap the same agent, then verify the loaded executable.
Do not just kill the KeepAlive process; it respawns.

Previous interim install hash:
`bfae4c2df4093f7982b4b8a2f752e175fe76acd3d680c48f2f428e7b2f19efd8`.
Interim local DMG: `build/installers/20260918-glass-movement/`.
Final local DMG: `build/installers/20260918-centered-glass-final/Gaze-0.1-arm64-local-preview.dmg`, SHA256 `6b345781db9407421a752cea09acd297d74d1488003d5bcc5e7dcf137d11203c`, 101273187 bytes. Mounted executable hash and signature passed. Receipt keeps distributionReady=false.

Public release remains blocked by Developer ID/notarization, model/asset rights,
live-Mac negative/fallback/wake/relock/install acceptance, and the Gaze Passwords
profile expiring September 20 at 23:51 UTC. No public release, deployment,
upload or third-party message is authorized or performed by this pass.

Earlier reliability work and all its evidence remain in the archived checkpoint.
