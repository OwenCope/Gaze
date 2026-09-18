# Gaze improvement pass, September 18

Latest installation follow-up: the full-window introduction now includes the
movement demonstrations in its nine-page tour. The tour is now constrained to
640x520 points, with 180-point movement demos; other setup stages retain their
880x660 minimum. It continues directly into the remaining setup steps, and Back
from capture restores the last tour page and compact window constraints.
The signed build was installed at `build/Gaze.app` and relaunched at
2026-09-18 04:05 UTC. One running agent, PID 93030, was verified against the
installed executable. The login agent was temporarily unloaded for the swap and
restored without changing its plist. The prior bundle is preserved under
`build/archive/2026-09-18/before-compact-tour-20260918T040547Z/Gaze.app`.
`build/gaze-ship-20260918/compact-tour-install-result.json` records the replacement.

This pass adds native feature guidance, improves onboarding and admin workflows,
and validates the combined app and website changes. Timing is recorded in
`WORK-SESSION.json`.

## Review artifacts

- Local app: `build/gaze-ship-20260918/Gaze.app`
- Earlier installer (predates the unified tour): `build/installers/20260918-tourkit-tipkit/Gaze-0.1-arm64-local-preview.dmg`
- Website preview: http://127.0.0.1:55524/features
- Current tour captures: `build/gaze-ship-20260918/compact-tour-interaction/step-1.png` through `step-9.png`
- Detailed evidence: `build/gaze-ship-20260918/validation-summary.json`

The earlier installer is 98,729,532 bytes and contains an arm64 app targeting macOS 26+.
It is Apple Development signed and is a local preview, not a notarized public
release. It has not been repackaged with the unified tour; the installed app and
local app candidate above contain the latest changes.

App executable SHA-256:
`661efd273ee80ef2fcd50b004b7456d317c9032c9c175e8e346873764ffaa3fb`

DMG SHA-256:
`0d7f1145acf3237bd61082ab8aadb0897f18c716b93564880d8f65719c0a0b3f`

## Native changes

- Ezra 4 added a native TipKit hint for the simulated panel preview. It uses
  daily display frequency, a two-display maximum, and invalidates after Play.
  Review/scan/browser-only execution does not configure or update tip history.
- The TourKit introduction fills its native window and includes the movement
  demonstrations with one Back/Continue system and page indicator. Only the
  active movement mounts a renderer. Its Pause control respects Reduce Motion,
  and all demonstrations keep the camera off. The native window owns closing;
  the invisible first-page Back button is excluded from focus. Finishing the tour
  leads directly to the remaining setup steps, without a separate practice guide.
- Setup avoids duplicate capture when a usable enrollment already exists.
  Recognition testing offers a setup path without starting the camera for an
  unenrolled user.
- Settings and setup use more consistent spacing and adaptive controls.
  Preview playback respects Reduce Motion and Reduce Transparency.
- Root corrected the lockout error-clearing sequence: programmatically clearing
  an incorrect password no longer immediately erases its error message.
- The model is reused by readiness checks, and enrollment migration decodes
  both historical shapes after one vault read. No threshold was changed.

## Website and backend changes

- Release drafts retain text and completed upload references in tab-scoped
  recovery. Restore is explicit. Save conflicts preserve the draft.
- Release edits carry an expected content version; new releases cannot silently
  replace an existing tag. Invalid fields receive adjacent errors and focus.
- People role changes require Save. Removal has an explicit confirmation, and
  assigned roles cannot be deleted through the normal sequential workflow.
- Root replaced the shared admin overlay with a native dialog, added Tab
  containment and focus restoration, and fixed confirmation-cancel focus.
- Admin reads distinguish an unavailable store from an empty list. Uploads
  validate request shapes and return fixed errors. Unknown role IDs are refused.
- Settings reject malformed documents and stored JSON `null`; unavailable or
  invalid visibility metadata does not become a public default.
- Canonicals, social metadata, homepage structured data, and skip links are in
  place. Private/gated releases do not contribute identifying search metadata.
- Root added explicit dynamic sitemap configuration after the production build
  revealed that an async sitemap alone was being cached permanently.
- Root added explicit existing social-image URLs after browser checks showed
  secondary pages were losing Open Graph and Twitter images during metadata
  inheritance. The rendered image tags and SEO tests pass after the correction.
- The dashboard lists and filters all loaded releases. OAuth failures recover,
  sign-in preserves the pathname, and denied testers get an explanation.

## Checks completed

| Check | Result |
| --- | --- |
| Native production-source build | Passed with Xcode-beta; TipKit linked. |
| Native signature | Deep strict verification passed; established signing requirement retained. |
| DMG | Checksum, mounted app signature/hash, Applications link, Finder positions and background passed. |
| Tour fixture | All nine pages at 640x520, one navigation/progress system, Pause/Play, Back, saved page restoration, one-movement copy, app Reduce Motion, and native window closing passed using actual views and inert callbacks. System Reduce Motion and raw Escape injection were not exercised. |
| Setup fixture | 54 light/dark renders and plan checks passed; earlier display-driven lesson checks also passed. |
| Lockout feedback | Actual row/handler compiled with a fake verifier: failure persists, typing clears it, and only verified input clears lockout. |
| Backend/SEO tests | 82 tests passed with temporary data or mocked services. |
| Website production build | Passed after the final dialog changes; sitemap is dynamic and absent from the prerender manifest. |
| TypeScript / lint | TypeScript passed. The 37-file source lint pass was clean; the later modal/tester edits also passed scoped lint and build. |
| Mounted release editor | Invalid-submit focus, zero invalid requests, conflict retention, explicit recovery, confirmed-save cleanup, and storage-failure unload protection passed. |
| Mounted account flow | Duplicate OAuth request guard, failure/retry feedback, callback preservation, and denied tester data isolation passed. |
| Browser | Desktop skip navigation, release field errors, navigation/recovery, dashboard filters, SEO metadata, and dialog keyboard behavior passed in Aside. |
| Visibility / SEO | Local sign-in gating produced noindex/nofollow and a five-page sitemap without release URLs. Original fixture settings restored. |

Test scripts are in this directory. Browser evidence is copied into
`build/gaze-ship-20260918/browser/`; screenshots and logs remain local build
artifacts. The website preview retains simulated auth/email and its write-blocking
proxy. No real email, upload, account mutation, or deployment command was run.

## Remaining release gates

Mobile layout has not been visually verified at a mobile viewport. The TipKit
popover was compiled and its framework link checked, but was not displayed using
the owner's normal app profile. Native tour fixtures do not establish live camera,
unlock, password fallback, or clean-install acceptance. Launch-time improvement
has not been measured against an equivalent before/after baseline.

Developer ID signing, notarization, exact model/asset redistribution evidence,
and owner-supervised installation/unlock testing remain open. Role deletion's
reference check spans separate metadata documents and is not a cross-document
transaction. These limits are not closed by passing fixture tests or by this DMG.

No SwiftUIX, WhatsNewKit, or third-party Settings package was added. TourKit's
pinned source, MIT license, and local accessibility changes are documented under
`ThirdParty/TourKit/`.
