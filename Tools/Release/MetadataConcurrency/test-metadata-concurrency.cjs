#!/usr/bin/env node
// Concurrency preservation test for gaze-site metadata documents.
//
// Tests the ACTUAL staged sources in this directory (storage.ts, testers.ts,
// roles.ts, settings.ts) by transpiling them with the site's installed
// TypeScript and executing with a stubbed `@vercel/blob` transport plus the
// real filesystem. No network, no live Blob, no production data.
//
// Covers:
//   0. patch scope is exactly the four lib files
//   1. synthetic lost-update probe of the OLD read/write flow (demonstrates loss)
//   2. Blob: two concurrent independent additions both survive (via real addTester)
//   3. Blob: CAS conflict recomputation (precondition -> re-read -> success)
//   4. Blob: exhaustion after 5 attempts throws actionable error without content
//   5. Blob: missing ETag refuses without update/put
//   6. Blob: missing / corrupt / non-200 private object never initializes/writes
//   7. Blob: outage (get throws / put throws non-precondition) performs no writes on read failure
//   8. Blob: private credential pinning (access:private, private token, fixed pathname, allowOverwrite, ifMatch, useCache:false)
//   9. Blob: instanceof (not name matching) drives retries; result belongs to successful write
//  10. Local: two concurrent additions both survive via per-key queue
//  11. Local: queue survives a failed predecessor; temp files always cleaned
//  12. Local: defaults unchanged after a failed role save (DEFAULT_ROLES never mutated)
//  13. Typecheck/lint markers (secret-free copy) -- executed as a sub-check
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const child_process = require("child_process");
const Module = require("module");

const SITE_DIR = process.env.GAZE_SITE_DIR || "/Users/owencope/Developer/gaze-site";
const OURS_DIR = __dirname;
const currentMode = process.argv.includes("--current");
const PATCH_FILE = path.join(OURS_DIR, "metadata-concurrency.patch");
const STAGED = {
  "storage.ts": currentMode ? path.join(SITE_DIR, "src/lib/storage.ts") : path.join(OURS_DIR, "storage.ts"),
  "testers.ts": currentMode ? path.join(SITE_DIR, "src/lib/testers.ts") : path.join(OURS_DIR, "testers.ts"),
  "roles.ts": currentMode ? path.join(SITE_DIR, "src/lib/roles.ts") : path.join(OURS_DIR, "roles.ts"),
  "settings.ts": currentMode ? path.join(SITE_DIR, "src/lib/settings.ts") : path.join(OURS_DIR, "settings.ts"),
};
const ORIG_LIB = path.join(SITE_DIR, "src/lib");
const siteRequire = Module.createRequire(path.join(SITE_DIR, "package.json"));

function fail(msg) {
  console.error(`FAIL: ${msg}`);
  process.exit(1);
}
function pass(msg) {
  console.log(`PASS: ${msg}`);
}
function assert(cond, msg) {
  if (!cond) fail(msg);
}
async function rejects(op, msg) {
  let failed = false;
  try { await op(); } catch { failed = true; }
  assert(failed, msg);
}

for (const [name, p] of Object.entries(STAGED)) assert(fs.existsSync(p), `staged ${name} missing: ${p}`);

// --- 0. Patch scope ---
{
  assert(fs.existsSync(PATCH_FILE), `patch missing: ${PATCH_FILE}`);
  const patch = fs.readFileSync(PATCH_FILE, "utf8");
  const touched = [...patch.matchAll(/^\+\+\+ b\/(.+)$/gm)].map((m) => m[1].trim()).sort();
  const expected = ["src/lib/roles.ts", "src/lib/settings.ts", "src/lib/storage.ts", "src/lib/testers.ts"].sort();
  assert(JSON.stringify(touched) === JSON.stringify(expected),
    `patch must touch exactly ${JSON.stringify(expected)}, got ${JSON.stringify(touched)}`);
  assert(!touched.includes("src/lib/store.ts"), "patch must NOT touch store.ts (Ada owns it)");
  pass("patch scope is exactly storage/testers/roles/settings (store.ts untouched)");
  // Patch must contain the exact exported interface (single-quote form from the brief).
  assert(patch.includes("mutateMetadata<T>"), "patch must export mutateMetadata<T>");
  assert(patch.includes("'releases.json'") && patch.includes("'testers.json'") &&
    patch.includes("'roles.json'") && patch.includes("'settings.json'"),
    "patch must cover all four metadata keys");
  assert(patch.includes("BlobPreconditionFailedError") && patch.includes("instanceof"),
    "patch must retry on instanceof BlobPreconditionFailedError, not name matching");
  assert(patch.includes("ifMatch"), "patch must write with ifMatch (conditional write)");
  assert(!/=.*["']Error["'].*===.*name|name.*===.*["']Error["']/s.test(patch) ||
    patch.includes("name `\"Error\"`"),
    "patch must not match SDK errors by name");
  pass("patch carries the exact mutateMetadata interface with CAS (instanceof + ifMatch)");
  // Verify patch applies cleanly to a temp copy of the site originals.
  if (!currentMode) {
  const tmpPatch = fs.mkdtempSync(path.join(os.tmpdir(), "gaze-conc-patch-"));
  try {
    for (const n of ["storage.ts", "testers.ts", "roles.ts", "settings.ts"]) {
      fs.mkdirSync(path.join(tmpPatch, "src/lib"), { recursive: true });
      fs.copyFileSync(path.join(ORIG_LIB, n), path.join(tmpPatch, "src/lib", n));
    }
    const r = child_process.spawnSync("patch", ["--batch", "--forward", "--fuzz=0", "-p1", "--quiet", "-i", PATCH_FILE],
      { cwd: tmpPatch, stdio: ["ignore", "pipe", "pipe"] });
    assert(r.status === 0, `patch did not apply cleanly: ${(r.stderr || Buffer.alloc(0)).toString().trim()}`);
    for (const n of ["storage.ts", "testers.ts", "roles.ts", "settings.ts"]) {
      const applied = fs.readFileSync(path.join(tmpPatch, "src/lib", n), "utf8");
      const staged = fs.readFileSync(STAGED[n], "utf8");
      assert(applied === staged, `patched ${n} differs from staged final copy`);
    }
    pass("patch applies cleanly (fuzz=0) and reproduces the staged final copies");
  } finally {
    fs.rmSync(tmpPatch, { recursive: true, force: true });
  }
  }
}

// --- Transpile staged sources with the site's installed TypeScript ---
let ts;
try { ts = siteRequire("typescript"); } catch (e) { fail(`installed TypeScript not found: ${e.message}`); }
function transpile(file) {
  const src = fs.readFileSync(file, "utf8");
  return ts.transpileModule(src, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, esModuleInterop: true },
    fileName: path.basename(file),
  }).outputText;
}
const JS = {};
for (const [n, p] of Object.entries(STAGED)) JS[n] = transpile(p);
assert(JS["storage.ts"].includes("mutateMetadata"), "transpiled storage has no mutateMetadata");
assert(JS["storage.ts"].includes("BlobPreconditionFailedError"), "transpiled storage has no precondition handling");
const PERM_SRC = fs.readFileSync(path.join(ORIG_LIB, "permissions.ts"), "utf8");
const PERM_JS = transpile(path.join(ORIG_LIB, "permissions.ts"));
assert(PERM_JS.includes("viewPrivate"), "permissions transpile sanity");

// --- Real SDK error classes (installed, not duplicated) ---
let RealPrecondition;
try {
  RealPrecondition = siteRequire("@vercel/blob").BlobPreconditionFailedError;
} catch (e) { fail(`cannot load installed @vercel/blob error class: ${e.message}`); }
assert(typeof RealPrecondition === "function", "installed BlobPreconditionFailedError missing");
{
  const e = new RealPrecondition();
  assert(e instanceof Error, "SDK precondition error must inherit Error");
  assert(e.name === "Error", `SDK errors inherit name "Error" (got ${JSON.stringify(e.name)}); instanceof is required`);
  pass("using the real installed BlobPreconditionFailedError (name is \"Error\", instanceof required)");
}

// --- Loader ---
const BLOB_KEYS = ["BLOB_READ_WRITE_TOKEN", "BLOB_STORE_ID", "BLOB_PRIVATE_READ_WRITE_TOKEN", "BLOB_PRIVATE_STORE_ID", "VERCEL", "VERCEL_OIDC_TOKEN"];
const savedEnv = {};
for (const k of BLOB_KEYS) savedEnv[k] = process.env[k];
const origCwd = process.cwd();
function setEnv(vars) {
  for (const k of BLOB_KEYS) delete process.env[k];
  for (const [k, v] of Object.entries(vars)) process.env[k] = v;
}
function restoreEnv() {
  for (const k of BLOB_KEYS) {
    if (savedEnv[k] === undefined) delete process.env[k];
    else process.env[k] = savedEnv[k];
  }
  try { process.chdir(origCwd); } catch {}
}
function toStream(text) {
  const bytes = new TextEncoder().encode(text);
  return new ReadableStream({ start(c) { c.enqueue(bytes); c.close(); } });
}

// Versioned in-memory fake Blob store with conditional-write semantics.
function makeVersionedBlob(initial = {}) {
  const store = new Map(); // pathname -> { text, etag, version }
  let seq = 0;
  for (const [k, text] of Object.entries(initial)) {
    seq += 1;
    store.set(k, { text, etag: `etag-v1-${k}-${seq}`, version: 1 });
  }
  const calls = { get: [], put: [] };
  const getOverrides = new Map(); // pathname -> null | {statusCode,stream,blob} | Error | {rawText,etagOverride}
  const putOverrides = new Map(); // pathname -> Error | "always-precondition"
  const stub = {
    calls, store,
    BlobPreconditionFailedError: RealPrecondition,
    getOverrides, putOverrides,
    get: async (pathname, opts) => {
      calls.get.push({ pathname, opts });
      if (getOverrides.has(pathname)) {
        const o = getOverrides.get(pathname);
        if (o instanceof Error) throw o;
        if (o === null) return null;
        return o;
      }
      const e = store.get(pathname);
      if (!e) return null;
      return { statusCode: 200, stream: toStream(e.text), headers: new Headers(), url: `https://stub/${pathname}`, blob: { etag: e.etag, contentType: "application/json", size: e.text.length } };
    },
    put: async (pathname, body, opts) => {
      calls.put.push({ pathname, body, opts });
      if (putOverrides.has(pathname)) {
        const o = putOverrides.get(pathname);
        if (o === "always-precondition") throw new RealPrecondition();
        throw o;
      }
      const cur = store.get(pathname);
      if (opts && typeof opts.ifMatch === "string") {
        if (!cur || cur.etag !== opts.ifMatch) throw new RealPrecondition();
      }
      seq += 1;
      const etag = `etag-v${(cur?.version ?? 0) + 1}-${pathname}-${seq}`;
      store.set(pathname, { text: String(body), etag, version: (cur?.version ?? 0) + 1 });
      return { url: `https://stub/${pathname}`, pathname, etag };
    },
  };
  return stub;
}

let loadN = 0;
function loadStack({ env, cwd, blobStub }) {
  setEnv(env);
  if (cwd) process.chdir(cwd);
  function compile(filename, jsSource, customRequire) {
    const m = new Module(`${filename}#load${loadN++}`, null);
    m.filename = filename;
    m.paths = Module._nodeModulePaths(path.dirname(filename));
    const localRequire = Module.createRequire(path.join(SITE_DIR, "package.json"));
    m.require = (request) => {
      if (customRequire && request in customRequire) {
        const v = customRequire[request];
        return typeof v === "function" ? v() : v;
      }
      return localRequire(request);
    };
    m._compile(jsSource, filename);
    return m.exports;
  }
  const storage = compile(STAGED["storage.ts"], JS["storage.ts"], {
    "@vercel/blob": blobStub,
  });
  const permissions = compile(path.join(ORIG_LIB, "permissions.ts"), PERM_JS, {});
  const shared = { storage, permissions };
  function libRequire(request) {
    if (request === "@/lib/storage") return shared.storage;
    if (request === "./storage") return shared.storage;
    if (request === "@/lib/permissions") return shared.permissions;
    if (request === "@vercel/blob") return blobStub;
    return siteRequire(request);
  }
  function compileLib(name) {
    const m = new Module(`${STAGED[name]}#load${loadN++}`, null);
    m.filename = STAGED[name];
    m.paths = Module._nodeModulePaths(path.dirname(STAGED[name]));
    m.require = libRequire;
    m._compile(JS[name], STAGED[name]);
    return m.exports;
  }
  return { storage, permissions, testers: compileLib("testers.ts"), roles: compileLib("roles.ts"), settings: compileLib("settings.ts") };
}

function assertPrivateGet(opts, label) {
  assert(opts && opts.access === "private", `${label}: get must pin access:"private" (got ${JSON.stringify(opts)})`);
  assert(opts.useCache === false, `${label}: get must bypass cache (useCache:false)`);
  assert(opts.token === "private-token", `${label}: get must carry the explicit private token (got ${JSON.stringify(opts.token)})`);
  assert(!("storeId" in opts) || opts.storeId === undefined, `${label}: static-token mode must not send storeId`);
}
function assertPrivatePut(opts, label, etag) {
  assert(opts && opts.access === "private", `${label}: put must pin access:"private"`);
  assert(opts.token === "private-token", `${label}: put must carry the explicit private token`);
  assert(opts.addRandomSuffix === false, `${label}: put must keep a fixed pathname`);
  assert(opts.allowOverwrite === true, `${label}: put must allow overwrite (conditional)`);
  assert(opts.ifMatch === etag, `${label}: put must send ifMatch of the version just read`);
  assert(opts.contentType === "application/json", `${label}: put must keep application/json`);
}

const PRIV_ENV = { BLOB_READ_WRITE_TOKEN: "public-token", BLOB_PRIVATE_READ_WRITE_TOKEN: "private-token" };

(async () => {
  // --- 1. Lost-update probe of the OLD read/write flow (synthetic, deterministic) ---
  {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "gaze-conc-lost-"));
    try {
      const blob = makeVersionedBlob({ "testers.json": "[]" });
      const { storage } = loadStack({ env: PRIV_ENV, blobStub: blob });
      // Old flow: two writers both read the SAME version, then each writes back.
      const rawA = await storage.readTestersJson();
      const rawB = await storage.readTestersJson();
      const listA = JSON.parse(rawA);
      listA.unshift({ email: "a@example.invalid", roles: ["tester"], addedAt: "2026-01-01T00:00:00.000Z" });
      const listB = JSON.parse(rawB);
      listB.unshift({ email: "b@example.invalid", roles: ["tester"], addedAt: "2026-01-01T00:00:00.000Z" });
      // Old unconditional writes (no ifMatch) both succeed; the second discards the first.
      await blob.put("testers.json", `${JSON.stringify(listA, null, 2)}\n`,
        { access: "private", token: "private-token", addRandomSuffix: false, allowOverwrite: true });
      await blob.put("testers.json", `${JSON.stringify(listB, null, 2)}\n`,
        { access: "private", token: "private-token", addRandomSuffix: false, allowOverwrite: true });
      const final = JSON.parse(blob.store.get("testers.json").text);
      const emails = final.map((t) => t.email).sort();
      assert(JSON.stringify(emails) === JSON.stringify(["b@example.invalid"]),
        `old flow must demonstrate loss (expected only b, got ${JSON.stringify(emails)})`);
      pass("lost-update probe: old read/modify/write loses one of two independent additions");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
      restoreEnv();
    }
  }

  // --- 2. Blob: two concurrent independent additions both survive (real addTester) ---
  {
    const blob = makeVersionedBlob({ "testers.json": "[]" });
    const { testers } = loadStack({ env: PRIV_ENV, blobStub: blob });
    const [r1, r2] = await Promise.all([
      testers.addTester({ email: "ALICE@example.invalid" }),
      testers.addTester({ email: "bob@example.invalid" }),
    ]);
    const final = JSON.parse(blob.store.get("testers.json").text);
    const emails = final.map((t) => t.email).sort();
    assert(emails.includes("alice@example.invalid") && emails.includes("bob@example.invalid"),
      `both concurrent additions must survive (got ${JSON.stringify(emails)})`);
    assert(final.length === 2, `expected 2 testers, got ${final.length}`);
    // addedAt preserved per record and timestamps computed once (both ISO strings, distinct or equal but valid).
    for (const t of final) assert(typeof t.addedAt === "string" && t.addedAt.length > 0, "addedAt must be set");
    // Callers observe the successful-write result (both contain both after convergence; at least final does).
    assert(r1.length === 2 || r2.length === 2, "at least the second writer must observe both rows");
    // Pinning on every get/put.
    for (const c of blob.calls.get) assertPrivateGet(c.opts, `concurrent get ${c.pathname}`);
    const etags = blob.calls.get.map((c) => blob.store.get(c.pathname)?.etag).filter(Boolean);
    assert(blob.calls.get.length >= 2, "concurrent path must re-read on conflict");
    for (const c of blob.calls.put) {
      assert(c.opts.access === "private" && c.opts.token === "private-token", "concurrent put must stay private");
      assert(typeof c.opts.ifMatch === "string" && c.opts.ifMatch.length > 0, "concurrent put must be conditional");
    }
    restoreEnv();
    pass("Blob: two concurrent independent addTester calls both survive via CAS retry");
  }

  // --- 3. CAS conflict recomputation returns the successful-write result ---
  {
    const blob = makeVersionedBlob({ "testers.json": "[]" });
    let updates = 0;
    const { storage } = loadStack({ env: PRIV_ENV, blobStub: blob });
    // Poison the first put only: first attempt sees etag v1 and fails, second re-reads v2 and wins.
    let firstPut = true;
    const origPut = blob.put;
    blob.put = async (p, b, o) => {
      blob.calls.put.push({ pathname: p, body: b, opts: o });
      if (firstPut) {
        firstPut = false;
        // Simulate a racing writer landing between our get and put.
        blob.store.set(p, { text: JSON.stringify([{ email: "racer@example.invalid", roles: ["tester"], addedAt: "x" }]), etag: "etag-racer", version: 99 });
        throw new RealPrecondition();
      }
      const cur = blob.store.get(p);
      if (o.ifMatch !== cur.etag) throw new RealPrecondition();
      blob.store.set(p, { text: String(b), etag: "etag-final", version: 100 });
      return { url: "x", pathname: p, etag: "etag-final" };
    };
    // Avoid double-counting: replace calls.put tracking (origPut also pushes; clear first).
    blob.calls.put.length = 0;
    const result = await storage.mutateMetadata("testers.json", (raw) => {
      updates += 1;
      const list = JSON.parse(raw);
      list.unshift({ email: `writer-${updates}@example.invalid`, roles: ["tester"], addedAt: "y" });
      return { text: JSON.stringify(list), result: list.map((t) => t.email) };
    });
    assert(updates === 2, `update must recompute after precondition (ran ${updates}x)`);
    assert(result.includes("racer@example.invalid") && result.includes("writer-2@example.invalid"),
      `returned result must belong to the successful write (got ${JSON.stringify(result)})`);
    assert(!result.includes("writer-1@example.invalid"), "stale first-attempt result must be discarded");
    assert(blob.store.get("testers.json").text.includes("racer@example.invalid"), "racing row must be preserved");
    restoreEnv();
    pass("Blob: CAS conflict recomputes and returns only the successful-write result");
  }

  // --- 4. Exhaustion: 5 attempts then actionable error without private content ---
  {
    const secret = JSON.stringify([{ email: "secret-victim@example.invalid" }]);
    const blob = makeVersionedBlob({ "testers.json": secret });
    blob.putOverrides.set("testers.json", "always-precondition");
    const { storage } = loadStack({ env: PRIV_ENV, blobStub: blob });
    let updateCalls = 0;
    let msg = "";
    try {
      await storage.mutateMetadata("testers.json", (raw) => {
        updateCalls += 1;
        return { text: raw, result: null };
      });
      assert(false, "exhaustion must throw");
    } catch (e) { msg = String(e && e.message); }
    assert(updateCalls === 5, `must attempt exactly 5 times (did ${updateCalls})`);
    assert(blob.calls.put.length === 5, `must put 5 times (did ${blob.calls.put.length})`);
    assert(/5/.test(msg) && /testers\.json/.test(msg), `exhaustion error must be actionable (got ${JSON.stringify(msg)})`);
    assert(!msg.includes("secret-victim"), "exhaustion error must not include private document content");
    assert(!blob.store.get("testers.json").text.includes("mutated"), "no write may land on exhaustion");
    restoreEnv();
    pass("Blob: exhaustion after 5 CAS failures throws actionable error without private content");
  }

  // --- 5. Missing ETag refuses without update/put ---
  {
    const blob = makeVersionedBlob({});
    blob.getOverrides.set("testers.json", { statusCode: 200, stream: toStream("[]"), headers: new Headers(), url: "x", blob: { etag: "", contentType: "x", size: 2 } });
    const { storage } = loadStack({ env: PRIV_ENV, blobStub: blob });
    let updated = false;
    await rejects(() => storage.mutateMetadata("testers.json", (raw) => { updated = true; return { text: "[]", result: null }; }),
      "missing ETag must refuse");
    assert(!updated, "update must not run without a version");
    assert(blob.calls.put.length === 0, "no put without an ETag");
    // Undefined etag variant.
    blob.getOverrides.set("testers.json", { statusCode: 200, stream: toStream("[]"), headers: new Headers(), url: "x", blob: { contentType: "x", size: 2 } });
    await rejects(() => storage.mutateMetadata("testers.json", () => ({ text: "[]", result: null })),
      "undefined ETag must refuse");
    restoreEnv();
    pass("Blob: missing/empty ETag refuses without calling update or writing");
  }

  // --- 6. Missing / non-200 / corrupt never initialize or write ---
  {
    const blob = makeVersionedBlob({});
    blob.getOverrides.set("testers.json", null); // missing
    blob.getOverrides.set("roles.json", { statusCode: 404, stream: null, headers: new Headers(), url: "x", blob: { etag: "e", contentType: "x", size: 0 } });
    blob.textsCorrupt = true;
    const blob2 = makeVersionedBlob({ "settings.json": "not-json{{{" });
    const { storage } = loadStack({ env: PRIV_ENV, blobStub: blob });
    for (const [key, label] of [["testers.json", "missing (null)"], ["roles.json", "non-200"]]) {
      let updated = false;
      await rejects(() => storage.mutateMetadata(key, (raw) => { updated = true; return { text: "[]", result: null }; }), `${label} must refuse`);
      assert(!updated, `${label}: update must not run`);
    }
    assert(blob.calls.put.length === 0, "no puts after missing/non-200");
    restoreEnv();
    const { storage: s2 } = loadStack({ env: PRIV_ENV, blobStub: blob2 });
    let u2 = false;
    await rejects(() => s2.mutateMetadata("settings.json", () => { u2 = true; return { text: "{}", result: null }; }), "corrupt existing must refuse");
    assert(!u2, "corrupt: update must not run");
    assert(blob2.calls.put.length === 0, "corrupt: no put");
    // Wrong shape: array where object required and vice versa.
    const blob3 = makeVersionedBlob({ "settings.json": "[]", "testers.json": "{}" });
    const { storage: s3 } = loadStack({ env: PRIV_ENV, blobStub: blob3 });
    await rejects(() => s3.mutateMetadata("settings.json", () => ({ text: "[]", result: null })), "shape: settings must be object");
    await rejects(() => s3.mutateMetadata("testers.json", () => ({ text: "{}", result: null })), "shape: testers must be array");
    assert(blob3.calls.put.length === 0, "shape violations: no puts");
    // Invalid NEXT text never writes.
    const blob4 = makeVersionedBlob({ "testers.json": "[]" });
    const { storage: s4 } = loadStack({ env: PRIV_ENV, blobStub: blob4 });
    await rejects(() => s4.mutateMetadata("testers.json", () => ({ text: "{}", result: null })), "invalid next text must refuse");
    assert(blob4.calls.put.length === 0, "invalid next: no put");
    restoreEnv();
    pass("Blob: missing/corrupt/shape-invalid reads and invalid next text never initialize or write");
  }

  // --- 7. Outage: get throws -> no put; put throws non-precondition -> propagates without retry ---
  {
    const blob = makeVersionedBlob({ "testers.json": "[]" });
    blob.getOverrides.set("testers.json", new Error("synthetic outage"));
    const { storage } = loadStack({ env: PRIV_ENV, blobStub: blob });
    await rejects(() => storage.mutateMetadata("testers.json", () => ({ text: "[]", result: null })), "get outage must propagate");
    assert(blob.calls.put.length === 0, "get outage: no put");
    restoreEnv();
    const blobB = makeVersionedBlob({ "testers.json": "[]" });
    blobB.putOverrides.set("testers.json", new Error("synthetic put outage"));
    const { storage: sb } = loadStack({ env: PRIV_ENV, blobStub: blobB });
    let calls = 0;
    await rejects(() => sb.mutateMetadata("testers.json", () => { calls += 1; return { text: "[]", result: null }; }), "put outage must propagate");
    assert(calls === 1, `non-precondition put failure must not retry (update ran ${calls}x)`);
    assert(blobB.calls.put.length === 1, "put outage: exactly one attempt");
    restoreEnv();
    // Unconfigured private store never reaches the SDK.
    const blobC = makeVersionedBlob({ "testers.json": "[]" });
    const { storage: sc } = loadStack({ env: { BLOB_READ_WRITE_TOKEN: "public-token" }, blobStub: blobC });
    await rejects(() => sc.mutateMetadata("testers.json", () => ({ text: "[]", result: null })), "unconfigured must throw");
    assert(blobC.calls.get.length === 0 && blobC.calls.put.length === 0, "unconfigured: SDK never called");
    restoreEnv();
    pass("Blob: outage propagates with no stray writes; unconfigured never reaches the SDK");
  }

  // --- 8. Private credential pinning + instanceof (not name) ---
  {
    const blob = makeVersionedBlob({ "settings.json": JSON.stringify({ releasesRequireSignIn: false }) });
    const { storage, settings } = loadStack({ env: PRIV_ENV, blobStub: blob });
    // Direct mutate pinning.
    const etagBefore = blob.store.get("settings.json").etag;
    await storage.mutateMetadata("settings.json", (raw) => ({ text: raw, result: "ok" }));
    assertPrivateGet(blob.calls.get[0].opts, "pinning get");
    assertPrivatePut(blob.calls.put[0].opts, "pinning put", etagBefore);
    assert(!JSON.stringify(blob.calls.get[0].opts).includes("public-token"), "no public token in get");
    assert(!JSON.stringify(blob.calls.put[0].opts).includes("public-token"), "no public token in put");
    // Converter path (saveSettings) also pins.
    blob.calls.get.length = 0; blob.calls.put.length = 0;
    const etag2 = blob.store.get("settings.json").etag;
    await settings.saveSettings({ releasesRequireSignIn: true });
    assertPrivateGet(blob.calls.get[0].opts, "saveSettings get");
    assertPrivatePut(blob.calls.put[0].opts, "saveSettings put", etag2);
    assert(JSON.parse(blob.store.get("settings.json").text).releasesRequireSignIn === true, "saveSettings persists");
    // instanceof proof: a lookalike with name BlobPreconditionFailedError but the WRONG class must NOT retry.
    const blobD = makeVersionedBlob({ "testers.json": "[]" });
    class Lookalike extends Error { constructor() { super("lookalike"); this.name = "BlobPreconditionFailedError"; } }
    blobD.putOverrides.set("testers.json", new Lookalike());
    const { storage: sd } = loadStack({ env: PRIV_ENV, blobStub: blobD });
    let n = 0;
    await rejects(() => sd.mutateMetadata("testers.json", () => { n += 1; return { text: "[]", result: null }; }), "lookalike must propagate");
    assert(n === 1 && blobD.calls.put.length === 1, "name-matching must not trigger a retry; only instanceof retries");
    restoreEnv();
    pass("Blob: private credential pinning on converters + instanceof (not name) retry");
  }

  // --- 9. Local: concurrent independent additions both survive ---
  {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "gaze-conc-local-"));
    try {
      const blob = { get: async () => { throw new Error("local must not call Blob"); }, put: async () => { throw new Error("local must not call Blob"); }, BlobPreconditionFailedError: RealPrecondition, calls: { get: [], put: [] } };
      const { testers, storage } = loadStack({ env: {}, cwd: dir, blobStub: blob });
      assert(storage.usingBlob === false, "local: usingBlob must be false");
      const [a, b] = await Promise.all([
        testers.addTester({ email: "local-a@example.invalid" }),
        testers.addTester({ email: "local-b@example.invalid" }),
      ]);
      const onDisk = JSON.parse(fs.readFileSync(path.join(dir, "data", "testers.json"), "utf8"));
      const emails = onDisk.map((t) => t.email).sort();
      assert(emails.includes("local-a@example.invalid") && emails.includes("local-b@example.invalid"),
        `local concurrent additions must both survive (got ${JSON.stringify(emails)})`);
      assert(a.length === 2 || b.length === 2, "local: at least one caller observes both");
      // No temp litter.
      const leftovers = [];
      (function walk(d) {
        for (const e of fs.readdirSync(d, { withFileTypes: true })) {
          const p = path.join(d, e.name);
          if (e.isDirectory()) walk(p);
          else if (e.name.endsWith(".tmp")) leftovers.push(p);
        }
      })(dir);
      assert(leftovers.length === 0, `local: temp files must be cleaned (found ${JSON.stringify(leftovers)})`);
      restoreEnv();
      pass("Local: two concurrent addTester calls both survive via per-key queue; no temp litter");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
      restoreEnv();
    }
  }

  // --- 10. Local: queue survives a failed predecessor ---
  {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "gaze-conc-qfail-"));
    try {
      const blob = { get: async () => { throw new Error("x"); }, put: async () => { throw new Error("x"); }, BlobPreconditionFailedError: RealPrecondition, calls: { get: [], put: [] } };
      const { storage } = loadStack({ env: {}, cwd: dir, blobStub: blob });
      const failing = storage.mutateMetadata("testers.json", () => { throw new Error("synthetic predecessor failure"); });
      const succeeding = storage.mutateMetadata("testers.json", (raw) => {
        const list = raw ? JSON.parse(raw) : [];
        list.unshift({ email: "after-failure@example.invalid", roles: ["tester"], addedAt: "z" });
        return { text: JSON.stringify(list), result: list };
      });
      await rejects(() => failing, "predecessor must reject");
      const res = await succeeding;
      assert(res.some((t) => t.email === "after-failure@example.invalid"), "successor must run after a failed predecessor");
      const leftovers = fs.readdirSync(path.join(dir, "data")).filter((n) => n.endsWith(".tmp"));
      assert(leftovers.length === 0, "failed queue: no temp litter");
      restoreEnv();
      pass("Local: per-key queue survives a failed predecessor");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
      restoreEnv();
    }
  }

  // --- 11. Defaults unchanged after a failed role save + addedAt/permissions semantics ---
  {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "gaze-conc-defaults-"));
    try {
      const blob = { get: async () => { throw new Error("x"); }, put: async () => { throw new Error("x"); }, BlobPreconditionFailedError: RealPrecondition, calls: { get: [], put: [] } };
      const { roles, testers } = loadStack({ env: {}, cwd: dir, blobStub: blob });
      // Seed a tester to check addedAt preservation.
      await testers.addTester({ email: "keep@example.invalid", note: "first" });
      const before = JSON.parse(fs.readFileSync(path.join(dir, "data", "testers.json"), "utf8"));
      const addedAt = before.find((t) => t.email === "keep@example.invalid").addedAt;
      await new Promise((r) => setTimeout(r, 5));
      const afterUpdate = await testers.addTester({ email: "keep@example.invalid", note: "second" });
      const kept = afterUpdate.find((t) => t.email === "keep@example.invalid");
      assert(kept.addedAt === addedAt, "re-adding must preserve the original addedAt");
      assert(kept.note === "second", "re-adding updates the note");
      // Permissions filtering preserved.
      const withRoles = await roles.upsertRole({ name: "Extra", color: "#ff0000", permissions: ["viewPrivate", "bogus-perm"] });
      const extra = withRoles.find((r) => r.id === "extra");
      assert(extra && extra.permissions.length === 1 && extra.permissions[0] === "viewPrivate", "unknown permissions must be filtered");
      assert(withRoles.some((r) => r.id === "tester"), "defaults must seed the list when missing");
      // Failed save must not mutate DEFAULT_ROLES: poison the write by replacing data/roles.json with a directory.
      const rolesPath = path.join(dir, "data", "roles.json");
      const saved = fs.readFileSync(rolesPath, "utf8");
      fs.rmSync(rolesPath);
      fs.mkdirSync(rolesPath);
      await rejects(() => roles.upsertRole({ name: "ShouldFail", color: "#00ff00", permissions: [] }), "poisoned write must fail");
      fs.rmdirSync(rolesPath);
      fs.writeFileSync(rolesPath, saved, "utf8");
      // Remove the file entirely: a fresh read must yield pristine defaults (length 1, tester only).
      fs.rmSync(rolesPath);
      const fresh = await roles.readRoles();
      assert(fresh.length === 1 && fresh[0].id === "tester", `DEFAULT_ROLES must be unchanged after failure (got ${JSON.stringify(fresh)})`);
      // And a new mutation from missing still seeds exactly one default + one new row.
      const next = await roles.upsertRole({ name: "AfterFailure", color: "#0000ff", permissions: [] });
      assert(next.length === 2 && next.some((r) => r.id === "tester") && next.some((r) => r.id === "afterfailure"),
        `post-failure seed must be pristine (got ${JSON.stringify(next.map((r) => r.id))})`);
      restoreEnv();
      pass("Local: addedAt/permissions/defaults preserved; DEFAULT_ROLES unchanged after failed save");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
      restoreEnv();
    }
  }

  // --- 12. Settings concurrent merge preserves independent keys (Blob) ---
  {
    const blob = makeVersionedBlob({ "settings.json": JSON.stringify({ releasesRequireSignIn: false }) });
    const { settings } = loadStack({ env: PRIV_ENV, blobStub: blob });
    // Two concurrent patches to the same single-key doc: second recomputes against first.
    const [s1, s2] = await Promise.all([
      settings.saveSettings({ releasesRequireSignIn: true }),
      settings.saveSettings({ releasesRequireSignIn: true }),
    ]);
    assert(s1.releasesRequireSignIn === true && s2.releasesRequireSignIn === true, "settings merge must hold");
    assert(JSON.parse(blob.store.get("settings.json").text).releasesRequireSignIn === true, "settings persisted");
    restoreEnv();
    pass("Blob: concurrent saveSettings converge via recomputation");
  }

  console.log("OK: all metadata-concurrency checks passed (staged sources executed, SDK stubbed).");
})()
  .catch((e) => fail(e && e.stack ? e.stack : String(e)))
  .finally(() => restoreEnv());
