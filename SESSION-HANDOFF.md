## Latest correction: no top bar, blurred photo fade, current icon

User explicitly rejected the 48pt top bar and the hard photo/footer boundary.
- Removed the top bar. Native images use wider 1440×900 crops preserving the
  photographed window's side margins, so Back/X overlay the photo without hitting
  its controls. Web photo crops remain 1280×800.
- TourKit photographs now blend into a 14pt blurred copy toward the bottom, then
  fade to zero alpha before the footer. This replaces the old color scrim.
  All four rendered photo/footer boundaries were sampled and are uniform.
  Actual ScreenCaptureKit capture confirms the compositor blur and bar removal:
  build/tour-blend-20260918/welcome.png (1440×1360).
- Unlock my Mac now uses GazeBrand.toolbarIcon through SettingToggle's portrait
  slot, replacing the old green faceid symbol. Binding/actions unchanged.
  Recaptured actual Unlock Settings and refreshed native/site assets and manifest.
- Native build and the 18-state tour fixture pass. Installed PID 58514,
  SHA256 525de5931abb9e0c41dad0809806c098b703a20a7c7af0930469a5fb3369df7f; KeepAlive plist restored unchanged.
- READY website preview: https://gaze-site-1114ztm7z-gaze2.vercel.app
  Refreshed icon photo HTTP200 and byte-for-byte identical to the local WebP.
- ProductCapture selects visible content windows without requiring canBecomeKey,
  because the plain tour window is not key-capable. Evidence: build/tour-blend-20260918.

Earlier top-bar and 96pt-scrim notes below are superseded. Pinned website comments
remain pending user-supplied text/thread link; no contents were guessed.

## Latest: real app photographs, September 18 at 22:30

User supplied three recordings: Droppy Code's photo-heavy tour as the reference,
plus two Gaze recordings. Keep TourKit's preset structure, dark card and blue CTA;
plain Back/X controls; autoplay movement previews without player chrome or subtitles.
Do not redesign the site. No helper heads were used in this pass.

Completed:
- Fixed ProductCapture to use `SCShareableContent.currentProcess`, the supported
  own-window capture API used by Droppy Code. The prior all-window enumeration
  was why captures required Screen Recording permission. No permission workaround
  or access to other apps: the helper captures only its own current production
  Settings views and system-wallpaper backdrop. Empty enrollment, inert credentials.
- Four real Settings close-ups now replace the illustrations in the native intro,
  completion, website gallery, feature carousel, product tour and setup walkthrough.
  Source/output hashes and crop coordinates: Tools/ProductCapture/tour-shots.json.
  User recordings and camera images were NOT exported or published.
- TourKit photo fade reduced from 220 to 96 pt; text centered in the existing footer;
  navigation has a 48 pt clear strip above photographs so screenshot controls do
  not collide with Back/X. Fixed measured hosting size for standalone TourKit windows.
- Movement animation remains live with no player controls or subtitles.
- Native build and 18-state tour fixture pass (four intro, six movement, eight
  completion/action cases). Website targeted ESLint, TypeScript and production
  build pass. Real photos loaded in the isolated browser preview; desktop screenshot
  in Aside session 2026-09-18_BarXj7EQnL4ukkf3/artifacts/gaze-photos-desktop.png.
- Installed app PID: 56577; SHA256: 10d04edc952de24d0e08f860ebb552c02459f2ea7a3c81d5b2031f6c9a9640bb.
  Signature verified; KeepAlive agent restored with the original plist unchanged.
- New Vercel preview READY: https://gaze-site-l4342mke9-gaze2.vercel.app
  Deployment dpl_MoUM4Cz7k8V3QRGxktDw2LqtWtVZ. 196 verified tracked inputs uploaded.
  Preview home and all four photos return HTTP 200; deployed hashes match local.
  Gallery centered at 1231px viewport with no overflow; movement video plays muted
  and loops, controls=false, textTracks=0.
  No production promotion and no git commit/push/branch/PR operation.

Still outstanding: actual pinned website comments. The Vercel toolbar is absent
in the attached preview browser, and /v1/comments returned 404. Asked user for
comment text or a direct thread link via async input; no answer yet. Do not invent
comment contents or claim those comments were addressed.

Evidence: build/droppy-reference-20260918 (captures, native build log, tour fixture log),
and gaze-site/build/deployment-recovery-20260918 (photos-build.log, preview receipt).
The older notes below describe previous iterations; their capture-permission
block and screenshot-pending status are superseded by this section.

# Gaze handoff, September 18

## Latest UI refinement: autoplay and real app shots

The user explicitly wants previews to autoplay without subtitles, player bars,
Play/Pause buttons or a visible Enlarge overlay. Marketing video components now
render plain inline muted loops; gallery media can still be clicked to enlarge.
OS reduced-motion and offscreen/background pause remain silent. The native
movement guide also autoplays without its extra playback controls/caption.

The user specifically rejected the Back/check circles. The tour retains the
preset dark card/blue primary action, but uses a plain back chevron and close X
with clear hit areas. Build and tour interaction checks passed; installed PID
51047 at verification, SHA256 883957ab4bee829b72daf6f4233d69cb6f7eb53e0784593acd2c716a13fb5066.
Evidence: build/seamless-media-20260918.

Website preview: https://gaze-site-3zb7363qw-gaze2.vercel.app, deployment
dpl_DA3EdxFadVuGrVi2TFD98uz8HJLr READY. Source changes also synced to local55524.

Still unfinished: real CURRENT app screenshots in BOTH tour and website. The
latest capture retry returned ScreenCaptureKit -3801 and CGPreflight returned
false. User was asked to enable Screen & System Audio Recording for Droppy Code
Dev / Gaze Product Capture. No response yet. Do not replace photos with more
illustrations or old app shots. The capture helper now copies the installed
app's full resources, including icon/model availability, while keeping empty
enrollment, a stub Keychain and no production service startup.

## Website deployment recovery

The failed Vercel preview at commit 3d5bf3f omitted 11 local-only imported modules
and required media. Application source, referenced media and package declarations
are now staged for Hydra. `npm run build` has a prebuild input check that catches
missing/untracked deployment files. No manual commit or push was made.

Lapse's private registry then caused npm E401 in the first recovery preview.
It is now an optional local install (`npm run setup:lapse`, `npm run dev:lapse`),
with production aliases to an empty component. User-level npm credentials stay
local. Vercel CLI link refreshed its local OIDC configuration; env files were
excluded from uploads and Git.

Successful preview: https://gaze-site-e7u0w982h-gaze2.vercel.app
Deployment: dpl_HJab3L1ZZNYsgXiWws7uxAmpp7D9, READY. Public pages/media returned200;
/admin redirects to /signin. All82 existing tests pass. Browser access retains
Vercel protection; authenticated CLI checks passed. Evidence is in gaze-site/
build/deployment-recovery-20260918/RESULT.json. The temporary upload allowlist
was removed. Production was not promoted.

TourKit preset styling remains restored and installed. Its fresh local DMG is
build/installers/20260918-tourkit-preset/Gaze-0.1-arm64-local-preview.dmg,
SHA256 504e84e9ae2582aaa166bbfb6f200442b9d4904096a96ac8277261f4328ccb27.
Real app screenshot replacement is still waiting for macOS capture access.

## Latest correction: TourKit preset styling

The user rejected the translucent custom-glass tour in a screenshot and explicitly
reaffirmed TourKit’s preset styling. The pinned upstream opaque dark card, blue
action button, icon circles, white text and page indicators have been restored.
Live movement content, centering, navigation and accessibility fixes remain.
Build, preset-style comparison and tour interaction checks passed. Installed
PID 45776, executable SHA256 e6ca309966aaac249415249a6caa57701586ba2da9a25297ee36a219a9be294c.
Evidence: build/tourkit-preset-20260918. The ProductCapture helper must be rebuilt
with build.py before future screenshots; its previous binary has the rejected skin.
This correction supersedes the custom-glass decisions described below.
Do not reinterpret a general glass request as permission to replace TourKit’s skin.

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
