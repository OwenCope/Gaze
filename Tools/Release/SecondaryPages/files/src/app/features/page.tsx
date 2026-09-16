import { PageIntro } from "@/components/page-intro";
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

      <PageIntro eyebrow="Features" title="Face unlock, at home on your Mac." description="Local recognition, guided movements, and controls that stay close at hand.">
        <nav aria-label="On this page" className="mt-5 flex flex-wrap gap-x-6">
          <a href="#tour" className="site-link text-[15px] font-medium">Product tour</a>
          <a href="#features" className="site-link text-[15px] font-medium">Feature list</a>
        </nav>
      </PageIntro>

      <ProductTour />
      <FeatureList />
      <PageLinks current="/features" />
    </main>
  );
}
