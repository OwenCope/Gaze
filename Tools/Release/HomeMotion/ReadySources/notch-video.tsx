"use client";

import { useEffect, useRef, useState } from "react";
import { motion } from "framer-motion";

export type NotchStyle = "normal" | "semiGlass" | "liquidGlass";

const CLIPS: Record<NotchStyle, string> = {
  normal: "/previews/gaze-panel-normal.mp4",
  semiGlass: "/previews/gaze-panel-semi-liquid-glass.mp4",
  liquidGlass: "/previews/gaze-panel-native-liquid-glass.mp4",
};

/**
 * Cross-fade length for a pointer-driven style switch. 200ms keeps the
 * continuity between panel materials without lingering past the 220ms budget.
 */
const FADE_SECONDS = 0.2;

const POSTERS: Record<NotchStyle, string> = {
  normal: "/previews/gaze-panel-normal-poster.png",
  semiGlass: "/previews/gaze-panel-semi-liquid-glass-poster.png",
  liquidGlass: "/previews/gaze-panel-native-liquid-glass-poster.png",
};

type Intent = "auto" | "play" | "pause";

function prefersReducedMotionNow(): boolean {
  if (typeof window === "undefined" || typeof window.matchMedia !== "function") {
    return false;
  }
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

/** Local media previews; playback never accesses a camera. */
export function NotchVideo({ style }: { style: NotchStyle }) {
  const hostRef = useRef<HTMLDivElement>(null);
  // Stable registry, not a ref: element attach callbacks may not read refs.
  const [clips] = useState(() => new Map<NotchStyle, HTMLVideoElement | null>());
  /** Generation counter: each playback pass owns its `play()` continuations. */
  const opRef = useRef(0);
  /** Latest `style` for element event handlers, which outlive a render. */
  const styleRef = useRef(style);
  const previousStyleRef = useRef(style);

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
  const [playAttempt, setPlayAttempt] = useState(0);
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
      ([entry]) => setInView(entry.isIntersecting && entry.intersectionRatio >= 0.1),
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
  const showPoster = reducedMotion && intent === "auto";

  // Drive playback through refs. State updates happen in element events and
  // play() continuations only — never synchronously here.
  useEffect(() => {
    const op = ++opRef.current;
    const previous = clips.get(previousStyleRef.current);
    const sharedTimeline = style !== "liquidGlass" && previousStyleRef.current !== "liquidGlass";
    const phaseTime = sharedTimeline ? previous?.currentTime ?? 0 : 0;
    const changedStyle = previousStyleRef.current !== style;
    previousStyleRef.current = style;
    for (const [key, el] of clips) {
      if (el && key !== style && !el.paused) el.pause();
    }
    const current = clips.get(style) ?? null;
    if (!current) return;
    let removeSeekListener = () => {};
    if (changedStyle) {
      const seek = () => {
        if (opRef.current !== op || styleRef.current !== style) return;
        current.currentTime = Number.isFinite(current.duration)
          ? Math.min(phaseTime, Math.max(0, current.duration - 0.01)) : phaseTime;
      };
      if (current.readyState >= 1) seek();
      else {
        current.addEventListener("loadedmetadata", seek, { once: true });
        removeSeekListener = () => current.removeEventListener("loadedmetadata", seek);
      }
    }
    // React's `muted` prop does not reliably stick on every render; the
    // property (and `defaultMuted`, which has no JSX equivalent) is enforced
    // here and at attach time so the clip can never play with sound.
    current.muted = true;
    current.defaultMuted = true;
    if (!shouldPlay) {
      if (!current.paused) current.pause();
      return removeSeekListener;
    }
    if (!current.paused) return removeSeekListener;
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
    return removeSeekListener;
  }, [clips, style, shouldPlay, playAttempt]);

  const toggle = () => {
    setIntent(isPlaying ? "pause" : "play");
    if (!isPlaying) setPlayAttempt((attempt) => attempt + 1);
  };

  return (
    <div ref={hostRef} className="relative h-full w-full overflow-hidden bg-black">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={POSTERS[style]}
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
            poster={POSTERS[key]}
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
            animate={{ opacity: key === style && !showPoster ? 1 : 0 }}
            transition={{ duration: canAnimate ? FADE_SECONDS : 0, ease: "easeOut" }}
            className="absolute inset-0 h-full w-full object-fill"
          />
        ))}

      {/* Playback remains available directly on the preview. */}
      <button
        type="button"
        onClick={toggle}
        aria-label={isPlaying ? "Pause preview" : "Play preview"}
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
