import Link from "next/link";
import { AppIcon } from "./app-icon";
import type { Release } from "@/lib/releases";

export function ReleaseCard({ release, index }: { release: Release; index: number }) {
  const cover = release.images[0];
  const date = new Date(release.date).toLocaleDateString("en-US", {
    day: "numeric", month: "long", year: "numeric", timeZone: "UTC",
  });

  return (
    <li className="grid gap-6 border-t border-[var(--hairline)] py-9 md:grid-cols-[180px_1fr] md:gap-12">
      <div className="flex flex-wrap items-baseline gap-x-3 gap-y-2 md:block">
        <p className="text-lg font-semibold tracking-[-0.02em]">{release.tag}</p>
        <time dateTime={release.date} className="text-sm tabular-nums text-[var(--muted-ink)] md:mt-2 md:block">{date}</time>
        {release.prerelease && <span className="mt-3 inline-block rounded-md bg-[var(--panel-bg)] px-2 py-1 text-xs font-medium">Beta</span>}
      </div>
      <article className="min-w-0">
        <div className="flex items-start gap-4">
          {!cover && <AppIcon size={64} className="size-12 shrink-0" />}
          <div>
            <h2 className="text-balance text-[clamp(1.5rem,3vw,2rem)] font-semibold leading-tight tracking-[-0.025em]">
              <Link href={`/releases/${encodeURIComponent(release.tag)}`} className="rounded-sm underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]">{release.name}</Link>
            </h2>
            {release.excerpt && <p className="mt-3 max-w-[65ch] text-[17px] leading-relaxed text-[var(--muted-ink)]">{release.excerpt}</p>}
          </div>
        </div>
        {cover && (
          <Link href={`/releases/${encodeURIComponent(release.tag)}`} aria-label={`Open release ${release.tag}`} className="mt-6 block overflow-hidden rounded-[20px] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={cover.src} alt={cover.alt} loading={index === 0 ? "eager" : "lazy"} width={1200} height={750} className="aspect-[16/10] w-full object-contain" />
          </Link>
        )}
        <div className="mt-5 flex flex-wrap items-center justify-between gap-4">
          <Link href={`/releases/${encodeURIComponent(release.tag)}`} className="site-link font-medium" aria-label={`Read release notes for ${release.tag}`}>Read release notes <span aria-hidden>→</span></Link>
          {release.contributors.length > 0 && (
            <div className="flex items-center gap-2">
              <span className="text-sm text-[var(--muted-ink)]">With</span>
              <div className="flex -space-x-1.5">
                {release.contributors.slice(0, 4).map((contributor) => (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img key={contributor.login} src={contributor.avatar} alt={contributor.login} loading="lazy" width={28} height={28} className="size-7 rounded-full border-2 border-[var(--background)]" />
                ))}
              </div>
              {release.contributors.length > 4 && <span className="text-sm text-[var(--muted-ink)]">+{release.contributors.length - 4}</span>}
            </div>
          )}
        </div>
      </article>
    </li>
  );
}
