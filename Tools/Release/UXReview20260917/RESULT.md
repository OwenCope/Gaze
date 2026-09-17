# Gaze app and website UX pass — September 17, 2026

The updated app is installed at the normal `build/Gaze.app` location and running.
The earlier copy is preserved at `build/Gaze.before-full-ux-20260917.app`.
This fixes the stale-build problem behind the owner's screenshot: earlier edits
had been built in separate candidate folders while the usual app stayed unchanged.

Website changes are applied to `/Users/owencope/Developer/gaze-site`. A separate,
isolated preview is running at **http://127.0.0.1:55524**. It contains sample releases,
a simulated owner account and simulated email; mutation routes are blocked. The
production website has not been deployed or changed through live services.

## Reference and UX review

- Kai 4 studied rendered views of Launch Me, Droppy and Droppy Code. His method was
  the installed Neo engine rendered headlessly plus live AX trees; OS capture was
  denied. Root also inspected the saved Launch Me hero, Droppy Code hero and Droppy
  feature-section images. This is stronger evidence than the earlier source-only
  Droppy Code note, but it is not a motion or purchase-flow review.
- Vera 4 inventoried all 15 website UI routes and reviewed their source and key
  components, including sign-in, tester and admin flows.
- Finn 4 covered the main app panes, menus, setup and recognition-test UX. The
  report marks its source inferences and partial copy coverage explicitly.
- Adopted clearer hierarchy, spacing and prominent actions. Rejected the reference
  report's blanket image-framing recommendation because the owner asked to avoid
  nested picture frames. No reference branding, code, copy or assets were reused.

The three review reports and `DECISIONS.md` record the evidence and priorities.

## Implemented

Native app:

- The now-installed build includes Lena's enrolled-face collection near the top,
  removal of the duplicate header Add a Face action, and General-pane reordering.
- It includes Bo's visible Panel/Material segmented controls, simpler preview edge,
  unboxed caption, reordered help, and native slider stepping.
- Mira 4 widened the readiness action column to 168pt, renamed Hardening to
  Security checks, made setup titles scale while retaining their default sizes,
  and gave recognition-test actions native button treatment.
- Earlier camera retry, login-item feedback, release notes, wallpaper recovery and
  lesson-pausing fixes remain included. Authentication and recognition policy were
  not changed during this pass.

Website:

- Odin 4 strengthened secondary-page headline/description hierarchy and navigation
  rhythm, made complete page-navigation rows clickable, linked release titles and
  covers, removed extra cover framing, and connected the 404 page to site navigation.
- Suki 4 routed draft titles to their editor, added a visible Draft badge, clarified
  admin sign-in, and added a 30-second resend countdown that leaves code entry usable.
- Root applied both patches only after all seven baseline hashes matched. Canonical
  lint found a synchronous state update inside the countdown effect; root removed
  that branch so updates occur in the existing interval callback. Final lint passes.

## Validation

| Check | Evidence |
| --- | --- |
| Gaze build | Optimized build with the macOS 26.5 SDK succeeds. |
| Gaze signature/install | Deep strict signature verified before and after installation; same established Apple Development requirement. Exact running executable path verified. |
| Setup rendering | Onboarding policy checks and 54 light/dark offscreen screens pass. Display-driven pacing was explicitly skipped in this run. |
| Website types | Canonical `tsc --noEmit --incremental false` passes. |
| Website lint | All seven changed canonical files pass after the root effect fix. |
| Route rendering | All 15 preview routes return expected status: 200 for pages, 404 for a missing route. These are HTTP/rendered-HTML checks, not visual browser acceptance. |
| Navigation assertions | Rendered HTML confirms draft-to-editor links, linked release covers, admin sign-in explanation, and navigation on the 404. |
| Actual email component | Eight mounted React scenarios pass with fake transport/virtual time: first send, early resend refusal, usable code entry, expiry, failure retention, successful resend, address change, unmount cleanup. No email sent. |
| Live visual inspection | Incomplete. CUA repeatedly returned `SCStreamErrorDomain -3811` while capturing the browser/app windows. No final desktop/mobile visual sign-off is claimed. |

The component test uses React and react-test-renderer 19.2.8 installed only under
`build/gaze-full-ux-20260917/react-fixture`, with install scripts disabled. App/site
dependencies were not changed. `test-email-component.cjs` compiles the actual current
component and callback policy; it does not duplicate their implementation.

App SHA-256:
`84c1015c041ddea1c570c218f9f333773169695f9b7e04b1b68e6907201871b5`

`CHECKPOINT.json` contains the running PID and current canonical website hashes.
`APP-INSTALL.json` records the backed-up artifact. Logs, route results, the email
component result, and preview manifest are under `build/gaze-full-ux-20260917/`.

## Preview boundaries and next work

`preview-site.py` copies source into the build directory, links public assets and
installed dependencies, seeds sample data, and replaces auth/email only inside that
copy. It starts with a clean environment and listens only on 127.0.0.1. Never copy
the preview's auth, proxy or sample data back into the canonical site.

Still open from the review: release-gallery focus restoration/announcements, account
menu dismissal/focus behavior, release-card summary preview, video descriptions and
tester download context. Native large-text/keyboard acceptance and actual window
reopening behavior still need live checks. Current native product media was not
recaptured during this pass.

No production camera, lock, enrollment, credential or login-item test was initiated.
The app was closed through its normal Quit action, and the console was confirmed
unlocked before the updated build launched. No git status/diff, commit, branch,
push, deployment, external message or production data write was performed.

Public release still requires owner-supervised acceptance, distribution-rights
clearance, clean-install/update coverage, Developer ID/notarization and production
website-service acceptance. This UX pass does not close those gates.
