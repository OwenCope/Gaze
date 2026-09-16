import { EmailSignIn } from "@/components/email-sign-in";

export default function EmailReview() {
  return (
    <main className="min-h-dvh bg-[var(--background)] px-6 py-16 text-[var(--foreground)]">
      <div className="mx-auto max-w-sm">
        <h1 className="mb-3 text-2xl font-semibold">Synthetic sign-in UI test</h1>
        <p className="mb-8 text-[var(--muted-ink)]">This temporary review page has no email service or real accounts.</p>
        <EmailSignIn callbackUrl="/email-ui-review" />
      </div>
    </main>
  );
}
