"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { AppIcon } from "./app-icon";
import { ThemeToggle } from "./theme-toggle";
import { AccountButton } from "./account-button";
import { cn } from "@/lib/utils";

const LINKS = [
  { label: "How it works", href: "/how-it-works" },
  { label: "Features", href: "/features" },
  { label: "Security", href: "/security" },
  { label: "Releases", href: "/releases" },
];

const DISCORD = "https://discord.gg/BFgKT5YJH";

// Inactive links use ink at 70% rather than the secondary grey: at 12px the
// secondary tone sits right on the AA boundary, while ink-based type keeps
// the quiet Apple-nav size with comfortable contrast in both themes.
const DESKTOP_LINK = "flex min-h-11 items-center text-[12px] hover:text-[var(--foreground)] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]";

export function TopNav() {
  const pathname = usePathname();
  const [menuOpen, setMenuOpen] = useState(false);
  const [pointerDriven, setPointerDriven] = useState(false);
  const header = useRef<HTMLElement>(null);
  const menuButton = useRef<HTMLButtonElement>(null);

  // Browser back/forward while the menu is open swaps the page underneath
  // it. In-menu taps already close it via onClick; this covers the rest.
  useEffect(() => {
    if (!menuOpen) return;
    const close = () => { setPointerDriven(false); setMenuOpen(false); };
    window.addEventListener("popstate", close);
    return () => window.removeEventListener("popstate", close);
  }, [menuOpen]);

  useEffect(() => {
    if (!menuOpen) return;
    const dismiss = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setPointerDriven(false);
        setMenuOpen(false);
        menuButton.current?.focus();
      }
    };
    const outside = (event: PointerEvent) => {
      if (event.target instanceof Node && !header.current?.contains(event.target)) {
        setPointerDriven(true);
        setMenuOpen(false);
      }
    };
    document.addEventListener("keydown", dismiss);
    document.addEventListener("pointerdown", outside);
    return () => {
      document.removeEventListener("keydown", dismiss);
      document.removeEventListener("pointerdown", outside);
    };
  }, [menuOpen]);

  return (
    <header ref={header} data-menu-open={menuOpen} data-menu-animate={pointerDriven} className="top-nav fixed inset-x-0 top-0 z-50 border-b border-[var(--panel-edge)] bg-[var(--nav-bg)] backdrop-blur-[16px]">
      <nav aria-label="Main navigation" className="site-container flex h-14 items-center gap-4">
        <Link href="/" aria-label="Gaze home" className="mr-auto flex min-h-11 items-center gap-2 rounded-md text-[18px] font-semibold tracking-[-0.025em] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]">
          <AppIcon size={48} className="size-6" />
          Gaze
        </Link>
        <ul className="hidden items-center gap-6 md:flex">
          {LINKS.map((link) => (
            <li key={link.href}>
              <Link
                href={link.href}
                aria-current={pathname === link.href ? "page" : undefined}
                className={cn(DESKTOP_LINK, pathname === link.href ? "text-[var(--foreground)]" : "text-[color-mix(in_srgb,var(--foreground)_70%,transparent)]")}
              >
                {link.label}
              </Link>
            </li>
          ))}
        </ul>
        <div className="flex items-center gap-1 md:ml-4">
          <ThemeToggle />
          <AccountButton />
          <button
            ref={menuButton}
            type="button"
            aria-label={menuOpen ? "Close navigation" : "Open navigation"}
            aria-expanded={menuOpen}
            aria-controls="mobile-navigation"
            onClick={(event) => { setPointerDriven(event.detail > 0); setMenuOpen((open) => !open); }}
            className="flex size-11 cursor-pointer items-center justify-center rounded-full focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)] md:hidden"
          >
            <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" aria-hidden>
              <path className="nav-line nav-line-first" d="M3 10h14" />
              <path className="nav-line nav-line-second" d="M3 10h14" />
            </svg>
          </button>
        </div>
      </nav>
      <nav id="mobile-navigation" aria-label="Mobile navigation" aria-hidden={!menuOpen} inert={!menuOpen} className="mobile-navigation grid md:hidden">
        <div className="min-h-0 overflow-hidden">
        <div className="border-t border-[var(--panel-edge)] bg-[var(--background)]">
        <ul className="site-container py-3">
          {LINKS.map((link) => (
            <li key={link.href}>
              <Link
                href={link.href}
                aria-current={pathname === link.href ? "page" : undefined}
                onClick={(event) => { setPointerDriven(event.detail > 0); setMenuOpen(false); }}
                className={cn(
                  "flex min-h-12 items-center rounded-md text-[17px] font-medium focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]",
                  pathname === link.href ? "text-[var(--foreground)]" : "text-[color-mix(in_srgb,var(--foreground)_78%,transparent)]",
                )}
              >
                {link.label}
              </Link>
            </li>
          ))}
          <li><a href={DISCORD} target="_blank" rel="noreferrer" className="site-link text-[15px]">Join the Discord</a></li>
        </ul>
        </div>
        </div>
      </nav>
      <style jsx>{`
        .mobile-navigation { grid-template-rows: 0fr; opacity: 0; }
        [data-menu-open="true"] .mobile-navigation { grid-template-rows: 1fr; opacity: 1; }
        .nav-line { transform-origin: 10px 10px; }
        .nav-line-first { transform: translateY(-3px); }
        .nav-line-second { transform: translateY(3px); }
        [data-menu-open="true"] .nav-line-first { transform: rotate(45deg); }
        [data-menu-open="true"] .nav-line-second { transform: rotate(-45deg); }
        [data-menu-animate="true"] .mobile-navigation {
          transition: grid-template-rows 150ms cubic-bezier(0.32,0.72,0,1), opacity 150ms ease-out;
        }
        [data-menu-animate="true"] .nav-line { transition: transform 150ms cubic-bezier(0.32,0.72,0,1); }
        [data-menu-animate="true"][data-menu-open="true"] .mobile-navigation,
        [data-menu-animate="true"][data-menu-open="true"] .nav-line { transition-duration: 200ms; }
        @media (prefers-reduced-motion: reduce) {
          [data-menu-animate="true"] .mobile-navigation, [data-menu-animate="true"] .nav-line { transition: none; }
        }
      `}</style>
    </header>
  );
}
