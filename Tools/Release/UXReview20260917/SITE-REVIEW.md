# Gaze website UX review — source review, not browser verification

Canonical checkout reviewed read-only: `/Users/owencope/Developer/gaze-site`.
Report owned in this worktree only. No patches applied. Completed work
(FAQ/navigation motion, frameless media, pacing, tester-note draft recovery,
explicit publish/unpublish, metadata concurrency protection) is taken as done
and is not re-verified or re-proposed here.

## 1. Route coverage

Inventory from `find src/app -type f` (sorted), plus the components each route
actually imports. API routes are supporting context, not UI pages.

| Route | Source inspected | Composition / components followed |
|---|---|---|
| `/` | `src/app/page.tsx` | `top-nav.tsx`, `home-hero-motion.tsx`, `mac-screen.tsx`, `live-demo.tsx`, `features-carousel.tsx`, `screenshot-gallery.tsx`, `faqs.tsx`, `ui/footer-section.tsx`, `ui/liquid-glass-button.tsx` |
| `/features` | `src/app/features/page.tsx` | `page-intro.tsx`, `product-tour.tsx`, `feature-list.tsx`, `page-links.tsx`, `top-nav.tsx` |
| `/security` | `src/app/security/page.tsx` | `page-intro.tsx`, `page-links.tsx`, `top-nav.tsx`, `app-icon.tsx` |
| `/how-it-works` | `src/app/how-it-works/page.tsx` | `page-intro.tsx`, `setup-walkthrough.tsx`, `page-links.tsx`, `top-nav.tsx` |
| `/credits` | `src/app/credits/page.tsx` | `credits-scroller.tsx`, `credit-links.tsx`, `ui/contact-cards.tsx` (via CreditLinks), `ui/footer-section.tsx`, `top-nav.tsx` |
| `/releases` | `src/app/releases/page.tsx` | `page-intro.tsx`, `release-card.tsx`, `ui/footer-section.tsx`, `top-nav.tsx` |
| `/releases/[tag]` | `src/app/releases/[tag]/page.tsx` | `back-link.tsx`, `release-gallery.tsx`, `disk-image.tsx`, `ui/footer-section.tsx`, `top-nav.tsx` |
| `/signin` | `src/app/signin/page.tsx` | `ui/sign-in.tsx` (SignInPage), `email-sign-in.tsx` |
| `/testers` | `src/app/testers/page.tsx` | `top-nav.tsx`, `app-icon.tsx`, `ui/liquid-glass-button.tsx`, `icons.tsx` |
| `/admin` | `src/app/admin/page.tsx` | `site-nav.tsx`, `traffic-panel.tsx`, `settings-panel.tsx`, `ui/liquid-glass-button.tsx` |
| `/admin/new` | `src/app/admin/new/page.tsx` | `site-nav.tsx`, `back-link.tsx`, `release-composer.tsx` |
| `/admin/[tag]/edit` | `src/app/admin/[tag]/edit/page.tsx` | `site-nav.tsx`, `back-link.tsx`, `release-composer.tsx` |
| `/admin/readme` | `src/app/admin/readme/page.tsx` | `site-nav.tsx`, `back-link.tsx`, `readme-editor.tsx` |
| `/admin/testers` | `src/app/admin/testers/page.tsx` | `site-nav.tsx`, `back-link.tsx`, `testers-manager.tsx`, `roles-manager.tsx`, `ui/modal.tsx`, `ui/color-picker.tsx` |
| 404 | `src/app/not-found.tsx` | standalone (AppIcon only — see F10) |
| API (context only) | `api/auth/[...nextauth]`, `api/latest`, `api/me`, `api/readme`, `api/releases`, `api/roles`, `api/settings`, `api/signin-code`, `api/testers`, `api/upload`, `dl/[file]` | read only where a UX finding depends on client behavior (email resend, role/tester confirmation) |

Also inspected: `src/app/layout.tsx`, `src/app/globals.css`,
`account-button.tsx`, `site-nav.tsx`, `top-nav.tsx`, `page-intro.tsx`,
`release-card.tsx`, `release-gallery.tsx`, `screenshot-gallery.tsx`,
`feature-list.tsx`, `faqs.tsx`, `live-demo.tsx`, `product-tour.tsx`,
`setup-walkthrough.tsx`, `page-links.tsx`, `credit-links.tsx`,
`credits-scroller.tsx`, `ui/modal.tsx`, `ui/sign-in.tsx`, `traffic-panel.tsx`.

## 2. Findings (new, max ten)

### F1. Release-card cover image is a dead end
- File: `src/components/release-card.tsx`, JSX anchor: the `{cover && (…)}` block
  (lines ~26–31) — bare `<img>` inside a rounded container, sibling of the
  "Read release notes" `Link` (line ~33).
- Consequence: the largest visual on each releases row does nothing when
  clicked. Users tap the picture expecting the release and get no response,
  then must find the small text link below.
- Proposed change: wrap the cover in the same `Link` used for "Read release
  notes" (`href={/releases/${encodeURIComponent(release.tag)}}`), keep the
  `<img alt>` as-is. One-line ownership: `release-card.tsx` only.

### F2. Release-gallery lightbox strands keyboard and screen-reader users
- File: `src/components/release-gallery.tsx`, anchors: `ReleaseGallery`
  (`open` state, lines ~18/49–66) and the `role="dialog"` viewer (lines
  ~69–103); `close`/`step` callbacks (lines ~20–25).
- Consequence: opening a picture never moves focus into the dialog and closing
  never returns focus to the thumbnail that opened it; there is no position
  announcement ("2 of 5"). Keyboard users lose their place in the grid on
  every open/close cycle.
- Proposed change: on open, focus the Close button; on close, restore focus to
  `thumbnailRefs[closedIndex]` (add a refs array to the grid buttons); set the
  dialog `aria-label` to `` `${img.alt} (${open+1} of ${images.length})` ``.
  Ownership: `release-gallery.tsx` only. No change to grid layout.

### F3. Draft rows on the admin dashboard link to a page that 404s
- File: `src/app/admin/page.tsx`, anchor: "Recent releases" list item link
  (lines ~146–167): `href={/releases/${encodeURIComponent(r.tag)}}` renders
  for every record including `r.draft`.
- Consequence: a draft has no public page, so clicking its title from the
  dashboard lands the owner on the 404 page — the most common click on the
  most common admin screen.
- Proposed change: `href={r.draft ? `/admin/${encodeURIComponent(r.tag)}/edit` : `/releases/…`}`
  and render the existing "Draft · " prefix (line ~157) as a badge so the
  destination is predictable. Ownership: `src/app/admin/page.tsx` only.

### F4. Composer gives video clips no description field, and release pages render undescribed `<video>`
- Files: `src/components/release-composer.tsx` (media list item, lines
  ~431–474; video branch line ~457–459 renders static "Video clip") and
  `src/app/releases/[tag]/page.tsx` (video block lines ~135–148: bare
  `<video … controls>` with no `aria-label`).
- Consequence: every attached clip ships with no accessible description;
  screen-reader users get an anonymous video control on the release page.
  Permission/auth boundaries untouched — this is metadata the author already
  provides for images.
- Proposed change: add the same per-item text input used for image `alt` to
  video items (label "Clip description"), persist as `videos: {src, alt}[]`
  (or parallel caption field), and render `aria-label={alt || release.name}`
  on the release-page `<video>`. Ownership: composer + release detail page
  (needs a store shape decision by root; UI-only alternative: caption input
  without schema change is not possible — flagging so root picks).

### F5. Composer hides the card summary the author is actually writing
- File: `src/components/release-composer.tsx`, anchor: notes `<textarea
  id="body">` + hint (lines ~331–344): "The first line that isn't a heading or
  a bullet becomes the summary on the card."
- Consequence: the rule is described but never shown, so authors discover what
  the card says only after publishing and opening `/releases`.
- Proposed change: render a read-only "Card summary" preview line under the
  hint, derived with the same first-non-heading-non-bullet rule, updating as
  `body` changes (empty state: "No summary yet — the card will show the title
  only"). Ownership: `release-composer.tsx` only.

### F6. Sign-in reason copy misdescribes admin bounces
- File: `src/app/signin/page.tsx`, anchor: `reason` record (lines ~36–39) —
  keys exist only for `/releases` and `/testers`; every admin callback
  (`/admin`, `/admin/new`, `/admin/readme`, `/admin/testers`) falls through to
  the default `description="Access releases and your tester account."`
- Consequence: an owner bounced from `/admin/new` is told this sign-in is
  about "releases and your tester account" — confusing at exactly the moment
  they need confidence they are at the right door.
- Proposed change: `description={callbackUrl ? (reason[callbackUrl] ?? "Sign in to continue to the site admin.") : undefined}`.
  Ownership: `src/app/signin/page.tsx` only.

### F7. Account menu has no Escape path and blur-close races menu taps
- File: `src/components/account-button.tsx`, anchors: trigger `<button
  aria-haspopup="menu">` with `onBlur={() => setTimeout(() => setOpen(false),
  120)}` (line ~67); menu `motion.div role="menu"` (lines ~87–108) with no
  key handler.
- Consequence: keyboard users cannot Escape out of the menu; pointer users can
  have the menu close between blur and link activation on slow frames. Focus
  is never returned to the trigger.
- Proposed change: add `onKeyDown` on the wrapper closing on Escape + refocus
  trigger; replace blur-timeout close with close-on-`signOut`/link-activate
  plus outside-pointer close (same pattern `top-nav.tsx` already uses).
  Ownership: `account-button.tsx` only.

### F8. Tester header download button names a tag, not the thing being downloaded
- File: `src/app/testers/page.tsx`, anchor: header CTA (lines ~88–94):
  `<a …>Download {latest.tag}</a>` — no release name, no size, no beta/private
  context, positioned far above the build card that carries the notes.
- Consequence: a tester grabs "Download v0.9" without knowing what changed,
  how big it is, or which notes apply; the button duplicates the per-build
  "Download · {size}" row (line ~151–155) with less information.
- Proposed change: label `Download {latest.name} · {size(latest.download.size)}`
  reusing the existing `size()` helper, and add `aria-describedby` pointing at
  the first build card heading. Ownership: `src/app/testers/page.tsx` only.

### F9. Email-code resend has no cooldown, inviting code spam
- File: `src/components/email-sign-in.tsx`, anchor: "Request a new code"
  button (lines ~125–128) calling `requestCode` with no timer; `busy` only
  covers in-flight.
- Consequence: each tap issues a fresh six-digit code and invalidates the
  previous one, so a double-tap leaves the user typing a dead code and seeing
  "That code isn't right or has expired" — a self-inflicted failure loop.
- Proposed change: 30-second resend cooldown after each successful send
  (`resendAt` timestamp state; button disabled with "New code in Ns" label),
  preserving existing error/validation behavior. Ownership:
  `email-sign-in.tsx` only.

### F10. 404 page ships no site chrome
- File: `src/app/not-found.tsx` (whole file, 32 lines): standalone `<main>`
  with AppIcon + two links; no `TopNav`, no footer, no page list.
- Consequence: a mistyped `/releases/<tag>` URL — the likeliest 404 on this
  site — drops the visitor outside the site's navigation with no way forward
  except Home/Releases.
- Proposed change: render `TopNav` above and the standard `Footer` below the
  existing centered block (same props as `releases/page.tsx` footer).
  Ownership: `src/app/not-found.tsx` only.

## 3. Ranked shortlist (implementable in the rest of an hour, non-overlapping files)

1. F3 — `src/app/admin/page.tsx` (draft link target). Smallest diff, fixes a
   guaranteed 404 on the owner's main loop.
2. F6 — `src/app/signin/page.tsx` (admin reason fallback). One expression,
   removes a confusing dead-end message.
3. F1 — `src/components/release-card.tsx` (link the cover). One wrapper,
   highest public-page tap-target payoff.
4. F9 — `src/components/email-sign-in.tsx` (resend cooldown). Self-contained
   state; stops the expired-code loop.
5. F7 — `src/components/account-button.tsx` (Escape + focus return). Contained
   a11y fix reusing the top-nav outside-dismiss pattern.
6. F2 — `src/components/release-gallery.tsx` (lightbox focus + position).
   Slightly larger; pairs naturally with F7 if time remains.
7. F10 — `src/app/not-found.tsx` (add chrome). Trivial JSX, low traffic but
   zero risk.
8. F5 — `src/components/release-composer.tsx` (summary preview). Display-only
   derivation; no schema change.
9. F8 — `src/app/testers/page.tsx` (header download label). Copy + helper
   reuse; needs care not to crowd mobile header.
10. F4 — composer + release detail (video descriptions). Ranked last only
    because it needs root's store-shape call before implementation.

## 4. Explicit non-goals honored

- No reimplementation or verification of FAQ/navigation motion, frameless
  media, pacing, tester-note draft recovery, publish/unpublish, or metadata
  concurrency work.
- No permission or authentication boundary changes: private-release 404
  behavior, tester/admin gating, and role semantics are described, never
  altered.
- No production services exercised, no sign-in emails sent, no uploads, no
  deployments, no git operations.
- This is a source review only. Nothing above is browser-verified; visual,
  motion, and responsive behavior await the reference head's findings and
  root's running-build inspection.
