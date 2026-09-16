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
  const header = useRef<HTMLElement>(null);
  const menuButton = useRef<HTMLButtonElement>(null);

  // Browser back/forward while the menu is open swaps the page underneath
  // it. In-menu taps already close it via onClick; this covers the rest.
  useEffect(() => {
    if (!menuOpen) return;
    const close = () => setMenuOpen(false);
    window.addEventListener("popstate", close);
    return () => window.removeEventListener("popstate", close);
  }, [menuOpen]);

  useEffect(() => {
    if (!menuOpen) return;
    const dismiss = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setMenuOpen(false);
        menuButton.current?.focus();
      }
    };
    const outside = (event: PointerEvent) => {
      if (event.target instanceof Node && !header.current?.contains(event.target)) setMenuOpen(false);
    };
    document.addEventListener("keydown", dismiss);
    document.addEventListener("pointerdown", outside);
    return () => {
      document.removeEventListener("keydown", dismiss);
      document.removeEventListener("pointerdown", outside);
    };
  }, [menuOpen]);

  return (
    <header ref={header} className="top-nav fixed inset-x-0 top-0 z-50 border-b border-[var(--panel-edge)] bg-[var(--nav-bg)] backdrop-blur-[16px]">
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
            onClick={() => setMenuOpen((open) => !open)}
            className="flex size-11 cursor-pointer items-center justify-center rounded-full focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)] md:hidden"
          >
            <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" aria-hidden>
              <path d={menuOpen ? "M5 5l10 10M15 5 5 15" : "M3 7h14M3 13h14"} />
            </svg>
          </button>
        </div>
      </nav>
      <nav id="mobile-navigation" aria-label="Mobile navigation" hidden={!menuOpen} className="border-t border-[var(--panel-edge)] bg-[var(--background)] md:hidden">
        <ul className="site-container py-3">
          {LINKS.map((link) => (
            <li key={link.href}>
              <Link
                href={link.href}
                aria-current={pathname === link.href ? "page" : undefined}
                onClick={() => setMenuOpen(false)}
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
      </nav>
    </header>
  );
}
