# Whole-site design pass — September 16, 2026

The live local website is /Users/owencope/Developer/gaze-site. The review server is
http://127.0.0.1:55523. Nothing was deployed. `files/` contains current source/media
copies; SOURCES.json records their SHA-256 values. These are mirrors, not pending
patches: the actual local site source is already updated.

## Decisions based on the rendered site

| Before | After | Why |
| --- | --- | --- |
| Secondary pages used different oversized headings and long introductions | Shared PageIntro, a restrained type scale, shorter copy and consistent spacing | Make each page feel part of the same product |
| Credits was first a screen per person, then a flat, text-heavy list the owner rejected | Smaller centered introduction, two project cards, a separate people grid, shorter factual contributions | Give the actual icons and contributors visual priority |
| Features presented unmeasured speed and overly absolute privacy/spoof claims | Local-recognition, optional-portrait, authorization and spoof-limit wording | Keep marketing aligned with actual behavior |
| Public media mixed current previews with old flat-panel screenshots and a personal desktop | Current first-party setup renders and current panel previews, clearly labelled as previews | Present a coherent current product without implying a live camera demo |
| How It Works was a prose grid | Three keyboard-operable steps with current app visuals and a controlled movement video | Let visitors understand the sequence without reading a wall of text |
| Security was undifferentiated prose | A data-storage ledger plus camera-use and limitation sections | Make storage and user choices easy to compare |
| Releases used animated floating cards and cropped images | A dated changelog layout with contained images and direct note links | Improve reading and remove decorative movement |
| Sign-in was a large decorative split screen | Compact account card and clear way back to the website | Keep the task and available providers obvious |
| Admin pages used an old marketing dock and incorrect homepage anchors | Persistent admin navigation with Dashboard, New release, Tester notes and People | Make navigation match the actual task |
| Dense admin panels used glass everywhere; editor tools were 28px | Solid grouped surfaces, visible focus and 44px formatting controls | Make the editing interface easier to read and operate |
| A long release title widened the dashboard past a phone screen | Explicit minmax(0, 1fr) base grid | Keep the card inside the viewport |
| Unknown URLs fell through to a generic page | Branded, neutral 404 with working return links | Provide recovery without exposing private release existence |

## Validation

- Production build and TypeScript pass; focused ESLint passes across changed routes/components.
- Isolated builds exclude .env/.npmrc, real data and inherited service credentials.
- Five HTTP assertions pass: homepage, releases, latest feed, missing download and
  unauthenticated admin redirect.
- 15 routes were rendered at 1470px light and 390px dark (30 route/viewport cases),
  including all five admin routes, tester access, release detail and missing page.
  No broken images were found. One dashboard overflow was measured at 512px on a
  390px viewport, corrected in source, then rebuilt for a focused recheck.
- Actual private pages were inspected using an explicitly synthetic local Auth.js
  cookie and ADMIN_EMAILS=preview@example.test. No real account/session, OAuth,
  email, Blob service or production record was used. No save/upload was performed.
- Walkthrough tab selection, ArrowRight/Home focus, video removal when switching
  away, paused/controlled video startup and reduced-motion animation suppression pass.
- Gallery selection, native dialog open, Escape close and focus restoration pass.
- Mobile navigation contains Credits; closing returns focus and restores inertness.
- Final viewport/focus rechecks are in build/website-whole-site-final/final-checks.json.

Visual captures and route results: build/website-whole-site/ and
build/website-whole-site-final/. The first gallery test used the old 'screenshot'
label; the current accessible label is 'preview'. A later npm CLI invocation timed
out; the same state was inspected through the installed CLI. After the rebuild the synthetic
admin cookie was reinstalled, and route/heading assertions were added to the final
viewport checks so a sign-in redirect could not count as a dashboard pass. These were test-driver
issues, not hidden product changes.

## Limits and continuation

This is a local UI pass, not a public launch approval. Native Liquid Glass still
needs a faithful current capture; old flat-face footage was not restored. The site
shows the current Solid/Semi previews and labelled setup renders. Authentication,
private release gates, download validation, notes versioning and admin write logic
were preserved. The previously stopped account-menu and release-gallery behavior
work was not resumed; ScreenshotGallery is a separate public component.

Reference sites reviewed: launchmeapp.com, getdroppy.app and getdroppycode.app.
Their spacing, product-led layouts and hierarchy informed the changes; their code,
branding and assets were not copied. No additional automated intro/scroll animation
was added; interaction motion and reduced-motion behavior remain deliberate.

Hydra note: on Codex, spawned agents are Hydra heads. The owner's screenshot of
Droppy Code's developer clarified this. Earlier claims that a separate Hydra launch
tool was required were incorrect. Do not repeat that diagnosis or resend completed
work solely because the sidebar displays delegated-head tool rows.
