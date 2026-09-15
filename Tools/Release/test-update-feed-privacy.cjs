#!/usr/bin/env node
// Privacy gate test for gaze-site src/app/api/latest/route.ts + update-feed-privacy.patch.
// Loads the ACTUAL patched route (original + patch applied in a temp dir) with stubbed
// "@/lib/store" and "@/lib/settings"; NextResponse is real. No filter/sort logic is duplicated.
// Covers: hidden=>no readAll + {latest:null}, public eligible (numeric order + draft/private
// filtering), only draft/private=>null, empty=>null, Cache-Control: no-store on every branch.
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const child_process = require("child_process");
const Module = require("module");

const SITE_DIR = process.env.GAZE_SITE_DIR || "/Users/owencope/Developer/gaze-site";
const ORIG_ROUTE = path.join(SITE_DIR, "src/app/api/latest/route.ts");
const PATCH_FILE = path.join(__dirname, "update-feed-privacy.patch");
const currentRoute = process.argv.includes("--current");
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

assert(fs.existsSync(ORIG_ROUTE), `original route not found: ${ORIG_ROUTE}`);
assert(fs.existsSync(PATCH_FILE), `patch not found: ${PATCH_FILE}`);

// --- 1. Stage original in a temp repo-shaped tree and apply the patch there (read-only site). ---
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "gaze-feed-privacy-"));
process.on("exit", () => fs.rmSync(tmp, { recursive: true, force: true }));
const staged = path.join(tmp, "src/app/api/latest/route.ts");
fs.mkdirSync(path.dirname(staged), { recursive: true });
fs.copyFileSync(ORIG_ROUTE, staged);
if (!currentRoute) {
  const applied = child_process.spawnSync("patch", ["--batch", "--forward", "--fuzz=0", "-p1", "--quiet", "-i", PATCH_FILE], {
    cwd: tmp,
    stdio: ["ignore", "pipe", "pipe"],
  });
  if (applied.status !== 0) {
    fail(`patch did not apply cleanly: ${applied.stderr.toString().trim()}`);
  }
}
assert(fs.existsSync(staged), "patched route missing after patch");
const patchedSrc = fs.readFileSync(staged, "utf8");
assert(patchedSrc.includes("@/lib/settings"), "patched route does not import getSettings");
assert(patchedSrc.includes("releasesRequireSignIn"), "patched route missing visibility gate");
pass(currentRoute ? "testing the current website route" : "patch applies cleanly to a temp copy of the route");

// --- 2. Transpile the patched TS with the site's installed TypeScript (no network). ---
let ts;
try {
  ts = require(path.join(SITE_DIR, "node_modules/typescript"));
} catch (e) {
  fail(`installed TypeScript not found under ${SITE_DIR}/node_modules: ${e.message}`);
}
const js = ts.transpileModule(patchedSrc, {
  compilerOptions: {
    module: ts.ModuleKind.CommonJS,
    target: ts.ScriptTarget.ES2020,
    esModuleInterop: true,
  },
  fileName: "route.ts",
}).outputText;
assert(js && js.includes("GET"), "transpiled route has no GET");

// --- 3. Load it with controlled fakes (no dev server, no network). ---
let currentGate = false;
let currentData = [];
let readAllCalls = 0;
const fakeStore = {
  readAll: async () => {
    readAllCalls++;
    return JSON.parse(JSON.stringify(currentData));
  },
};
const fakeSettings = {
  getSettings: async () => ({ releasesRequireSignIn: currentGate }),
};
const nextServer = siteRequire("next/server");
const m = new Module(staged, null);
m.filename = staged;
m.paths = Module._nodeModulePaths(path.dirname(staged));
m.require = (request) => {
  if (request === "next/server") return nextServer;
  if (request === "@/lib/store") return fakeStore;
  if (request === "@/lib/settings") return fakeSettings;
  return siteRequire(request);
};
m._compile(js, staged);
const route = m.exports;
assert(route && typeof route.GET === "function", "patched route exports no GET()");

function checkNoStore(res, label) {
  const cc = res.headers.get("cache-control");
  assert(cc === "no-store", `${label}: expected Cache-Control "no-store", got ${JSON.stringify(cc)}`);
}

function mkRelease(tag, opts = {}) {
  return {
    tag,
    name: `Gaze ${tag}`,
    date: "2026-09-01",
    body: `notes ${tag}`,
    images: [],
    videos: [],
    contributors: [],
    prerelease: false,
    draft: false,
    ...opts,
  };
}

(async () => {
  // 1) Hidden releases: gate on => {latest:null}, 200, and readAll never called.
  currentGate = true;
  currentData = [mkRelease("0.10", { download: { url: "https://gazeunlock.com/dl/Gaze-0.10.dmg", name: "Gaze-0.10.dmg", size: 1 } })];
  readAllCalls = 0;
  {
    const res = await route.GET();
    const body = await res.json();
    assert(res.status === 200, "hidden: expected HTTP 200");
    assert(body && body.latest === null, `hidden: expected {latest:null}, got ${JSON.stringify(body)}`);
    assert(readAllCalls === 0, `hidden: readAll called ${readAllCalls}x, expected 0 (gate must precede fetch)`);
    checkNoStore(res, "hidden");
    pass("hidden releases => 200 {latest:null} with zero readAll calls");
  }

  // 2) Public eligible: numeric order + draft/private/prerelease handling preserved.
  currentGate = false;
  currentData = [
    mkRelease("0.9"),
    mkRelease("0.10", { download: { url: "https://gazeunlock.com/dl/Gaze-0.10.dmg", name: "Gaze-0.10.dmg", size: 42 } }),
    mkRelease("0.12", { prerelease: true }),
    mkRelease("9.9", { draft: true }),
    mkRelease("9.8", { private: true }),
  ];
  readAllCalls = 0;
  {
    const res = await route.GET();
    const body = await res.json();
    assert(res.status === 200, "public: expected HTTP 200");
    assert(body && body.latest && body.latest.tag === "0.10",
      `public: expected latest.tag "0.10" (numeric 0.10>0.9, draft 9.9/private 9.8 excluded, prerelease 0.12 deferred), got ${JSON.stringify(body)}`);
    assert(body.latest.notes === "notes 0.10", "public: notes must carry stored body");
    assert(body.latest.prerelease === false, "public: prerelease flag must pass through");
    assert(body.latest.download && body.latest.download.url === "https://gazeunlock.com/dl/Gaze-0.10.dmg",
      "public: download must pass through");
    assert(readAllCalls === 1, `public: expected exactly 1 readAll call, got ${readAllCalls}`);
    checkNoStore(res, "public");
    pass('public eligible => newest stable "0.10" (numeric order, filters preserved)');
  }

  // 3) Only draft/private => {latest:null}.
  currentGate = false;
  currentData = [mkRelease("9.9", { draft: true }), mkRelease("9.8", { private: true })];
  {
    const res = await route.GET();
    const body = await res.json();
    assert(res.status === 200, "draft/private-only: expected HTTP 200");
    assert(body && body.latest === null, `draft/private-only: expected {latest:null}, got ${JSON.stringify(body)}`);
    checkNoStore(res, "draft/private-only");
    pass("only draft/private data => 200 {latest:null}");
  }

  // 4) Empty store => {latest:null}.
  currentGate = false;
  currentData = [];
  {
    const res = await route.GET();
    const body = await res.json();
    assert(res.status === 200, "empty: expected HTTP 200");
    assert(body && body.latest === null, `empty: expected {latest:null}, got ${JSON.stringify(body)}`);
    checkNoStore(res, "empty");
    pass("empty data => 200 {latest:null}");
  }

  currentGate = true;
  currentData = [mkRelease("0.10")];
  readAllCalls = 0;
  const restrictedAgain = await route.GET();
  assert((await restrictedAgain.json()).latest === null && readAllCalls === 0,
    "a visibility change must be re-read on the next request");
  checkNoStore(restrictedAgain, "restricted again");
  pass("visibility changes take effect on the next request; all response branches use no-store");

  console.log("OK: all update-feed privacy checks passed (patched route executed, logic not duplicated).");
})().catch((e) => fail(e && e.stack ? e.stack : String(e)));
