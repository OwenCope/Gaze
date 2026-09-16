import type { Metadata } from "next";
import { TopNav } from "@/components/top-nav";
import { ProductTour } from "@/components/product-tour";
import { FeatureList } from "@/components/feature-list";
import { PageLinks } from "@/components/page-links";

export const metadata: Metadata = {
  title: "Features",
  description: "Explore Gaze's local face recognition, lock-screen experience, and controls for what stays on your Mac.",
};

export default function FeaturesPage() {
  return (
    <main className="min-h-dvh bg-[var(--background)] pt-16 text-[var(--foreground)] antialiased">
      <TopNav />

      <header className="px-6 pb-8 pt-20">
        <div className="mx-auto max-w-[1080px]">
          <p className="text-[13px] font-medium uppercase tracking-[0.08em] text-[var(--faint-ink)]">
            Features
          </p>
          <h1 className="mt-4 max-w-[19ch] text-balance text-[clamp(2.5rem,6vw,4rem)] font-bold leading-[1.03] tracking-[-0.035em]">
            A small part of your Mac. A familiar way in.
          </h1>
          <p className="mt-6 max-w-2xl text-[18px] leading-relaxed text-[var(--muted-ink)]">
            Gaze recognizes enrolled faces on your Mac, guides the unlock flow at the lock screen, and keeps its controls close at hand in Settings.
          </p>
          <nav aria-label="On this page" className="mt-7">
            <ul className="flex flex-wrap gap-x-6 gap-y-2">
              <li>
                <a href="#tour" className="flex min-h-11 items-center rounded-md text-[15px] font-medium text-[var(--action)] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]">
                  Product tour
                </a>
              </li>
              <li>
                <a href="#features" className="flex min-h-11 items-center rounded-md text-[15px] font-medium text-[var(--action)] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]">
                  Feature list
                </a>
              </li>
            </ul>
          </nav>
        </div>
      </header>

      <ProductTour />
      <FeatureList />
      <PageLinks current="/features" />
    </main>
  );
}
