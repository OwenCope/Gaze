import type { Metadata } from "next";
import { TopNav } from "@/components/top-nav";
import { PageIntro } from "@/components/page-intro";
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
      <PageIntro title="Credits" description="People and projects that helped shape Gaze." />

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
