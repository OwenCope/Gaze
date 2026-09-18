"use client";

import { useState, type ReactNode } from "react";
import { signIn } from "next-auth/react";
import { EmailSignIn } from "@/components/email-sign-in";
import Link from "next/link";
import { AppIcon } from "@/components/app-icon";

export function SignInPage({
  providers,
  callbackUrl,
  title = "Sign in to Gaze",
  description = "Access releases and your tester account.",
}: {
  providers: { google: boolean; github: boolean; email: boolean };
  callbackUrl: string;
  title?: ReactNode;
  description?: ReactNode;
}) {
  const [busy, setBusy] = useState<"google" | "github" | null>(null);
  const none = !providers.google && !providers.github && !providers.email;

  const begin = (id: "google" | "github") => {
    setBusy(id);
    void signIn(id, { callbackUrl });
  };

  return (
    <div className="flex min-h-dvh flex-col px-4 sm:px-6">
      <nav aria-label="Return to website" className="mx-auto w-full max-w-[1080px] py-5">
        <Link href="/" className="site-link"><span aria-hidden>←</span> Back to Gaze</Link>
      </nav>
      <section className="flex flex-1 items-center justify-center pb-16 pt-6">
        <div className="w-full max-w-[440px] rounded-[24px] bg-[var(--surface)] p-6 shadow-[var(--card-shadow)] sm:p-8">
          <AppIcon size={72} className="mb-5 size-14" />
          <h1 className="text-balance text-[clamp(2rem,4vw,2.25rem)] font-semibold leading-[1.12] tracking-[-0.025em]">
            {title}
          </h1>
          <p className="mt-4 leading-relaxed text-[var(--muted-ink)]">
            {description}
          </p>
          <p className="mt-3 text-sm leading-relaxed text-[var(--muted-ink)]">
            Website sign-in only. Gaze’s Mac app works without an account.
          </p>

          <div className="mt-6 space-y-3">
            {providers.google && (
              <ProviderButton
                busy={busy === "google"}
                disabled={busy !== null}
                onClick={() => begin("google")}
                icon={<GoogleMark />}
                label="Continue with Google"
                busyLabel="Opening Google…"
              />
            )}

            {providers.github && (
              <ProviderButton
                busy={busy === "github"}
                disabled={busy !== null}
                onClick={() => begin("github")}
                icon={<GitHubMark />}
                label="Continue with GitHub"
                busyLabel="Opening GitHub…"
              />
            )}

            {/* A rule with the word on it, only when there is something on both sides of
                it to separate. An "or" above nothing is a divider between one thing. */}
            {providers.email && (providers.google || providers.github) && (
              <div className="flex items-center gap-3 py-1">
                <span className="h-px flex-1 bg-[var(--hairline)]" />
                <span className="text-[12px] text-[var(--faint-ink)]">or</span>
                <span className="h-px flex-1 bg-[var(--hairline)]" />
              </div>
            )}

            {providers.email && (
              <EmailSignIn callbackUrl={callbackUrl} />
            )}

            {none && (
              <p className="rounded-[16px] border border-[var(--panel-edge)] bg-[var(--panel-bg)] p-4 text-[14px] leading-relaxed text-[var(--muted-ink)]">
                Sign-in is not available here yet. You can still explore the website.
              </p>
            )}
          </div>

          {(providers.google || providers.github) && (
            <p className="mt-6 text-sm leading-relaxed text-[var(--muted-ink)]">
              Gaze only sees your name, email and avatar.
            </p>
          )}
        </div>
      </section>

    </div>
  );
}

function ProviderButton({
  icon,
  label,
  busyLabel,
  busy,
  disabled,
  onClick,
  className = "",
}: {
  icon: ReactNode;
  label: string;
  busyLabel: string;
  busy: boolean;
  disabled: boolean;
  onClick: () => void;
  className?: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className={`${className} flex h-[52px] w-full cursor-pointer items-center justify-center gap-3 rounded-[16px] border border-[var(--hairline)] bg-[var(--background)] text-base font-medium outline-none transition-[background-color,border-color] duration-150 hover:border-[var(--muted-ink)] active:bg-[var(--panel-bg)] focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[var(--foreground)] disabled:cursor-default disabled:opacity-55`}
    >
      <span className="flex size-5 shrink-0 items-center justify-center">{icon}</span>
      {busy ? busyLabel : label}
    </button>
  );
}


function GoogleMark() {
  return (
    <svg viewBox="0 0 48 48" className="size-5" aria-hidden>
      <path
        fill="#FFC107"
        d="M43.611 20.083H42V20H24v8h11.303c-1.649 4.657-6.08 8-11.303 8-6.627 0-12-5.373-12-12s5.373-12 12-12c3.059 0 5.842 1.154 7.961 3.039l5.657-5.657C34.046 6.053 29.268 4 24 4 12.955 4 4 12.955 4 24s8.955 20 20 20 20-8.955 20-20c0-2.641-.21-5.236-.389-7.917z"
      />
      <path
        fill="#FF3D00"
        d="M6.306 14.691l6.571 4.819C14.655 15.108 18.961 12 24 12c3.059 0 5.842 1.154 7.961 3.039l5.657-5.657C34.046 6.053 29.268 4 24 4 16.318 4 9.656 8.337 6.306 14.691z"
      />
      <path
        fill="#4CAF50"
        d="M24 44c5.166 0 9.86-1.977 13.409-5.192l-6.19-5.238C29.211 35.091 26.715 36 24 36c-5.202 0-9.619-3.317-11.283-7.946l-6.522 5.025C9.505 39.556 16.227 44 24 44z"
      />
      <path
        fill="#1976D2"
        d="M43.611 20.083H42V20H24v8h11.303c-.792 2.237-2.231 4.166-4.087 5.571l6.19 5.238C42.022 35.026 44 30.038 44 24c0-2.641-.21-5.236-.389-7.917z"
      />
    </svg>
  );
}

function GitHubMark() {
  return (
    <svg viewBox="0 0 24 24" className="size-5 fill-current" aria-hidden>
      <path d="M12 .5a12 12 0 0 0-3.8 23.4c.6.1.8-.3.8-.6v-2c-3.3.7-4-1.6-4-1.6-.6-1.4-1.4-1.8-1.4-1.8-1-.7.1-.7.1-.7 1.2.1 1.8 1.2 1.8 1.2 1 1.8 2.8 1.3 3.5 1 .1-.8.4-1.3.7-1.6-2.7-.3-5.5-1.3-5.5-5.9 0-1.3.5-2.4 1.2-3.2-.1-.3-.5-1.5.1-3.2 0 0 1-.3 3.3 1.2a11.5 11.5 0 0 1 6 0C17.3 4.7 18.3 5 18.3 5c.6 1.7.2 2.9.1 3.2.8.8 1.2 1.9 1.2 3.2 0 4.6-2.8 5.6-5.5 5.9.4.4.8 1.1.8 2.2v3.3c0 .3.2.7.8.6A12 12 0 0 0 12 .5Z" />
    </svg>
  );
}
