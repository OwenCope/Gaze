import { NextResponse } from "next/server";
import { CODE_COOKIE, canonicalEmail } from "@/lib/email-code";
import {
  emailCodeEnabled,
  getProductionChallengeStore,
  normalizeIp,
  requestCodeFlow,
} from "@/lib/email-challenge-store";

export async function POST(request: Request) {
  let body: unknown = null;
  try {
    body = await request.json();
  } catch {
    body = null;
  }
  const rawEmail = body && typeof body === "object" ? (body as { email?: unknown }).email : null;
  const email = canonicalEmail(rawEmail);

  if (!email) {
    return NextResponse.json({ error: "Enter a valid email address." }, { status: 400 });
  }

  const apiKey = process.env.RESEND_API_KEY;
  const from = process.env.SIGNIN_EMAIL_FROM;
  if (!apiKey || !from) {
    // Configuration, not user error — and worth saying plainly in the response rather than
    // failing as though the address were wrong.
    return NextResponse.json(
      { error: "Email sign-in isn't configured on this deployment yet." },
      { status: 503 },
    );
  }

  if (!emailCodeEnabled()) {
    // Production-like without the private challenge store: offering codes
    // would silently re-enable replayable, unthrottled sign-in. Fail closed.
    return NextResponse.json(
      { error: "Email sign-in isn't configured on this deployment yet." },
      { status: 503 },
    );
  }

  const storeOrStatus = getProductionChallengeStore();
  if ("status" in storeOrStatus) {
    return NextResponse.json(
      { error: "Email sign-in isn't configured on this deployment yet." },
      { status: 503 },
    );
  }
  const store = storeOrStatus;

  const forwarded = request.headers.get("x-forwarded-for");
  const realIp = request.headers.get("x-real-ip");
  const ip = normalizeIp(forwarded ?? realIp ?? null);

  const flow = await requestCodeFlow({
    emailRaw: email,
    ipRaw: ip,
    now: Date.now(),
    store,
    sendEmail: async ({ to, code }) => {
      const sent = await fetch("https://api.resend.com/emails", {
        method: "POST",
        signal: AbortSignal.timeout(10_000),
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from,
          to,
          subject: `${code} is your Gaze sign-in code`,
          text: `Your Gaze sign-in code is ${code}.\n\nIt expires in ten minutes. If you didn't ask for it, ignore this email — nothing has happened to any account.`,
        }),
      }).catch(() => null);
      return sent?.ok ? { ok: true as const } : { ok: false as const };
    },
  });

  if (flow.status === "invalid") {
    return NextResponse.json({ error: "Enter a valid email address." }, { status: 400 });
  }
  if (flow.status === "throttled-email" || flow.status === "throttled-ip" || flow.status === "throttled") {
    return NextResponse.json(
      { error: "Too many codes requested. Wait a while and try again." },
      { status: 429 },
    );
  }
  if (flow.status === "unconfigured") {
    return NextResponse.json(
      { error: "Email sign-in isn't configured on this deployment yet." },
      { status: 503 },
    );
  }
  if (flow.status === "backend") {
    return NextResponse.json({ error: "Couldn't send the email. Try again." }, { status: 503 });
  }
  if (flow.status === "email-failed") {
    return NextResponse.json({ error: "Couldn't send the email. Try again." }, { status: 502 });
  }

  if (flow.status !== "ok") {
    return NextResponse.json({ error: "Couldn't send the email. Try again." }, { status: 503 });
  }
  const response = NextResponse.json({ ok: true });
  response.cookies.set(CODE_COOKIE, flow.cookieValue, {
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    path: "/",
    maxAge: flow.maxAge,
  });
  return response;
}
