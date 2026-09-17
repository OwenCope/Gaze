# Visual reference study — LaunchMe, Droppy Code, Droppy

Studied 2026-09-17 (~09:00 UTC) for the one-hour Gaze UX pass. Rendered-page
evidence only: every claim below comes from screenshots I viewed or from the
pages' accessibility trees. No source was read for this note.

## Visited URLs (final, after navigation — no redirects)

| Site | Final URL | Page title |
|---|---|---|
| LaunchMe | https://launchmeapp.com/ | LaunchMe — Customizable App Launcher for Mac |
| Droppy Code | https://getdroppycode.app/ | Droppy Code. Supercharged coding agent for Mac |
| Droppy | https://getdroppy.app/ | Droppy. Supercharged Dynamic Island for Mac |

All three loaded cleanly. No permission prompts, no browser warnings, no
failed URLs. The same three pages are open as live tabs in the GUI
BrowserOS Neo window for the lead to inspect.

## Views inspected (all rendered, all viewed as images)

Desktop renders at an effective 1200×763 viewport, narrow renders at an
effective 386×707 viewport (dimensions reported by the capture harness, not
assumed). Per site: hero (top of page), one substantive feature section
(scrolled to the second `<section>`), footer (scrolled to bottom), one
narrow-window hero. Accessibility: full AX tree per desktop page
(LaunchMe 1291 nodes, Droppy Code 1167, Droppy 3379).

Screenshot files (transient, under /tmp/ka4shots): `{launchme,droppycode,
droppy}_{hero,feature,footer,narrow}.png` plus `{tag}_ax.txt` AX dumps.

## What was observed

### LaunchMe (light theme)
- Nav: slim full-width bar, logo left; four text links
  (Features, Customization, Spaces, Pricing — confirmed in AX) plus one
  black pill "Download" right.
- Hero: small eyebrow with Apple logo, one very large tight-tracked black
  headline, one centered gray sub-paragraph (narrow column), one black
  pill CTA, one small muted capability row, then a large product
  screenshot bleeding off the bottom edge.
- Feature ("Hello notch / Better together."): tiny eyebrow ("New
  feature"), headline mixing grotesk with a teal script accent word, gray
  body copy, then a large rounded card (textured teal field) framing the
  product screenshot. A second feature block ("Everything Launchpad had…",
  seen in AX) repeats the pattern: short head + gray sub + media card.
- Footer: brand + tagline + CTA stacked left; three link columns
  (Menu / Navigation / Social); copyright + builder-credit line.
- Narrow: links collapse to a hamburger; headline reflows to ~5 stacked
  lines at still-large size; single column throughout.

### Droppy Code (dark theme)
- Nav: floating dark pill, centered, logo + four links (Hydra, Features,
  Changelog, FAQ) + light pill "Download". It floats over content rather
  than owning a full-width strip (visible overlapping the footer shot).
- Hero: pill eyebrow ("The coding app by Droppy ↗"), headline with one
  gradient word ("Supercharged", violet→teal) + white remainder, gray
  sub-paragraph, two CTAs side by side (light primary, dark secondary
  with ↓). Backdrop is a faint binary-digit texture; an app screenshot
  sits in a rounded frame over iridescent art at the fold.
- Feature ("One chat, many heads." / "Meet Hydra."): centered headline +
  gray sub, then a dark rounded card holding a two-column text block above
  a screenshot. Same head → sub → media-card rhythm as LaunchMe.
- Footer: brand column + four link columns (product / resources / legal /
  connect), giant low-contrast "Droppy Code" watermark along the bottom,
  copyright + builder credit.
- Narrow: pill nav keeps logo + hamburger + Download; the two CTAs stack
  full-width; type stays large.

### Droppy (light illustrated theme)
- Nav: same floating dark pill as Droppy Code (logo + iOS, Droplets,
  Compare, Cloud, Changelog, Docs + light "Purchase" pill).
- Hero: date eyebrow ("Updated on September 13, 2026"), gradient accent
  word + dark remainder, full-bleed duotone-blue mountain illustration
  behind everything, two CTAs (dark primary + light secondary), small
  cross-link ("Syncs with Droppy for iOS! ↗").
- Feature ("The wonderkid, greetings from your notch"): light header card
  with a "▶ Play with it" pill at top-right, then a dark body card with a
  grid of captioned product screenshots (player, HUDs, calendar, VPN,
  agent progress). Caption-under-each-shot pattern.
- Footer: same shape as Droppy Code (brand + columns + giant watermark).
- Narrow: identical stacking behavior to Droppy Code.

## Comparison

- Content hierarchy: identical everywhere — eyebrow → one big headline →
  one muted sub-paragraph → CTA row → product visual. Feature sections
  repeat it smaller: eyebrow/headline → gray body → media card. One idea
  per band, text column kept narrow, media full-width inside a card.
- Image treatment: no bare screenshots. Every product shot sits inside a
  device-ish frame or a tinted rounded card over a textured/illustrated
  field (teal grain, iridescent art, duotone illustration). Droppy's
  feature grid adds a one-line caption under each shot.
- Spacing: very tall bands (page bodies ~15–20k px at desktop width with
  ~10–12 sections); cards use large radii (≈24px+ look) with generous
  internal padding.
- Typography: oversized tight-tracked headlines (negative tracking
  visible), muted gray body copy clearly subordinate, one gradient or
  accent-type word per hero for emphasis. Narrow views keep headlines big
  and just stack them.
- Navigation: LaunchMe uses a plain full-width bar; both Droppy sites use
  the same floating dark pill that overlaps content. Both keep a single
  contrasting CTA in the bar. Narrow: hamburger everywhere; Droppy pills
  retain their CTA, LaunchMe's bar shows none.
- Material use: dark floating/translucent chrome (Droppy pill nav, dark
  cards on light pages and vice versa), watermark wordmarks in footers,
  texture/illustration fields behind media rather than flat fills.
- Motion: OBSERVED — Pause/Play buttons and Previous/Next controls exist
  in the LaunchMe AX tree (video or carousel present); a "▶ Play with
  it" button sits on Droppy's feature card (interactive demo affordance).
  INFERENCE (not verified) — scroll-reveal easing, hover states, and any
  spring/physics feel could not be judged from stills; no motion claim in
  this note goes beyond the controls listed.

## Principles Gaze could adopt (original implementation only)

1. One band, one idea: eyebrow → headline → muted sub → CTA → media
   card. (Behind: all three heroes; LaunchMe "Hello notch" block.)
2. Never show a bare screenshot: frame product visuals in a rounded card
   over a textured or tinted field. (Behind: LaunchMe teal card,
   Droppy Code iridescent-framed shot, Droppy duotone hero.)
3. Caption each visual with one plain-language line of what it proves.
   (Behind: Droppy "wonderkid" shot grid.)
4. Float the chrome: a compact pill bar overlapping content instead of a
   full-width strip, with one contrasting action. (Behind: Droppy and
   Droppy Code nav.)
5. Keep secondary copy visibly subordinate: smaller, gray, narrower
   measure than the headline, at every width. (Behind: all three heroes,
   desktop and narrow.)
6. Offer one interactive proof, not more claims: a single clearly-labeled
   play/try control on the strongest feature. (Behind: Droppy "Play with
   it"; LaunchMe in-page media controls.)

Do not lift their branding, copy, artwork, code, or assets — shapes and
rhythm only, rebuilt in Gaze's own voice.

## Blocked / limited surfaces

- OS screen capture (`screencapture`, window or display) is denied in this
  context — no Screen Recording permission — so pixels could not be
  grabbed from the interactive browser. Rendered evidence instead comes
  from the same installed browser engine (BrowserOS Neo 151.0.8162.137,
  Chromium 151) driven headless over its DevTools protocol: real layout,
  type, and paint, screenshotted and viewed as images, plus live AX
  trees. The same three URLs are additionally open as live tabs in the
  running Neo window for direct inspection.
- Only top-of-page, second-section, footer, and one narrow hero were
  viewed per site; deeper pages, docs, changelogs, and checkout/purchase
  flows were not opened. No sign-ins, forms, purchases, or downloads were
  touched. No motion, hover, or scroll feel was evaluated beyond the
  controls named above.
