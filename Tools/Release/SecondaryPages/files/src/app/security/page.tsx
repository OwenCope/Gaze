import type { Metadata } from "next";
import Link from "next/link";
import { TopNav } from "@/components/top-nav";
import { PageLinks } from "@/components/page-links";
import { AppIcon } from "@/components/app-icon";

const records = [
  {
    name: "Recognition measurements",
    storage: "Encrypted on this Mac",
    body: "Your faceprint is encrypted using a key held by this Mac’s Secure Enclave. Camera frames are processed locally.",
  },
  {
    name: "Mac login password",
    storage: "Stored only for automatic unlocking",
    body: "If you enable automatic unlocking, Gaze stores an encrypted copy of your password. After the configured recognition and movement checks pass, it decrypts and submits that password to macOS.",
  },
  {
    name: "Face-tile portraits",
    storage: "Optional local image files",
    body: "Pictures you choose for face tiles are saved separately from encrypted recognition templates. They are not uploaded or used to recognize you.",
  },
];

export const metadata: Metadata = {
  title: "Security",
  description: "What Gaze stores on your Mac, how it uses the camera, and the limits of recognition with an ordinary camera.",
};

export default function SecurityPage() {
  return (
    <main className="min-h-dvh bg-[var(--background)] pt-16 text-[var(--foreground)] antialiased">
      <TopNav />
      <header className="site-container py-16 sm:py-20">
        <p className="mb-5 text-base font-medium text-[var(--muted-ink)]">Security</p>
        <h1 className="max-w-[17ch] text-balance text-[clamp(2.5rem,6vw,4rem)] font-semibold leading-[1.05] tracking-[-0.035em]">Your Mac. Your data. Your choice.</h1>
        <p className="mt-6 max-w-[38rem] text-lg leading-relaxed text-[var(--muted-ink)]">Recognition happens on your Mac, without a Gaze account. Here’s exactly what the app keeps and what protects it.</p>
      </header>
      <section aria-labelledby="storage-heading" className="site-container pb-20">
        <div className="overflow-hidden rounded-[28px] bg-[var(--surface)] shadow-[var(--card-shadow)]">
          <div className="grid gap-8 border-b border-[var(--hairline)] p-6 sm:p-10 md:grid-cols-[0.8fr_1.2fr] md:gap-16">
            <div>
              <AppIcon size={72} className="mb-6 size-16" />
              <h2 id="storage-heading" className="text-[28px] font-semibold leading-tight tracking-[-0.025em]">What stays here.</h2>
            </div>
            <p className="self-end text-[17px] leading-relaxed text-[var(--muted-ink)]">Your face is not an encryption key. Recognition decides when Gaze may submit your saved password. You can use recognition-only mode without enabling automatic unlocking.</p>
          </div>
          <dl className="px-6 sm:px-10">
            {records.map((record) => (
              <div key={record.name} className="grid gap-3 border-b border-[var(--hairline)] py-7 last:border-0 md:grid-cols-[0.8fr_1.2fr] md:gap-16">
                <dt>
                  <span className="block text-lg font-semibold tracking-[-0.015em]">{record.name}</span>
                  <span className="mt-1.5 block text-sm text-[var(--muted-ink)]">{record.storage}</span>
                </dt>
                <dd className="leading-relaxed text-[var(--muted-ink)]">{record.body}</dd>
              </div>
            ))}
          </dl>
        </div>
      </section>
      <section className="site-container grid gap-12 pb-20 md:grid-cols-2 md:gap-20" aria-label="Camera access and security limits">
        <div>
          <h2 className="text-[28px] font-semibold leading-tight tracking-[-0.025em]">When the camera is used.</h2>
          <p className="mt-5 text-[17px] leading-relaxed text-[var(--muted-ink)]">Setup, recognition tests, automatic unlocking and Passwords approvals can use the camera. Optional walk-away locking checks for your presence while the Mac is idle. You control these features in Settings.</p>
          <Link href="/how-it-works" className="site-link mt-4">See the unlocking flow <span aria-hidden>→</span></Link>
        </div>
        <div>
          <h2 className="text-[28px] font-semibold leading-tight tracking-[-0.025em]">Know the limits.</h2>
          <p className="mt-5 text-[17px] leading-relaxed text-[var(--muted-ink)]">Gaze uses a regular camera. Movement prompts and spoof checks can still be fooled by photos or replay; they do not provide Face ID’s depth sensing.</p>
          <p className="mt-4 text-[17px] leading-relaxed text-[var(--muted-ink)]">Your Mac password remains available. After a restart, sign in normally so Gaze can start.</p>
        </div>
      </section>
      <PageLinks current="/security" />
    </main>
  );
}
