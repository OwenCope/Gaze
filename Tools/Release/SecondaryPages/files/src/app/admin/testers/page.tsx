import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { auth } from "@/auth";
import { SiteNav } from "@/components/site-nav";
import { BackLink } from "@/components/back-link";
import { TestersManager } from "@/components/testers-manager";
import { readTesters } from "@/lib/testers";
import { readRoles } from "@/lib/roles";
import { RolesManager } from "@/components/roles-manager";

export const metadata: Metadata = {
  title: "People",
  robots: { index: false, follow: false },
};

export const dynamic = "force-dynamic";

export default async function Testers() {
  const session = await auth();

  // Checked here as well as in middleware: a matcher can be misconfigured, a
  // page that guards itself cannot be.
  if (!session?.user) redirect("/signin?callbackUrl=/admin/testers");
  if (!session.user.isAdmin) redirect("/");

  const [testers, roles] = await Promise.all([readTesters(), readRoles()]);

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
            People
          </h1>
          <p className="mt-3 max-w-xl text-[var(--muted-ink)]">
            Who can open a private release, and what each role is allowed to do.
            The list carries across releases — add someone once and they see
            every private one after it.
          </p>

          <div className="mt-10">
            <TestersManager initial={testers} roles={roles} />
          </div>

          <h2 className="mt-16 text-balance text-[clamp(1.5rem,3vw,2rem)] font-semibold tracking-[-0.025em]">
            Roles
          </h2>
          <div className="mt-6">
            <RolesManager initial={roles} />
          </div>
        </div>
      </section>

    </main>
  );
}
