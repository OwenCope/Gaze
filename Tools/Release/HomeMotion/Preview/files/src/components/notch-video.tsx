"use client";

import { useEffect, useRef, useState } from "react";
import { motion } from "framer-motion";

export type NotchStyle = "normal" | "semiGlass" | "liquidGlass";

const CLIPS: Record<NotchStyle, string> = {
  normal: "/clips/normal.mp4",
  semiGlass: "/clips/semiLiquidGlass.mp4",
  liquidGlass: "/clips/liquidGlass.mp4",
};

/**
 * Cross-fade length for a pointer-driven style switch. 200ms keeps the
 * continuity between panel materials without lingering past the 220ms budget.
 */
const FADE_SECONDS = 0.2;

type Intent = "auto" | "play" | "pause";

function prefersReducedMotionNow(): boolean {
  if (typeof window === "undefined" || typeof window.matchMedia !== "function") {
    return false;
  }
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

/**
 * The real app, recorded.
 *
 * A CSS recreation can only approximate the material — the app draws
 * `.ultraThinMaterial` and macOS 26's `glassEffect`, neither of which the web
 * has. These are recordings of the actual panel over the actual wallpaper.
 *
 * All three are cross-faded rather than swapped into one `src`, because
 * changing `src` tears the frame and restarts the sequence. That means three
 * files, so nothing is fetched until the section is near the viewport — 13MB
 * of demo has no business loading while someone reads the hero. A poster of
 * the same desktop stands in until the first frame decodes, so the screen is
 * never briefly black.
 *
 * Playback contract (all of it driven through video refs — CSS opacity alone
 * never stops a clip):
 *
 * - Only the selected style may play; every hidden clip is paused.
 * - The preview pauses when it leaves the actual viewport or the document is
 *   hidden, and an explicit user pause survives style switches and re-entry.
 * - Reduced motion starts static and pauses the moment it is enabled (a Play
 *   pressed before that does not carry over); an explicit Play pressed under
 *   reduced motion still plays the chosen recording, but the cross-fade stays
 *   off. The fade also stays off on first paint and for keyboard-driven
 *   changes — it is pointer-driven switches only.
 * - Hidden styles load nothing (`preload="none"`); the selected clip uses
 *   `metadata` until playback actually needs the bytes.
 * - `play()` rejections resolve to a usable Play button, never an unhandled
 *   promise, and a stale `play()` continuation never restarts a clip a newer
 *   pass paused or hid (it may only confirm its own generation).
 */
export function NotchVideo({ style }: { style: NotchStyle }) {
  const hostRef = useRef<HTMLDivElement>(null);
  // Stable registry, not a ref: element attach callbacks may not read refs.
  const [clips] = useState(() => new Map<NotchStyle, HTMLVideoElement | null>());
  /** Generation counter: each playback pass owns its `play()` continuations. */
  const opRef = useRef(0);
  /** Latest `style` for element event handlers, which outlive a render. */
  const styleRef = useRef(style);

  // The lazy init covers the no-IntersectionObserver fallback without
  // a setState-in-effect; the server renders unarmed, as before.
  const noObserver =
    typeof window !== "undefined" && !("IntersectionObserver" in window);
  /** Near the viewport (with margin): mount the clips. Preserved behaviour. */
  const [armed, setArmed] = useState(noObserver);
  /** Actually in the viewport (no margin): allowed to play. */
  const [inView, setInView] = useState(noObserver);
  const [docHidden, setDocHidden] = useState(
    () => typeof document !== "undefined" && document.hidden,
  );
  const [reducedMotion, setReducedMotion] = useState(prefersReducedMotionNow);
  /** Explicit user choice; `auto` plays unless reduced motion asks for static. */
  const [intent, setIntent] = useState<Intent>("auto");
  /** Whether the selected clip is currently playing — synced from the element. */
  const [isPlaying, setIsPlaying] = useState(false);
  /** Last input modality, for gating the cross-fade to pointer switches. */
  const [pointerDriven, setPointerDriven] = useState(false);

  useEffect(() => {
    styleRef.current = style;
  }, [style]);

  useEffect(() => {
    const host = hostRef.current;
    if (!host || !("IntersectionObserver" in window)) return;
    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setArmed(true);
          io.disconnect();
        }
      },
      { rootMargin: "600px" },
    );
    io.observe(host);
    return () => io.disconnect();
  }, []);

  useEffect(() => {
    const host = hostRef.current;
    if (!host || !("IntersectionObserver" in window)) return;
    const io = new IntersectionObserver(
      ([entry]) => setInView(entry.isIntersecting),
      { threshold: 0.1 },
    );
    io.observe(host);
    return () => io.disconnect();
  }, []);

  useEffect(() => {
    const onVisibility = () => setDocHidden(document.hidden);
    document.addEventListener("visibilitychange", onVisibility);
    return () => document.removeEventListener("visibilitychange", onVisibility);
  }, []);

  useEffect(() => {
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    const onChange = () => {
      setReducedMotion(mq.matches);
      if (mq.matches) {
        // A Play pressed before reduced motion was enabled does not carry
        // over: enabling pauses immediately, and only a fresh explicit Play
        // under reduced motion resumes the chosen recording.
        setIntent((prev) => (prev === "play" ? "auto" : prev));
      }
    };
    onChange();
    mq.addEventListener("change", onChange);
    return () => mq.removeEventListener("change", onChange);
  }, []);

  useEffect(() => {
    const onPointerDown = () => setPointerDriven(true);
    const onKeyDown = () => setPointerDriven(false);
    window.addEventListener("pointerdown", onPointerDown, { passive: true });
    window.addEventListener("keydown", onKeyDown);
    return () => {
      window.removeEventListener("pointerdown", onPointerDown);
      window.removeEventListener("keydown", onKeyDown);
    };
  }, []);

  // Unmount: invalidate pending play() continuations and stop every clip.
  // (Node removal stops playback on its own; this makes it explicit.)
  useEffect(() => {
    return () => {
      opRef.current += 1;
      for (const el of clips.values()) {
        if (el && !el.paused) {
          try {
            el.pause();
          } catch {
            // Element already gone — nothing left to stop.
          }
        }
      }
    };
  }, [clips]);

  const wantMotion = intent === "play" ? true : intent === "pause" ? false : !reducedMotion;
  const shouldPlay = armed && inView && !docHidden && wantMotion;
  // Pointer-driven switches only, and never under reduced motion. First paint
  // is covered by `initial={false}` on each clip (mounts at rest, no fade).
  const canAnimate = pointerDriven && !reducedMotion;

  // Drive playback through refs. State updates happen in element events and
  // play() continuations only — never synchronously here.
  useEffect(() => {
    const op = ++opRef.current;
    for (const [key, el] of clips) {
      if (el && key !== style && !el.paused) el.pause();
    }
    const current = clips.get(style) ?? null;
    if (!current) return;
    // React's `muted` prop does not reliably stick on every render; the
    // property (and `defaultMuted`, which has no JSX equivalent) is enforced
    // here and at attach time so the clip can never play with sound.
    current.muted = true;
    current.defaultMuted = true;
    if (!shouldPlay) {
      if (!current.paused) current.pause();
      return;
    }
    if (!current.paused) return;
    const pending = current.play();
    if (pending && typeof pending.then === "function") {
      pending.then(
        () => {
          if (opRef.current === op && styleRef.current === style) setIsPlaying(true);
        },
        () => {
          // Rejection (autoplay policy, interrupted load, missing bytes):
          // surface a usable Play button instead of an unhandled promise.
          if (opRef.current === op && styleRef.current === style) setIsPlaying(false);
        },
      );
    }
  }, [clips, style, shouldPlay]);

  const toggle = () => setIntent(isPlaying ? "pause" : "play");

  return (
    <div ref={hostRef} className="relative h-full w-full overflow-hidden bg-black">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src="/desktop.jpg"
        alt=""
        aria-hidden
        className="absolute inset-0 h-full w-full object-fill"
      />

      {armed &&
        (Object.keys(CLIPS) as NotchStyle[]).map((key) => (
          <motion.video
            key={key}
            ref={(el) => {
              clips.set(key, el);
              if (el) {
                el.muted = true;
                el.defaultMuted = true;
              }
            }}
            src={CLIPS[key]}
            poster="/desktop.jpg"
            loop
            muted
            playsInline
            preload={key === style ? (shouldPlay ? "auto" : "metadata") : "none"}
            aria-hidden
            onPlay={() => {
              if (styleRef.current === key) setIsPlaying(true);
            }}
            onPause={() => {
              if (styleRef.current === key) setIsPlaying(false);
            }}
            initial={false}
            animate={{ opacity: key === style ? 1 : 0 }}
            transition={{ duration: canAnimate ? FADE_SECONDS : 0, ease: "easeOut" }}
            className="absolute inset-0 h-full w-full object-fill"
          />
        ))}

      {/* Always visible, never hover-gated: top-right keeps it clear of the
          center-bottom style switcher that rides on this same footage. */}
      <button
        type="button"
        onClick={toggle}
        aria-label={isPlaying ? "Pause preview" : "Play preview"}
        aria-pressed={isPlaying}
        className="absolute right-3 top-3 flex min-h-[44px] min-w-[44px] items-center justify-center gap-1.5 rounded-full border border-white/25 bg-black/60 px-3 text-[13px] font-medium text-white backdrop-blur-[14px] backdrop-saturate-[1.7] transition-colors hover:bg-black/75 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
      >
        <svg aria-hidden width="11" height="12" viewBox="0 0 11 12" fill="currentColor">
          {isPlaying ? (
            <path d="M0 0h3.7v12H0zM7.3 0H11v12H7.3z" />
          ) : (
            <path d="M0 0l11 6-11 6z" />
          )}
        </svg>
        <span aria-hidden>{isPlaying ? "Pause" : "Play"}</span>
      </button>
    </div>
  );
}
