"use client";

import { useEffect, useLayoutEffect, useRef } from "react";
import type { ReactNode } from "react";

// Layout effect before paint on the client, plain effect on the server (where
// `window` does not exist and layout effects warn). The intro starts from this
// hook so the opening frame is set before the browser paints the hydrated
// tree — a post-paint effect would flash the resting state for a frame first.
const useIsomorphicLayoutEffect = typeof window === "undefined" ? useEffect : useLayoutEffect;

/** Played once per browser session, then skipped until a genuinely new visit. */
export const HOME_INTRO_KEY = "gaze.homeIntro.v1";

/** The site's own curve (globals.css, Theme.Motion.standard, Reveal). */
const EASE_CSS = "cubic-bezier(0.32, 0.72, 0, 1)";

/** Copy groups: fade + rise, 480ms, staggered 0/60/120ms in reading order. */
const COPY_DURATION_MS = 480;
const COPY_TRAVEL_PX = 12;
const COPY_DELAYS_MS = [0, 60, 120] as const;

/** Product frame: a longer, slightly deeper settle, starting with the CTAs. */
const PRODUCT_DURATION_MS = 600;
const PRODUCT_DELAY_MS = 120;
const PRODUCT_TRAVEL_PX = 24;
const PRODUCT_SCALE_FROM = 0.985;

/**
 * How long after first contentful paint the intro may still begin. Past this
 * the visitor has been looking at the resting page, and hiding content to
 * replay an entrance would be the page performing at them
 * (emil-marketing-pages: motion must map to user input; an entrance that
 * fires after reading began does not). Anchored to paint, not to navigation
 * start: server time, compile time, and blank-tab time are not reading time.
 * A missing paint entry means nothing has painted yet, so it is never late.
 * Heuristic — see REPORT.md.
 */
const LATE_HYDRATION_BUDGET_MS = 250;

function firstContentfulPaintMs(): number | null {
  const paints = performance.getEntriesByType("paint");
  const entry =
    paints.find((e) => e.name === "first-contentful-paint") ??
    paints.find((e) => e.name === "first-paint") ??
    null;
  return entry ? entry.startTime : null;
}

export type IntroSkipReason = "reduced-motion" | "late-hydration" | "no-storage" | "seen";

export function decideIntro(input: {
  reducedMotion: boolean;
  lateHydration: boolean;
  storageUsable: boolean;
  seen: boolean;
}): { play: boolean; reason?: IntroSkipReason } {
  if (input.reducedMotion) return { play: false, reason: "reduced-motion" };
  if (input.lateHydration) return { play: false, reason: "late-hydration" };
  if (!input.storageUsable) return { play: false, reason: "no-storage" };
  if (input.seen) return { play: false, reason: "seen" };
  return { play: true };
}

/** First-visit entrance; server-rendered content remains visible without JavaScript. */
export function HomeHeroMotion({
  headline,
  lede,
  actions,
  product,
}: {
  headline: ReactNode;
  lede: ReactNode;
  actions: ReactNode;
  product: ReactNode;
}) {
  const rootRef = useRef<HTMLDivElement | null>(null);
  const copyRefs = useRef<Array<HTMLDivElement | null>>([]);
  const productZoneRef = useRef<HTMLDivElement | null>(null);

  useIsomorphicLayoutEffect(() => {
    const groups = copyRefs.current.filter((el): el is HTMLDivElement => el !== null);
    const productZone = productZoneRef.current;
    const root = rootRef.current;

    const reducedMotion =
      typeof window.matchMedia === "function" &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    // Load-event timing is deliberately NOT a signal: on a fast connection
    // `load` can fire ~600ms in, long before anyone has started reading, and
    // gating on it skips an intro that should play. Time-since-paint is the
    // honest measure of "the visitor has been looking at static content".
    const paintedAt = firstContentfulPaintMs();
    const lateHydration = paintedAt !== null && performance.now() - paintedAt > LATE_HYDRATION_BUDGET_MS;

    let seen = false;
    let storageUsable = true;
    try {
      seen = window.sessionStorage.getItem(HOME_INTRO_KEY) !== null;
      if (!seen) {
        window.sessionStorage.setItem(`${HOME_INTRO_KEY}.probe`, "1");
        window.sessionStorage.removeItem(`${HOME_INTRO_KEY}.probe`);
      }
    } catch {
      // Storage blocked (private mode, disabled cookies/storage): skip the
      // intro rather than throw. Content stays exactly as SSR rendered it.
      storageUsable = false;
    }

    const decision = decideIntro({ reducedMotion, lateHydration, storageUsable, seen });
    if (!decision.play) {
      root?.setAttribute("data-intro", `skipped:${decision.reason ?? "unknown"}`);
      return;
    }
    root?.setAttribute("data-intro", "played");

    const running: Animation[] = [];
    const media = window.matchMedia("(prefers-reduced-motion: reduce)");
    const stopIfReduced = () => {
      if (media.matches) for (const animation of running) animation.cancel();
    };
    media.addEventListener("change", stopIfReduced);
    groups.forEach((el, i) => {
      running.push(
        el.animate(
          [
            { opacity: "0", transform: `translateY(${COPY_TRAVEL_PX}px)` },
            { opacity: "1", transform: "translateY(0px)" },
          ],
          {
            duration: COPY_DURATION_MS,
            delay: COPY_DELAYS_MS[Math.min(i, COPY_DELAYS_MS.length - 1)],
            easing: EASE_CSS,
            // Hold the opening frame through the stagger delay; with fill
            // "none" the element falls back to its natural (visible) style the
            // moment the animation is cancelled or finishes.
            fill: "backwards",
          },
        ),
      );
    });
    if (productZone) {
      running.push(
        productZone.animate(
          [
            {
              opacity: "0",
              transform: `translateY(${PRODUCT_TRAVEL_PX}px) scale(${PRODUCT_SCALE_FROM})`,
            },
            { opacity: "1", transform: "translateY(0px) scale(1)" },
          ],
          {
            duration: PRODUCT_DURATION_MS,
            delay: PRODUCT_DELAY_MS,
            easing: EASE_CSS,
            fill: "backwards",
          },
        ),
      );
    }

    // Claim completion, not start: the session flag is written only if every
    // group finishes. A mid-intro unmount cancels the animations, their
    // `finished` promises reject, and a later mount replays rather than
    // skipping an entrance nobody saw. This is also what keeps the intro
    // working under React StrictMode's dev double-effect (mount, cancel,
    // re-run): the cancelled first pass writes nothing, the second pass
    // plays to completion and claims the session.
    Promise.all(running.map((animation) => animation.finished))
      .then(() => {
        try {
          window.sessionStorage.setItem(HOME_INTRO_KEY, "1");
        } catch {
          // Read worked but the write failed — nothing to recover; the
          // entrance already played and cancels cleanly.
        }
      })
      .catch(() => {
        // Cancelled or otherwise interrupted: leave the flag unset so the
        // next mount replays.
      });

    return () => {
      media.removeEventListener("change", stopIfReduced);
      // Cancel restores the natural styles (fill "none" holds nothing), so an
      // unmount mid-intro can never leave content hidden or offset.
      for (const animation of running) {
        try {
          animation.cancel();
        } catch {
          // Already finished or already cancelled — nothing held either way.
        }
      }
    };
  }, []);

  return (
    <div ref={rootRef} data-home-hero="">
      <div
        ref={(el) => {
          copyRefs.current[0] = el;
        }}
      >
        {headline}
      </div>
      <div
        ref={(el) => {
          copyRefs.current[1] = el;
        }}
      >
        {lede}
      </div>
      <div
        ref={(el) => {
          copyRefs.current[2] = el;
        }}
      >
        {actions}
      </div>
      <div ref={productZoneRef}>{product}</div>
    </div>
  );
}
