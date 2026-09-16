# Gaze homepage motion reference — Droppy / Droppy Code website study (2026-09-16)

Independent reference research for the homepage intro / product-feedback / preview-playback
work happening elsewhere. Read-only: public websites inspected in an isolated browser
session; the Gaze homepage at `http://127.0.0.1:50510` (root-owned server) inspected
read-only. No app-source edits, no copied code, copy, branding, icons, or assets —
consistent with the AGPLv3/trademark constraint recorded in
`Tools/Release/DROPPY-DESIGN-REFERENCE-20260916.md`. Borrow mechanisms and timing,
never visuals or wording.

## Confirmed URLs

- Droppy Code website: `https://getdroppycode.app/` — visited, inspected, screenshotted.
- Droppy website: `https://getdroppy.app/` — reached via official links on the Droppy Code
  site (nav "Droppy", hero kicker "The coding app by Droppy", footer "Droppy for Mac" /
  "Meet Droppy for Mac" all point to `https://getdroppy.app/`). Visited, inspected,
  screenshotted.
- Launch Me: **could not be identified from official links.** Neither `getdroppycode.app`
  nor `getdroppy.app` links to a product called Launch Me (full outbound-link enumeration
  on both sites; the only "launch" hits on `getdroppy.app` are the verb "launch apps" /
  "launch it"). Per the brief, no substitute product is offered. All observations below
  come from the two confirmed sites only.

## Screenshots (git-ignored `build/home-reference/`)

`droppycode-hero-desktop.png`, `droppycode-hero-mobile.png` (390px),
`droppy-hero-desktop.png`, `droppy-hero-mobile.png` (390px),
`gaze-hero-desktop.png`, `gaze-hero-mobile.png` (390px). Static captures only —
they show layout, not motion; timing claims below come from the sites' stylesheets.

## Observed vs inferred

**Observed** = rendered DOM, computed stylesheet text, element attributes read in the
browser. **Inferred** = behaviour I did not see execute (e.g. JS-gated autoplay,
exact frame timing). Each idea marks the split.

Reference timing tokens observed on `getdroppycode.app` (`:root` computed):
`--dur-fast: 150ms`, `--dur-slow: 600ms`, `--ease-out: cubic-bezier(0.16,1,0.3,1)`,
nav dock `--nav-dock-duration: 640ms`, `--nav-dock-curve: cubic-bezier(0.32,1.22,0.36,1)`,
`--nav-dock-intro-delay: 120ms`; button morph `--morph-dur: 340ms`,
`--morph-ease: cubic-bezier(0.22,1,0.36,1)`, `--morph-blur: 16px`, tap replay
`--morph-tap-dur: 620ms`; hero reveal delays 60/120/180/340ms via `--reveal-delay`.

---

## Idea 1 — CTA hover that morphs label into icon (user-caused, 340ms blur dissolve)

**Observed reference behaviour.** Every pill button on `getdroppycode.app` (nav Download,
hero "Download for macOS" / "See what it does") contains two stacked faces: the text
label and an icon-only face that starts at `opacity: 0; filter: blur(16px)`. On hover
(and only on `@media (hover:hover) and (pointer:fine)`) the label dissolves to blur
while the icon resolves from blur to sharp, `340ms cubic-bezier(0.22,1,0.36,1)`. On
touch devices a tap replays the same dissolve as a one-shot `620ms` animation
(`btn-morph-tap-out/in`). Under `prefers-reduced-motion` the hover face is hidden
entirely and hover just dims to `0.85`. **Inferred:** I did not click-test the tap
replay; it is read from keyframes, not seen.

**Why it suits Gaze.** It is the purest allowed marketing-page motion: it only ever
moves *because the pointer is already on the control*, confirms affordance, and costs
nothing at rest. Gaze's hero has exactly one primary action ("Join the Discord") plus
a text link ("Watch it unlock ›") — the morph gives the primary button a felt,
physical response without adding any ambient animation to a security product's page.

**Likely source target.** The hero CTA in `src/app/page.tsx` (`LiquidButton` as used
for the Discord links) plus the button's own stylesheet; geometry lives wherever
`LiquidButton` is defined (patch tree shows the pattern at
`Tools/Release/AppleSitePolish/files/src/components/ui/` — the live checkout's
equivalent file is the target, verify before editing).

**Proposed timing/geometry.** Keep Gaze's glass pill shape; add a second face holding
a right-arrow / external glyph at the same optical size as the label cap-height.
`opacity + blur(12–16px)`, `340ms` with Gaze's existing `cubic-bezier(0.32,0.72,0,1)`,
hover-gated to fine pointers; tap replays once at `~600ms`; reduced-motion falls back
to a plain `150ms` background/opacity change. Transform/opacity/filter only.

## Idea 2 — One-shot staggered hero reveal that settles, gated per session

**Observed reference behaviour.** Hero elements on `getdroppycode.app` carry
`data-reveal-on-load` with `--reveal-delay` of 60ms (title) / 120ms (subtitle) /
180ms (actions) / 340ms (hero media); base state is `opacity: 0; translateY(24px)`,
visible state eases out. Once finished, elements gain `.is-settled`
(`transform: none; transition: none`) so later style recalculations can't re-animate
them. The nav dock plays once (`640ms` overshooting curve from
`translateY(-6px) scaleX(0.78)` + `blur(8px)`), and an inline script sets
`sessionStorage.droppyCodeNavIntro` so repeat views in the same session skip the
intro (`html.nav-intro-done .nav__pill { animation: none }`). `getdroppy.app` uses
the identical sessionStorage gate (`droppyNavIntro`). A decorative charge/sheen
sequence on the hero word runs once (`850–900ms`) except for one slow ambient sheen
(`3.2s linear infinite`) — the single most disposable detail on the page.

**Why it suits Gaze.** Gaze already owns this vocabulary
(`gaze-fade-slide-in 0.7s`, `translateY(12px)` + `blur(6px)`, `.animate-delay-*`
100–800ms in `globals.css`) — the gap is lifecycle, not look: nothing settles, and
nothing skips on repeat view. Adopting settle + session gate keeps the arrival feel
for first-time visitors while making the page instant for everyone else, which
matters more for a utility homepage than for a launch spectacle.

**Likely source target.** `src/app/globals.css` (`.animate-element`,
`.animate-slide-right`, delay utilities) and the hero section of `src/app/page.tsx`.

**Proposed timing/geometry.** Keep `0.7s` / `12px` / `blur(6px)` exactly as-is;
cap the cascade at ~4 steps (≤400ms last delay — today's 800ms tail is the slowest
thing on the page); add a settled state clearing `animation`/`transition` on finish;
gate the whole hero cascade behind `sessionStorage` so it plays once per session.
Do not adopt the infinite sheen.

## Idea 3 — Manual scroll-snap rail for the product galleries (no auto-advance)

**Observed reference behaviour.** The Droppy Code highlights section is a horizontal
rail (`display: grid; grid-auto-flow: column`, card width `min(820px, 100vw-48px)`,
`20px` gap) with `scroll-snap-type: x mandatory`, `scroll-behavior: smooth`,
hidden scrollbars, and arrow Prev/Next buttons; while dragging it switches to
`snap: none; behavior: auto; cursor: grabbing`. Slides carry real
`role="group" aria-roledescription="slide" aria-label "…n of 4"` semantics. No
`setInterval`/autoplay machinery was found in markup or timed behaviour — it only
moves when the visitor drags, arrows, or trackpads. **Inferred:** JS file contents
were not fully enumerated, so "no auto-advance" rests on absence of timers in the
observed DOM plus manual-only affordances, not a full script audit.

**Why it suits Gaze.** Gaze already has the right components (`FeaturesCarousel`,
`ScreenshotGallery`, `.no-scrollbar` with the same hidden-scrollbar + arrow-button
pattern noted in `globals.css`). The reference confirms the shape to converge on:
snap for landing precision, drag for direct manipulation, buttons for discoverability
— and it is the correct answer to preview playback that must never feel like the
page performing at the visitor.

**Likely source target.** The carousel/gallery components (`FeaturesCarousel`,
`ScreenshotGallery`) and `.no-scrollbar` in `src/app/globals.css`.

**Proposed timing/geometry.** `scroll-snap-type: x mandatory` with card width
`min(820px, 100vw-48px)`-equivalent scaled to Gaze's container, `~20px` gap,
`scroll-behavior: smooth` only outside active drag, visible Prev/Next buttons and
slide-count semantics. Explicitly: no timers, no auto-advance, no scroll-triggered
entrance motion on the cards.

## Idea 4 — Keep the honest demo pattern; add poster + responsive sources (Droppy promo)

**Observed reference behaviour.** The Droppy hero promo is a `muted + loop +
playsinline` video with `preload="auto"`, a real `poster` frame, and responsive
sources (`data-src-wide` / `data-src-square` with matching posters, remote CDN
base) — the square crop serves narrow viewports instead of letterboxing the wide
cut. **Inferred:** the `autoplay` IDL read `false` with no `autoplay` attribute in
markup, so playback is presumably JS-gated (e.g. on-intersection); I did not verify
the trigger, only the attributes.

**Why it suits Gaze.** Gaze's demo treatment is already exemplary and should be
preserved, not replaced: the three material clips are `autoplay + loop + muted`
(ambient, silent, honest), while the 8-second unlock recording is `controls +
preload="none" + autoplay=false` — visitor-gated, zero bytes until asked — under
copy that says exactly what it is ("An eight-second recording of Gaze. No camera
access, no simulated recognition."). That honesty is a conversion asset for a
security-adjacent product. The two portable details are the poster frame (Gaze's
gated player shows no poster today) and the wide/square source split for mobile.

**Likely source target.** The `LiveDemo` component (renders `#demo` and the
`lock-unlock.mp4` player) and the material-switcher block rendering the three
`clips/*.mp4` previews.

**Proposed timing/geometry.** No timing change. Add `poster` to the gated unlock
player (first frame of the panel at rest) and serve a square-cropped rendition under
`~640px` viewports; keep `preload="none"` on the gated player and keep the
material clips silent/muted/looping. No geometry change to the player itself.

## Idea 5 — Reduced-motion and small-screen discipline as a checklist, not a feature

**Observed reference behaviour.** Both reference sites handle `prefers-reduced-motion`
at every layer: reveals collapse to near-instant/static, the nav dock animation is
removed, morph hover faces are hidden (hover becomes a simple dim), and pricing
numeric transitions are disabled. Small screens get a hamburger whose icon morphs
(`320ms` overshooting curve on the bars, `180ms` on middle-bar fade), the wordmark
hides under `380px`, and floating controls shrink rather than overflow (Gaze's own
`globals.css` already documents the same 500px-vs-358px arithmetic for its
switcher). **Inferred:** nothing — all read directly from stylesheets.

**Why it suits Gaze.** Root and other heads are adding intro and preview motion
right now; this is the guardrail that keeps that work shippable: Gaze's
`globals.css` already has the reduced-motion block for `.animate-element` /
`.animate-slide-right`, but every *new* animation must join it on day one, and the
material switcher's fixed `40px`/`80px` pill travel (36px/72px on mobile) is exactly
the kind of geometry that must stay in sync across breakpoints.

**Likely source target.** `src/app/globals.css` reduced-motion block and the
`@media (max-width: 639px)` switcher section; any new keyframes added by the
parallel homepage work.

**Proposed timing/geometry.** Rule, not animation: all new motion uses
`transform`/`opacity` (filter blur ≤16px) only; travel ≤28px; durations ≤300ms for
feedback, ≤700ms for one-shot entrances; every keyframe ships the same-day
reduced-motion path (static end-state, no slide/spring); pill/indicator travel
values stay breakpoint-paired (desktop 40/80px, mobile 36/72px as today).

---

## What to preserve about Gaze

- **Identity:** "Your face. Your Mac. Unlocked." with the glass notch-panel material
  language (`backdrop-filter: blur(24px) saturate(1.7)`, lit top edge) — none of the
  reference sites' dark-dock / orange-charge styling should migrate.
- **Honest in-development copy:** "Free and open source. Currently in development.",
  "Help shape Gaze. Gaze is still in development." — keep the work-in-progress
  framing; the reference sites sell finished products and their certainty must not
  leak into Gaze's claims.
- **Honest security copy:** "Gaze uses a regular camera, not Face ID. A photograph
  may fool it. It's a convenience feature, not a replacement for your Mac's
  security." plus "Your password still works", offline/no-account, and the specific
  FAQ answers (notchless Macs, glasses/beards, five faces, battery). These are the
  page's strongest trust signals; motion work must not crowd them out.
- **Already-right mechanics:** user-gated unlock recording (`preload="none"` +
  controls), silent looping material previews, manual carousels, skip link,
  tabular-nums-scale restraint. Ideas above extend these; none replace them.

## Limitations

- Single-pass inspection on 2026-09-16; no frame-level measurement (no slow-motion
  or rAF profiling), so durations are stylesheet values, not verified rendered timing.
- Launch Me unidentified (see URLs) — if the lead supplies its URL, the study can be
  extended, but no further browsing was done on guesses.
- No keyboard / screen-reader / assistive-tech testing beyond reading ARIA markup;
  no network-waterfall measurement (poster/preload claims are attribute reads).
- Gaze source targets are inferred from the live DOM plus the
  `Tools/Release/AppleSitePolish/files/` patch tree, which matches the served CSS
  verbatim for the cited rules — but the live checkout itself was not opened; verify
  paths before editing.
- Screenshots are static; motion claims rest on stylesheet evidence cited per idea.

## Lead qualifications

The existing Gaze unlock player already has a poster; no missing-poster defect
was found. The reference site's label-to-icon morph is not being adopted: Gaze
keeps action labels readable. The selected ideas are a bounded first-visit
entrance, direct pointer feedback, manual galleries, and explicit playback
controls. Static CSS values do not prove rendered timing or autoplay behavior.
The original Gaze clips were also independently found to contain a personal
desktop; appearance alone is not evidence that those assets are suitable.
