import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { auth } from "@/auth";
import { SiteNav } from "@/components/site-nav";
import { BackLink } from "@/components/back-link";
import { ReadmeEditor } from "@/components/readme-editor";
import { readReadmeDocument } from "@/lib/readme";

export const metadata: Metadata = {
  title: "Tester notes",
  robots: { index: false, follow: false },
};

export const dynamic = "force-dynamic";

export default async function ReadmePage() {
  const session = await auth();
  if (!session?.user) redirect("/signin?callbackUrl=/admin/readme");
  if (!session.user.isAdmin) redirect("/");

  const { text: readme, version: readmeVersion } = await readReadmeDocument();

  return (
    <main
      id="top"
      className="min-h-dvh bg-[var(--background)] text-[var(--foreground)] antialiased"
    >
      <section className="px-6 pb-28 pt-24">
        <div className="mx-auto max-w-[1080px]">
          <BackLink />
          <h1 className="mt-7 text-balance text-[clamp(2rem,4.5vw,3rem)] font-bold leading-[1.05] tracking-[-0.035em]">
            Tester notes
          </h1>
          <p className="mt-3 max-w-xl text-[var(--muted-ink)]">
            What testers read beside the builds — what to install, what to look
            for, what is known to be broken.
          </p>

          <div className="mt-10">
            <ReadmeEditor initial={readme} initialVersion={readmeVersion} />
          </div>
        </div>
      </section>

      <SiteNav />
    </main>
  );
}
