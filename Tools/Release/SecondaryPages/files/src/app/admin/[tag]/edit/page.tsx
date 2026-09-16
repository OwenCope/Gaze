import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { auth } from "@/auth";
import { SiteNav } from "@/components/site-nav";
import { BackLink } from "@/components/back-link";
import { ReleaseComposer } from "@/components/release-composer";
import { readAll } from "@/lib/store";

export const metadata: Metadata = {
  title: "Edit release",
  robots: { index: false, follow: false },
};

export const dynamic = "force-dynamic";

export default async function EditRelease({
  params,
}: {
  params: Promise<{ tag: string }>;
}) {
  const session = await auth();

  // Checked here as well as in middleware: a matcher can be misconfigured, a
  // page that guards itself cannot be.
  if (!session?.user) redirect("/signin?callbackUrl=/admin");
  if (!session.user.isAdmin) redirect("/");

  const { tag } = await params;

  // The raw record, not the rendered one. `getReleases` turns the markdown into
  // HTML, and an editor needs the markdown back.
  const release = (await readAll()).find((r) => r.tag === decodeURIComponent(tag));
  if (!release) notFound();

  return (
    <main
      id="top"
      className="admin-page min-h-dvh bg-[var(--background)] text-[var(--foreground)] antialiased"
    >
      <SiteNav />
      <section className="px-6 pb-20 pt-40">
        <div className="mx-auto max-w-[1080px]">
          <BackLink href="/admin">Dashboard</BackLink>
          <h1 className="mt-7 text-balance text-[clamp(2rem,4.5vw,3rem)] font-semibold leading-[1.08] tracking-[-0.035em]">
            Edit {release.name}
          </h1>
          <p className="mt-3 text-[var(--muted-ink)]">
            {release.draft ? "Draft" : "Published"} · {release.tag}
          </p>

          <div className="mt-10">
            <ReleaseComposer initial={release} />
          </div>
        </div>
      </section>

    </main>
  );
}
