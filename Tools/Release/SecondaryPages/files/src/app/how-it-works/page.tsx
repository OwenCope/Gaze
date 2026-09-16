import type { Metadata } from "next";
import Link from "next/link";
import { TopNav } from "@/components/top-nav";
import { PageLinks } from "@/components/page-links";
import { SetupWalkthrough } from "@/components/setup-walkthrough";

export const metadata: Metadata = {
  title: "How it works",
  description: "From enrolling your face to following the lock-screen prompts, with a clear account of Gaze’s limits.",
};

export default function HowItWorksPage() {
  return (
    <main className="min-h-dvh bg-[var(--background)] pt-16 text-[var(--foreground)] antialiased">
      <TopNav />
      <header className="site-container py-16 sm:py-20">
        <p className="mb-5 text-base font-medium text-[var(--muted-ink)]">How it works</p>
        <h1 className="max-w-[17ch] text-balance text-[clamp(2.5rem,6vw,4rem)] font-semibold leading-[1.05] tracking-[-0.035em]">A familiar way back to your Mac.</h1>
        <p className="mt-6 max-w-[38rem] text-lg leading-relaxed text-[var(--muted-ink)]">A little setup. A look at the camera. A guided movement. Here’s what happens along the way.</p>
      </header>
      <SetupWalkthrough />
      <section className="bg-[var(--surface)] py-16 sm:py-20" aria-labelledby="limits-heading">
        <div className="site-container grid gap-10 md:grid-cols-[0.8fr_1.2fr] md:gap-20">
          <div>
            <p className="mb-4 text-sm font-medium text-[var(--muted-ink)]">Before you turn it on</p>
            <h2 id="limits-heading" className="site-heading">Convenience, with limits.</h2>
            <Link href="/security" className="site-link mt-5">Read about security <span aria-hidden>→</span></Link>
          </div>
          <div className="space-y-8">
            <div>
              <h3 className="text-xl font-semibold tracking-[-0.02em]">The camera you already have</h3>
              <p className="mt-3 leading-relaxed text-[var(--muted-ink)]">Gaze uses your Mac’s ordinary camera. Macs do not have the infrared depth camera used by Apple’s Face ID.</p>
            </div>
            <div>
              <h3 className="text-xl font-semibold tracking-[-0.02em]">Movement checks aren’t a guarantee</h3>
              <p className="mt-3 leading-relaxed text-[var(--muted-ink)]">Photos or replay can still fool a regular camera. Gaze’s movement and spoof checks add hurdles, but do not provide Face ID’s depth sensing.</p>
            </div>
            <div>
              <h3 className="text-xl font-semibold tracking-[-0.02em]">Your usual way in stays available</h3>
              <p className="mt-3 leading-relaxed text-[var(--muted-ink)]">Your password and Touch ID continue to work. Gaze submits a saved password when its checks pass; it does not replace macOS authentication.</p>
            </div>
            <p className="text-sm text-[var(--muted-ink)]">Gaze is independently made and is not affiliated with Apple.</p>
          </div>
        </div>
      </section>
      <PageLinks current="/how-it-works" />
    </main>
  );
}
