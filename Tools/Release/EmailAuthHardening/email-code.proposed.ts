import "server-only";
import { createHmac, randomBytes, randomInt, timingSafeEqual } from "node:crypto";

export const CODE_TTL_MS = 10 * 60 * 1000;
export const CODE_COOKIE = "gaze_signin";
export const CODE_RE = /^\d{6}$/;
export const CHALLENGE_ID_RE = /^[0-9a-f]{32}$/;
const MAC_RE = /^[0-9a-f]{64}$/;
const EXPIRY_RE = /^\d{1,15}$/;
const B64URL_RE = /^[A-Za-z0-9_-]+$/;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
export const MAX_EMAIL_LENGTH = 254;

function secret(): string {
  const value = process.env.AUTH_SECRET;
  // Failing loudly beats signing with a fallback: a predictable secret here would let
  // anyone mint a cookie for any address, which is the whole authentication story.
  if (!value?.trim()) throw new Error("AUTH_SECRET is required to issue sign-in codes");
  return value;
}

export function newCode(): string {
  return String(randomInt(0, 1_000_000)).padStart(6, "0");
}

export function newChallengeId(): string {
  return randomBytes(16).toString("hex");
}

export function isChallengeId(value: unknown): value is string {
  return typeof value === "string" && CHALLENGE_ID_RE.test(value);
}

export function canonicalEmail(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim().toLowerCase();
  if (normalized.length === 0 || normalized.length > MAX_EMAIL_LENGTH) return null;
  if (/[\u0000-\u001f\u007f]/.test(normalized)) return null;
  if (!EMAIL_RE.test(normalized)) return null;
  return normalized;
}

export function canonicalCode(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!CODE_RE.test(trimmed)) return null;
  return trimmed;
}

export function looksLikeEmail(value: string): boolean {
  return canonicalEmail(value) !== null;
}

function signV2(challengeId: string, email: string, code: string, expiresAt: number): string {
  return createHmac("sha256", secret())
    .update(`v2\x00${challengeId}\x00${email}\x00${code}\x00${expiresAt}`)
    .digest("hex");
}

function encodeEmail(email: string): string {
  return Buffer.from(email, "utf8").toString("base64url");
}

function decodeEmailStrict(encoded: string): string | null {
  if (!encoded || encoded.length > 512 || !B64URL_RE.test(encoded)) return null;
  let decoded: string;
  try {
    decoded = Buffer.from(encoded, "base64url").toString("utf8");
  } catch {
    return null;
  }
  // Buffer's base64url decoder skips invalid characters instead of throwing,
  // so round-trip: the encoding must re-encode to itself (unpadded).
  const roundTrip = Buffer.from(decoded, "utf8").toString("base64url");
  if (roundTrip !== encoded) return null;
  const canonical = canonicalEmail(decoded);
  // The cookie must hold the canonical spelling, not merely something that
  // normalizes to it — otherwise `Foo@x.com` and `foo@x.com` would be two
  // spellings of one challenge and the store key discipline would blur.
  if (canonical === null || decoded !== canonical) return null;
  return decoded;
}

export function issue(
  email: string,
  code: string,
  challengeId: string,
  now: number = Date.now(),
): { value: string; maxAge: number; expiresAt: number } {
  const canonical = canonicalEmail(email);
  const cleanCode = canonicalCode(code);
  if (canonical === null) throw new Error("issue: non-canonical email");
  if (cleanCode === null) throw new Error("issue: code must be six digits");
  if (!isChallengeId(challengeId)) throw new Error("issue: bad challenge id");
  if (!Number.isSafeInteger(now) || now < 0) throw new Error("issue: bad clock");
  const expiresAt = now + CODE_TTL_MS;
  if (!Number.isSafeInteger(expiresAt)) throw new Error("issue: expiry overflow");
  const value = ["v2", challengeId, String(expiresAt), encodeEmail(canonical), signV2(challengeId, canonical, cleanCode, expiresAt)].join(".");
  return { value, maxAge: Math.floor(CODE_TTL_MS / 1000), expiresAt };
}

export type VerifyOk = { ok: true; email: string; challengeId: string; expiresAt: number };
export type VerifyFail = {
  ok: false;
  reason: "missing" | "malformed" | "legacy" | "email-mismatch" | "expired" | "code-mismatch";
  challengeId?: string;
};
export type VerifyResult = VerifyOk | VerifyFail;

export function verify(
  cookie: string | undefined | null | unknown,
  email: unknown,
  code: unknown,
  now: number = Date.now(),
): VerifyResult {
  if (typeof cookie !== "string" || cookie.length === 0 || cookie.length > 1024) return { ok: false, reason: "missing" };
  const canonical = canonicalEmail(email);
  if (canonical === null) return { ok: false, reason: "email-mismatch" };
  if (!Number.isSafeInteger(now) || now < 0) return { ok: false, reason: "malformed" };

  const parts = cookie.split(".");
  if (parts.length === 3) return { ok: false, reason: "legacy" };
  if (parts.length !== 5) return { ok: false, reason: "malformed" };
  const [version, challengeId, rawExpiry, encodedEmail, mac] = parts;
  if (version !== "v2") return { ok: false, reason: "malformed" };
  if (!isChallengeId(challengeId)) return { ok: false, reason: "malformed" };
  if (!EXPIRY_RE.test(rawExpiry)) return { ok: false, reason: "malformed" };
  const expiresAt = Number(rawExpiry);
  if (!Number.isSafeInteger(expiresAt)) return { ok: false, reason: "malformed" };

  const cookieEmail = decodeEmailStrict(encodedEmail);
  if (cookieEmail === null) return { ok: false, reason: "malformed" };
  if (cookieEmail !== canonical) return { ok: false, reason: "email-mismatch" };
  if (now >= expiresAt) return { ok: false, reason: "expired", challengeId };

  const cleanCode = canonicalCode(code);
  if (cleanCode === null) return { ok: false, reason: "code-mismatch", challengeId };
  if (!MAC_RE.test(mac)) return { ok: false, reason: "code-mismatch", challengeId };

  const expected = Buffer.from(signV2(challengeId, cookieEmail, cleanCode, expiresAt), "hex");
  let actual: Buffer;
  try {
    actual = Buffer.from(mac, "hex");
  } catch {
    return { ok: false, reason: "code-mismatch", challengeId };
  }
  if (expected.length !== actual.length) return { ok: false, reason: "code-mismatch", challengeId };
  if (!timingSafeEqual(expected, actual)) return { ok: false, reason: "code-mismatch", challengeId };
  return { ok: true, email: cookieEmail, challengeId, expiresAt };
}
