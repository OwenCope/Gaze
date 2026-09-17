// Stubbed transport/clock check for the EmailSignIn 30s resend cooldown.
// Runs with installed tooling only: `node cooldown-check.mjs` from this dir.
// Sends no real email: fetch is stubbed, Date.now is virtual.
// Part A asserts the delivered component source carries the required logic.
// Part B drives a faithful model of requestCode's guard/deadline transitions.

import { readFileSync } from "node:fs";
import assert from "node:assert/strict";

const SRC = "src/components/email-sign-in.tsx";
const src = readFileSync(SRC, "utf8");
let passed = 0;
const check = (name, cond) => { assert.ok(cond, `FAIL: ${name}`); passed++; console.log(`ok - ${name}`); };

// ---- Part A: source assertions ----
check("30s cooldown constant", src.includes("const RESEND_COOLDOWN_MS = 30_000;"));
check("inFlight guard preserved in both handlers",
  (src.match(/if \(inFlight\.current\) return;/g) || []).length === 2);
check("request payload unchanged", src.includes("body: JSON.stringify({ email })"));
check("verification payload unchanged",
  src.includes('signIn("email-code", { email, code, redirect: false'));
check("wall-clock resend guard before send",
  src.includes('if (step === "code" && resendAvailableAt !== null && Date.now() < resendAvailableAt) return;'));
check("deadline set once, on success only",
  (src.match(/setResendAvailableAt\(/g) || []).length === 4 &&
  src.includes("setResendAvailableAt(sentAt + RESEND_COOLDOWN_MS);"));
check("failure branches start no cooldown", !/if \(!response\.ok\) \{[^}]*setResendAvailableAt/s.test(src) &&
  !/catch \{\s*setError\("Couldn't send the code[^}]*setResendAvailableAt/s.test(src));
check("remaining whole seconds from wall clock",
  src.includes("Math.ceil((resendAvailableAt - nowMs) / 1000)"));
check("only resend button gated by cooldown",
  src.includes("disabled={busy || resendInSeconds > 0}") &&
  src.includes("disabled={busy || code.length !== 6}"));
check("resend button shows remaining seconds",
  src.includes("`Request a new code in ${resendInSeconds}s`"));
check("different address clears countdown", /setStep\("email"\);\s*setCode\(""\);\s*setError\(null\);\s*setResendAvailableAt\(null\);/s.test(src));
check("interval cleaned up", src.includes("return () => window.clearInterval(id);"));

// ---- Part B: behavioral model (mirrors the component's guard verbatim) ----
const COOLDOWN = 30_000;
let now = 1_000_000;
const realNow = Date.now;
Date.now = () => now;

const model = {
  step: "email", code: "", error: null, inFlight: false, resendAvailableAt: null,
  fetchCalls: 0, nextOk: true,
  async fetch() { this.fetchCalls++; return this.nextOk; },
  async requestCode() {
    if (this.inFlight) return "inflight";
    if (this.step === "code" && this.resendAvailableAt !== null && Date.now() < this.resendAvailableAt) return "cooldown-blocked";
    this.inFlight = true;
    try {
      const ok = await this.fetch();
      if (!ok) { this.error = "Couldn't send the code. Try again."; return "failed"; }
      this.code = ""; this.step = "code";
      const sentAt = Date.now();
      this.resendAvailableAt = sentAt + COOLDOWN;
      return "sent";
    } finally { this.inFlight = false; }
  },
  useDifferentAddress() {
    this.step = "email"; this.code = ""; this.error = null; this.resendAvailableAt = null;
  },
};

const r1 = await model.requestCode();
check("first send succeeds and starts deadline",
  r1 === "sent" && model.step === "code" && model.resendAvailableAt === now + COOLDOWN && model.fetchCalls === 1);

now += 10_000;
model.code = "654321";
const r2 = await model.requestCode();
check("early resend blocked without transport use",
  r2 === "cooldown-blocked" && model.fetchCalls === 1 && model.code === "654321");

now += 21_000; // 31s after send: past deadline
const r3 = await model.requestCode();
check("resend after expiry sends and restarts deadline",
  r3 === "sent" && model.fetchCalls === 2 && model.resendAvailableAt === now + COOLDOWN);

model.code = "123456";
model.nextOk = false;
now += 5_000;
const deadlineBefore = model.resendAvailableAt;
const r4 = await model.requestCode();
// NOTE: with a live cooldown this resend is guard-blocked; to exercise the
// failure path, expire the deadline first (failure must not restart it).
model.resendAvailableAt = now - 1;
const r4b = await model.requestCode();
check("failed send retains code and starts no cooldown",
  r4 === "cooldown-blocked" && r4b === "failed" && model.code === "123456" &&
  model.step === "code" && model.resendAvailableAt === now - 1 && deadlineBefore !== model.resendAvailableAt);

model.useDifferentAddress();
check("changing address clears countdown and resets fields",
  model.resendAvailableAt === null && model.step === "email" && model.code === "" && model.error === null);

Date.now = realNow;
console.log(`\nPASS: ${passed} checks, 0 failures. No network used; fetch and clock were stubbed.`);
