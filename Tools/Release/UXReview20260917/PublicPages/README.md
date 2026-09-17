# PublicPages patch (UXReview20260917)

Scoped secondary-page layout + release navigation patch. Applies to the
canonical site root (`gaze-site`) with `patch -p1 --fuzz=0 < public-pages.patch`.

## Files (patched copies, paths relative to site root)

- `src/components/page-intro.tsx` — header spacing `pt-14 pb-14 sm:pt-20 sm:pb-16`;
  title `clamp(2.5rem,6vw,4rem)` / `leading-[1.06]` / `-0.035em`, keeping
  `max-w-[22ch]`, `text-balance`, semibold; description `max-w-[42ch]`,
  `17px` / `sm:19px`, `leading-[1.55]`, keeping muted-ink + `mt-5`.
  API, alignment, copy, children unchanged. No new decoration.
- `src/components/page-links.tsx` — each page item is one `Link` (label +
  blurb + aria-hidden `→`); full-width flex row `min-h-20 py-5 gap-6` with
  bottom hairline; label 18px semibold, blurb 14px muted; site focus token
  (`outline-[var(--action)]`); two-column grid kept, inter-row gaps removed.
  Page list, filtering, Discord link, copy unchanged. No cards/hover motion.
- `src/components/release-card.tsx` — release name and cover image link to
  `/releases/${encodeURIComponent(release.tag)}`; existing notes link, image
  alt/loading/dimensions, dates, contributors, Beta badge unchanged. Cover
  `Link` is block-level with the existing `mt-6`, overflow clip and
  `rounded-[20px]` plus focus outline; `bg-[var(--surface)]` ring framing
  removed; no new frame/crop/scale/hover. Name link keeps heading styling
  with hover underline + focus outline.
- `src/app/not-found.tsx` — message and recovery links unchanged; adds
  `TopNav` and `PageLinks current="/404"`; fixed-nav clearance via
  `pt-28 sm:pt-32`; `max-w-[440px]` centered content kept for narrow screens.
  No auth or route-visibility changes.

## Proof

- `patch -p1 --fuzz=0` applied to temp copies of the originals reproduces all
  four staged files byte-for-byte (`cmp` identical).
- `MANIFEST.sha256` holds original SHA-256 hashes (site-root-relative paths).
- ESLint (installed `eslint-config-next`) on the four patched files: clean.
- `tsc --noEmit` on an overlay copy (full `src` + patched files, symlinked
  `node_modules`, no `.env` copied): zero errors in the four files; the only
  error is pre-existing/environmental (`LayoutProps` in `src/app/layout.tsx`,
  from `.next` generated types absent in the overlay).

## Not run

No visual/browser check — pages need Root review (`next dev`, visit a
secondary page, `/releases`, and a bad URL at desktop + 390px widths).
