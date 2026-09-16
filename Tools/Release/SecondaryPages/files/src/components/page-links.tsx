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
        </div>
        <nav aria-label="More pages">
          <ul className="grid gap-x-10 gap-y-4 sm:grid-cols-2">
            {PAGES.filter((page) => page.href !== current).map((page) => (
              <li key={page.href}>
                <Link href={page.href} className="site-link font-medium">{page.label} <span aria-hidden>→</span></Link>
                <p className="text-sm text-[var(--muted-ink)]">{page.blurb}</p>
              </li>
            ))}
          </ul>
        </nav>
      </div>
    </footer>
  );
}
