# Home hero motion — Tova 2 report

First-visit entrance + pointer tilt for gaze-site's homepage hero. Original implementation; no new library, no CSS file, no scroll/parallax/float.

## Deliverables (this folder)

- `gaze-home-hero.patch` — applies from the gaze-site root with `patch -p1` (git-style headers; verified below). Touches only `src/app/page.tsx`, adds only `src/components/home-hero-motion.tsx`.
- `home-hero-motion.tsx`, `page.tsx` — final source copies (patch output verified byte-identical).
- `hero-resting.png` — resting hero after the intro on the temp prod build.

## What was built

`HomeHeroMotion` (`src/components/home-hero-motion.tsx`, `"use client"`) takes four server-rendered nodes — `headline`, `lede`, `actions`, `product` — and wraps each in a plain block `div` (margins collapse through, layout-neutral; confirmed by screenshot). `page.tsx` stays a server component; every section, CTA, security statement, and the skip link's `id`/`tabIndex` are untouched (diff is import + hero regrouping only).

**Entrance (WAAPI, fired pre-paint from an isomorphic layout effect; SSR markup has zero hidden styles):**

| Group | From | Duration | Delay | Easing |
|---|---|---|---|---|
| headline / lede / actions | `opacity 0, translateY(12px)` | 480ms | 0 / 60 / 120ms | `cubic-bezier(0.32,0.72,0,1)` |
| product frame | `opacity 0, translateY(24px) scale(0.985)` | 600ms | 120ms | same |

`fill: "backwards"` holds the opening frame through stagger delays; `fill` is otherwise `"none"`, so finish/cancel always falls back to the natural visible style. Cleanup cancels all animations. The session flag `gaze.homeIntro.v1` is written **on completion** (all `finished` promises resolve), not at start — a mid-intro unmount or StrictMode dev double-effect cancels the first pass without claiming the session, so the next mount replays instead of skipping an entrance nobody saw.

**Play gates (skip = leave SSR content exactly as-is):** reduced motion → effect more than 2500ms after first contentful paint (`LATE_HYDRATION_BUDGET_MS`; paint-anchored, not navigation-anchored, and deliberately not `readyState`, which fires ~600ms on fast connections) → `sessionStorage` unreadable → flag already set. Decision is a pure exported `decideIntro()`; outcome is exposed as `data-intro="played|skipped:<reason>"` on `[data-home-hero]` for verification.

**Tilt:** pointer position over the product zone drives `useMotionValue` targets through `useSpring({ duration: 0.4, bounce: 0 })` (framer-motion, already in use; duration/bounce form confirmed in the installed motion-dom types) rendered on an inner `motion.div` (`perspective: 1200px` on the static outer zone). Mapping: `rotateY = px·4°, rotateX = −py·4°` with ±0.5 clamping → hard cap ±2° per axis, surface tips toward the cursor. No React state per mousemove. `pointerType !== "mouse"` ignored; `(hover: hover) and (pointer: fine)` via `useSyncExternalStore` (SSR-safe, reacts to device changes); `useReducedMotion` disables immediately and zeroes the springs. `pointerleave` restores neutral. Text/CTAs never rotate (own element). `LiquidButton` inspected: no press transform exists, so nothing to double.

## Checks (secret-free /tmp copy, installed deps, ports 3127 dev / 3128 prod)

- `tsc --noEmit`: clean except pre-existing `layout.tsx` `LayoutProps` baseline error (present before my change; generated types).
- `eslint` on both files: clean (one `set-state-in-effect` hit reworked to `useSyncExternalStore`).
- `next build`: passes.
- SSR/`curl` (no-JS equivalent): all hero copy, skip link, `tabindex="-1"`, security section present; zero `opacity:0` inline styles.
- Prod, fresh profile: `data-intro="played"`, flag set ~1s after load (consistent with a ≥720ms entrance, not an instant skip); resting `opacity 1`, all transforms `none`, zero running animations.
- Reload in-session: `skipped:seen`, content visible.
- Reduced-motion emulation: `skipped:reduced-motion`, content visible; real mouse over product → no transform.
- Tilt, real CDP mouse: edge point (px 0.35, py 0.10) → `rotateX(−0.398°) rotateY(1.399°)` — exact formula match; far-outside pointer clamps at exactly ±2°; touch `pointermove` ignored; real mouse-leave → `none`; zone and headline transforms stay `none` throughout.
- Storage failure (fault-injected `sessionStorage` throw + init script, temp copy only): `skipped:no-storage`, content visible, no exception.
- Keyboard: skip-link + Tab navigation → no tilt, no errors from the component.
- `patch -p1 --dry-run` + apply on a pristine copy reproduces both files byte-for-byte.

## Unobserved / notes for the lead

- The staggered hide→reveal frames were not screenshot mid-flight (CLI round-trips are slower than the 720ms intro); entrance verified via `data-intro`, flag timing, and resting state, not visually frame-by-frame.
- `late-hydration` skip observed live on dev (paint 512ms, hydration >2500ms — the guard working as designed) but not on prod; the 2500ms budget is a heuristic.
- Console shows pre-existing Auth.js `ClientFetchError`s (no `AUTH_SECRET` in the secret-free copy; from layout's `SessionProvider`, unrelated to this change).
- One agent-browser flake: a tab once dropped to `about:blank` after a failed `focus` + Tab sequence; re-open fixed it, no site involvement.
- Microcopy ("Free and open source…") rides with the CTA group at 120ms — single group, no extra delay step.

## Root integration (applied locally)

The original patch plus root-integration.patch is applied. Root reduced the
late-hydration budget to 250ms after paint, probes storage writes before starting,
cancels an active intro on reduced-motion changes, resets spring values when
motion is disabled, and neutralizes tilt over media controls/on keyboard input.
Combined production build/lint passed. Fresh-browser inspection confirms played
with flag set; reload confirms skipped:seen; no horizontal overflow at 1440px.
The CLI screencast returned blank frames and is not visual proof of the entrance.
Do not describe that recording as a successful captured animation.
