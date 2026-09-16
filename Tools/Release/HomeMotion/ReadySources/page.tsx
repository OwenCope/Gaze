import Link from "next/link";
import { AppIcon } from "@/components/app-icon";
import { MacScreen } from "@/components/mac-screen";
import { TopNav } from "@/components/top-nav";
import { LiveDemo } from "@/components/live-demo";
import { FAQs } from "@/components/faqs";
import { FeaturesCarousel } from "@/components/features-carousel";
import { ScreenshotGallery } from "@/components/screenshot-gallery";
import { HomeHeroMotion } from "@/components/home-hero-motion";
import { LiquidButton } from "@/components/ui/liquid-glass-button";
import { Footer } from "@/components/ui/footer-section";

const DISCORD = "https://discord.gg/BFgKT5YJH";

export default function Home() {
  return (
    <main id="top" className="min-h-dvh bg-[var(--background)] pt-14 text-[var(--foreground)]">
      <a href="#main-content" className="skip-link">Skip to content</a>
      <TopNav />
      <section id="main-content" tabIndex={-1} aria-labelledby="hero-title" className="overflow-hidden pb-12 pt-10 sm:pb-20 sm:pt-14">
        <div className="site-container text-center">
          <div className="flex items-center justify-center gap-2.5">
            <AppIcon size={88} priority className="size-11" />
            <p className="text-[19px] font-semibold tracking-[-0.02em]">Gaze for Mac</p>
          </div>
          <HomeHeroMotion
            headline={
              <h1 id="hero-title" className="mx-auto mt-5 max-w-3xl text-[clamp(2.75rem,7.5vw,4.75rem)] font-semibold leading-[1.02] tracking-[-0.045em]">
                Your face.<br />Your Mac. Unlocked.
              </h1>
            }
            lede={
              <p className="mx-auto mt-6 max-w-[540px] text-balance text-[clamp(1.125rem,2vw,1.375rem)] leading-[1.45] tracking-[-0.015em] text-[var(--muted-ink)]">
                Gaze uses your Mac&rsquo;s camera to recognize you at the lock screen.
                No account. Nothing uploaded. Your password still works.
              </p>
            }
            actions={
              <>
                <div className="mt-7 flex flex-wrap items-center justify-center gap-x-7 gap-y-2">
                  <LiquidButton variant="solid" asChild>
                    <Link href={DISCORD} target="_blank" rel="noreferrer">Join the Discord</Link>
                  </LiquidButton>
                  <a href="#demo" className="site-link text-[17px]">See how it works <span aria-hidden>›</span></a>
                </div>
                <p className="mt-4 text-[12px] text-[var(--muted-ink)]">Free and open source. Currently in development.</p>
              </>
            }
            product={
              <div className="mx-auto mt-10 max-w-[980px] sm:mt-12">
                <MacScreen interactive />
              </div>
            }
          />
        </div>
      </section>

      <LiveDemo />
      <FeaturesCarousel />
      <ScreenshotGallery />

      <section aria-labelledby="security-title" className="py-20 sm:py-28">
        <div className="site-container grid items-start gap-8 md:grid-cols-2 md:gap-20">
          <div>
            <p className="mb-4 text-[14px] font-semibold text-[var(--muted-ink)]">Privacy &amp; security</p>
            <h2 id="security-title" className="site-heading">Your face stays on your Mac.</h2>
          </div>
          <div className="max-w-lg text-[17px] leading-relaxed text-[var(--muted-ink)]">
            <p>Recognition runs locally. Gaze doesn&rsquo;t send your face to a server, and your password remains available.</p>
            <p className="mt-4">Gaze uses a regular camera, not Face ID. A photograph may fool it. It&rsquo;s a convenience feature, not a replacement for your Mac&rsquo;s security.</p>
            <Link href="/security" className="site-link mt-4">Read about security <span aria-hidden>›</span></Link>
          </div>
        </div>
      </section>

      <FAQs />

      <section className="py-20 text-center sm:py-28">
        <div className="site-container">
          <h2 className="site-heading">Help shape Gaze.</h2>
          <p className="mx-auto mt-5 max-w-md text-balance text-[19px] leading-relaxed text-[var(--muted-ink)]">
            Gaze is still in development. Join the Discord for builds, updates, and feedback.
          </p>
          <div className="mt-7">
            <LiquidButton variant="solid" asChild>
              <Link href={DISCORD} target="_blank" rel="noreferrer">Join the Discord</Link>
            </LiquidButton>
          </div>
          <p className="mt-8 text-[13px] text-[var(--muted-ink)]">
            Made possible by the projects and people in the <Link href="/credits" className="underline underline-offset-4">credits</Link>.
          </p>
        </div>
      </section>

      <Footer
        note="Gaze · free and open source · not affiliated with Apple."
        columns={[
          { label: "Gaze", links: [
            { title: "How it works", href: "/how-it-works" },
            { title: "Features", href: "/features" },
            { title: "Security", href: "/security" },
            { title: "Releases", href: "/releases" },
          ] },
          { label: "Built on", links: [
            { title: "Sapphire", href: "https://sapphire-app.tech", external: true },
            { title: "DynamicLake", href: "https://dynamiclake.com", external: true },
            { title: "Atoll", href: "https://getatoll.app", external: true },
          ] },
          { label: "Community", links: [
            { title: "Discord", href: DISCORD, external: true },
            { title: "Credits", href: "/credits" },
          ] },
        ]}
      />
    </main>
  );
}
