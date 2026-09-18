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

      <PageIntro title="Features" description="Recognition runs on your Mac, with movement prompts before automatic unlocking.">
        <nav aria-label="On this page" className="mt-4 flex flex-wrap gap-x-6 gap-y-2">
          <a href="#tour" className="site-link text-[15px] font-medium">Product tour</a>
          <a href="#features" className="site-link text-[15px] font-medium">Details</a>
        </nav>
      </PageIntro>

      <ProductTour />
      <FeatureList />
      <PageLinks current="/features" />
    </main>
  );
}
