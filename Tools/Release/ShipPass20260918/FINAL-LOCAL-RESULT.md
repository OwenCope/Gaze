# Final local checkpoint — September 18

The extended work session completed after119.5 minutes. This checkpoint is ready
for local review; it is not cleared for public distribution.

## Website

The homepage now explains the product directly, with a left-aligned introduction
and an illustrated story instead of the centered slogan, MacBook mockup and
screenshot gallery. The copy states what Gaze does and what the user controls.
The demo and security limits remain explicit.

Scrolling through the desktop story changes the illustration for the current
section. All copy remains visible. Keyboard scrolling and reduced-motion CSS
disable transitions. Narrow layouts show each illustration inline with its text.
Existing Features and How-it-works media keep consistent16:10 frames and correct
source dimensions. Illustrations are labelled as illustrations.

- User preview: http://127.0.0.1:55524/ (isolated fake auth/email, mutations blocked).
- Actual-checkout dev preview: http://127.0.0.1:55525/.
- ESLint, TypeScript and production build passed after the homepage rewrite.
- All82 backend/SEO tests passed again (`site-final-tests.log`).
- Desktop story selected the correct illustration for all4 sections; copy stayed
  visible and the document had no horizontal overflow.
- Responsive document widths320,390,768 passed without overflow. At320/390 all4
  illustrations appear inline; at768 the sticky desktop presentation appears.
- Keyboard test returned `data-motion=off` and zero transition duration.
- Evidence: `build/gaze-ship-20260918/browser-final/`.

Responsive checks used same-origin iframe viewports in Aside's desktop Chromium,
not physical phones or Safari. Actual Chrome DevTools emulation was unavailable
because Google Chrome is not installed. Touch/Safari acceptance remains open.

## Native app

The app has a four-page stock TourKit introduction, a truthful final completion
page after setup, and a separate six-page camera-free movement guide in Settings.
The art is generated from Gaze's real companion renderer. Old screenshots with
embedded controls and names are no longer used by these tours.

TourKit's source remains identical to upstream:
`4d67d1f9eaa13dd63d5dc72044b5a9d28cb707117e0a39ef6070ca6187a76207`.
The user's Liquid Glass button request still needs resolution of the earlier
instruction not to edit TourKit. The button-style-only question is unanswered.

Reliability fixes include safe Back navigation after saved enrollment, cancellable
instance-owned update scheduling, recovery from future check timestamps, and
same-bundle foreground/Settings launch handoff before services start. The packaged
legacy launch-agent template now includes `--agent`.

The integrated build passed. The fixture passed4 introduction pages,6 movement
pages and8 completion/action scenarios with inert callbacks and no clipping.
Failure, partial setup, add-face, optional recognition testing and Close were checked.
Enrollment/task-lifecycle checks passed; update and handoff regressions passed.
The Passwords icon-cache source fix passed698 offline checks; that separate app
was not rebuilt or reinstalled during this pass.

Installed and relaunched at `build/Gaze.app`, PID38071 at verification.
Executable SHA256:
`bbbd3c98d02c5037d2f479b7d3ad2253de1a2405f66616bafc1223d44d7f97b8`.
One installed-path process and its loaded executable were verified. The existing
LaunchAgent plist was restored unchanged after the temporary bootout/swap.
Receipt: `build/gaze-ship-20260918/final-guides-install-result.json`.

## Fresh local installer

`build/installers/20260918-final-guides/Gaze-0.1-arm64-local-preview.dmg`

- 101,273,615 bytes, arm64, minimum macOS26.0.
- DMG SHA256: `50cf708c3db4c20c3bb632df56af000c0343387665423538a3db16d72f413c14`.
- Contains the exact installed executable above.
- Image checksum, mounted app signature/hash, Applications link and Finder layout passed.
- Receipt is alongside the DMG and explicitly sets `distributionReady: false`.

## Requirements still open

Public release still needs model/asset redistribution rights, Developer ID signing,
notarization/stapling, and owner-supervised real-Mac acceptance. The clearance
inventory now includes19 additional artwork files and their hashes/provenance.
No grant or clearance was invented: validation still REFUSEs the6 unresolved groups,
but reports no missing-file/hash/coverage defects (`final-clearance.json`).

Live unlock/fallback, sleep/relock, clean install/update and supported-Mac behavior
are not established by the fixtures. The separate Gaze Passwords development
profile expires2026-09-20 23:51 UTC and needs attention if that app will be shipped.
No deployment, public upload, notarization, credential export, or third-party
message was performed.
