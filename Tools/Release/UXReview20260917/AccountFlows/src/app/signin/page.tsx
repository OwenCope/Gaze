import type { Metadata } from "next";
import { SignInPage } from "@/components/ui/sign-in";
import { safeCallbackPath } from "@/lib/safe-callback";
import { emailCodeEnabled } from "@/lib/email-challenge-store";

export const metadata: Metadata = {
  title: "Sign in",
  robots: { index: false, follow: false },
};

export default async function SignIn({
  searchParams,
}: {
  searchParams: Promise<{ callbackUrl?: string }>;
}) {
  const { callbackUrl } = await searchParams;
  const sanitizedCallback = safeCallbackPath(callbackUrl);

  // Read on the server so the keys never reach the browser — the card only
  // learns which buttons to draw.
  const providers = {
    google: Boolean(process.env.AUTH_GOOGLE_ID),
    github: Boolean(process.env.AUTH_GITHUB_ID),
    // Email needs a sender as well as a secret, so both are checked — a key with no
    // "from" address would draw the form and then fail at the send. It is
    // additionally hidden production-like without the private challenge
    // store: drawing the form there would promise codes the send route must
    // refuse (503) rather than issue insecurely.
    email: Boolean(process.env.RESEND_API_KEY && process.env.SIGNIN_EMAIL_FROM && emailCodeEnabled()),
  };

  // Say why they are here, when they did not choose to be.
  //
  // Being bounced to a sign-in page with no explanation reads as the site
  // having lost your session, or as a page that has quietly disappeared. The
  // callback URL already says which door they were turned away from.
  const reason: Record<string, string> = {
    "/releases": "Releases are behind sign-in at the moment. Sign in to see them.",
    "/testers": "The tester page is for people on the tester list. Sign in to check.",
  };

  const description =
    reason[sanitizedCallback] ??
    (sanitizedCallback === "/admin" || sanitizedCallback.startsWith("/admin/")
      ? "Sign in to manage Gaze."
      : undefined);

  return (
    <main className="min-h-dvh bg-[var(--background)] text-[var(--foreground)] antialiased">
      <SignInPage
        providers={providers}
        callbackUrl={sanitizedCallback}
        description={description}
      />
    </main>
  );
}
