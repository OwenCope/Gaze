"use client";

import { useState, useSyncExternalStore } from "react";
import { useTheme } from "next-themes";

/**
 * One small glyph that cycles light → dark → auto.
 *
 * This was a three-segment sliding pill — a whole floating control, taller than the bar it
 * sat in and the brightest thing on the page. In a 48px Apple-style nav made of 12px text
 * with no backgrounds on anything, a white capsule with three icons in it is the only
 * object up there, so the eye goes straight to the least important control on the site.
 *
 * Apple's own nav has no theme control at all. The closest honest thing is a single glyph
 * that matches the links beside it and says what it is by what it draws: sun, moon, or
 * half-filled for "follow the system". Three states still reachable, one target, no chrome.
 */

const ORDER = ["light", "dark", "system"] as const;
type Mode = (typeof ORDER)[number];

const LABEL: Record<Mode, string> = {
  light: "Light appearance",
  dark: "Dark appearance",
  system: "Match system appearance",
};

const subscribe = () => () => {};

export function ThemeToggle() {
  const { theme, setTheme } = useTheme();
  const [pointerDriven, setPointerDriven] = useState(false);
  const mounted = useSyncExternalStore(subscribe, () => true, () => false);

  const mode: Mode = !mounted
    ? "system"
    : theme === "dark"
      ? "dark"
      : theme === "light"
        ? "light"
        : "system";

  const next = ORDER[(ORDER.indexOf(mode) + 1) % ORDER.length];

  return (
    <button
      type="button"
      onClick={(event) => {
        setPointerDriven(event.detail > 0);
        setTheme(next);
      }}
      aria-label={LABEL[mode] + ". Switch to " + LABEL[next].toLowerCase()}
      title={LABEL[mode] + ". Switch to " + LABEL[next].toLowerCase()}
      className="flex size-11 cursor-pointer items-center justify-center rounded-full text-[var(--muted-ink)] hover:text-[var(--foreground)] focus-visible:outline-2 focus-visible:outline-[var(--action)]"
    >
      <span key={mode} className="theme-glyph" data-animate={pointerDriven}>
        <Glyph mode={mode} />
      </span>
      <style jsx>{`
        .theme-glyph { display: flex; }
        .theme-glyph[data-animate="true"] { animation: theme-glyph-in 140ms ease-out; }
        @keyframes theme-glyph-in {
          from { opacity: 0; transform: scale(0.95); }
          to { opacity: 1; transform: scale(1); }
        }
        @media (prefers-reduced-motion: reduce) {
          .theme-glyph[data-animate="true"] { animation: none; }
        }
      `}</style>
    </button>
  );
}

function Glyph({ mode }: { mode: Mode }) {
  const base = {
    width: 15,
    height: 15,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 1.8,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
    "aria-hidden": true,
  };

  if (mode === "dark") {
    return (
      <svg {...base}>
        <path d="M20 14.2A8.2 8.2 0 0 1 9.8 4 8.4 8.4 0 1 0 20 14.2Z" />
      </svg>
    );
  }

  if (mode === "light") {
    return (
      <svg {...base}>
        <circle cx="12" cy="12" r="4.1" />
        <path d="M12 2.6v2.2M12 19.2v2.2M4.2 12H2M22 12h-2.2M6.5 6.5 5 5M19 19l-1.5-1.5M17.5 6.5 19 5M5 19l1.5-1.5" />
      </svg>
    );
  }

  // System: a circle half filled, which is the convention for "whichever the machine is".
  return (
    <svg {...base}>
      <circle cx="12" cy="12" r="8.4" />
      <path d="M12 3.6a8.4 8.4 0 0 1 0 16.8Z" fill="currentColor" stroke="none" />
    </svg>
  );
}
