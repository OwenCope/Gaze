import "server-only";
import { createHash } from "node:crypto";
import {
  CODE_TTL_MS,
  canonicalCode,
  canonicalEmail,
  isChallengeId,
  newChallengeId,
  newCode,
} from "./email-code.proposed.ts";

export const MAX_VERIFY_ATTEMPTS = 5;
export const SEND_WINDOW_MS = 60 * 60 * 1000;
export const MAX_SENDS_PER_EMAIL_PER_HOUR = 5;
export const MAX_SENDS_PER_IP_PER_HOUR = 20;
const CAS_RETRIES = 5;

export interface ChallengeRecord {
  email: string;
  createdAt: number;
  expiresAt: number;
  attempts: number;
  consumed: boolean;
}

export type StoreDenied = "backend" | "unconfigured";
export type CreateOutcome = { status: "ok" } | { status: "exists" } | { status: StoreDenied };
export type ConsumeOutcome =
  | { status: "ok"; record: ChallengeRecord }
  | { status: "not-found" | "expired" | "consumed" | "locked" }
  | { status: StoreDenied };
export type FailOutcome =
  | { status: "ok" | "locked"; attempts: number }
  | { status: "not-found" | "expired" | "consumed" }
  | { status: StoreDenied };
export type SendGateOutcome =
  | { status: "ok" }
  | { status: "throttled-email" | "throttled-ip" }
  | { status: StoreDenied };

export interface ChallengeStore {
  create(id: string, record: ChallengeRecord): Promise<CreateOutcome>;
  tryConsume(id: string, now: number): Promise<ConsumeOutcome>;
  recordFailedAttempt(id: string, now: number): Promise<FailOutcome>;
  checkAndRecordSend(email: string, ip: string | null, now: number): Promise<SendGateOutcome>;
  voidChallenge?(id: string): Promise<void>;
}

// ---------------------------------------------------------------------------
// Configuration boundary
// ---------------------------------------------------------------------------

export function privateStoreConfigured(): boolean {
  try { blobPrivateOptions(); return true; } catch { return false; }
}

export function isProductionLike(): boolean {
  return Boolean(
    process.env.NODE_ENV !== "development" ||
      process.env.VERCEL === "1" ||
      process.env.BLOB_READ_WRITE_TOKEN ||
      process.env.BLOB_STORE_ID ||
      process.env.BLOB_PRIVATE_READ_WRITE_TOKEN ||
      process.env.BLOB_PRIVATE_STORE_ID,
  );
}

export function emailCodeEnabled(): boolean {
  if (!process.env.AUTH_SECRET?.trim() || !process.env.RESEND_API_KEY?.trim() || !process.env.SIGNIN_EMAIL_FROM?.trim()) return false;
  if (isProductionLike() && !privateStoreConfigured()) return false;
  return true;
}

export function storeStatus(): { mode: "blob" } | { mode: "local-dev" } | { mode: "unconfigured" } {
  if (privateStoreConfigured()) return { mode: "blob" };
  if (isProductionLike()) return { mode: "unconfigured" };
  return { mode: "local-dev" };
}

// ---------------------------------------------------------------------------
// Test/dev-only memory store. NOT shared. NEVER production.
// ---------------------------------------------------------------------------

export function createMemoryChallengeStore(): ChallengeStore & { size(): number } {
  const challenges = new Map<string, ChallengeRecord>();
  // bucketKey -> { count, windowStart }
  const counters = new Map<string, { count: number; windowStart: number }>();

  function hourStart(now: number): number {
    return Math.floor(now / SEND_WINDOW_MS) * SEND_WINDOW_MS;
  }

  function gate(key: string, limit: number, now: number): "ok" | "throttled" {
    const start = hourStart(now);
    const current = counters.get(key);
    if (!current || current.windowStart !== start) {
      counters.set(key, { count: 1, windowStart: start });
      return "ok";
    }
    if (current.count >= limit) return "throttled";
    current.count += 1;
    return "ok";
  }

  return {
    size: () => challenges.size,
    async create(id, record) {
      if (challenges.has(id)) return { status: "exists" };
      challenges.set(id, { ...record });
      return { status: "ok" };
    },
    async tryConsume(id, now) {
      const rec = challenges.get(id);
      if (!rec) return { status: "not-found" };
      if (now >= rec.expiresAt) return { status: "expired" };
      if (rec.consumed) return { status: "consumed" };
      if (rec.attempts >= MAX_VERIFY_ATTEMPTS) return { status: "locked" };
      const next = { ...rec, consumed: true };
      challenges.set(id, next);
      return { status: "ok", record: next };
    },
    async recordFailedAttempt(id, now) {
      const rec = challenges.get(id);
      if (!rec) return { status: "not-found" };
      if (now >= rec.expiresAt) return { status: "expired" };
      if (rec.consumed) return { status: "consumed" };
      if (rec.attempts >= MAX_VERIFY_ATTEMPTS) return { status: "locked", attempts: rec.attempts };
      const attempts = rec.attempts + 1;
      challenges.set(id, { ...rec, attempts });
      return { status: attempts >= MAX_VERIFY_ATTEMPTS ? "locked" : "ok", attempts };
    },
    async checkAndRecordSend(email, ip, now) {
      const emailKey = `email:${sha("email:" + email)}:${hourStart(now)}`;
      if (gate(emailKey, MAX_SENDS_PER_EMAIL_PER_HOUR, now) === "throttled") {
        return { status: "throttled-email" };
      }
      if (ip) {
        const ipKey = `ip:${sha("ip:" + ip)}:${hourStart(now)}`;
        if (gate(ipKey, MAX_SENDS_PER_IP_PER_HOUR, now) === "throttled") {
          return { status: "throttled-ip" };
        }
      }
      return { status: "ok" };
    },
    async voidChallenge(id) {
      challenges.delete(id);
    },
  };
}

function sha(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

export function createFailingChallengeStore(reason: StoreDenied = "backend"): ChallengeStore {
  const out = { status: reason } as const;
  return {
    async create() {
      return out;
    },
    async tryConsume() {
      return out;
    },
    async recordFailedAttempt() {
      return out;
    },
    async checkAndRecordSend() {
      return out;
    },
    async voidChallenge() {},
  };
}

// ---------------------------------------------------------------------------
// Production Blob store (private metadata store, ETag CAS).
// ---------------------------------------------------------------------------

const CHALLENGE_PREFIX = "auth/challenges/";
const SEND_PREFIX = "auth/sends/";

function blobPrivateOptions(): { access: "private"; token?: string; storeId?: string; oidcToken?: string } {
  const token = process.env.BLOB_PRIVATE_READ_WRITE_TOKEN?.trim();
  const storeId = process.env.BLOB_PRIVATE_STORE_ID?.trim();
  if (!token && !storeId) {
    throw Object.assign(new Error("Private metadata store is not configured"), { code: "UNCONFIGURED" });
  }
  if (token && token === process.env.BLOB_READ_WRITE_TOKEN?.trim()) {
    throw new Error("Metadata must use a separate private Blob credential.");
  }
  if (storeId && storeId.replace(/^store_/, "") === process.env.BLOB_STORE_ID?.replace(/^store_/, "")) {
    throw new Error("Metadata must use a separate private Blob store.");
  }
  if (token) return { access: "private", token };
  const oidcToken = process.env.VERCEL_OIDC_TOKEN?.trim();
  if (!oidcToken) {
    throw Object.assign(
      new Error("Private Blob OIDC requires VERCEL_OIDC_TOKEN; configure a private read-write token otherwise."),
      { code: "UNCONFIGURED" },
    );
  }
  return { access: "private", storeId, oidcToken };
}

function isUnconfigured(error: unknown): boolean {
  return Boolean(error && typeof error === "object" && "code" in error && (error as { code: unknown }).code === "UNCONFIGURED");
}

function challengePath(id: string): string {
  return `${CHALLENGE_PREFIX}${id}.json`;
}

function sendPath(kind: "email" | "ip", hashed: string, windowStart: number): string {
  return `${SEND_PREFIX}${kind}-${hashed}-${windowStart}.json`;
}

function validRecord(value: unknown): value is ChallengeRecord {
  if (!value || typeof value !== "object") return false;
  const r = value as Record<string, unknown>;
  return (
    typeof r.email === "string" &&
    canonicalEmail(r.email) === r.email &&
    Number.isSafeInteger(r.createdAt) &&
    Number.isSafeInteger(r.expiresAt) &&
    (r.createdAt as number) >= 0 &&
    (r.expiresAt as number) - (r.createdAt as number) === CODE_TTL_MS &&
    Number.isSafeInteger(r.attempts) &&
    (r.attempts as number) >= 0 &&
    typeof r.consumed === "boolean"
  );
}

type BlobSDK = Pick<typeof import("@vercel/blob"), "get" | "put" | "del" | "BlobPreconditionFailedError" | "BlobNotFoundError">;

// Existing blobs require an ETag; missing counters are created without overwrite.
export function createBlobChallengeStore(sdk: () => Promise<BlobSDK> = () => import("@vercel/blob")): ChallengeStore {
  async function readJson(path: string): Promise<{ data: unknown; etag: string } | null> {
    const blob = await sdk();
    let result: Awaited<ReturnType<typeof blob.get>>;
    try {
      result = await blob.get(path, { ...blobPrivateOptions(), useCache: false });
    } catch (error) {
      if (error instanceof blob.BlobNotFoundError) return null;
      throw error;
    }
    if (!result) return null;
    if (result.statusCode !== 200 || !result.stream || typeof result.blob.etag !== "string" || !result.blob.etag.trim()) {
      throw new Error("Invalid challenge-store response");
    }
    const text = await new Response(result.stream).text();
    return { data: JSON.parse(text) as unknown, etag: result.blob.etag };
  }

  async function casWrite(path: string, next: unknown, etag: string | null, contentType = "application/json"): Promise<"ok" | "conflict"> {
    const blob = await sdk();
    try {
      await blob.put(path, JSON.stringify(next), {
        ...blobPrivateOptions(),
        contentType,
        addRandomSuffix: false,
        allowOverwrite: etag !== null,
        cacheControlMaxAge: 60,
        ...(etag ? { ifMatch: etag } : {}),
      });
      return "ok";
    } catch (error) {
      if (error instanceof blob.BlobPreconditionFailedError) return "conflict";
      // The SDK reports create collisions as a generic BlobError. Re-read,
      // then retry with the winner's ETag; never retry an unconditional put.
      if (etag === null && await readJson(path) !== null) return "conflict";
      throw error;
    }
  }

  return {
    async create(id, record) {
      if (!isChallengeId(id) || !validRecord(record)) throw new Error("create: invalid challenge");
      try {
        const blob = await sdk();
        try {
          await blob.put(challengePath(id), JSON.stringify(record), {
            ...blobPrivateOptions(),
            contentType: "application/json",
            addRandomSuffix: false,
            allowOverwrite: false,
            cacheControlMaxAge: 60,
          });
          return { status: "ok" };
        } catch (error) {
          // Already exists reads as exists rather than backend failure; the
          // id space is 128-bit so a collision is a bug, not an attack.
          if (error instanceof blob.BlobPreconditionFailedError) return { status: "exists" };
          throw error;
        }
      } catch (error) {
        if (isUnconfigured(error)) return { status: "unconfigured" };
        return { status: "backend" };
      }
    },

    async tryConsume(id, now) {
      if (!isChallengeId(id)) return { status: "not-found" };
      try {
        for (let attempt = 0; attempt < CAS_RETRIES; attempt += 1) {
          const current = await readJson(challengePath(id));
          if (!current) return { status: "not-found" };
          if (!validRecord(current.data)) return { status: "backend" };
          const rec = current.data;
          if (now >= rec.expiresAt) return { status: "expired" };
          if (rec.consumed) return { status: "consumed" };
          if (rec.attempts >= MAX_VERIFY_ATTEMPTS) return { status: "locked" };
          const next: ChallengeRecord = { ...rec, consumed: true };
          const written = await casWrite(challengePath(id), next, current.etag);
          if (written === "ok") return { status: "ok", record: next };
        }
        return { status: "backend" };
      } catch (error) {
        if (isUnconfigured(error)) return { status: "unconfigured" };
        return { status: "backend" };
      }
    },

    async recordFailedAttempt(id, now) {
      if (!isChallengeId(id)) return { status: "not-found" };
      try {
        for (let attempt = 0; attempt < CAS_RETRIES; attempt += 1) {
          const current = await readJson(challengePath(id));
          if (!current) return { status: "not-found" };
          if (!validRecord(current.data)) return { status: "backend" };
          const rec = current.data;
          if (now >= rec.expiresAt) return { status: "expired" };
          if (rec.consumed) return { status: "consumed" };
          if (rec.attempts >= MAX_VERIFY_ATTEMPTS) return { status: "locked", attempts: rec.attempts };
          const attempts = rec.attempts + 1;
          const written = await casWrite(challengePath(id), { ...rec, attempts }, current.etag);
          if (written === "ok") {
            return { status: attempts >= MAX_VERIFY_ATTEMPTS ? "locked" : "ok", attempts };
          }
        }
        return { status: "backend" };
      } catch (error) {
        if (isUnconfigured(error)) return { status: "unconfigured" };
        return { status: "backend" };
      }
    },

    async checkAndRecordSend(email, ip, now) {
      const canonical = canonicalEmail(email);
      if (canonical === null || !Number.isSafeInteger(now)) return { status: "backend" };
      try {
        const windowStart = Math.floor(now / SEND_WINDOW_MS) * SEND_WINDOW_MS;
        const emailHash = sha(`email:${canonical}`);
        const emailOutcome = await bumpCounter(sendPath("email", emailHash, windowStart), MAX_SENDS_PER_EMAIL_PER_HOUR);
        if (emailOutcome !== "ok") return { status: emailOutcome === "throttled" ? "throttled-email" : emailOutcome };
        const cleanIp = normalizeIp(ip);
        if (cleanIp) {
          const ipOutcome = await bumpCounter(sendPath("ip", sha(`ip:${cleanIp}`), windowStart), MAX_SENDS_PER_IP_PER_HOUR);
          if (ipOutcome !== "ok") return { status: ipOutcome === "throttled" ? "throttled-ip" : ipOutcome };
        }
        return { status: "ok" };

        async function bumpCounter(path: string, limit: number): Promise<"ok" | "throttled" | StoreDenied> {
          for (let attempt = 0; attempt < CAS_RETRIES; attempt += 1) {
            const current = await readJson(path);
            let count = 0;
            if (current) {
              const data = current.data as { count?: unknown; windowStart?: unknown } | null;
              if (!data || !Number.isSafeInteger(data.count) || (data.count as number) < 0 ||
                  (data.count as number) > limit || data.windowStart !== windowStart) return "backend";
              count = data.count as number;
            }
            if (count >= limit) return "throttled";
            const written = await casWrite(path, { count: count + 1, windowStart }, current ? current.etag : null);
            if (written === "ok") return "ok";
          }
          return "backend";
        }
      } catch (error) {
        if (isUnconfigured(error)) return { status: "unconfigured" };
        return { status: "backend" };
      }
    },

    async voidChallenge(id) {
      try {
        const blob = await sdk();
        await blob.del(challengePath(id), { ...blobPrivateOptions() }).catch(() => {});
      } catch {
        // Best-effort only.
      }
    },
  };
}

export function getProductionChallengeStore(): ChallengeStore | { status: StoreDenied } {
  const status = storeStatus();
  if (status.mode === "blob") return createBlobChallengeStore();
  if (status.mode === "local-dev") {
    const state = globalThis as typeof globalThis & { __gazeDevEmailChallenges?: ChallengeStore };
    return state.__gazeDevEmailChallenges ??= createMemoryChallengeStore();
  }
  return { status: "unconfigured" };
}

// ---------------------------------------------------------------------------
// Testable flows: the route and authorize thinly wrap these with real I/O.
// ---------------------------------------------------------------------------

export function normalizeIp(value: string | null | undefined | unknown): string | null {
  if (typeof value !== "string") return null;
  const first = value.split(",")[0]?.trim().toLowerCase() ?? "";
  if (!first || first.length > 128) return null;
  return first;
}

export type SendEmail = (args: { to: string; code: string }) => Promise<{ ok: true } | { ok: false }>;

export type RequestCodeResult =
  | { status: "ok"; cookieValue: string; maxAge: number; challengeId: string; expiresAt: number }
  | { status: "invalid" | "throttled" | "throttled-email" | "throttled-ip" | "unconfigured" | "backend" | "email-failed" };

export async function requestCodeFlow(args: {
  emailRaw: unknown;
  ipRaw: unknown;
  now: number;
  store: ChallengeStore;
  sendEmail: SendEmail;
  issue?: typeof import("./email-code.proposed.ts").issue;
  makeCode?: () => string;
  makeChallengeId?: () => string;
}): Promise<RequestCodeResult> {
  const email = canonicalEmail(args.emailRaw);
  if (email === null || !Number.isSafeInteger(args.now)) return { status: "invalid" };
  const issue = args.issue ?? (await import("./email-code.proposed.ts")).issue;
  const code = (args.makeCode ?? newCode)();
  if (canonicalCode(code) === null) return { status: "backend" };
  const challengeId = (args.makeChallengeId ?? newChallengeId)();
  if (!isChallengeId(challengeId)) return { status: "backend" };

  const gate = await args.store.checkAndRecordSend(email, normalizeIp(args.ipRaw), args.now);
  if (gate.status === "throttled-email" || gate.status === "throttled-ip") {
    return { status: gate.status === "throttled-email" ? "throttled-email" : "throttled-ip" };
  }
  if (gate.status === "unconfigured") return { status: "unconfigured" };
  if (gate.status !== "ok") return { status: "backend" };

  const createdAt = args.now;
  const expiresAt = args.now + CODE_TTL_MS;
  const created = await args.store.create(challengeId, { email, createdAt, expiresAt, attempts: 0, consumed: false });
  if (created.status !== "ok") {
    return { status: created.status === "unconfigured" ? "unconfigured" : "backend" };
  }

  let cookie: { value: string; maxAge: number; expiresAt: number };
  try {
    cookie = issue(email, code, challengeId, args.now);
  } catch {
    await args.store.voidChallenge?.(challengeId).catch(() => {});
    return { status: "backend" };
  }

  const sent = await args.sendEmail({ to: email, code }).catch(() => ({ ok: false as const }));
  if (!sent || sent.ok !== true) {
    await args.store.voidChallenge?.(challengeId).catch(() => {});
    return { status: "email-failed" };
  }

  return {
    status: "ok",
    cookieValue: cookie.value,
    maxAge: cookie.maxAge,
    challengeId,
    expiresAt: cookie.expiresAt,
  };
}

export type VerifyCodeResult =
  | { status: "ok"; email: string; challengeId: string }
  | { status: "invalid" | "expired" | "locked" | "replay" | "unconfigured" | "backend"; challengeId?: string };

export async function verifyCodeFlow(args: {
  cookie: unknown;
  emailRaw: unknown;
  codeRaw: unknown;
  now: number;
  store: ChallengeStore;
}): Promise<VerifyCodeResult> {
  const { verify } = await import("./email-code.proposed.ts");
  const parsed = verify(args.cookie, args.emailRaw, args.codeRaw, args.now);
  if (!parsed.ok) {
    // Wrong digits (or an unparseable code) against a well-formed, live,
    // matching challenge still costs an attempt — otherwise malformed codes
    // would bypass the attempt bound.
    if ((parsed.reason === "code-mismatch" || parsed.reason === "expired") && parsed.challengeId) {
      if (parsed.reason === "expired") return { status: "expired", challengeId: parsed.challengeId };
      const recorded = await args.store.recordFailedAttempt(parsed.challengeId, args.now);
      if (recorded.status === "locked") return { status: "locked", challengeId: parsed.challengeId };
      if (recorded.status === "consumed") return { status: "replay", challengeId: parsed.challengeId };
      if (recorded.status === "expired") return { status: "expired", challengeId: parsed.challengeId };
      if (recorded.status === "not-found") return { status: "invalid", challengeId: parsed.challengeId };
      if (recorded.status === "backend" || recorded.status === "unconfigured") {
        return { status: recorded.status, challengeId: parsed.challengeId };
      }
      return { status: "invalid", challengeId: parsed.challengeId };
    }
    if (parsed.reason === "expired") return { status: "expired", challengeId: parsed.challengeId };
    return { status: "invalid", challengeId: parsed.challengeId };
  }

  const consumed = await args.store.tryConsume(parsed.challengeId, args.now);
  if (consumed.status === "ok") {
    if (consumed.record.email !== parsed.email || consumed.record.expiresAt !== parsed.expiresAt) return { status: "backend" };
    return { status: "ok", email: parsed.email, challengeId: parsed.challengeId };
  }
  if (consumed.status === "consumed") return { status: "replay", challengeId: parsed.challengeId };
  if (consumed.status === "locked") return { status: "locked", challengeId: parsed.challengeId };
  if (consumed.status === "expired") return { status: "expired", challengeId: parsed.challengeId };
  if (consumed.status === "not-found") return { status: "invalid", challengeId: parsed.challengeId };
  return { status: consumed.status, challengeId: parsed.challengeId };
}
