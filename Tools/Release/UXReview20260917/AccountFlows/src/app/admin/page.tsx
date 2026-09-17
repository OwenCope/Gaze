import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { auth } from "@/auth";
import { SiteNav } from "@/components/site-nav";
import { LiquidButton } from "@/components/ui/liquid-glass-button";
import { getAllReleases } from "@/lib/releases";
import { analyticsConfigured, getTraffic } from "@/lib/analytics";
import { TrafficPanel, TrafficUnavailable } from "@/components/traffic-panel";
import { SettingsPanel } from "@/components/settings-panel";
import { getSettings } from "@/lib/settings";
import { Tag, Cards, Gaze, Faceprint } from "@/components/icons";

export const metadata: Metadata = {
  title: "Dashboard",
  robots: { index: false, follow: false },
};



function Stat({
  icon: Icon,
  label,
  value,
  hint,
}: {
  icon: React.ComponentType<{ className?: string }>;
  label: string;
  value: string;
  hint?: string;
}) {
  return (
    <div className="rounded-[18px] panel p-6">
      <div className="flex items-center gap-2.5">
        <Icon className="size-[17px] text-[var(--faint-ink)]" />
        <p className="text-[14px] text-[var(--muted-ink)]">{label}</p>
      </div>
      <p className="mt-3 text-[32px] font-semibold leading-none tracking-[-0.03em] tabular-nums">
        {value}
      </p>
      {hint && <p className="mt-2 text-[13px] text-[var(--faint-ink)]">{hint}</p>}
    </div>
  );
}

export default async function Dashboard() {
  const session = await auth();

  // Checked here as well as in middleware: a matcher can be misconfigured, a
  // page that guards itself cannot be.
  if (!session?.user) redirect("/signin?callbackUrl=/admin");
  if (!session.user.isAdmin) redirect("/");

  const [releases, traffic, settings] = await Promise.all([
    getAllReleases(),
    getTraffic(),
    getSettings(),
  ]);
  const latest = releases[0];
  const contributors = new Set(
    releases.flatMap((r) => r.contributors.map((c) => c.login.toLowerCase())),
  );
  const shots = releases.reduce((n, r) => n + r.images.length, 0);

  return (
    <main
      id="top"
      className="admin-page min-h-dvh bg-[var(--background)] text-[var(--foreground)] antialiased"
    >
      <SiteNav />
      <section className="px-6 pb-20 pt-40">
        <div className="mx-auto max-w-[1080px]">
          <Link href="/" className="site-link text-sm">View website <span aria-hidden>↗</span></Link>

          <div className="mt-7 flex flex-wrap items-end justify-between gap-5">
            <div>
              <h1 className="text-balance text-[clamp(2rem,4.5vw,3rem)] font-semibold leading-[1.08] tracking-[-0.035em]">
                Dashboard
              </h1>
              <p className="mt-3 text-[var(--muted-ink)]">
                {session.user.name?.split(" ")[0] ?? "Signed in"} · {session.user.email}
              </p>
            </div>
            <div className="flex flex-wrap gap-2.5">
              <LiquidButton size="default" asChild>
                <Link href="/admin/testers">Testers</Link>
              </LiquidButton>
              <LiquidButton variant="solid" size="default" asChild>
                <Link href="/admin/new">New release</Link>
              </LiquidButton>
            </div>
          </div>

          {/* Only what is actually known. A dashboard of invented numbers is
              worse than four honest ones. Visitors leads because it is the one
              number that changes without you doing anything. */}
          <div className="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <Stat
              icon={Faceprint}
              label="Visitors"
              value={traffic ? traffic.visitors.toLocaleString() : "—"}
              hint={traffic ? "Last 30 days" : "Analytics not connected"}
            />
            <Stat
              icon={Gaze}
              label="Page views"
              value={traffic ? traffic.pageviews.toLocaleString() : "—"}
              hint={
                traffic && traffic.visitors > 0
                  ? `${(traffic.pageviews / traffic.visitors).toFixed(1)} a visitor`
                  : "Last 30 days"
              }
            />
            <Stat
              icon={Tag}
              label="Releases"
              value={String(releases.length)}
              hint={latest ? `Latest ${latest.tag}` : "None published"}
            />
            <Stat
              icon={Cards}
              label="Screenshots"
              value={String(shots)}
              hint={`${contributors.size} credited across them`}
            />
          </div>

          {traffic ? (
            <TrafficPanel traffic={traffic} />
          ) : (
            <TrafficUnavailable configured={analyticsConfigured} />
          )}

          <div className="mt-5 grid min-w-0 grid-cols-1 gap-4 lg:grid-cols-[1.4fr_1fr]">
            <div className="rounded-[20px] panel p-7">
              <h2 className="text-[17px] font-semibold tracking-[-0.01em]">
                Recent releases
              </h2>
              {releases.length === 0 ? (
                <p className="mt-3 leading-relaxed text-[var(--muted-ink)]">
                  Nothing yet. Write one here — pictures, clips and credits all go in the
                  same form, and it is on the site the moment you publish.
                </p>
              ) : (
                <ul className="mt-4 divide-y divide-[var(--hairline)]">
                  {releases.slice(0, 5).map((r) => (
                    <li key={r.tag} className="flex items-baseline gap-3">
                      <Link
                        href={r.draft ? `/admin/${encodeURIComponent(r.tag)}/edit` : `/releases/${encodeURIComponent(r.tag)}`}
                        className="group flex min-w-0 flex-1 items-baseline justify-between gap-4 rounded-md py-3.5 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]"
                      >
                        <span className="min-w-0">
                          <span className="flex min-w-0 items-center gap-2">
                            <span className="truncate font-medium transition-colors group-hover:text-[var(--foreground)]">
                              {r.name}
                            </span>
                            {r.draft && (
                              <span className="shrink-0 rounded-full border border-[var(--panel-edge)] bg-[var(--panel-bg)] px-2 py-0.5 text-[11px] font-medium text-[var(--muted-ink)]">
                                Draft
                              </span>
                            )}
                          </span>
                          <span className="text-[13px] text-[var(--faint-ink)]">
                            {r.images.length} images · {r.contributors.length} credited
                          </span>
                        </span>
                        <span className="shrink-0 text-[13px] text-[var(--faint-ink)]">
                          {new Date(r.date).toLocaleDateString("en-US", {
                            day: "numeric",
                            month: "short",
                          })}
                        </span>
                      </Link>
                      <Link
                        href={`/admin/${encodeURIComponent(r.tag)}/edit`}
                        className="inline-flex min-h-11 shrink-0 items-center rounded-lg px-3 text-[14px] text-[var(--faint-ink)] transition-colors hover:bg-[var(--foreground)]/[0.07] hover:text-[var(--foreground)]"
                      >
                        Edit
                      </Link>
                    </li>
                  ))}
                </ul>
              )}
            </div>

            <SettingsPanel initial={settings} />

            <div className="rounded-[20px] panel p-7">
              <h2 className="text-[17px] font-semibold tracking-[-0.01em]">
                Publishing a release
              </h2>
              <ol className="mt-4 space-y-3 text-[15px] text-[var(--muted-ink)]">
                {[
                  "Give it a version and a title, e.g. v1.1.",
                  "Add pictures or clips — the first image becomes the card’s cover.",
                  "List anyone who helped; each gets an avatar linking to their GitHub.",
                  "Save it as a draft, or publish it straight to the site.",
                ].map((step, i) => (
                  <li key={step} className="flex gap-3">
                    <span className="mt-0.5 flex size-5 shrink-0 items-center justify-center rounded-full bg-[var(--foreground)]/[0.07] text-[12px] font-semibold tabular-nums text-[var(--muted-ink)]">
                      {i + 1}
                    </span>
                    <span className="leading-relaxed">{step}</span>
                  </li>
                ))}
              </ol>
              <div className="mt-6 flex flex-wrap gap-2.5">
                <LiquidButton size="default" asChild>
                  <Link href="/admin/new">Write one</Link>
                </LiquidButton>
              </div>
            </div>
          </div>
        </div>
      </section>

    </main>
  );
}
