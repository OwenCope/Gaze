"use client";

import { signIn } from "next-auth/react";
import { useEffect, useId, useRef, useState } from "react";

import { safeCallbackPath } from "@/lib/safe-callback";

type Step = "email" | "code";

const RESEND_COOLDOWN_MS = 30_000;

export function EmailSignIn({ callbackUrl }: { callbackUrl: string }) {
  const [step, setStep] = useState<Step>("email");
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const inFlight = useRef(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [resendAvailableAt, setResendAvailableAt] = useState<number | null>(null);
  const [nowMs, setNowMs] = useState(() => Date.now());
  const uid = useId();
  const emailInputId = `${uid}-email-input`;
  const codeInputId = `${uid}-code-input`;
  const errorMessageId = `${uid}-error-message`;

  // Whole seconds left on the resend deadline, derived from wall-clock time so
  // a throttled background tab still shows the right number on return.
  const resendInSeconds =
    resendAvailableAt === null
      ? 0
      : Math.max(0, Math.ceil((resendAvailableAt - nowMs) / 1000));

  useEffect(() => {
    if (resendAvailableAt === null) return;
    const id = window.setInterval(() => {
      if (Date.now() >= resendAvailableAt) {
        setResendAvailableAt(null);
      } else {
        setNowMs(Date.now());
      }
    }, 500);
    return () => window.clearInterval(id);
  }, [resendAvailableAt]);

  async function requestCode(event: { preventDefault(): void }) {
    event.preventDefault();
    if (inFlight.current) return;
    if (step === "code" && resendAvailableAt !== null && Date.now() < resendAvailableAt) return;
    inFlight.current = true;
    setBusy(true);
    setError(null);

    try {
      const response = await fetch("/api/signin-code", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email }),
        signal: AbortSignal.timeout(15_000),
      });
      if (!response.ok) {
        const body = await response.json().catch(() => null);
        setError(typeof body?.error === "string" ? body.error : "Couldn't send the code. Try again.");
        return;
      }
      setCode("");
      setStep("code");
      const sentAt = Date.now();
      setResendAvailableAt(sentAt + RESEND_COOLDOWN_MS);
      setNowMs(sentAt);
    } catch {
      setError("Couldn't send the code. Check your connection and try again.");
    } finally {
      inFlight.current = false;
      setBusy(false);
    }
  }

  async function submitCode(event: React.FormEvent) {
    event.preventDefault();
    if (inFlight.current) return;
    inFlight.current = true;
    setBusy(true);
    setError(null);

    try {
      const result = await signIn("email-code", { email, code, redirect: false, callbackUrl: safeCallbackPath(callbackUrl) });
      if (!result?.ok || result.error) {
        setError(result?.error === "CredentialsSignin"
          ? "That code isn't right or has expired. After several tries, request a new code."
          : "Couldn't sign in. Try again in a moment.");
        return;
      }
      window.location.assign(safeCallbackPath(callbackUrl));
    } catch {
      setError("Couldn't check the code. Check your connection and try again.");
    } finally {
      inFlight.current = false;
      setBusy(false);
    }
  }

  if (step === "email") {
    return (
      <form aria-busy={busy} onSubmit={requestCode} className="flex flex-col gap-2.5">
        <label htmlFor={emailInputId} className="text-[14px] font-medium text-[var(--foreground)]">
          Email address
        </label>
        <input
          id={emailInputId}
          aria-label="Email address"
          aria-describedby={error ? errorMessageId : undefined}
          readOnly={busy}
          type="email"
          required
          autoComplete="email"
          placeholder="you@example.com"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          className="min-h-11 w-full rounded-xl border border-[var(--panel-edge)] bg-[var(--panel-bg)] px-4 py-2.5 text-[16px] transition-colors focus:border-[var(--foreground)]/30 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]"
        />
        <button
          type="submit"
          disabled={busy || !email}
          className="min-h-11 w-full rounded-xl bg-[var(--foreground)] px-4 py-2.5 text-[15px] font-medium text-[var(--background)] transition-opacity hover:opacity-85 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)] disabled:opacity-40"
        >
          {busy ? "Sending…" : "Email me a code"}
        </button>
        {error && <Message id={errorMessageId} text={error} />}
      </form>
    );
  }

  return (
    <form aria-busy={busy} onSubmit={submitCode} className="flex flex-col gap-2.5">
      <p className="text-[14px] leading-relaxed text-[var(--muted-ink)]">
        Six digits are on their way to <span className="break-all text-[var(--foreground)]">{email}</span>.
        They expire in ten minutes.
      </p>
      <label htmlFor={codeInputId} className="text-[14px] font-medium text-[var(--foreground)]">
        Sign-in code
      </label>
      <input
        id={codeInputId}
        aria-label="Six-digit sign-in code"
        aria-describedby={error ? errorMessageId : undefined}
        readOnly={busy}
        type="text"
        inputMode="numeric"
        autoComplete="one-time-code"
        pattern="\d{6}"
        maxLength={6}
        required
        autoFocus
        placeholder="123456"
        value={code}
        onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
        className="min-h-11 w-full rounded-xl border border-[var(--panel-edge)] bg-[var(--panel-bg)] px-4 py-2.5 text-center text-[17px] tracking-[0.4em] tabular-nums transition-colors focus:border-[var(--foreground)]/30 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)]"
      />
      <button
        type="submit"
        disabled={busy || code.length !== 6}
        className="min-h-11 w-full rounded-xl bg-[var(--foreground)] px-4 py-2.5 text-[15px] font-medium text-[var(--background)] transition-opacity hover:opacity-85 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--action)] disabled:opacity-40"
      >
        {busy ? "Checking…" : "Sign in"}
      </button>
      <button type="button" disabled={busy || resendInSeconds > 0} onClick={requestCode}
        className="min-h-11 text-[14px] text-[var(--action)] underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-[var(--action)] disabled:opacity-40">
        {resendInSeconds > 0 ? `Request a new code in ${resendInSeconds}s` : "Request a new code"}
      </button>
      <button
        type="button"
        disabled={busy}
        onClick={() => {
          setStep("email");
          setCode("");
          setError(null);
          setResendAvailableAt(null);
        }}
        className="min-h-11 text-[14px] text-[var(--muted-ink)] transition-colors hover:text-[var(--foreground)] focus-visible:outline-2 focus-visible:outline-[var(--action)] disabled:opacity-40"
      >
        Use a different address
      </button>
      {error && <Message id={errorMessageId} text={error} />}
    </form>
  );
}

function Message({ id, text }: { id: string; text: string }) {
  // `role="alert"` so the failure is announced rather than only drawn — the input keeps
  // focus after a bad code, so a sighted user sees it and a screen reader would not.
  return (
    <p id={id} role="alert" className="text-[13px] text-[var(--destructive)]">
      {text}
    </p>
  );
}
