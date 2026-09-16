# AppleSitePolish — report (Mira)

Bounded Apple-style restraint pass over the Gaze public homepage. The current
source was already close (system font, Apple palette, honest in-dev copy), so
this is polish, not redesign. No copy changes, no new sections, no animation
added, no download button.

## Apply

From a gaze-site checkout at the same revision these files were copied from:

```bash
patch -p1 < gaze-site-apple-polish.patch
# or copy files/<path> over src/<path> per file
node tests/check-apple-polish.mjs        # with FILES_ROOT=<checkout>/src for a live tree
```

`files/` mirrors gaze-site `src/` paths. Only these 5 files are touched; auth,
metadata, release gates, download routes, sign-in, and env files are not.

## What changed (per file)

- **`src/app/page.tsx`** — skip link (`Skip to content` → `#main-content` on the
  hero); closing CTA wrapped in `.site-container` instead of a lone `px-6`, so
  its measure aligns with every other section. Copy, CTAs, imagery untouched.
- **`src/app/globals.css`** (append-only) — smooth anchor scrolling (existing
  reduced-motion guard already forces it back to `auto`); `section[id]`
  scroll-margin safety net (5rem, matches existing utilities); `::selection`
  tint; `.skip-link` styles; `prefers-reduced-transparency` (solid nav/panel,
  no blur) and `prefers-contrast: more` (solid nav, defined edge, underlined
  links) per the apple-design skill §14. All palette tokens byte-identical.
- **`src/components/top-nav.tsx`** — desktop + mobile inactive links move from
  12px/17px secondary grey to ink-based `color-mix` tones (≈6.4:1 light,
  ≈9:1 dark) at the same sizes; visible `:focus-visible` on logo, desktop
  links (new), and mobile rows (new); menu now also closes on browser
  back/forward (`popstate` subscription; in-menu taps already closed via
  onClick). Escape/outside-dismiss unchanged. Header gains a `top-nav` class
  so the transparency media query can drop its blur without fragile selectors.
- **`src/components/faqs.tsx`** — copy, order, and native `details` accordion
  untouched. Chevron gets a 200ms rotate transition (the global reduced-motion
  rule disables it automatically); answers get `text-pretty`.
- **`src/components/ui/footer-section.tsx`** — internal links use Next `Link`
  (client-side nav + prefetch; the previously imported `Link` was unused for
  columns), externals stay `<a target=_blank rel=noreferrer>`; columns wrapped
  in `<nav aria-label="Footer">`; brand link gains the standard visible focus
  ring. Visuals and columns/note identical.

## Verification

- `tests/check-apple-polish.mjs`: **38/38 pass** — skip link, focus states,
  contrast approach, motion/transparency/contrast prefs, no-download-button
  guard, honesty-copy guards (photo-spoof, in-development, non-affiliation),
  FAQ copy/order preservation, footer Link/external split.
- Sandbox copy of gaze-site + patch overlay (no `.env*` copied, node_modules
  symlinked): `tsc --noEmit` shows only the **3 pre-existing baseline errors**
  (`LayoutProps`, two missing `gaze-icon-*.png` imports) — byte-identical
  before and after the patch. `eslint` on the 4 touched TSX files: **clean**.
  (One iteration was rejected here: sync `setState` in an effect for
  route-change closing tripped `react-hooks/set-state-in-effect`; replaced
  with the `popstate` subscription above.)
- Gaze-site source was treated read-only: all edits were composed in
  `Tools/Release/AppleSitePolish/files/`; the real tree was only read and
  copied to `/tmp` for checking.

## Lead must know

1. **No screenshot verification.** This environment has no browser/render tool,
   only web fetch — I did not visually observe the result. The changes are
   deliberately low-risk (type, spacing, focus, media queries), but someone
   should eyeball the nav, skip link (Tab from load), FAQ chevron, and footer
   in light + dark before merging.
2. **Pre-existing site issues noticed, not touched** (out of owned files):
   `tsc` already fails on `LayoutProps` and the missing `gaze-icon-light/
   dark.png` imports — worth a look independent of this patch.
3. Contrast choice preserves the 12px desktop nav size (Apple convention) and
   fixes it with ink-based color instead of larger type — flag if you'd rather
   bump the size.

## Root visual integration

Applied locally. Root made the skip-link target explicitly focusable; browser
activation now moves focus to main-content. Inspected 1440px desktop and 390px
mobile, light/dark: no horizontal overflow or broken images. Mobile Escape closes
the menu and restores its button's focus. A homepage axe audit reported zero
violations, with video/certain obscured contrast checks left for manual review.
Later HomeMotion changes are separately documented; this report is not a public
release approval. No deployment.
