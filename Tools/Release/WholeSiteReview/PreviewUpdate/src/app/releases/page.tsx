import { PageIntro } from "@/components/page-intro";
import type { Metadata } from "next";
import Link from "next/link";
import { TopNav } from "@/components/top-nav";
import { Footer } from "@/components/ui/footer-section";
import { LiquidButton } from "@/components/ui/liquid-glass-button";
import { ReleaseCard } from "@/components/release-card";
import { redirect } from "next/navigation";
import { auth } from "@/auth";
import { getReleases } from "@/lib/releases";
import { canSeePrivate } from "@/lib/viewer";
import { getSettings } from "@/lib/settings";

const DISCORD = "https://discord.gg/BFgKT5YJH";

export const metadata: Metadata = {
  title: "Releases",
  description: "Every version of Gaze, what changed in it, and what it looked like.",
};

/** Publishing revalidates this path directly, so there is nothing to poll. */
export const dynamic = "force-dynamic";

export default async function Releases() {
  // Closed entirely, when the owner has asked for that.
  //
  // Separate from the per-release private flag, which hides tester builds from
  // everyone else. This hides the fact that any of them exist — for the stretch
  // before a public launch, when the version numbers themselves are more than
  // is wanted in public.
  //
  // Checked on the server before anything is fetched. A page that renders and
  // then hides itself has already sent the data.
  const { releasesRequireSignIn } = await getSettings();
  if (releasesRequireSignIn && !(await auth())?.user) {
    redirect("/signin?callbackUrl=%2Freleases");
  }

  const releases = await getReleases({ includePrivate: await canSeePrivate() });
  // Split rather than mixed. A tester scanning the page needs to know which of
  // these the public can see — the badge alone is easy to miss on a card you
  // are looking past.
  const testerOnly = releases.filter((r) => r.private);
  const published = releases.filter((r) => !r.private);

  return (
    <main
      id="top"
      className="min-h-dvh bg-[var(--background)] pt-16 text-[var(--foreground)] antialiased"
    >
      <TopNav />
      <PageIntro title="Releases" description="Builds and release notes." />

      <section className="px-6 pb-20">
        <div className="mx-auto max-w-[1080px]">
          {releases.length === 0 ? (
            <div className="rounded-[28px] bg-[var(--surface)] p-8 shadow-[var(--card-shadow)] sm:p-10">
              <h2 className="text-[20px] font-semibold tracking-[-0.02em]">
                Nothing published yet
              </h2>
              <p className="mt-2.5 max-w-xl leading-relaxed text-[var(--muted-ink)]">
                There are no published builds to show yet. Release notes and available
                downloads will appear here when a build is published.
              </p>
              <div className="mt-6 flex flex-wrap gap-3">
                <LiquidButton variant="solid" size="default" asChild>
                  <Link href={DISCORD} target="_blank" rel="noreferrer">
                    Join the Discord
                  </Link>
                </LiquidButton>

              </div>
            </div>
          ) : (
            <div className="space-y-16">
              {testerOnly.length > 0 && (
                <section>
                  <div className="flex items-baseline gap-3">
                    <h2 className="text-[15px] font-semibold uppercase tracking-[0.08em] text-[var(--faint-ink)]">
                      Testers only
                    </h2>
                    <span className="rounded-full bg-[var(--system-green)]/15 px-2.5 py-0.5 text-[12px] font-medium text-[var(--system-green)]">
                      Not public
                    </span>
                  </div>
                  <ol className="mt-7">
                    {testerOnly.map((r, i) => (
                      <ReleaseCard key={r.tag} release={r} index={i} />
                    ))}
                  </ol>
                </section>
              )}

              {published.length > 0 && (
                <section>
                  {testerOnly.length > 0 && (
                    <h2 className="text-[15px] font-semibold uppercase tracking-[0.08em] text-[var(--faint-ink)]">
                      Public
                    </h2>
                  )}
                  <ol
                    className={`${
                      testerOnly.length > 0 ? "mt-7" : ""
                    }`}
                  >
                    {published.map((r, i) => (
                      <ReleaseCard key={r.tag} release={r} index={i} />
                    ))}
                  </ol>
                </section>
              )}
            </div>
          )}
        </div>
      </section>


      <Footer
        note="Gaze · free and open source · not affiliated with Apple."
        columns={[
          {
            label: "The app",
            links: [
              { title: "How it works", href: "/how-it-works" },
              { title: "Try it", href: "/#demo" },
              { title: "Security", href: "/security" },
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
