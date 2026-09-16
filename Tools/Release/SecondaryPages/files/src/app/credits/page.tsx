import type { Metadata } from "next";
import { TopNav } from "@/components/top-nav";
import { Footer } from "@/components/ui/footer-section";
import { credits, type Credit } from "@/lib/credits";
import { CreditsScroller } from "@/components/credits-scroller";
import { getContributions } from "@/lib/contributions";
import type { Contributions } from "@/components/credit-links";

export const metadata: Metadata = {
  title: "Credits",
  description: "The people, projects, and ideas behind Gaze.",
};

export default async function Credits() {
  // Fetched here rather than in the browser: the card component can pull a year
  // of activity from a third-party mirror itself, which would hand that service
  // the handle of everyone credited and the IP of everyone reading. One request
  // per person, on the server, cached for an hour.
  const contributions: Record<string, Contributions | null> = {};
  await Promise.all(
    credits
      .map((c) => c.github)
      .filter((login): login is string => Boolean(login))
      .map(async (login) => {
        contributions[login] = await getContributions(login);
      }),
  );

  return (
    <main
      id="top"
      className="credits-page min-h-dvh bg-[var(--background)] pt-16 text-[var(--foreground)] antialiased"
    >
      <TopNav />
      <section className="px-6 pb-12 pt-12 sm:pt-14">
        <div className="mx-auto max-w-[640px] text-center">
          <p className="text-[13px] font-medium uppercase tracking-[0.08em] text-[var(--muted-ink)]">
            Credits
          </p>
          <h1 className="mt-4 text-balance text-[clamp(2rem,4vw,2.75rem)] font-semibold leading-[1.12] tracking-[-0.035em]">
            The people behind Gaze.
          </h1>
          <p className="mx-auto mt-4 max-w-[34rem] text-[17px] leading-[1.6] text-[var(--muted-ink)]">
            The projects we learned from, and the people who helped make it happen.
          </p>
        </div>
      </section>

      <CreditsScroller credits={credits} contributions={contributions} />
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
            // Only the apps. Two of the credits are people, and a footer
            // column of links needs somewhere for each link to go.
            links: credits
              .filter((c): c is Credit & { app: string; href: string } =>
                Boolean(c.app && c.href),
              )
              .map((c) => ({ title: c.app, href: c.href, external: true })),
          },
          {
            label: "Elsewhere",
            links: [
              { title: "Discord", href: "https://discord.gg/BFgKT5YJH", external: true },
              { title: "Releases", href: "/releases" },
            ],
          },
        ]}
      />
    </main>
  );
}
