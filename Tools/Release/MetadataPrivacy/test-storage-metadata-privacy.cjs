#!/usr/bin/env node
// Private-metadata storage test for gaze-site src/lib/storage.ts +
// storage-metadata-privacy.patch.
//
// Loads the ACTUAL (patched) storage module with a stubbed `@vercel/blob`
// SDK and the real filesystem, and exercises read/write/error paths:
//   - local-disk mode (no Blob env): file round-trips, missing file => null.
//   - Blob mode with private store configured: every get/put pins
//     access:"private" + the private credential; reads return content,
//     writes forward key/contentType/options; get=>null yields null.
//   - Blob mode WITHOUT private config: every helper throws naming the
//     required vars, and the stubbed SDK is never called (no silent public
//     fallback).
//   - OIDC variant: BLOB_PRIVATE_STORE_ID alone is passed as storeId.
//   - scope: patch touches only src/lib/storage.ts; upload route and the
//     public-download allowlist keep their existing markers.
//
// No network, dev server, deployment, production data, or site edits. The
// website checkout is only read (original copied to a temp dir for patching).
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const child_process = require("child_process");
const Module = require("module");

const SITE_DIR = process.env.GAZE_SITE_DIR || "/Users/owencope/Developer/gaze-site";
const ORIG_STORAGE = path.join(SITE_DIR, "src/lib/storage.ts");
const PATCH_FILE = path.join(__dirname, "storage-metadata-privacy.patch");
const UPLOAD_ROUTE = path.join(SITE_DIR, "src/app/api/upload/route.ts");
const DOWNLOAD_LIB = path.join(SITE_DIR, "src/lib/release-download.ts");
const currentSource = process.argv.includes("--current");
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

assert(fs.existsSync(ORIG_STORAGE), `original storage.ts not found: ${ORIG_STORAGE}`);
assert(fs.existsSync(PATCH_FILE), `patch not found: ${PATCH_FILE}`);

// --- 0. Patch scope: storage.ts only; public upload/download paths untouched. ---
{
  const patch = fs.readFileSync(PATCH_FILE, "utf8");
  const touched = [...patch.matchAll(/^\+\+\+ b\/(.+)$/gm)].map((m) => m[1]);
  assert(
    JSON.stringify(touched.sort()) === JSON.stringify(["src/lib/roles.ts", "src/lib/storage.ts", "src/lib/store.ts", "src/lib/testers.ts"]),
    `patch must touch storage and its three mutation callers, got ${JSON.stringify(touched)}`,
  );
  pass("patch covers private storage and strict mutation reads");
  const upload = fs.readFileSync(UPLOAD_ROUTE, "utf8");
  assert(upload.includes("handleUpload"), "upload route lost its client-upload handler");
  assert(upload.includes("onBeforeGenerateToken"), "upload route lost its admin token gate");
  const dl = fs.readFileSync(DOWNLOAD_LIB, "utf8");
  assert(
    dl.includes("public\\.blob\\.vercel-storage\\.com"),
    "public download hostname allowlist changed",
  );
  pass("public upload route + HTTPS download allowlist markers intact (out of scope)");
}

// --- 1. Stage original in a temp tree and apply the patch there (site stays read-only). ---
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "gaze-metadata-privacy-"));
process.on("exit", () => fs.rmSync(tmp, { recursive: true, force: true }));
const staged = path.join(tmp, "src/lib/storage.ts");
fs.mkdirSync(path.dirname(staged), { recursive: true });
fs.copyFileSync(ORIG_STORAGE, staged);
for (const name of ["store.ts", "roles.ts", "testers.ts"]) {
  fs.copyFileSync(path.join(SITE_DIR, "src/lib", name), path.join(tmp, "src/lib", name));
}
if (!currentSource) {
  const applied = child_process.spawnSync(
    "patch",
    ["--batch", "--forward", "--fuzz=0", "-p1", "--quiet", "-i", PATCH_FILE],
    { cwd: tmp, stdio: ["ignore", "pipe", "pipe"] },
  );
  if (applied.status !== 0) {
    fail(`patch did not apply cleanly: ${applied.stderr.toString().trim()}`);
  }
}
assert(fs.existsSync(staged), "staged storage.ts missing");
const patchedSrc = fs.readFileSync(staged, "utf8");
assert(!patchedSrc.includes('access: "public"'), "patched source still uses public access");
assert(patchedSrc.includes('access: "private"'), "patched source has no private access");
assert(
  patchedSrc.includes("BLOB_PRIVATE_READ_WRITE_TOKEN") &&
    patchedSrc.includes("BLOB_PRIVATE_STORE_ID"),
  "patched source must name the private-store credential explicitly",
);
assert(
  patchedSrc.includes("BLOB_READ_WRITE_TOKEN") && patchedSrc.includes("BLOB_STORE_ID"),
  "patched source must keep the existing public-store detection (usingBlob)",
);
pass(
  currentSource
    ? "testing the current website storage.ts"
    : "patch applies cleanly to a temp copy of storage.ts (fuzz=0)",
);

// --- 2. Transpile the staged TS with the site's installed TypeScript. ---
let ts;
try {
  ts = siteRequire("typescript");
} catch (e) {
  fail(`installed TypeScript not found under ${SITE_DIR}/node_modules: ${e.message}`);
}
let js;
try {
  js = ts.transpileModule(patchedSrc, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2020,
      esModuleInterop: true,
    },
    fileName: "storage.ts",
  }).outputText;
} catch (e) {
  fail(`transpile failed: ${e.message}`);
}
assert(js && js.includes("privateStoreOptions"), "transpiled storage has no private helper");

// --- 3. Loader: fresh module per scenario with stubbed @vercel/blob. ---
const BLOB_KEYS = [
  "BLOB_READ_WRITE_TOKEN",
  "BLOB_STORE_ID",
  "BLOB_PRIVATE_READ_WRITE_TOKEN",
  "BLOB_PRIVATE_STORE_ID", "VERCEL", "VERCEL_OIDC_TOKEN",
];
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
  process.chdir(origCwd);
}

function makeBlobStub() {
  const calls = { get: [], put: [] };
  // scripted get results by pathname; default is { statusCode: 200, text }.
  const stub = {
    calls,
    texts: new Map(), // pathname -> string body
    getResults: new Map(), // pathname -> full result | null | Error
    putErrors: new Map(), // pathname -> Error to throw
    get: async (pathname, opts) => {
      calls.get.push({ pathname, opts });
      if (stub.getResults.has(pathname)) {
        const r = stub.getResults.get(pathname);
        if (r instanceof Error) throw r;
        return r;
      }
      const text = stub.texts.has(pathname)
        ? stub.texts.get(pathname)
        : `{"stub":"${pathname}"}`;
      return { statusCode: 200, stream: toStream(text) };
    },
    put: async (pathname, body, opts) => {
      calls.put.push({ pathname, body, opts });
      if (stub.putErrors.has(pathname)) throw stub.putErrors.get(pathname);
      return { url: `https://stub/${pathname}`, pathname };
    },
  };
  return stub;
}

function toStream(text) {
  const bytes = new TextEncoder().encode(text);
  return new ReadableStream({
    start(c) {
      c.enqueue(bytes);
      c.close();
    },
  });
}

let loadN = 0;
function loadStorage({ env, cwd, blobStub }) {
  setEnv(env);
  if (cwd) process.chdir(cwd);
  const filename = `${staged}#load${loadN++}`;
  const m = new Module(filename, null);
  m.filename = staged;
  m.paths = Module._nodeModulePaths(path.dirname(staged));
  const localRequire = Module.createRequire(path.join(SITE_DIR, "package.json"));
  m.require = (request) => {
    if (request === "@vercel/blob") return blobStub;
    return localRequire(request);
  };
  m._compile(js, staged);
  return m.exports;
}

function assertPrivateOpts(opts, label, { expectToken = true, expectStoreId = false } = {}) {
  assert(opts && opts.access === "private", `${label}: expected access "private", got ${JSON.stringify(opts)}`);
  assert(opts.useCache === false || opts.useCache === undefined, `${label}: reads must bypass cache`);
  if (expectToken) {
    assert(opts.token === "private-token", `${label}: expected private token passthrough, got ${JSON.stringify(opts.token)}`);
  } else {
    assert(!("token" in opts) || opts.token === undefined, `${label}: unexpected token ${JSON.stringify(opts.token)}`);
  }
  if (expectStoreId) {
    assert(opts.storeId === "private-store-id", `${label}: expected private storeId passthrough, got ${JSON.stringify(opts.storeId)}`);
  }
}

async function rejects(operation, message) {
  let failed = false;
  try { await operation(); } catch { failed = true; }
  assert(failed, message);
}

const PRIV_ENV = {
  BLOB_READ_WRITE_TOKEN: "public-token",
  BLOB_PRIVATE_READ_WRITE_TOKEN: "private-token",
};

(async () => {
  // --- A. Local-disk mode: no Blob env at all. ---
  {
    const dataDir = path.join(tmp, "disk-fixture");
    fs.mkdirSync(dataDir);
    const store = loadStorage({ env: {}, cwd: dataDir, blobStub: makeBlobStub() });
    assert(store.usingBlob === false, "disk mode: usingBlob must be false");
    assert(store.usingPrivateMetadataStore === false, "disk mode: private flag must be false");
    assert((await store.readReleasesJson()) === null, "disk mode: missing releases => null");
    assert((await store.readJSON("settings.json")) === null, "disk mode: missing settings => null");
    await store.writeReleasesJson('[{"tag":"v0.1"}]\n');
    assert((await store.readReleasesJson()) === '[{"tag":"v0.1"}]\n', "disk mode: releases round-trip");
    await store.writeTestersJson('[{"email":"a@x.test"}]\n');
    assert((await store.readTestersJson()) === '[{"email":"a@x.test"}]\n', "disk mode: testers round-trip");
    await store.writeRolesJson('[{"id":"tester"}]\n');
    assert((await store.readRolesJson()) === '[{"id":"tester"}]\n', "disk mode: roles round-trip");
    await store.writeReadme("# hi\n");
    assert((await store.readReadme()) === "# hi\n", "disk mode: readme round-trip");
    await store.writeJSON("settings.json", { releasesRequireSignIn: true });
    assert(
      JSON.stringify(await store.readJSON("settings.json")) ===
        JSON.stringify({ releasesRequireSignIn: true }),
      "disk mode: generic settings round-trip",
    );
    fs.rmSync(dataDir, { recursive: true, force: true });
    restoreEnv();
    pass("local-disk mode preserved: round-trips + missing=>null, no Blob calls");
  }

  // --- B. Blob mode with private store: all 10 ops pin access:"private" + token. ---
  {
    const blob = makeBlobStub();
    blob.texts.set("releases.json", '[{"tag":"v0.2"}]');
    blob.texts.set("testers.json", '[{"email":"b@x.test"}]');
    blob.texts.set("readme.md", "# notes");
    blob.texts.set("roles.json", '[{"id":"tester"}]');
    blob.texts.set("settings.json", '{"releasesRequireSignIn":false}');
    const store = loadStorage({ env: PRIV_ENV, blobStub: blob });
    assert(store.usingBlob === true, "blob mode: usingBlob must be true");
    assert(store.usingPrivateMetadataStore === true, "blob mode: private flag must be true");

    assert((await store.readReleasesJson()) === '[{"tag":"v0.2"}]', "private: releases body");
    assert((await store.readTestersJson()) === '[{"email":"b@x.test"}]', "private: testers body");
    assert((await store.readReadme()) === "# notes", "private: readme body");
    assert((await store.readRolesJson()) === '[{"id":"tester"}]', "private: roles body");
    assert(
      JSON.stringify(await store.readJSON("settings.json")) ===
        JSON.stringify({ releasesRequireSignIn: false }),
      "private: generic settings parse",
    );
    for (const c of blob.calls.get) assertPrivateOpts(c.opts, `get ${c.pathname}`);
    const gotPaths = blob.calls.get.map((c) => c.pathname).sort();
    assert(
      JSON.stringify(gotPaths) ===
        JSON.stringify(["readme.md", "releases.json", "roles.json", "settings.json", "testers.json"]),
      `private: unexpected get pathnames ${JSON.stringify(gotPaths)}`,
    );
    for (const c of blob.calls.get) {
      assert(!("token" in c.opts) || c.opts.token === "private-token", "private: no public token leak in get");
    }

    await store.writeReleasesJson('[{"tag":"v0.3"}]');
    await store.writeTestersJson("[]");
    await store.writeReadme("# n");
    await store.writeRolesJson("[]");
    await store.writeJSON("settings.json", { releasesRequireSignIn: true });
    assert(blob.calls.put.length === 5, `private: expected 5 puts, got ${blob.calls.put.length}`);
    const puts = Object.fromEntries(blob.calls.put.map((c) => [c.pathname, c]));
    assert(puts["releases.json"].body === '[{"tag":"v0.3"}]', "private: releases write is verbatim");
    assert(puts["settings.json"].body === JSON.stringify({ releasesRequireSignIn: true }, null, 2), "private: generic write keeps 2-space JSON format");
    assert(puts["releases.json"].opts.contentType === "application/json", "private: releases contentType");
    assert(puts["readme.md"].opts.contentType === "text/markdown", "private: readme contentType");
    for (const c of blob.calls.put) {
      assertPrivateOpts(c.opts, `put ${c.pathname}`);
      assert(c.opts.addRandomSuffix === false, `put ${c.pathname}: must keep fixed pathname`);
      assert(c.opts.allowOverwrite === true, `put ${c.pathname}: must allow overwrite`);
      assert(!("token" in c.opts) || c.opts.token === "private-token", "private: no public token leak in put");
    }
    restoreEnv();
    pass("Blob+private mode: 5 reads + 5 writes all pinned to access:private with private token");
  }

  // --- C. Error paths: null / non-200 / SDK throw / unparseable. ---
  {
    const blob = makeBlobStub();
    blob.getResults.set("releases.json", null);
    blob.getResults.set("testers.json", { statusCode: 404, stream: null });
    blob.getResults.set("roles.json", new Error("boom"));
    blob.texts.set("settings.json", "not json{{{");
    const store = loadStorage({ env: PRIV_ENV, blobStub: blob });
    await rejects(() => store.readReleasesJson(), "missing private catalog must refuse");
    await rejects(() => store.readTestersJson(), "non-200 private response must refuse");
    let threw = false;
    try {
      await store.readRolesJson();
    } catch (e) {
      threw = /boom/.test(String(e && e.message));
    }
    assert(threw, "error: SDK failure must propagate, not become null");
    await rejects(() => store.readJSON("settings.json"), "corrupt private settings cannot default to public visibility");
    blob.getResults.delete("releases.json");
    blob.texts.set("releases.json", "[]");
    blob.putErrors.set("releases.json", new Error("put-boom"));
    let putThrew = false;
    const putCallsBefore = blob.calls.put.length;
    try {
      await store.writeReleasesJson("[]");
    } catch (e) {
      putThrew = true;
    }
    assert(putThrew, "error: put failure must propagate");
    assert(blob.calls.put.length === putCallsBefore + 1, "error: failing put still targeted the private store");
    assertPrivateOpts(blob.calls.put[blob.calls.put.length - 1].opts, "failing put");
    restoreEnv();
    pass("missing/non-200/corrupt private metadata and SDK failures refuse safely");
  }

  // --- D. Fail-closed: Blob mode with NO private config throws, SDK never called. ---
  {
    const blob = makeBlobStub();
    const store = loadStorage({ env: { BLOB_READ_WRITE_TOKEN: "public-token" }, blobStub: blob });
    assert(store.usingBlob === true, "fail-closed: usingBlob must be true on public token");
    assert(store.usingPrivateMetadataStore === false, "fail-closed: private flag must be false");
    const ops = [
      ["readReleasesJson", []],
      ["writeReleasesJson", ["[]"]],
      ["readTestersJson", []],
      ["writeTestersJson", ["[]"]],
      ["readReadme", []],
      ["writeReadme", ["# x"]],
      ["readRolesJson", []],
      ["writeRolesJson", ["[]"]],
      ["readJSON", ["settings.json"]],
      ["writeJSON", ["settings.json", {}]],
    ];
    for (const [name, args] of ops) {
      let msg = "";
      try {
        await store[name](...args);
      } catch (e) {
        msg = String(e && e.message);
      }
      assert(
        /BLOB_PRIVATE_READ_WRITE_TOKEN/.test(msg) && /BLOB_PRIVATE_STORE_ID/.test(msg),
        `${name}: must throw naming the private vars, got ${JSON.stringify(msg)}`,
      );
    }
    assert(
      blob.calls.get.length === 0 && blob.calls.put.length === 0,
      `fail-closed: SDK must never be called (get:${blob.calls.get.length} put:${blob.calls.put.length})`,
    );
    restoreEnv();
    pass("fail-closed: all 10 helpers throw without private config; zero public-store calls");
  }

  // --- E. OIDC variant: private storeId alone passes through, no token. ---
  {
    const blob = makeBlobStub();
    blob.texts.set("releases.json", "[]");
    const store = loadStorage({
      env: { BLOB_STORE_ID: "public-store", BLOB_PRIVATE_STORE_ID: "private-store-id", VERCEL_OIDC_TOKEN: "synthetic-oidc" },
      blobStub: blob,
    });
    assert(store.usingBlob === true, "oidc: usingBlob must be true");
    assert(store.usingPrivateMetadataStore === true, "oidc: private flag must be true");
    assert((await store.readReleasesJson()) === "[]", "oidc: read works");
    await store.writeReleasesJson("[]");
    assertPrivateOpts(blob.calls.get[0].opts, "oidc get", { expectToken: false, expectStoreId: true });
    assert(blob.calls.get[0].opts.oidcToken === "synthetic-oidc", "OIDC must be explicit to avoid public-token fallback");
    assertPrivateOpts(blob.calls.put[0].opts, "oidc put", { expectToken: false, expectStoreId: true });
    restoreEnv();
    pass("OIDC variant: BLOB_PRIVATE_STORE_ID passes as storeId with no static token");
  }

  {
    const blob = makeBlobStub(); blob.texts.set("releases.json", "[]");
    const store = loadStorage({ env: { BLOB_PRIVATE_READ_WRITE_TOKEN: "private-token" }, blobStub: blob });
    assert(store.usingBlob, "private-only configuration must never select disk");
    await store.readReleasesJson();
    assertPrivateOpts(blob.calls.get[0].opts, "private-only");
    restoreEnv();
    pass("private-only configuration uses private Blob");
  }
  for (const env of [{ VERCEL: "1" },
    { BLOB_READ_WRITE_TOKEN: "public-token", BLOB_PRIVATE_STORE_ID: "private-store-id" },
    { BLOB_READ_WRITE_TOKEN: "same", BLOB_PRIVATE_READ_WRITE_TOKEN: "same" }]) {
    const blob = makeBlobStub();
    const store = loadStorage({ env, blobStub: blob });
    await rejects(() => store.readReleasesJson(), "unsafe cloud configuration must refuse");
    assert(blob.calls.get.length === 0, "unsafe configuration must not reach Blob SDK");
    restoreEnv();
  }
  pass("Vercel missing config, missing OIDC and reused public credential refuse");
  {
    const blob = makeBlobStub(); blob.getResults.set("releases.json", null);
    const store = loadStorage({ env: PRIV_ENV, blobStub: blob });
    await rejects(() => store.writeReleasesJson("[]"), "ordinary writes cannot initialize an unmigrated private catalog");
    assert(blob.calls.put.length === 0, "no put after missing migrated data");
    restoreEnv();
    pass("missing migration refuses writes");
  }
  {
    let writes = 0;
    const failingStorage = {};
    for (const name of ["readReleasesJson", "readRolesJson", "readTestersJson"]) failingStorage[name] = async () => { throw new Error("synthetic read failure"); };
    for (const name of ["writeReleasesJson", "writeRolesJson", "writeTestersJson"]) failingStorage[name] = async () => { writes++; };
    const readers = {};
    for (const name of ["store", "roles", "testers"]) {
      const file = path.join(tmp, "src/lib", name + ".ts");
      const module = new Module(file, null);
      module.require = request => request === "@/lib/storage" ? failingStorage : request === "@/lib/permissions" ? { PERMISSIONS: {} } : siteRequire(request);
      module._compile(ts.transpileModule(fs.readFileSync(file, "utf8"), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText, file);
      readers[name] = module.exports;
    }
    await rejects(() => readers.store.upsert({ tag: "fixture" }), "release mutation must propagate read failure");
    await rejects(() => readers.testers.addTester({ email: "test@example.invalid" }), "tester mutation must propagate read failure");
    await rejects(() => readers.roles.removeRole("tester"), "role mutation must propagate read failure");
    assert((await readers.roles.readRoles()).length === 0, "unavailable roles must not grant default permissions");
    assert(writes === 0, "no partial-catalog writes after failed reads");
    failingStorage.readRolesJson = async () => "[]";
    assert((await readers.roles.readRoles()).length === 0, "an explicitly empty role list must stay empty");
    failingStorage.readReleasesJson = async () => "{}";
    await rejects(() => readers.store.upsert({ tag: "fixture" }), "malformed catalogs must not be overwritten");
    let catalog = JSON.stringify([{ tag: "0.1", date: "2026-01-01" }]);
    failingStorage.readReleasesJson = async () => catalog;
    failingStorage.writeReleasesJson = async (value) => { catalog = value; };
    await readers.store.upsert({ tag: "0.2", date: "2026-01-02" });
    assert(JSON.parse(catalog).length === 2 && JSON.parse(catalog).some((release) => release.tag === "0.1"),
      "a successful strict read preserves the existing catalog on update");
    pass("all three mutation callers refuse failed reads; role lookup fails closed");
  }

  console.log("OK: all metadata-privacy storage checks passed (patched source executed, SDK stubbed).");
})()
  .catch((e) => fail(e && e.stack ? e.stack : String(e)))
  .finally(() => restoreEnv());
