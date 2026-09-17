import Link from "next/link";
import { AppIcon } from "@/components/app-icon";
import { TopNav } from "@/components/top-nav";
import { PageLinks } from "@/components/page-links";

export default function NotFound() {
  return (
    <div className="flex min-h-dvh flex-col bg-[var(--background)] text-[var(--foreground)] antialiased">
      <TopNav />
      <main className="flex flex-1 items-center justify-center px-6 pb-16 pt-28 sm:pt-32">
        <div className="flex w-full max-w-[440px] flex-col items-center text-center">
          <AppIcon size={64} className="size-16" />
          <p className="mt-6 text-[13px] font-medium tracking-[0.04em] text-[var(--muted-ink)]">
            404
          </p>
          <h1 className="mt-3 text-balance text-[clamp(2rem,7vw,2.5rem)] font-semibold leading-[1.08] tracking-[-0.03em]">
            This page isn&rsquo;t here.
          </h1>
          <p className="mt-5 max-w-[38ch] text-[17px] leading-[1.6] text-[var(--muted-ink)]">
            The link may have changed, or this page may not be available.
          </p>
          <div className="mt-8 flex flex-col items-center gap-2">
            <Link
              href="/"
              className="inline-flex min-h-11 items-center justify-center rounded-full bg-[var(--action-fill)] px-6 py-2.5 text-[15px] font-medium text-white transition-opacity hover:opacity-90 active:opacity-75 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[var(--action)]"
            >
              Back to Gaze
            </Link>
            <Link href="/releases" className="site-link text-[15px]">
              View releases
            </Link>
          </div>
        </div>
      </main>
      <PageLinks current="/404" />
    </div>
  );
}
