import { cookies } from "next/headers";
import NextAuth from "next-auth";
import Credentials from "next-auth/providers/credentials";
import Google from "next-auth/providers/google";
import GitHub from "next-auth/providers/github";
import Apple from "next-auth/providers/apple";
import { CODE_COOKIE, canonicalCode, canonicalEmail } from "@/lib/email-code";
import { emailCodeEnabled, getProductionChallengeStore, verifyCodeFlow } from "@/lib/email-challenge-store";

/**
 * Who counts as the owner.
 *
 * Signing in is open to anyone; being *you* is not. Admin is decided by email
 * against this list rather than by a role in a database, because there is one
 * admin and a database would be a thing to secure for no gain.
 */
const ADMINS = (process.env.ADMIN_EMAILS ?? "")
  .split(",")
  .map((e) => e.trim().toLowerCase())
  .filter(Boolean);

export const { handlers, signIn, signOut, auth } = NextAuth({
  providers: [
    // Both are optional at build time: a provider with no credentials simply
    // does not appear, so the site still builds before the keys exist.
    ...(process.env.AUTH_GOOGLE_ID ? [Google] : []),
    ...(process.env.AUTH_GITHUB_ID ? [GitHub] : []),
    // Apple needs a paid Developer Program membership to issue the Services ID
    // and key, so it stays dark until those exist. Wired up regardless: the
    // work is the same whether the credentials arrive today or next year, and
    // a provider that appears the moment its keys do is easier to reason about
    // than one somebody has to remember to add.
    ...(process.env.AUTH_APPLE_ID ? [Apple] : []),

    // Email, as a six-digit code rather than a magic link.
    //
    // NextAuth's own email provider needs a database adapter to hold verification tokens,
    // and this site has none on purpose. `lib/email-code` signs the code into an httpOnly
    // cookie under a server-generated challenge id instead, and
    // `lib/email-challenge-store` holds the single-use/attempt/send state in
    // the private Blob store — see the comments there for the policy. The
    // HMAC alone no longer suffices: every verification spends its challenge
    // atomically, wrong guesses are bounded per challenge, and a missing or
    // failing store denies rather than falling back to the old stateless check.
    //
    // A `Credentials` provider is the only way in without an adapter. It is normally the
    // wrong choice, because it usually means checking a password against a database this
    // app does not have; here the "credential" has already been proven by receiving it at
    // an address, which is the same thing a magic link proves.
    ...(process.env.RESEND_API_KEY
      ? [
          Credentials({
            id: "email-code",
            name: "Email",
            credentials: {
              email: { label: "Email", type: "email" },
              code: { label: "Code", type: "text" },
            },
            async authorize(raw) {
              const email = canonicalEmail(raw?.email);
              const code = canonicalCode(raw?.code);
              if (!email || !code) return null;
              if (!emailCodeEnabled()) return null;

              const storeOrStatus = getProductionChallengeStore();
              if ("status" in storeOrStatus) {
                return null;
              }

              const jar = await cookies();
              const outcome = await verifyCodeFlow({
                cookie: jar.get(CODE_COOKIE)?.value,
                emailRaw: email,
                codeRaw: code,
                now: Date.now(),
                store: storeOrStatus,
              });

              if (outcome.status !== "ok") {
                // End terminal windows so a spent, locked or expired challenge
                // cannot linger: the next attempt needs a fresh code. A plain
                // wrong code keeps its cookie so typos can be retried until
                // the attempt bound locks the challenge.
                if (outcome.status === "replay" || outcome.status === "locked" || outcome.status === "expired") {
                  jar.delete(CODE_COOKIE);
                }
                return null;
              }

              // Spending happened atomically inside the store: a replayed
              // cookie with the same challenge id now reads as consumed.
              jar.delete(CODE_COOKIE);
              return { id: outcome.email, email: outcome.email };
            },
          }),
        ]
      : []),
  ],
  pages: { signIn: "/signin" },
  callbacks: {
    async jwt({ token }) {
      token.isAdmin = ADMINS.includes((token.email ?? "").toLowerCase());
      return token;
    },
    async session({ session, token }) {
      session.user.isAdmin = Boolean(token.isAdmin);
      return session;
    },
  },
});
