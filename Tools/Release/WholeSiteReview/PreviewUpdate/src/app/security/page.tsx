import { PageIntro } from "@/components/page-intro";
import type { Metadata } from "next";
import Link from "next/link";
import { TopNav } from "@/components/top-nav";
import { PageLinks } from "@/components/page-links";

const records = [
  {
    name: "Face data",
    body: "Your faceprint is encrypted using a key held by this Mac’s Secure Enclave. Camera frames are processed locally.",
  },
  {
    name: "Saved password",
    body: "If you enable automatic unlocking, Gaze stores an encrypted copy of your password. After the configured recognition and movement checks pass, it decrypts and submits that password to macOS.",
  },
  {
    name: "Profile pictures",
    body: "Optional profile pictures are stored separately from encrypted recognition templates. They are not uploaded or used to recognize you.",
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
      <PageIntro title="Security and privacy" description="What Gaze stores on your Mac, when it uses the camera, and its security limits." />
      <section aria-labelledby="storage-heading" className="site-container pb-14">
          <div className="mb-7 grid gap-4 md:grid-cols-[220px_minmax(0,1fr)] md:gap-12">
            <h2 id="storage-heading" className="text-[24px] font-medium leading-tight tracking-[-0.02em]">Stored on this Mac</h2>
            <p className="max-w-[66ch] text-base leading-relaxed text-[var(--muted-ink)]">Your face is not an encryption key. Recognition decides when Gaze may submit your saved password. You can use recognition-only mode without enabling automatic unlocking.</p>
          </div>
          <dl className="border-t border-[var(--hairline)]">
            {records.map((record) => (
              <div key={record.name} className="grid gap-3 border-b border-[var(--hairline)] py-5 md:grid-cols-[220px_minmax(0,1fr)] md:gap-12">
                <dt>
                  <span className="block text-base font-medium">{record.name}</span>
                </dt>
                <dd className="max-w-[66ch] text-base leading-relaxed text-[var(--muted-ink)]">{record.body}</dd>
              </div>
            ))}
          </dl>
      </section>
      <section className="site-container grid gap-8 pb-14 lg:grid-cols-2 lg:gap-14" aria-label="Camera access and security limits">
        <div>
          <h2 className="text-[24px] font-medium leading-tight tracking-[-0.02em]">Camera access</h2>
          <p className="mt-3 text-base leading-relaxed text-[var(--muted-ink)]">Setup, recognition tests, automatic unlocking and Passwords approvals can use the camera. Optional walk-away locking checks for your presence while the Mac is idle. You control these features in Settings.</p>
          <Link href="/how-it-works" className="site-link mt-4">See the unlocking flow <span aria-hidden>→</span></Link>
        </div>
        <div>
          <h2 className="text-[24px] font-medium leading-tight tracking-[-0.02em]">Security limits</h2>
          <p className="mt-3 text-base leading-relaxed text-[var(--muted-ink)]">Gaze uses a regular camera. Movement prompts and spoof checks can still be fooled by photos or replay; they do not provide Face ID’s depth sensing.</p>
          <p className="mt-4 text-base leading-relaxed text-[var(--muted-ink)]">Your Mac password remains available. After a restart, sign in normally so Gaze can start.</p>
        </div>
      </section>
      <PageLinks current="/security" />
    </main>
  );
}
