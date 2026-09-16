"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { AccountButton } from "./account-button";
import { AppIcon } from "./app-icon";
import { ThemeToggle } from "./theme-toggle";

const adminLinks = [
  { href: "/admin", label: "Dashboard" },
  { href: "/admin/new", label: "New release" },
  { href: "/admin/readme", label: "Tester notes" },
  { href: "/admin/testers", label: "People" },
] as const;

export function SiteNav() {
  const pathname = usePathname();

  return (
    <header className="admin-nav fixed inset-x-0 top-0 z-40 border-b border-[var(--hairline)] bg-[var(--nav-bg)] backdrop-blur-[16px] print:hidden">
      <div className="site-container flex h-16 items-center gap-3">
        <Link
          href="/"
          aria-label="Gaze website home"
          className="flex min-h-11 min-w-0 items-center gap-2 rounded-lg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]"
        >
          <AppIcon size={24} />
          <span className="text-[18px] font-semibold tracking-[-0.025em]">Gaze</span>
          <span className="text-[12px] text-[var(--muted-ink)]">Website</span>
        </Link>
        <div className="ml-auto flex shrink-0 items-center">
          <ThemeToggle />
          <AccountButton />
        </div>
      </div>

      <nav aria-label="Admin" className="h-12 overflow-x-auto">
        <div className="site-container flex h-full items-center gap-1">
          {adminLinks.map((link) => {
            const current = pathname === link.href;

            return (
              <Link
                key={link.href}
                href={link.href}
                aria-current={current ? "page" : undefined}
                className={`flex min-h-11 shrink-0 items-center rounded-lg px-4 text-[14px] font-medium focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)] ${
                  current
                    ? "bg-[var(--surface)] text-[var(--foreground)]"
                    : "text-[var(--muted-ink)] hover:text-[var(--foreground)]"
                }`}
              >
                {link.label}
              </Link>
            );
          })}
        </div>
      </nav>
    </header>
  );
}
