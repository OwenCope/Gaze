import Link from "next/link";

const PAGES = [
  { href: "/", label: "Overview", blurb: "Meet Gaze." },
  { href: "/how-it-works", label: "How it works", blurb: "From setup to unlocking." },
  { href: "/features", label: "Features", blurb: "A closer look at the app." },
  { href: "/security", label: "Security", blurb: "Your data and your choices." },
  { href: "/releases", label: "Releases", blurb: "Builds and release notes." },
  { href: "/credits", label: "Credits", blurb: "The people behind the details." },
];

export function PageLinks({ current }: { current: string }) {
  return (
    <footer className="border-t border-[var(--hairline)] py-12 sm:py-16">
      <div className="site-container grid gap-10 md:grid-cols-[1fr_2fr] md:gap-16">
        <div>
          <p className="text-2xl font-semibold tracking-[-0.025em]">More about Gaze.</p>
          <p className="mt-3 max-w-xs text-sm leading-relaxed text-[var(--muted-ink)]">Made for your Mac. Independently developed and not affiliated with Apple.</p>
          <a href="https://discord.gg/BFgKT5YJH" target="_blank" rel="noreferrer" className="site-link mt-3 text-sm">Questions or feedback? Ask on Discord</a>
        </div>
        <nav aria-label="More pages">
          <ul className="grid gap-x-10 sm:grid-cols-2">
            {PAGES.filter((page) => page.href !== current).map((page) => (
              <li key={page.href} className="border-b border-[var(--hairline)]">
                <Link href={page.href} className="flex min-h-20 w-full items-center gap-6 py-5 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]">
                  <span className="min-w-0 flex-1">
                    <span className="block text-[18px] font-semibold tracking-[-0.02em]">{page.label}</span>
                    <span className="mt-1 block text-[14px] leading-relaxed text-[var(--muted-ink)]">{page.blurb}</span>
                  </span>
                  <span aria-hidden className="shrink-0">→</span>
                </Link>
              </li>
            ))}
          </ul>
        </nav>
      </div>
    </footer>
  );
}
