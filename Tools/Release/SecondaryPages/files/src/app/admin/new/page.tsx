import { SiteNav } from "@/components/site-nav";
import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { auth } from "@/auth";
import { BackLink } from "@/components/back-link";
import { ReleaseComposer } from "@/components/release-composer";

export const metadata: Metadata = {
  title: "New release",
  robots: { index: false, follow: false },
};

export default async function NewRelease() {
  const session = await auth();
  if (!session?.user) redirect("/signin?callbackUrl=/admin/new");
  if (!session.user.isAdmin) redirect("/");

  return (
    <main className="admin-page min-h-dvh bg-[var(--background)] text-[var(--foreground)] antialiased">
      <SiteNav />
      <section className="px-6 pb-20 pt-40">
        <div className="mx-auto max-w-[1080px]">
          <BackLink href="/admin">Dashboard</BackLink>
          <h1 className="mt-7 text-balance text-[clamp(2rem,4.5vw,3rem)] font-semibold leading-[1.08] tracking-[-0.035em]">
            New release
          </h1>
          <p className="mt-3 max-w-xl text-[var(--muted-ink)]">
            Prepare the notes and media, then save a draft or publish when ready.
          </p>
          <div className="mt-10">
            <ReleaseComposer />
          </div>
        </div>
      </section>
    </main>
  );
}
