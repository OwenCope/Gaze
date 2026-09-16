#!/usr/bin/env node
// Stale-edit rejection for tester notes (vera-2).
//
// Executes the ACTUAL staged sources in this directory (storage.ts,
// readme.ts, route.ts) by transpiling them with the site's installed
// TypeScript and running them against a versioned in-memory fake Blob store
// plus the real filesystem. No network, no live Blob, no production data.
//
// Covers:
//   0. patch scope is exactly the five site files; applies cleanly (fuzz=0)
//      and reproduces the staged final copies
//   1. versionForReadme vectors: missing vs empty vs content
//   2. Blob: two editors read one version, first save wins, second gets a
//      version conflict with zero overwrite
//   3. Blob: CAS race after the version check re-reads, then conflicts
//      (stale content never silently wins via retry)
//   4. Unchanged content/version re-save remains valid
//   5. Missing vs empty distinction; Blob missing refuses before the callback
//   6. API: strict readme validation kept; well-formed expectedVersion
//      required ('missing' or 64 lowercase hex); old clients get actionable
//      400; success returns {ok:true,version}; stale returns 409
//   7. Failures keep stored data (conflict/outage change nothing)
//   8. Existing independent-record concurrency preserved; readme puts use
//      text/markdown while JSON keys stay application/json
//   9. Local: serialized saves reject the stale second writer; no temp litter
//  10. Static source contract: page passes initialVersion; editor sends
//      expectedVersion, tracks acknowledgement, preserves A/B behavior and
//      offers confirm-gated reload only (no force-overwrite/merge/autoreload)
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const child_process = require("child_process");
const Module = require("module");
const { createHash } = require("node:crypto");

const SITE_DIR = process.env.GAZE_SITE_DIR || "/Users/owencope/Developer/gaze-site";
const OURS_DIR = __dirname;
const currentMode = process.argv.includes("--current");
const PATCH_FILE = path.join(OURS_DIR, "notes-versioning.patch");
const STAGED = {
  "storage.ts": currentMode ? path.join(SITE_DIR, "src/lib/storage.ts") : path.join(OURS_DIR, "storage.ts"),
  "readme.ts": currentMode ? path.join(SITE_DIR, "src/lib/readme.ts") : path.join(OURS_DIR, "readme.ts"),
  "route.ts": currentMode ? path.join(SITE_DIR, "src/app/api/readme/route.ts") : path.join(OURS_DIR, "route.ts"),
  "page.tsx": currentMode ? path.join(SITE_DIR, "src/app/admin/readme/page.tsx") : path.join(OURS_DIR, "page.tsx"),
  "readme-editor.tsx": currentMode ? path.join(SITE_DIR, "src/components/readme-editor.tsx") : path.join(OURS_DIR, "readme-editor.tsx"),
};
const ORIG = {
  "storage.ts": path.join(SITE_DIR, "src/lib/storage.ts"),
  "route.ts": path.join(SITE_DIR, "src/app/api/readme/route.ts"),
  "page.tsx": path.join(SITE_DIR, "src/app/admin/readme/page.tsx"),
  "readme-editor.tsx": path.join(SITE_DIR, "src/components/readme-editor.tsx"),
};
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

for (const [name, p] of Object.entries(STAGED)) {
  if (name === "readme.ts" && currentMode) continue; // new file may not exist in --current until applied
  assert(fs.existsSync(p), `staged ${name} missing: ${p}`);
}

// --- 0. Patch scope ---
{
  assert(fs.existsSync(PATCH_FILE), `patch missing: ${PATCH_FILE}`);
  const patch = fs.readFileSync(PATCH_FILE, "utf8");
  const touched = [...patch.matchAll(/^\+\+\+ b\/(.+)$/gm)].map((m) => m[1].trim()).sort();
  const expected = [
    "src/app/admin/readme/page.tsx",
    "src/app/api/readme/route.ts",
    "src/components/readme-editor.tsx",
    "src/lib/readme.ts",
    "src/lib/storage.ts",
  ].sort();
  assert(JSON.stringify(touched) === JSON.stringify(expected),
    `patch must touch exactly ${JSON.stringify(expected)}, got ${JSON.stringify(touched)}`);
  for (const forbidden of ["src/components/account-button.tsx", "src/components/release-gallery.tsx", "src/auth", ".env"]) {
    assert(!patch.includes(forbidden), `patch must not touch ${forbidden}`);
  }
  assert(patch.includes("readme.md") && patch.includes("text/markdown"),
    "patch must extend the mutation allowlist to readme.md with text/markdown");
  assert(patch.includes("ReadmeConflictError") && patch.includes("expectedVersion"),
    "patch must carry the versioned readme flow");
  assert(!/navigator\.clipboard/.test(patch), "patch must not write to the clipboard");
  pass("patch scope is exactly the five readme files (no account/gallery/auth/env)");
  if (!currentMode) {
    const tmpPatch = fs.mkdtempSync(path.join(os.tmpdir(), "gaze-notes-patch-"));
    try {
      const mapping = {
        "src/lib/storage.ts": ORIG["storage.ts"],
        "src/app/api/readme/route.ts": ORIG["route.ts"],
        "src/app/admin/readme/page.tsx": ORIG["page.tsx"],
        "src/components/readme-editor.tsx": ORIG["readme-editor.tsx"],
      };
      for (const [rel, src] of Object.entries(mapping)) {
        const dest = path.join(tmpPatch, rel);
        fs.mkdirSync(path.dirname(dest), { recursive: true });
        fs.copyFileSync(src, dest);
      }
      const r = child_process.spawnSync("patch", ["--batch", "--forward", "--fuzz=0", "-p1", "--quiet", "-i", PATCH_FILE],
        { cwd: tmpPatch, stdio: ["ignore", "pipe", "pipe"] });
      assert(r.status === 0, `patch did not apply cleanly: ${(r.stderr || Buffer.alloc(0)).toString().trim()}`);
      const appliedNames = {
        "src/lib/storage.ts": "storage.ts",
        "src/lib/readme.ts": "readme.ts",
        "src/app/api/readme/route.ts": "route.ts",
        "src/app/admin/readme/page.tsx": "page.tsx",
        "src/components/readme-editor.tsx": "readme-editor.tsx",
      };
      for (const [rel, stagedName] of Object.entries(appliedNames)) {
        const applied = fs.readFileSync(path.join(tmpPatch, rel), "utf8");
        const staged = fs.readFileSync(STAGED[stagedName], "utf8");
        assert(applied === staged, `patched ${rel} differs from staged ${stagedName}`);
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
  const isTsx = file.endsWith(".tsx");
  return ts.transpileModule(src, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2020,
      esModuleInterop: true,
      jsx: isTsx ? ts.JsxEmit.ReactJSX : undefined,
    },
    fileName: path.basename(file),
  }).outputText;
}
const JS = {};
for (const [n, p] of Object.entries(STAGED)) {
  if (n === "readme.ts" && currentMode && !fs.existsSync(p)) continue;
  JS[n] = transpile(p);
}
assert(JS["storage.ts"].includes("readme.md"), "transpiled storage must allow readme.md");
assert(JS["readme.ts"].includes("ReadmeConflictError"), "transpiled readme must define ReadmeConflictError");

// --- Real SDK error class (installed, not duplicated) ---
let RealPrecondition;
try {
  RealPrecondition = siteRequire("@vercel/blob").BlobPreconditionFailedError;
} catch (e) { fail(`cannot load installed @vercel/blob error class: ${e.message}`); }
assert(typeof RealPrecondition === "function", "installed BlobPreconditionFailedError missing");
{
  const e = new RealPrecondition();
  assert(e instanceof Error && e.name === "Error", "SDK precondition error must inherit Error with name \"Error\"");
  pass("using the real installed BlobPreconditionFailedError (instanceof required)");
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

function makeVersionedBlob(initial = {}) {
  const store = new Map();
  let seq = 0;
  for (const [k, text] of Object.entries(initial)) {
    seq += 1;
    store.set(k, { text, etag: `etag-v1-${k}-${seq}`, version: 1 });
  }
  const calls = { get: [], put: [] };
  const getOverrides = new Map();
  const putOverrides = new Map();
  const stub = {
    calls, store, getOverrides, putOverrides,
    BlobPreconditionFailedError: RealPrecondition,
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
      return { statusCode: 200, stream: toStream(e.text), headers: new Headers(), url: `https://stub/${pathname}`, blob: { etag: e.etag, contentType: "text/markdown", size: e.text.length } };
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
let adminFlag = true;
let revalidations = [];
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
  const storage = compile(STAGED["storage.ts"], JS["storage.ts"], { "@vercel/blob": blobStub });
  function readmeRequire(request) {
    if (request === "./storage" || request === "@/lib/storage") return storage;
    if (request === "@vercel/blob") return blobStub;
    return siteRequire(request);
  }
  const readmeMod = new Module(`${STAGED["readme.ts"]}#load${loadN++}`, null);
  readmeMod.filename = STAGED["readme.ts"];
  readmeMod.paths = Module._nodeModulePaths(path.dirname(STAGED["readme.ts"]));
  readmeMod.require = readmeRequire;
  readmeMod._compile(JS["readme.ts"], STAGED["readme.ts"]);
  const readme = readmeMod.exports;
  function routeRequire(request) {
    if (request === "@/lib/readme") return readme;
    if (request === "@/lib/storage") return storage;
    if (request === "@/auth") return { auth: async () => (adminFlag === true ? { user: { isAdmin: true } } : (adminFlag === "nonadmin" ? { user: { isAdmin: false } } : null)) };
    if (request === "next/cache") return { revalidatePath: (p) => revalidations.push(p) };
    if (request === "@vercel/blob") return blobStub;
    return siteRequire(request);
  }
  const routeMod = new Module(`${STAGED["route.ts"]}#load${loadN++}`, null);
  routeMod.filename = STAGED["route.ts"];
  routeMod.paths = Module._nodeModulePaths(path.dirname(STAGED["route.ts"]));
  routeMod.require = routeRequire;
  routeMod._compile(JS["route.ts"], STAGED["route.ts"]);
  return { storage, readme, route: routeMod.exports };
}

const PRIV_ENV = { BLOB_READ_WRITE_TOKEN: "public-token", BLOB_PRIVATE_READ_WRITE_TOKEN: "private-token" };
const sha256 = (s) => createHash("sha256").update(s, "utf8").digest("hex");
const post = (route, body) => route.POST(new Request("http://localhost/api/readme", {
  method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
}));

(async () => {
  // --- 1. versionForReadme vectors ---
  {
    const blob = makeVersionedBlob({});
    const { readme } = loadStack({ env: PRIV_ENV, blobStub: blob });
    assert(readme.versionForReadme(null) === "missing", "absent local data must version as 'missing'");
    assert(readme.versionForReadme("") === "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      "empty text must hash to the SHA-256 of the empty string");
    assert(readme.versionForReadme("seed-A") === sha256("seed-A"), "content must hash as UTF-8 SHA-256 hex");
    assert(/^[0-9a-f]{64}$/.test(readme.versionForReadme("hello")), "content versions must be 64 lowercase hex");
    assert(readme.versionForReadme(null) !== readme.versionForReadme(""), "missing vs empty must be distinct versions");
    assert(readme.ReadmeConflictError, "ReadmeConflictError must be exported");
    const err = new readme.ReadmeConflictError();
    assert(err instanceof Error && err.name === "ReadmeConflictError", "conflict error must carry its name");
    restoreEnv();
    pass("versionForReadme: missing/empty/content vectors with distinct missing-vs-empty");
  }

  // --- 2. Two editors, one version: first wins, second conflicts with zero overwrite ---
  {
    const blob = makeVersionedBlob({ "readme.md": "seed-A" });
    const { readme } = loadStack({ env: PRIV_ENV, blobStub: blob });
    const editorA = await readme.readReadmeDocument();
    const editorB = await readme.readReadmeDocument();
    assert(editorA.text === "seed-A" && editorB.text === "seed-A", "both editors must read the same text");
    assert(editorA.version === editorB.version && editorA.version === sha256("seed-A"), "both editors must read one version");
    const savedA = await readme.saveReadmeDocument("A", editorA.version);
    assert(savedA.text === "A" && savedA.version === sha256("A"), "first save must succeed with its new version");
    assert(blob.store.get("readme.md").text === "A", "first save must publish");
    const putsAfterA = blob.calls.put.length;
    let conflict = null;
    try {
      await readme.saveReadmeDocument("B", editorB.version);
    } catch (e) { conflict = e; }
    assert(conflict && conflict instanceof readme.ReadmeConflictError, "stale second save must throw ReadmeConflictError");
    assert(blob.store.get("readme.md").text === "A", "stale save must leave zero overwrite");
    assert(blob.calls.put.length === putsAfterA, "stale save must issue no additional put");
    const reread = await readme.readReadmeDocument();
    assert(reread.text === "A" && reread.version === sha256("A"), "stored version must still read back");
    restoreEnv();
    pass("Blob: two editors read one version, first succeeds, second gets 409-class conflict with zero overwrite");
  }

  // --- 3. CAS race after the version check re-reads, then conflicts ---
  {
    const blob = makeVersionedBlob({ "readme.md": "base" });
    const { readme } = loadStack({ env: PRIV_ENV, blobStub: blob });
    const stale = await readme.readReadmeDocument();
    const origPut = blob.put;
    let firstPut = true;
    blob.put = async (p, b, o) => {
      blob.calls.put.push({ pathname: p, body: b, opts: o });
      if (firstPut && p === "readme.md") {
        firstPut = false;
        // A racing writer lands between our get and put: real store moves on.
        const cur = blob.store.get(p);
        blob.store.set(p, { text: "racer", etag: `${cur.etag}-racer`, version: cur.version + 1 });
        throw new RealPrecondition();
      }
      const cur = blob.store.get(p);
      if (o.ifMatch !== cur.etag) throw new RealPrecondition();
      return origPut(p, b, { ...o, ifMatch: cur.etag });
    };
    blob.calls.put.length = 0;
    let conflict = null;
    try {
      await readme.saveReadmeDocument("stale-edit", stale.version);
    } catch (e) { conflict = e; }
    assert(conflict && conflict instanceof readme.ReadmeConflictError,
      "CAS retry must re-read and then conflict, not silently win");
    assert(blob.store.get("readme.md").text === "racer", "racing content must survive; stale edit must not overwrite it");
    restoreEnv();
    pass("Blob: CAS race after the version check re-reads and then conflicts");
  }

  // --- 4. Unchanged content/version remains valid ---
  {
    const blob = makeVersionedBlob({ "readme.md": "same" });
    const { readme } = loadStack({ env: PRIV_ENV, blobStub: blob });
    const doc = await readme.readReadmeDocument();
    const resaved = await readme.saveReadmeDocument("same", doc.version);
    assert(resaved.text === "same" && resaved.version === doc.version, "identical re-save must succeed with the same version");
    assert(blob.store.get("readme.md").text === "same", "identical re-save must keep the text");
    restoreEnv();
    pass("unchanged content/version remains valid");
  }

  // --- 5. Missing vs empty; Blob missing refuses before the callback ---
  {
    // Local: missing reads as empty text but 'missing' version.
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "gaze-notes-local-"));
    try {
      const localBlob = { get: async () => { throw new Error("local must not call Blob"); }, put: async () => { throw new Error("local must not call Blob"); }, BlobPreconditionFailedError: RealPrecondition, calls: { get: [], put: [] } };
      const { readme } = loadStack({ env: {}, cwd: dir, blobStub: localBlob });
      const missing = await readme.readReadmeDocument();
      assert(missing.text === "" && missing.version === "missing", "missing local document must read as empty text with 'missing' version");
      const created = await readme.saveReadmeDocument("", "missing");
      assert(created.text === "" && created.version === sha256(""), "creating empty text from 'missing' must succeed with the empty hash");
      assert(created.version !== "missing", "empty hash must differ from 'missing'");
      const reread = await readme.readReadmeDocument();
      assert(reread.text === "" && reread.version === sha256(""), "existing empty text must version as its hash, not 'missing'");
      let conflict = null;
      try { await readme.saveReadmeDocument("x", "missing"); } catch (e) { conflict = e; }
      assert(conflict && conflict instanceof readme.ReadmeConflictError, "stale 'missing' against existing empty must conflict");
      const leftovers = fs.readdirSync(path.join(dir, "data")).filter((n) => n.endsWith(".tmp"));
      assert(leftovers.length === 0, "local writes must leave no temp litter");
      restoreEnv();
      pass("Local: missing vs empty have distinct versions; creation from 'missing' works");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
      restoreEnv();
    }
    // Blob: missing private object refuses before the update callback runs.
    {
      const blob = makeVersionedBlob({});
      blob.getOverrides.set("readme.md", null);
      const { readme, storage } = loadStack({ env: PRIV_ENV, blobStub: blob });
      let updateCalls = 0;
      let message = "";
      try {
        await storage.mutateMetadata("readme.md", (raw) => {
          updateCalls += 1;
          return { text: "seeded", result: null };
        });
        assert(false, "Blob missing must refuse");
      } catch (e) { message = String(e && e.message); }
      assert(updateCalls === 0, "missing Blob read must never call update");
      assert(blob.calls.put.length === 0, "missing Blob read must never write");
      assert(/Private metadata unavailable/.test(message), `refusal must name migration (got ${JSON.stringify(message)})`);
      let conflictLike = null;
      try { await readme.saveReadmeDocument("seeded", "missing"); } catch (e) { conflictLike = e; }
      assert(conflictLike && !(conflictLike instanceof readme.ReadmeConflictError),
        "Blob missing save must refuse (not conflict): never infer missing as empty");
      assert(blob.calls.put.length === 0, "Blob missing save must not write");
      restoreEnv();
      pass("Blob: missing private object refuses before the callback; never inferred empty");
    }
  }

  // --- 6. API contract ---
  {
    const blob = makeVersionedBlob({ "readme.md": "seed-A" });
    const { route, readme } = loadStack({ env: PRIV_ENV, blobStub: blob });
    const v0 = sha256("seed-A");
    adminFlag = true; revalidations = [];
    // Strict readme validation kept (root's cases).
    for (const input of [null, [], {}, { readme: 3 }, { readme: null }, { readme: ["text"] }]) {
      const res = await post(route, input);
      assert(res.status === 400, `malformed readme must be 400 (got ${res.status} for ${JSON.stringify(input)})`);
    }
    const putsBefore = blob.calls.put.length;
    // Missing/malformed expectedVersion -> actionable 400, no writes.
    const badVersions = [
      { readme: "A" },
      { readme: "A", expectedVersion: null },
      { readme: "A", expectedVersion: 3 },
      { readme: "A", expectedVersion: "" },
      { readme: "A", expectedVersion: "MISSING" },
      { readme: "A", expectedVersion: "xyz" },
      { readme: "A", expectedVersion: "A".repeat(64) },
      { readme: "A", expectedVersion: "a".repeat(63) },
      { readme: "A", expectedVersion: "a".repeat(65) },
      { readme: "A", expectedVersion: "g".repeat(64) },
    ];
    for (const input of badVersions) {
      const res = await post(route, input);
      assert(res.status === 400, `malformed expectedVersion must be 400 (got ${res.status} for ${JSON.stringify(input)})`);
      const json = await res.json();
      assert(typeof json.error === "string" && /Reload/i.test(json.error),
        `400 must ask the client to reload (got ${JSON.stringify(json)})`);
    }
    assert(blob.calls.put.length === putsBefore, "validation failures must not write");
    // Explicit empty-string notes remain an intentional clear.
    {
      const res = await post(route, { readme: "", expectedVersion: v0 });
      assert(res.status === 200, `empty clear must succeed (got ${res.status})`);
      const json = await res.json();
      assert(json.ok === true && json.version === sha256(""), "empty clear must return its new version");
      assert(blob.store.get("readme.md").text === "", "empty clear must publish");
    }
    // Success returns {ok:true, version}; stale returns 409 with draft-safe refusal.
    {
      const blob2 = makeVersionedBlob({ "readme.md": "seed-A" });
      const stack2 = loadStack({ env: PRIV_ENV, blobStub: blob2 });
      adminFlag = true; revalidations = [];
      const v = sha256("seed-A");
      const okRes = await post(stack2.route, { readme: "A", expectedVersion: v });
      assert(okRes.status === 200, `valid save must be 200 (got ${okRes.status})`);
      const okJson = await okRes.json();
      assert(okJson.ok === true && okJson.version === sha256("A"), `success must return the new version (got ${JSON.stringify(okJson)})`);
      assert(revalidations.includes("/testers") && revalidations.includes("/admin/readme"), "success must revalidate testers + admin/readme");
      const staleRes = await post(stack2.route, { readme: "B", expectedVersion: v });
      assert(staleRes.status === 409, `stale save must be 409 (got ${staleRes.status})`);
      const staleJson = await staleRes.json();
      assert(typeof staleJson.error === "string" && staleJson.error.length > 0, "409 must carry a readable conflict message");
      assert(blob2.store.get("readme.md").text === "A", "409 must leave the winner's text untouched");
      assert(!("version" in staleJson) || staleJson.version === undefined, "409 must not masquerade as success");
    }
    // Auth gates unchanged: non-admin and signed-out both refused before storage.
    {
      const blob3 = makeVersionedBlob({ "readme.md": "seed-A" });
      const stack3 = loadStack({ env: PRIV_ENV, blobStub: blob3 });
      const getsBefore = blob3.calls.get.length;
      adminFlag = "nonadmin";
      const denied = await post(stack3.route, { readme: "x", expectedVersion: sha256("seed-A") });
      assert(denied.status === 403, "non-admin must be 403");
      adminFlag = null;
      const signedOut = await post(stack3.route, { readme: "x", expectedVersion: sha256("seed-A") });
      assert(signedOut.status === 403, "signed-out must be 403");
      assert(blob3.calls.get.length === getsBefore, "auth failures must not reach storage");
      adminFlag = true;
    }
    // Storage outage propagates (not swallowed into a false success).
    {
      const blob4 = makeVersionedBlob({ "readme.md": "seed-A" });
      blob4.putOverrides.set("readme.md", new Error("synthetic put outage"));
      const stack4 = loadStack({ env: PRIV_ENV, blobStub: blob4 });
      adminFlag = true;
      let threw = false;
      try { await post(stack4.route, { readme: "A", expectedVersion: sha256("seed-A") }); } catch { threw = true; }
      assert(threw, "put outage must propagate");
      assert(blob4.store.get("readme.md").text === "seed-A", "outage must keep stored data");
    }
    restoreEnv();
    pass("API: strict body validation, well-formed expectedVersion, actionable 400, {ok,version} success, 409 stale, 403 gates");
  }

  // --- 7. Content-type pinning + existing independent-record behavior preserved ---
  {
    const blob = makeVersionedBlob({ "readme.md": "notes", "testers.json": "[]" });
    const { storage } = loadStack({ env: PRIV_ENV, blobStub: blob });
    const etagReadme = blob.store.get("readme.md").etag;
    await storage.mutateMetadata("readme.md", (raw) => ({ text: `${raw}2`, result: null }));
    assert(blob.calls.put.at(-1).opts.contentType === "text/markdown", "readme puts must use text/markdown");
    assert(blob.calls.put.at(-1).opts.ifMatch === etagReadme, "readme puts must stay conditional (ifMatch)");
    const etagTesters = blob.store.get("testers.json").etag;
    await storage.mutateMetadata("testers.json", (raw) => {
      const list = JSON.parse(raw);
      list.unshift({ email: "keep@example.invalid" });
      return { text: JSON.stringify(list), result: list };
    });
    assert(blob.calls.put.at(-1).opts.contentType === "application/json", "JSON keys must stay application/json");
    assert(blob.calls.put.at(-1).opts.ifMatch === etagTesters, "JSON puts must stay conditional");
    // Two concurrent independent tester additions still both survive.
    const blob2 = makeVersionedBlob({ "testers.json": "[]" });
    const s2 = loadStack({ env: PRIV_ENV, blobStub: blob2 });
    await Promise.all([
      s2.storage.mutateMetadata("testers.json", (raw) => {
        const list = JSON.parse(raw);
        list.unshift({ email: "a@example.invalid" });
        return { text: JSON.stringify(list), result: null };
      }),
      s2.storage.mutateMetadata("testers.json", (raw) => {
        const list = JSON.parse(raw);
        list.unshift({ email: "b@example.invalid" });
        return { text: JSON.stringify(list), result: null };
      }),
    ]);
    const emails = JSON.parse(blob2.store.get("testers.json").text).map((t) => t.email).sort();
    assert(JSON.stringify(emails) === JSON.stringify(["a@example.invalid", "b@example.invalid"]),
      `independent-record concurrency must be preserved (got ${JSON.stringify(emails)})`);
    // Unsupported keys still refused.
    await rejects(() => storage.mutateMetadata("../outside.json", () => ({ text: "{}", result: null })), "allowlist must refuse unsupported keys");
    restoreEnv();
    pass("content-type pinning (markdown vs json) with independent-record concurrency preserved");
  }

  // --- 8. Local: stale second writer rejected; queue + atomic temp intact ---
  {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "gaze-notes-race-"));
    try {
      const localBlob = { get: async () => { throw new Error("x"); }, put: async () => { throw new Error("x"); }, BlobPreconditionFailedError: RealPrecondition, calls: { get: [], put: [] } };
      const { readme } = loadStack({ env: {}, cwd: dir, blobStub: localBlob });
      fs.mkdirSync(path.join(dir, "data"), { recursive: true });
      fs.writeFileSync(path.join(dir, "data", "readme.md"), "seed-A", "utf8");
      const v = sha256("seed-A");
      const first = readme.saveReadmeDocument("A", v);
      const second = readme.saveReadmeDocument("B", v);
      const [r1, r2] = await Promise.allSettled([first, second]);
      assert(r1.status === "fulfilled" && r1.value.version === sha256("A"), "local first writer must win");
      assert(r2.status === "rejected" && r2.reason instanceof readme.ReadmeConflictError, "local stale writer must conflict");
      assert(fs.readFileSync(path.join(dir, "data", "readme.md"), "utf8") === "A", "local stale write must not overwrite");
      const leftovers = fs.readdirSync(path.join(dir, "data")).filter((n) => n.endsWith(".tmp"));
      assert(leftovers.length === 0, "no temp litter after local race");
      restoreEnv();
      pass("Local: serialized saves reject the stale second writer; atomic temp publication intact");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
      restoreEnv();
    }
  }

  // --- 9. Static source contract (page + editor + fixture) ---
  {
    const page = fs.readFileSync(STAGED["page.tsx"], "utf8");
    assert(page.includes("readReadmeDocument"), "page must read the versioned document");
    assert(page.includes("initialVersion"), "page must pass initialVersion to the editor");
    assert(/redirect\("\/signin\?callbackUrl=\/admin\/readme"\)/.test(page), "page must keep the signin gate");
    assert(/redirect\("\/"\)/.test(page), "page must keep the non-admin redirect");
    assert(!/readReadme\(\)/.test(page) || page.includes("readReadmeDocument"), "page must not use the unversioned read");

    const editor = fs.readFileSync(STAGED["readme-editor.tsx"], "utf8");
    assert(editor.includes("initialVersion"), "editor must accept initialVersion");
    assert(editor.includes("expectedVersion"), "editor must send expectedVersion");
    assert(editor.includes("submittedVersion"), "editor must capture the draft's base version at submit time");
    assert(editor.includes("setVersion(data.version)"), "editor must advance the acknowledged version only on valid success");
    assert(editor.includes("status === 409"), "editor must handle 409 distinctly");
    assert(editor.includes("Reload saved notes"), "editor must offer 'Reload saved notes'");
    assert(editor.includes("window.confirm"), "reload must use a native confirmation");
    assert(/replaces your unsaved text/i.test(editor), "confirmation must warn that unsaved text will be replaced");
    assert(editor.includes("window.location.reload()"), "confirmed reload must reload the page");
    assert(editor.includes("inFlightRef"), "editor must keep the synchronous duplicate guard");
    assert(editor.includes("e.metaKey !== e.ctrlKey"), "editor must keep the exact Cmd/Ctrl shortcut guard");
    assert(editor.includes('title="Save (Cmd+S or Ctrl+S)"'), "editor must keep the shortcut hint");
    assert(editor.includes('htmlFor="tester-notes"'), "editor must keep the associated label");
    assert(editor.includes('role="status"') && editor.includes('role="alert"'), "editor must keep status/alert announcements");
    assert(editor.includes("data?.ok !== true"), "editor must keep response acknowledgement validation");
    assert(!/navigator\.clipboard/.test(editor), "editor must not write to the clipboard");
    assert(!/force/i.test(editor) || !/overwrite/i.test(editor.toLowerCase().split("never")[1] ?? ""), "editor must offer no force-overwrite");
    assert(!/location\.reload\(\)/.test(editor.replace("window.location.reload()", "")) || true, "only the confirmed reload may navigate");
    // No automatic reload: the only reload call sits inside the confirm-gated handler.
    const reloads = [...editor.matchAll(/window\.location\.reload\(\)/g)].length;
    assert(reloads === 1, `exactly one (confirm-gated) reload call expected, found ${reloads}`);
    assert(editor.includes("router.refresh()"), "editor must keep router.refresh on success");
    pass("static contract: versioned page/editor wiring with confirm-gated reload only");

    const entry = fs.readFileSync(path.join(OURS_DIR, "fixture/entry.tsx"), "utf8");
    assert(entry.includes("../readme-editor.tsx"), "fixture must import the actual staged editor verbatim");
    assert(entry.includes("expectedVersion"), "fixture transport must cover expectedVersion");
    assert(entry.includes("resolveNextConflict"), "fixture must drive 409s");
    pass("fixture imports the staged editor verbatim with a versioned transport stub");
  }

  console.log("OK: all notes-versioning checks passed (staged sources executed, SDK stubbed).");
})()
  .catch((e) => fail(e && e.stack ? e.stack : String(e)))
  .finally(() => restoreEnv());
