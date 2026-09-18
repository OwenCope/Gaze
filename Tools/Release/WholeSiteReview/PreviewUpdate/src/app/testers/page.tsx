import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { renderMarkdown } from "@/lib/render-markdown";
import { auth } from "@/auth";
import { TopNav } from "@/components/top-nav";
import { LiquidButton } from "@/components/ui/liquid-glass-button";
import { Tag, Cards } from "@/components/icons";
import { getReleases } from "@/lib/releases";
import { readReadme } from "@/lib/storage";
import { getViewer } from "@/lib/viewer";
import { getCommits, getTree } from "@/lib/commits";

export const metadata: Metadata = {
  title: "Testing Gaze",
  robots: { index: false, follow: false },
};

export const dynamic = "force-dynamic";

function FolderIcon() {
  return (
    <svg viewBox="0 0 24 24" className="size-[17px]" fill="none" stroke="currentColor" strokeWidth="1.6" aria-hidden>
      <path d="M3 7.5A1.5 1.5 0 0 1 4.5 6h4l2 2h9a1.5 1.5 0 0 1 1.5 1.5v8A1.5 1.5 0 0 1 19.5 19h-15A1.5 1.5 0 0 1 3 17.5v-10Z" />
    </svg>
  );
}

function FileIcon() {
  return (
    <svg viewBox="0 0 24 24" className="size-[17px]" fill="none" stroke="currentColor" strokeWidth="1.6" aria-hidden>
      <path d="M14 3H7a1.5 1.5 0 0 0-1.5 1.5v15A1.5 1.5 0 0 0 7 21h10a1.5 1.5 0 0 0 1.5-1.5V7.5L14 3Z" />
      <path d="M14 3v4.5h4.5" />
    </svg>
  );
}

const size = (bytes: number) => {
  const mb = bytes / (1024 * 1024);
  return mb >= 1024 ? `${(mb / 1024).toFixed(1)} GB` : `${Math.round(mb)} MB`;
};

/**
 * The page testers land on: every build, and the notes that go with them.
 *
 * Builds lead and the notes sit beside them, because someone arriving here has
 * come to get the app — the reading is what they do once they have it.
 */
export default async function TestersPage() {
  const session = await auth();
  if (!session?.user) redirect("/signin?callbackUrl=/testers");

  const viewer = await getViewer();
  if (!viewer.can("viewPrivate")) redirect("/");

  const [releases, readme, commits] = await Promise.all([
    getReleases({ includePrivate: true }),
    readReadme().then((r) => r ?? ""),
    getCommits(),
  ]);
  const tree = await getTree();
  const html = readme ? renderMarkdown(readme) : "";
  const latest = releases[0];

  return (
    <main
      id="top"
      className="min-h-dvh bg-[var(--background)] pt-16 text-[var(--foreground)] antialiased"
    >
      <TopNav />
      <section className="px-6 py-10 sm:py-12">
        <div className="mx-auto max-w-[1080px]">
          <div className="flex flex-wrap items-end justify-between gap-6">
            <div>
              <div>
                <h1 className="text-balance text-[clamp(2rem,4.5vw,3rem)] font-semibold leading-[1.05] tracking-[-0.035em]">
                  Testing Gaze
                </h1>
              </div>
              <p className="mt-3 max-w-xl text-base leading-relaxed text-[var(--muted-ink)]">
                Builds and testing notes.
              </p>
            </div>

            {latest?.download && (
              <LiquidButton variant="solid" asChild>
                <a href={latest.download.url} download aria-label={`Download Gaze ${latest.tag}`}>
                  Download Gaze
                </a>
              </LiquidButton>
            )}
          </div>
        </div>
      </section>

      <section className="px-6 pb-14">
        <div className="mx-auto grid max-w-[1080px] gap-10 lg:grid-cols-[1.6fr_1fr] lg:gap-14">
          {/* Builds. */}
          <div>
            <h2 className="text-lg font-medium">
              Builds
            </h2>

            {releases.length === 0 ? (
              <p className="mt-5 leading-relaxed text-[var(--muted-ink)]">
                Nothing published yet. When the first build lands it appears here
                before it appears anywhere else.
              </p>
            ) : (
              <ol className="mt-3 border-t border-[var(--hairline)]">
                {releases.map((r) => (
                  <li key={r.tag} className="border-b border-[var(--hairline)] py-5">
                    <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1.5">
                      <span className="rounded-full bg-[var(--foreground)]/[0.07] px-2.5 py-0.5 text-[14px] font-medium tabular-nums text-[var(--muted-ink)]">
                        {r.tag}
                      </span>
                      {r.private && (
                        <span className="rounded-full bg-[var(--system-green)]/15 px-2.5 py-0.5 text-[14px] font-medium text-[var(--system-green)]">
                          Testers only
                        </span>
                      )}
                      {r.prerelease && (
                        <span className="rounded-full bg-[#FF9500]/15 px-2.5 py-0.5 text-[14px] font-medium text-[#FF9500]">
                          Beta
                        </span>
                      )}
                      <span className="text-[14px] text-[var(--faint-ink)]">
                        {new Date(r.date).toLocaleDateString("en-US", {
                          month: "long",
                          day: "numeric",
                          year: "numeric",
                          timeZone: "UTC",
                        })}
                      </span>
                    </div>

                    <h3 className="mt-3 text-[20px] font-medium tracking-[-0.02em]">
                      {r.name}
                    </h3>
                    {r.excerpt && (
                      <p className="mt-2 leading-relaxed text-[var(--muted-ink)]">
                        {r.excerpt}
                      </p>
                    )}

                    <div className="mt-5 flex flex-wrap items-center gap-2.5">
                      {r.download ? (
                        <LiquidButton size="default" asChild>
                          <a href={r.download.url} download>
                            Download · {size(r.download.size)}
                          </a>
                        </LiquidButton>
                      ) : (
                        <span className="text-[14px] text-[var(--faint-ink)]">
                          No build attached
                        </span>
                      )}
                      <Link
                        href={`/releases/${encodeURIComponent(r.tag)}`}
                        className="inline-flex min-h-11 items-center rounded-full px-3 py-2 text-[15px] text-[var(--muted-ink)] transition-colors hover:text-[var(--foreground)] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]"
                      >
                        Release notes
                      </Link>
                    </div>
                  </li>
                ))}
              </ol>
            )}

            {/* The repository, the way GitHub lays it out — folders first, each
                row carrying the last commit that touched it. Ours, though: no
                green button, no clone dropdown, and every row a link straight
                to the file. */}
            {tree && tree.length > 0 && (
              <div className="mt-12">
                <h2 className="text-[15px] font-semibold uppercase tracking-[0.08em] text-[var(--faint-ink)]">
                  The code
                </h2>
                <ul className="mt-5 overflow-hidden rounded-[24px] border border-[var(--hairline)] bg-[var(--surface)] shadow-[var(--card-shadow)]">
                  {tree.map((e, i) => (
                    <li
                      key={e.path}
                      className={i === 0 ? "" : "border-t border-[var(--hairline)]"}
                    >
                      <a
                        href={e.url}
                        target="_blank"
                        rel="noreferrer"
                        className="flex min-h-11 items-center gap-3 px-5 py-3 transition-colors hover:bg-[var(--foreground)]/[0.04] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]"
                      >
                        <span className="shrink-0 text-[var(--faint-ink)]">
                          {e.type === "dir" ? <FolderIcon /> : <FileIcon />}
                        </span>
                        <span className="w-[34%] shrink-0 truncate text-[15px] font-medium sm:w-[26%]">
                          {e.name}
                        </span>
                        <span className="min-w-0 flex-1 truncate text-[14px] text-[var(--muted-ink)]">
                          {e.last?.message}
                        </span>
                        <span className="shrink-0 text-[14px] tabular-nums text-[var(--faint-ink)]">
                          {e.last
                            ? new Date(e.last.date).toLocaleDateString("en-US", {
                                month: "short",
                                day: "numeric",
                                timeZone: "UTC",
                              })
                            : ""}
                        </span>
                      </a>
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </div>

          {/* The notes, and what to do with a build once you have it. */}
          <aside className="lg:sticky lg:top-24 lg:h-min">
            <h2 className="text-lg font-medium">
              Testing notes
            </h2>

            <div className="mt-4 text-base leading-relaxed">
              {html ? (
                <div
                  className="release-notes"
                  dangerouslySetInnerHTML={{ __html: html }}
                />
              ) : (
                <p className="leading-relaxed text-[var(--muted-ink)]">
                  Nothing written yet.{" "}
                  {session.user.isAdmin && (
                    <Link
                      href="/admin/readme"
                      className="inline-flex min-h-11 items-center font-medium text-[var(--foreground)] underline-offset-4 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]"
                    >
                      Write it
                    </Link>
                  )}
                </p>
              )}
            </div>

            <div className="mt-7 border-t border-[var(--hairline)] pt-6">
              <h3 className="text-[15px] font-semibold tracking-[-0.01em]">
                Report an issue
              </h3>
              <p className="mt-2 leading-relaxed text-[var(--muted-ink)]">
                Share the build version and what happened in Discord.
              </p>
              <div className="mt-5">
                <LiquidButton size="default" asChild>
                  <a
                    href="https://discord.gg/BFgKT5YJH"
                    target="_blank"
                    rel="noreferrer"
                  >
                    Open Discord
                  </a>
                </LiquidButton>
              </div>
            </div>

            {commits && commits.length > 0 && (
              <div className="mt-7 border-t border-[var(--hairline)] pt-6">
                <h3 className="text-[15px] font-semibold tracking-[-0.01em]">
                  Recent work
                </h3>
                <ul className="mt-4 space-y-3.5">
                  {commits.map((c) => (
                    <li key={c.sha} className="flex gap-3">
                      {c.author.avatar && (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          src={c.author.avatar}
                          alt=""
                          className="mt-0.5 size-6 shrink-0 rounded-full"
                        />
                      )}
                      <span className="min-w-0 flex-1">
                        <a
                          href={c.url}
                          target="_blank"
                          rel="noreferrer"
                          className="flex min-h-11 items-center text-[14px] leading-snug transition-colors hover:text-[var(--foreground)] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]"
                        >
                          {c.message}
                        </a>
                        <span className="text-[14px] text-[var(--faint-ink)]">
                          {c.author.login ?? c.author.name} ·{" "}
                          {new Date(c.date).toLocaleDateString("en-US", {
                            month: "short",
                            day: "numeric",
                            timeZone: "UTC",
                          })}
                        </span>
                      </span>
                    </li>
                  ))}
                </ul>
              </div>
            )}

            <dl className="mt-7 border-t border-[var(--hairline)] pt-5 text-[14px]">
              <div className="flex items-center justify-between gap-4">
                <dt className="flex items-center gap-2 text-[var(--muted-ink)]">
                  <Tag className="size-[15px] text-[var(--faint-ink)]" />
                  Builds
                </dt>
                <dd className="tabular-nums">{releases.length}</dd>
              </div>
              <div className="mt-3 flex items-center justify-between gap-4 border-t border-[var(--hairline)] pt-3">
                <dt className="flex items-center gap-2 text-[var(--muted-ink)]">
                  <Cards className="size-[15px] text-[var(--faint-ink)]" />
                  Latest
                </dt>
                <dd className="tabular-nums">{latest?.tag ?? "—"}</dd>
              </div>
            </dl>

            {session.user.isAdmin && (
              <p className="mt-5 text-[14px] text-[var(--faint-ink)]">
                <Link
                  href="/admin/readme"
                  className="inline-flex min-h-11 items-center underline-offset-4 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]"
                >
                  Edit these notes
                </Link>
              </p>
            )}
          </aside>
        </div>
      </section>

    </main>
  );
}
