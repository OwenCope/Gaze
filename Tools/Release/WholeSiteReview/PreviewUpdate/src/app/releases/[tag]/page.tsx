import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { TopNav } from "@/components/top-nav";
import { Footer } from "@/components/ui/footer-section";
import { LiquidButton } from "@/components/ui/liquid-glass-button";
import { BackLink } from "@/components/back-link";
import { ReleaseGallery } from "@/components/release-gallery";
import { DiskImage } from "@/components/disk-image";
import { canSeePrivate } from "@/lib/viewer";
import { getReleases } from "@/lib/releases";

const DISCORD = "https://discord.gg/BFgKT5YJH";

export const dynamic = "force-dynamic";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ tag: string }>;
}): Promise<Metadata> {
  const { tag } = await params;
  const release = (await getReleases()).find((r) => r.tag === decodeURIComponent(tag));
  if (!release) return { title: "Release" };
  return {
    title: release.name,
    description: release.excerpt || `What changed in ${release.name}.`,
    openGraph: {
      title: `${release.name} — Gaze`,
      description: release.excerpt,
      images: release.images[0] ? [release.images[0].src] : undefined,
    },
  };
}

export default async function ReleaseNotes({
  params,
}: {
  params: Promise<{ tag: string }>;
}) {
  const { tag } = await params;
  // A private release 404s for everyone who is not a tester, rather than
  // rendering a "you can't see this" page — a page that admits something
  // exists has already told you the thing you were not meant to know.
  const releases = await getReleases({ includePrivate: await canSeePrivate() });
  const release = releases.find((r) => r.tag === decodeURIComponent(tag));
  if (!release) notFound();

  const others = releases.filter((r) => r.tag !== release.tag).slice(0, 3);

  return (
    <main
      id="top"
      className="min-h-dvh bg-[var(--background)] pt-16 text-[var(--foreground)] antialiased"
    >
      <TopNav />
      <article className="px-6 pb-14 pt-10 sm:pt-12">
        <div className="mx-auto max-w-[760px]">
          <BackLink href="/releases">Releases</BackLink>

          <div className="mt-7 flex flex-wrap items-center gap-x-2.5 gap-y-1 text-[14px] text-[var(--faint-ink)]">
            <span className="rounded-full bg-[var(--foreground)]/[0.07] px-2.5 py-1 font-medium text-[var(--muted-ink)]">
              {release.tag}
            </span>
            {release.prerelease && (
              <span className="rounded-full bg-[#FF9500]/12 px-2.5 py-1 font-medium text-[#FF9500]">
                Beta
              </span>
            )}
            <span>·</span>
            <time dateTime={release.date}>
              {new Date(release.date).toLocaleDateString("en-US", {
                day: "numeric",
                month: "long",
                year: "numeric",
                timeZone: "UTC",
              })}
            </time>
          </div>

          <h1 className="mt-4 text-balance text-[clamp(2rem,4vw,3rem)] font-semibold leading-[1.12] tracking-[-0.025em]">
            {release.name}
          </h1>

          {/* The build, where the release notes are — not only on the tester
              page. Someone reading what changed is exactly the person about to
              want the thing that changed. */}
          {release.download && (
            <div className="mt-8 flex flex-wrap items-center gap-4 rounded-[22px] bg-[var(--surface)] p-6 shadow-[var(--card-shadow)]">
              <DiskImage className="size-14 shrink-0" />
              <div className="min-w-0">
                <p className="text-[15px] font-medium">{release.download.name}</p>
                <p className="text-[13px] text-[var(--faint-ink)]">
                  {Math.round(release.download.size / (1024 * 1024))} MB · macOS
                </p>
              </div>
              <LiquidButton variant="solid" size="default" asChild>
                <a href={release.download.url} download>
                  Download
                </a>
              </LiquidButton>
            </div>
          )}

          {release.contributors.length > 0 && (
            <div className="mt-7 flex flex-wrap items-center gap-2.5 border-y border-[var(--hairline)] py-5">
              <span className="text-[14px] text-[var(--faint-ink)]">With</span>
              {release.contributors.map((c) => (
                <a
                  key={c.login}
                  href={c.url}
                  target="_blank"
                  rel="noreferrer"
                  className="group flex cursor-pointer items-center gap-2 min-h-11 rounded-full border border-[var(--hairline)] bg-[var(--surface)] py-1 pl-1 pr-3 text-[14px] transition-colors hover:border-[var(--faint-ink)]/40 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--foreground)]"
                >
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={c.avatar}
                    alt=""
                    loading="lazy"
                    className="size-6 rounded-full bg-[var(--foreground)]/10"
                  />
                  <span className="font-medium text-[var(--muted-ink)] transition-colors group-hover:text-[var(--foreground)]">
                    {c.login}
                  </span>
                </a>
              ))}
            </div>
          )}

          {/* Media first, then the notes: people scroll to a release to see what
              changed, and a picture answers that faster than a paragraph. */}
          {release.images.length > 0 && <ReleaseGallery images={release.images} />}

          {release.videos.length > 0 && (
            <div className="mt-4 space-y-4">
              {release.videos.map((src) => (
                <video
                  key={src}
                  src={src}
                  controls
                  playsInline
                  preload="metadata"
                  className="w-full rounded-[16px] border border-[var(--surface-edge)]"
                />
              ))}
            </div>
          )}

          <div
            className="release-notes mt-10 text-[17px] leading-relaxed text-[var(--muted-ink)]"
            // Written by the repo owner, rendered back to them.
            dangerouslySetInnerHTML={{ __html: release.html }}
          />

          <div className="mt-10 flex flex-wrap gap-3 border-t border-[var(--hairline)] pt-8">
            <LiquidButton variant="solid" size="default" asChild>
              <Link href={DISCORD} target="_blank" rel="noreferrer">
                Discuss this release
              </Link>
            </LiquidButton>
          </div>
        </div>
      </article>

      {others.length > 0 && (
        <section className="px-6 pb-20">
          <div className="mx-auto max-w-[760px]">
            <h2 className="text-[15px] font-semibold tracking-[-0.01em] text-[var(--faint-ink)]">
              Other releases
            </h2>
            <ul className="mt-4 divide-y divide-[var(--hairline)] border-y border-[var(--hairline)]">
              {others.map((r) => (
                <li key={r.tag}>
                  <Link
                    href={`/releases/${encodeURIComponent(r.tag)}`}
                    className="group flex items-baseline justify-between gap-4 py-4 transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--foreground)]"
                  >
                    <span className="font-medium transition-colors group-hover:text-[var(--foreground)]">
                      {r.name}
                    </span>
                    <span className="shrink-0 text-[14px] text-[var(--faint-ink)]">
                      {new Date(r.date).toLocaleDateString("en-US", {
                        day: "numeric",
                        month: "short",
                        year: "numeric",
                timeZone: "UTC",
                      })}
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        </section>
      )}


      <Footer
        note="Gaze · free and open source · not affiliated with Apple."
        columns={[
          {
            label: "The app",
            links: [
              { title: "How it works", href: "/how-it-works" },
              { title: "Try it", href: "/#demo" },
              { title: "Releases", href: "/releases" },
            ],
          },
          {
            label: "Built on",
            links: [
              { title: "Sapphire", href: "https://sapphire-app.tech", external: true },
              { title: "DynamicLake", href: "https://dynamiclake.com", external: true },
              { title: "Atoll", href: "https://getatoll.app", external: true },
            ],
          },
          {
            label: "Elsewhere",
            links: [
              { title: "Discord", href: DISCORD, external: true },
              { title: "Credits", href: "/credits" },
            ],
          },
        ]}
      />
    </main>
  );
}
