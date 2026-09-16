// Email-auth hardening harness: synthetic clock, stubbed transport/state.
// No network, no Resend, no Blob, no real .env. Run: `node run-tests.mjs`
import { readFileSync } from "node:fs";
import { registerHooks } from "node:module";
registerHooks({ resolve(specifier, context, next) {
  if (specifier === "@/lib/email-code") return { url: "file:///Users/owencope/Developer/gaze-site/src/lib/email-code.ts", shortCircuit: true };
  if (specifier === "server-only") return { url: "data:text/javascript,export{}", shortCircuit: true };
  return next(specifier, context);
}});
process.env.NODE_ENV = "development";
delete process.env.VERCEL_OIDC_TOKEN;

const SECRET = "synthetic-test-secret-not-a-real-credential-0123456789";
process.env.AUTH_SECRET = SECRET;
// Keep config boundary deterministic: dev-like (no Vercel/Blob) unless a test sets it.
delete process.env.VERCEL;
delete process.env.BLOB_READ_WRITE_TOKEN;
delete process.env.BLOB_STORE_ID;
delete process.env.BLOB_PRIVATE_READ_WRITE_TOKEN;
delete process.env.BLOB_PRIVATE_STORE_ID;
process.env.RESEND_API_KEY = "synthetic-resend-key";
process.env.SIGNIN_EMAIL_FROM = "test@example.com";

const code = await import(process.argv.includes("--current") ? "file:///Users/owencope/Developer/gaze-site/src/lib/email-code.ts" : "./email-code.proposed.ts");
const storeMod = await import(process.argv.includes("--current") ? "file:///Users/owencope/Developer/gaze-site/src/lib/email-challenge-store.ts" : "./email-challenge-store.proposed.ts");

const T0 = 1_720_000_000_000;
let passed = 0;
let failed = 0;
const failures = [];
function check(name, cond, extra = "") {
  if (cond) {
    passed += 1;
    console.log(`PASS ${name}`);
  } else {
    failed += 1;
    failures.push(name);
    console.log(`FAIL ${name}${extra ? " — " + extra : ""}`);
  }
}
function wrongCode(right) {
  // Deterministic wrong code distinct from `right`.
  return right === "000000" ? "000001" : "000000";
}
const okSend = async () => ({ ok: true });
const failSend = async () => ({ ok: false });
const throwSend = async () => {
  throw new Error("transport down");
};

let n = 0;
const seqCode = (fixed) => () => fixed ?? String(100000 + (n++ % 900000));
const seqId = () => {
  n += 1;
  return n.toString(16).padStart(32, "a").slice(0, 32);
};

// 1. Successful verification -------------------------------------------------
{
  const store = storeMod.createMemoryChallengeStore();
  let sentTo = null;
  const req = await storeMod.requestCodeFlow({
    emailRaw: "  Alice@Example.com ",
    ipRaw: "203.0.113.7",
    now: T0,
    store,
    sendEmail: async ({ to, code: c }) => {
      sentTo = to;
      return { ok: true };
    },
    makeCode: () => "482916",
    makeChallengeId: () => "a".repeat(32),
  });
  check("success: request ok", req.status === "ok", JSON.stringify(req));
  check("success: email normalized for send", sentTo === "alice@example.com", String(sentTo));
  check("success: cookie is v2 with challenge", req.status === "ok" && req.cookieValue.startsWith("v2.a"), req.status === "ok" ? req.cookieValue.slice(0, 40) : "");
  check("success: maxAge 600", req.status === "ok" && req.maxAge === 600, JSON.stringify(req));
  const ver = await storeMod.verifyCodeFlow({
    cookie: req.cookieValue,
    emailRaw: "alice@example.com",
    codeRaw: "482916",
    now: T0 + 60_000,
    store,
  });
  check("success: verify ok", ver.status === "ok" && ver.email === "alice@example.com", JSON.stringify(ver));
  // Code must not be in the HTTP-safe return except the test-only email field; route drops it (structural check below).
  check("success: flow does not expose plaintext code", req.status === "ok" && !("codeForEmail" in req));
}

// 2. Bounded wrong attempts ---------------------------------------------------
{
  const store = storeMod.createMemoryChallengeStore();
  const req = await storeMod.requestCodeFlow({
    emailRaw: "bob@example.com",
    ipRaw: "198.51.100.9",
    now: T0,
    store,
    sendEmail: okSend,
    makeCode: () => "111111",
    makeChallengeId: () => "b".repeat(32),
  });
  const bad = wrongCode("111111");
  let last = null;
  for (let i = 1; i <= 5; i += 1) {
    last = await storeMod.verifyCodeFlow({ cookie: req.cookieValue, emailRaw: "bob@example.com", codeRaw: bad, now: T0 + i * 1000, store });
    if (i < 5) check(`attempts: wrong #${i} invalid (not locked)`, last.status === "invalid", JSON.stringify(last));
    else check("attempts: 5th wrong locks", last.status === "locked", JSON.stringify(last));
  }
  const afterLock = await storeMod.verifyCodeFlow({
    cookie: req.cookieValue,
    emailRaw: "bob@example.com",
    codeRaw: "111111",
    now: T0 + 6000,
    store,
  });
  check("attempts: correct code after lock still denied", afterLock.status === "locked", JSON.stringify(afterLock));
}

// 3. Replay refusal ------------------------------------------------------------
{
  const store = storeMod.createMemoryChallengeStore();
  const req = await storeMod.requestCodeFlow({
    emailRaw: "carol@example.com",
    ipRaw: null,
    now: T0,
    store,
    sendEmail: okSend,
    makeCode: () => "222222",
    makeChallengeId: () => "c".repeat(32),
  });
  const first = await storeMod.verifyCodeFlow({ cookie: req.cookieValue, emailRaw: "carol@example.com", codeRaw: "222222", now: T0 + 1000, store });
  check("replay: first verify ok", first.status === "ok", JSON.stringify(first));
  const second = await storeMod.verifyCodeFlow({ cookie: req.cookieValue, emailRaw: "carol@example.com", codeRaw: "222222", now: T0 + 2000, store });
  check("replay: second verify refused", second.status === "replay", JSON.stringify(second));
  const third = await storeMod.verifyCodeFlow({ cookie: req.cookieValue, emailRaw: "carol@example.com", codeRaw: "999999", now: T0 + 3000, store });
  check("replay: wrong code after spend stays replay", third.status === "replay", JSON.stringify(third));
}

// 4. Send throttling ------------------------------------------------------------
{
  const store = storeMod.createMemoryChallengeStore();
  let okCount = 0;
  let sixth = null;
  for (let i = 0; i < 6; i += 1) {
    const r = await storeMod.requestCodeFlow({
      emailRaw: "dave@example.com",
      ipRaw: "203.0.113.99",
      now: T0 + i * 1000,
      store,
      sendEmail: okSend,
      makeCode: () => String(300000 + i),
      makeChallengeId: () => i.toString(16).padStart(32, "d").slice(0, 32),
    });
    if (r.status === "ok") okCount += 1;
    if (i === 5) sixth = r;
  }
  check("throttle: 5 sends/hour/email ok", okCount === 5, `ok=${okCount}`);
  check("throttle: 6th send throttled-email", sixth && sixth.status === "throttled-email", JSON.stringify(sixth));
  const nextHour = await storeMod.requestCodeFlow({
    emailRaw: "dave@example.com",
    ipRaw: "203.0.113.99",
    now: T0 + 3600_000 + 5000,
    store,
    sendEmail: okSend,
    makeCode: () => "300099",
    makeChallengeId: () => "e".repeat(32),
  });
  check("throttle: next hour resets", nextHour.status === "ok", JSON.stringify(nextHour));
}
{
  const store = storeMod.createMemoryChallengeStore();
  let okCount = 0;
  let over = null;
  for (let i = 0; i < 21; i += 1) {
    const r = await storeMod.requestCodeFlow({
      emailRaw: `victim${i}@example.com`,
      ipRaw: "192.0.2.55",
      now: T0 + i * 500,
      store,
      sendEmail: okSend,
      makeCode: () => String(400000 + (i % 900000)).padStart(6, "0"),
      makeChallengeId: () => (i + 100).toString(16).padStart(32, "f").slice(0, 32),
    });
    if (r.status === "ok") okCount += 1;
    if (i === 20) over = r;
  }
  check("throttle: 20 sends/hour/ip ok", okCount === 20, `ok=${okCount}`);
  check("throttle: 21st send throttled-ip", over && over.status === "throttled-ip", JSON.stringify(over));
}

// 5. Expiry ----------------------------------------------------------------------
{
  const store = storeMod.createMemoryChallengeStore();
  const req = await storeMod.requestCodeFlow({
    emailRaw: "erin@example.com",
    ipRaw: null,
    now: T0,
    store,
    sendEmail: okSend,
    makeCode: () => "555555",
    makeChallengeId: () => "1".repeat(32),
  });
  const late = await storeMod.verifyCodeFlow({
    cookie: req.cookieValue,
    emailRaw: "erin@example.com",
    codeRaw: "555555",
    now: T0 + 10 * 60 * 1000 + 1,
    store,
  });
  check("expiry: code refused after 10 min", late.status === "expired", JSON.stringify(late));
  const edge = await (async () => {
    const s2 = storeMod.createMemoryChallengeStore();
    const r2 = await storeMod.requestCodeFlow({ emailRaw: "erin@example.com", ipRaw: null, now: T0, store: s2, sendEmail: okSend, makeCode: () => "555556", makeChallengeId: () => "2".repeat(32) });
    return storeMod.verifyCodeFlow({ cookie: r2.cookieValue, emailRaw: "erin@example.com", codeRaw: "555556", now: T0 + 10 * 60 * 1000, store: s2 });
  })();
  check("expiry: code refused at exactly TTL", edge.status === "expired", JSON.stringify(edge));
}

// 6. Malformed inputs ----------------------------------------------------------------
{
  const store = storeMod.createMemoryChallengeStore();
  for (const bad of [123, 45.6, {}, [], null, undefined, "", "   ", "not-an-email", "a@b", "a@b.c", "@example.com", "x".repeat(300) + "@example.com"]) {
    const r = await storeMod.requestCodeFlow({ emailRaw: bad, ipRaw: null, now: T0, store, sendEmail: okSend, makeCode: () => "123456", makeChallengeId: () => "3".repeat(32) });
    if (r.status !== "invalid") {
      check(`malformed email rejected (${JSON.stringify(bad)})`, false, JSON.stringify(r));
      break;
    }
    if (bad === "x".repeat(300) + "@example.com") check("malformed: non-string/oversize/shapeless emails invalid", true);
  }
  const req = await storeMod.requestCodeFlow({ emailRaw: "frank@example.com", ipRaw: null, now: T0, store, sendEmail: okSend, makeCode: () => "666666", makeChallengeId: () => "4".repeat(32) });
  const goodCookie = req.cookieValue;
  const cases = [
    ["missing cookie", undefined, "frank@example.com", "666666", "invalid"],
    ["empty cookie", "", "frank@example.com", "666666", "invalid"],
    ["two parts", "a.b", "frank@example.com", "666666", "invalid"],
    ["legacy 3-part", "Zm9vQGJhci5jb20.123.abc", "frank@example.com", "666666", "invalid"],
    ["bad version", goodCookie.replace(/^v2/, "v9"), "frank@example.com", "666666", "invalid"],
    ["bad challenge chars", goodCookie.replace(/^v2\.[0-9a-f]{32}/, "v2." + "z".repeat(32)), "frank@example.com", "666666", "invalid"],
    ["bad expiry", goodCookie.split(".").slice(0, 2).join(".") + ".notanumber." + goodCookie.split(".").slice(3).join("."), "frank@example.com", "666666", "invalid"],
    ["email mismatch", goodCookie, "other@example.com", "666666", "invalid"],
    ["non-string email", goodCookie, 12345, "666666", "invalid"],
    ["non-string code number", goodCookie, "frank@example.com", 666666, "invalid"],
    ["non-string code object", goodCookie, "frank@example.com", {}, "invalid"],
    ["short code", goodCookie, "frank@example.com", "12345", "invalid"],
    ["non-hex mac", goodCookie.slice(0, -1) + "z", "frank@example.com", "666666", "invalid"],
  ];
  for (const [name, c, e, cd, want] of cases) {
    const out = await storeMod.verifyCodeFlow({ cookie: c, emailRaw: e, codeRaw: cd, now: T0 + 1000, store });
    check(`malformed: ${name} denied`, out.status === want || (want === "invalid" && (out.status === "invalid" || out.status === "locked")), JSON.stringify(out));
  }
  // Tampered MAC must not verify even with the right digits.
  const tampered = goodCookie.slice(0, -1) + (goodCookie.endsWith("0") ? "1" : "0");
  const tOut = await storeMod.verifyCodeFlow({ cookie: tampered, emailRaw: "frank@example.com", codeRaw: "666666", now: T0 + 1000, store });
  check("malformed: flipped MAC bit denied", tOut.status === "invalid" || tOut.status === "locked", JSON.stringify(tOut));
  // Non-canonical cookie spelling (uppercase email inside) must not verify.
  const upperB64 = Buffer.from("FRANK@EXAMPLE.COM", "utf8").toString("base64url");
  const upperCookie = goodCookie.split(".").with(3, upperB64).join(".");
  const uOut = await storeMod.verifyCodeFlow({ cookie: upperCookie, emailRaw: "frank@example.com", codeRaw: "666666", now: T0 + 1000, store });
  check("canonical: non-canonical email spelling in cookie denied", uOut.status !== "ok", JSON.stringify(uOut));
}

// 7. Normalization consistency --------------------------------------------------------
{
  const store = storeMod.createMemoryChallengeStore();
  const req = await storeMod.requestCodeFlow({
    emailRaw: "  Grace@Example.COM ",
    ipRaw: null,
    now: T0,
    store,
    sendEmail: okSend,
    makeCode: () => "777777",
    makeChallengeId: () => "5".repeat(32),
  });
  check("normalize: padded mixed-case request accepted", req.status === "ok", JSON.stringify(req));
  if (req.status === "ok") {
    for (const spelling of ["grace@example.com", "  GRACE@example.com  ", "Grace@Example.com"]) {
      const out = await (async () => {
        const s = storeMod.createMemoryChallengeStore();
        // Fresh challenge per spelling would diverge; instead verify stateless HMAC accepts all spellings
        // by issuing once and verifying with each spelling against a fresh unspent clone.
        return null;
      })();
      void out;
    }
    // Stateless HMAC accepts every canonical spelling of the same address.
    const v1 = code.verify(req.cookieValue, "grace@example.com", "777777", T0 + 1000);
    const v2 = code.verify(req.cookieValue, "  GRACE@EXAMPLE.COM ", " 777777 ", T0 + 1000);
    check("normalize: HMAC accepts canonical spellings", v1.ok === true && v2.ok === true, JSON.stringify([v1, v2]));
    // Stored record holds the canonical address.
    const first = await storeMod.verifyCodeFlow({ cookie: req.cookieValue, emailRaw: "GRACE@EXAMPLE.COM", codeRaw: "777777", now: T0 + 1000, store });
    check("normalize: verify accepts mixed-case address", first.status === "ok" && first.email === "grace@example.com", JSON.stringify(first));
  }
  // Cross-challenge and cross-email binding.
  const s2 = storeMod.createMemoryChallengeStore();
  const ra = await storeMod.requestCodeFlow({ emailRaw: "henry@example.com", ipRaw: null, now: T0, store: s2, sendEmail: okSend, makeCode: () => "888881", makeChallengeId: () => "6".repeat(32) });
  const rb = await storeMod.requestCodeFlow({ emailRaw: "henry@example.com", ipRaw: null, now: T0, store: s2, sendEmail: okSend, makeCode: () => "888882", makeChallengeId: () => "7".repeat(32) });
  const cross = await storeMod.verifyCodeFlow({ cookie: ra.cookieValue, emailRaw: "henry@example.com", codeRaw: "888882", now: T0 + 1000, store: s2 });
  check("binding: code from sibling challenge denied", cross.status === "invalid" || cross.status === "locked", JSON.stringify(cross));
  const crossEmail = await storeMod.verifyCodeFlow({ cookie: rb.cookieValue, emailRaw: "alice@example.com", codeRaw: "888882", now: T0 + 1000, store: s2 });
  check("binding: cookie bound to its address", crossEmail.status === "invalid", JSON.stringify(crossEmail));
}

// 8. Backend failure fails closed --------------------------------------------------------
{
  const failing = storeMod.createFailingChallengeStore("backend");
  let mailed = false;
  const req = await storeMod.requestCodeFlow({
    emailRaw: "ivan@example.com",
    ipRaw: null,
    now: T0,
    store: failing,
    sendEmail: async () => {
      mailed = true;
      return { ok: true };
    },
    makeCode: () => "123456",
    makeChallengeId: () => "8".repeat(32),
  });
  check("backend: send refused when store down", req.status === "backend", JSON.stringify(req));
  check("backend: no email attempted when gate fails", mailed === false, String(mailed));

  // Valid HMAC but dead store still denies.
  process.env.AUTH_SECRET = SECRET;
  const mem = storeMod.createMemoryChallengeStore();
  const good = await storeMod.requestCodeFlow({ emailRaw: "judy@example.com", ipRaw: null, now: T0, store: mem, sendEmail: okSend, makeCode: () => "121212", makeChallengeId: () => "9".repeat(32) });
  const denied = await storeMod.verifyCodeFlow({ cookie: good.cookieValue, emailRaw: "judy@example.com", codeRaw: "121212", now: T0 + 1000, store: failing });
  check("backend: verify denied when store down", denied.status === "backend", JSON.stringify(denied));

  const unconf = storeMod.createFailingChallengeStore("unconfigured");
  const reqU = await storeMod.requestCodeFlow({ emailRaw: "kate@example.com", ipRaw: null, now: T0, store: unconf, sendEmail: okSend, makeCode: () => "131313", makeChallengeId: () => "0".repeat(32) });
  check("backend: unconfigured send refused", reqU.status === "unconfigured", JSON.stringify(reqU));

  // Resend failure: no cookie, challenge voided.
  const mem2 = storeMod.createMemoryChallengeStore();
  let voidedCookie = "";
  const failReq = await storeMod.requestCodeFlow({
    emailRaw: "leo@example.com",
    ipRaw: null,
    now: T0,
    store: mem2,
    sendEmail: failSend,
    makeCode: () => "141414",
    makeChallengeId: () => "ab".padEnd(32, "0"),
  });
  check("backend: mailer failure surfaces email-failed", failReq.status === "email-failed", JSON.stringify(failReq));
  const throwReq = await storeMod.requestCodeFlow({
    emailRaw: "mia@example.com",
    ipRaw: null,
    now: T0,
    store: mem2,
    sendEmail: throwSend,
    makeCode: () => "151515",
    makeChallengeId: () => "ac".padEnd(32, "0"),
  });
  check("backend: mailer throw surfaces email-failed", throwReq.status === "email-failed", JSON.stringify(throwReq));
  void voidedCookie;
}

// 9. HMAC/expiry/cookie protections preserved ------------------------------------------------
{
  check("preserve: TTL 10 min", code.CODE_TTL_MS === 600000, String(code.CODE_TTL_MS));
  check("preserve: cookie name unchanged", code.CODE_COOKIE === "gaze_signin", code.CODE_COOKIE);
  const c1 = code.newCode();
  const c2 = code.newCode();
  check("preserve: codes six digits", /^\d{6}$/.test(c1) && /^\d{6}$/.test(c2), `${c1}/${c2}`);
  const id = code.newChallengeId();
  check("preserve: challenge id 128-bit hex", /^[0-9a-f]{32}$/.test(id), id);
  const saved = process.env.AUTH_SECRET;
  delete process.env.AUTH_SECRET;
  let threw = false;
  try {
    code.newChallengeId && code.issue("a@example.com", "123456", "a".repeat(32), T0);
  } catch {
    threw = true;
  }
  check("preserve: no fallback secret (throws without AUTH_SECRET)", threw === true);
  process.env.AUTH_SECRET = saved;
}

// 10. Configuration boundary ---------------------------------------------------------------
{
  const save = { ...process.env };
  process.env.RESEND_API_KEY = "k";
  process.env.SIGNIN_EMAIL_FROM = "f@example.com";
  delete process.env.VERCEL;
  delete process.env.BLOB_READ_WRITE_TOKEN;
  delete process.env.BLOB_STORE_ID;
  delete process.env.BLOB_PRIVATE_READ_WRITE_TOKEN;
  delete process.env.BLOB_PRIVATE_STORE_ID;
  check("config: local dev email enabled", storeMod.emailCodeEnabled() === true);
  check("config: local dev store is local-dev", storeMod.storeStatus().mode === "local-dev");
  process.env.VERCEL = "1";
  check("config: Vercel without private store disables email", storeMod.emailCodeEnabled() === false);
  check("config: Vercel without private store is unconfigured", storeMod.storeStatus().mode === "unconfigured");
  process.env.BLOB_PRIVATE_READ_WRITE_TOKEN = "synthetic-private-token";
  check("config: Vercel with private store enables email", storeMod.emailCodeEnabled() === true);
  check("config: private store detected", storeMod.storeStatus().mode === "blob");
  delete process.env.RESEND_API_KEY;
  check("config: missing Resend disables email even with store", storeMod.emailCodeEnabled() === false);
  Object.keys(process.env).forEach((k) => delete process.env[k]);
  Object.assign(process.env, save);
  process.env.AUTH_SECRET = SECRET;
}

// 11. Proposed wiring present (structural checks on the patch sources) -----------------------
{
  const route = readFileSync(new URL("./signin-code-route.proposed.ts", import.meta.url), "utf8");
  const auth = readFileSync(new URL("./auth.proposed.ts", import.meta.url), "utf8");
  const page = readFileSync(new URL("./signin-page.proposed.tsx", import.meta.url), "utf8");
  const client = readFileSync(new URL("./email-sign-in.proposed.tsx", import.meta.url), "utf8");
  const lib = readFileSync(new URL("./email-code.proposed.ts", import.meta.url), "utf8");
  check("wiring: route normalizes strictly", route.includes("canonicalEmail(") && !route.includes("as { email?: string }"));
  check("wiring: route throttles with 429", route.includes("429") && route.includes("requestCodeFlow"));
  check("wiring: route never returns the code", !/NextResponse\.json\([^)]*code/i.test(route) && route.includes("never returns the code") === false ? true : !route.includes("codeForEmail"));
  check("wiring: route fails closed 503/502", route.includes("503") && route.includes("502"));
  check("wiring: route keeps cookie flags", route.includes("httpOnly: true") && route.includes('sameSite: "lax"') && route.includes('path: "/"'));
  check("wiring: auth spends via store", auth.includes("verifyCodeFlow") && auth.includes("tryConsume") === false ? true : auth.includes("verifyCodeFlow"));
  check("wiring: auth denies on store failure", auth.includes("return null"));
  check("wiring: auth clears spent/locked/expired cookies", auth.includes('"replay"') && auth.includes('"locked"') && auth.includes('"expired"'));
  check("wiring: auth preserves OAuth+admin", auth.includes("Google") && auth.includes("GitHub") && auth.includes("ADMINS") && auth.includes("isAdmin"));
  check("wiring: page gates email on store", page.includes("emailCodeEnabled()"));
  check("wiring: client keeps generic verify message", client.includes("request a new code") && !client.toLowerCase().includes("attempts left"));
  check("wiring: lib rejects legacy cookies", lib.includes('"legacy"'));
  check("wiring: no fallback secret added", !/process\.env\.AUTH_SECRET\s*\|\|/.test(lib) && !/AUTH_SECRET\s*=\s*["'][^"']+["']/.test(lib));
}

console.log(`\n${passed} passed, ${failed} failed`);
if (failed > 0) {
  console.log("failures:", failures.join("; "));
  process.exit(1);
}
