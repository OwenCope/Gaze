# HomeMotion / Preview — report (Gus 2)

Homepage preview motion is now controllable and efficient. One file touched:
`src/components/notch-video.tsx`. Recorded assets, the `style` prop, and the
static poster are unchanged. No camera APIs, no recognition claims, nothing
labeled a live unlock test.

## Apply

From a gaze-site checkout at the revision this was diffed against:

```bash
patch -p1 < home-preview-motion.patch
# or copy files/src/components/notch-video.tsx over src/components/notch-video.tsx
node tests/check-preview-motion.mjs        # 33 static contract checks
```

`files/` mirrors the gaze-site `src/` path. MacScreen, page.tsx, globals.css,
auth, storage, and packages are untouched. The gaze-site tree was treated
read-only throughout; all validation ran in a secret-free `/tmp` copy
(`.env.local` excluded, installed `node_modules` copied, no credentials).

## What changed

- **Play/Pause preview button.** Always rendered, never hover-gated, top-right
  (`right-3 top-3`) so it stays clear of the center-bottom style switcher that
  rides on the same footage. Minimum 80×44px measured (69×44px on the narrow
  harness), `focus-visible` 2px solid white outline (measured), accurate
  accessible name (`Play preview` / `Pause preview`, `aria-pressed`). Visible
  label is a compact Play/Pause pill with a glyph.
- **Ref-driven playback.** `autoPlay` is gone; a playback effect pauses every
  hidden clip and plays only the selected style. Pause triggers: leaves the
  actual viewport (second IntersectionObserver, threshold 0.1 — the 600px
  near-viewport arming observer is preserved for mounting), `visibilitychange`
  while hidden, reduced-motion enable, or explicit user pause. Intent
  (`auto`/`play`/`pause`) survives style switches and offscreen re-entry, so a
  user pause stays paused and an explicit Play resumes on return.
- **Reduced motion.** Starts static; enabling it mid-playback pauses
  immediately (a Play pressed *before* it was enabled is demoted to `auto`,
  so it does not carry over). Explicit Play pressed *under* reduced motion
  still plays the chosen recording. Cross-fade forced off.
- **Cross-fade.** Pointer-driven style switches fade in 200ms (≤220ms budget);
  first paint (`initial={false}`), keyboard-driven changes (window
  pointerdown/keydown modality tracking), and reduced motion swap instantly.
  Opacity only.
- **Loading.** Hidden styles use `preload="none"` (measured `readyState` 0,
  nothing fetched); selected uses `metadata`, upgraded to `auto` while
  playback is wanted. `muted` + `playsInline` in JSX plus imperative
  `muted`/`defaultMuted` enforcement at attach and on every playback pass
  (`defaultMuted` has no React JSX equivalent). `loop` kept.
- **Failure/cleanup hygiene.** `play()` rejections resolve to a usable Play
  button (no unhandled promise). A generation counter means a stale `play()`
  continuation can only confirm its own pass — never restart a clip a newer
  pass paused or hid. Every observer/listener is removed on cleanup; unmount
  invalidates pending continuations and pauses all clips.

## Verification (isolated /tmp copy, installed deps, BrowserOS neo via agent-browser)

- `tests/check-preview-motion.mjs`: **33/33 pass**.
- `tsc --noEmit`: **0 errors** with the patch; baseline original also 0 at
  check time (an earlier `LayoutProps` error resolved once the dev server
  generated types — identical before/after in both runs).
- `eslint` on the touched file: **clean** (one iteration rejected for
  `set-state-in-effect` ×3 and `refs`-in-render; fixed via lazy observer
  fallbacks, dropping `visited` state for plain `preload="none"`, and a
  state-held clip registry).
- Browser, motion allowed: only the selected clip plays (`paused:false`,
  `readyState` 4; hidden `readyState` 0); Pause flips the name and stops
  everything; pause survives a style switch and an offscreen round-trip;
  Play resumes on re-entry; scroll-out pauses; homepage autoplays on scroll
  into view (at 639px viewport height the hero preview is only ~3px visible,
  correctly below the 0.1 play threshold until scrolled to).
- Browser, pointer vs keyboard: 60ms after a pointer-flagged switch both
  clips show running 200ms WAAPI animations at opacities 0.58/0.42, settling
  to 1/0; after a keydown-flagged switch the swap is instant with zero
  animations. Keyboard Enter on the focused button toggles pause.
- Browser, reduced motion (CDP media emulation): starts static with Play;
  explicit Play plays with zero fade animations; enabling mid-playback
  pauses immediately with Play shown. `visibilitychange` with hidden
  pauses (via property override + dispatched event).
- Screenshot verified: Pause pill top-right over footage, always visible.

## Lead must know

1. **Two real-behavior approximations.** (a) True tab-hide was not tested —
    headless CDP cannot background the tab; the listener→state→ref-pause
    wiring is verified via override + event. (b) True OS reduced-motion was
    not tested — CDP emulation drives the identical `matchMedia` path.
    (c) No `next build` run; dev-server + tsc + eslint + live checks only.
2. **agent-browser `click` does not set pointer modality** (synthetic path —
    the switch still works, just without fade). Verified the fade instead via
    dispatched `pointerdown` plus genuine CDP mouse down/up for the switch
    itself. Real-user pointer input fires the window listener normally.
3. **Homepage renders `MacScreen` non-interactive**, so the style cross-fade
    was exercised through a scratch harness page (`/preview-test`, /tmp copy
    only, not shipped, not in the patch).
4. The `/tmp/gaze-preview-check` copy and the `gus2-notch-preview` browser
    session were closed/stopped; the dev server is down. Nothing was written
    outside `Tools/Release/HomeMotion/Preview/` in this worktree, and the
    gaze-site checkout was never modified.

## Root integration (applied locally)

Root added a play-attempt revision so an explicit Play can retry after rejection
even when intent is already play. Browser fault injection rejected play() twice;
two successive clicks made two attempts and retained the usable Play button.
Combined full production build/lint passed. The original patch plus
root-integration.patch is applied; video asset replacement is a separate step.
