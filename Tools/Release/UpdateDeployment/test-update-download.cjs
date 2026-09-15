#!/usr/bin/env node
// Same-origin download test for gaze-site src/app/dl/[file]/route.ts +
// the /api/latest feedDownload mapping (Tools/Release/UpdateDeployment/update-download.patch).
// Stages the patch in a temp dir (site checkout untouched), transpiles the ACTUAL route
// sources with the site's installed TypeScript, and executes GET() with the installed real
// next/server and stubbed "@/lib/store" / "@/lib/settings". No logic duplicated: eligibility,
// name matching, redirect targets and feed mapping all live in the routes. No network,
// dev server, deployment, or site edits.
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const child_process = require("child_process");
const Module = require("module");

const SITE_DIR = process.env.GAZE_SITE_DIR || "/Users/owencope/Developer/gaze-site";
const ORIG_FEED = path.join(SITE_DIR, "src/app/api/latest/route.ts");
const SITE_DL = path.join(SITE_DIR, "src/app/dl/[file]/route.ts");
const PATCH_FILE = path.join(__dirname, "update-download.patch");
const currentMode = process.argv.includes("--current");
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

assert(fs.existsSync(ORIG_FEED), `feed route not found: ${ORIG_FEED}`);
assert(fs.existsSync(PATCH_FILE), `patch not found: ${PATCH_FILE}`);

// --- 1. Stage the patch in a temp tree (read-only site) or read current files. ---
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "gaze-dl-"));
process.on("exit", () => fs.rmSync(tmp, { recursive: true, force: true }));

let feedSrc;
let dlSrc;
if (!currentMode) {
  const staged = path.join(tmp, "src/app/api/latest/route.ts");
  fs.mkdirSync(path.dirname(staged), { recursive: true });
  fs.copyFileSync(ORIG_FEED, staged);
  const applied = child_process.spawnSync(
    "patch",
    ["--batch", "--forward", "--fuzz=0", "-p1", "--quiet", "-i", PATCH_FILE],
    { cwd: tmp, stdio: ["ignore", "pipe", "pipe"] },
  );
  if (applied.status !== 0) {
    fail(`patch did not apply cleanly: ${applied.stderr.toString().trim()}`);
  }
  const stagedDL = path.join(tmp, "src/app/dl/[file]/route.ts");
  assert(fs.existsSync(stagedDL), "patch did not create src/app/dl/[file]/route.ts");
  feedSrc = fs.readFileSync(staged, "utf8");
  dlSrc = fs.readFileSync(stagedDL, "utf8");
  pass("patch applies cleanly to a temp copy (feed mapped, dl route created)");
} else {
  assert(fs.existsSync(SITE_DL), `download route not found (patch not applied to site?): ${SITE_DL}`);
  feedSrc = fs.readFileSync(ORIG_FEED, "utf8");
  dlSrc = fs.readFileSync(SITE_DL, "utf8");
  pass("testing the current website routes");
}

assert(feedSrc.includes("feedDownload"), "feed route has no feedDownload mapping");
assert(
  !/download:\s*latest\.download\s*\?\?\s*null/.test(feedSrc),
  "feed still advertises the stored URL verbatim",
);
assert(dlSrc.includes("releasesRequireSignIn"), "dl route missing visibility gate");
assert(!dlSrc.includes("max-age") && !dlSrc.includes("s-maxage"), "dl route must not set a cacheable lifetime");
assert(dlSrc.includes("status: 302"), "dl route must redirect temporarily (302), not permanently");

// --- 2. Transpile the actual sources with the site's installed TypeScript. ---
let ts;
try {
  ts = require(path.join(SITE_DIR, "node_modules/typescript"));
} catch (e) {
  fail(`installed TypeScript not found under ${SITE_DIR}/node_modules: ${e.message}`);
}

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

function load(src, fakeName) {
  const js = ts.transpileModule(src, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2020,
      esModuleInterop: true,
    },
    fileName: fakeName,
  }).outputText;
  const m = new Module(fakeName, null);
  m.filename = fakeName;
  m.paths = Module._nodeModulePaths(path.dirname(fakeName));
  m.require = (request) => {
    if (request === "next/server") return nextServer;
    if (request === "@/lib/store") return fakeStore;
    if (request === "@/lib/settings") return fakeSettings;
    return siteRequire(request);
  };
  m._compile(js, fakeName);
  return m.exports;
}

const feed = load(feedSrc, path.join(tmp, "feed-route.ts"));
const dl = load(dlSrc, path.join(tmp, "dl-route.ts"));
assert(feed && typeof feed.GET === "function", "feed route exports no GET()");
assert(dl && typeof dl.GET === "function", "dl route exports no GET()");

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

const BLOB_010 = "https://abc123.public.blob.vercel-storage.com/Gaze-0.10-x7q.dmg";
const BLOB_011 = "https://abc123.public.blob.vercel-storage.com/Gaze-0.11-z9k.dmg";
const dlReq = (p) => new Request(`https://gazeunlock.com${p}`);
// Every failure mode must answer identically: no oracle for unreleased versions.
const bodies404 = new Set();

async function expectMissing(label, reqPath) {
  const res = await dl.GET(dlReq(reqPath));
  assert(res.status === 404, `${label}: expected HTTP 404, got ${res.status}`);
  const body = await res.json();
  assert(body && body.error === "Not found", `${label}: unexpected 404 body ${JSON.stringify(body)}`);
  bodies404.add(JSON.stringify(body));
  checkNoStore(res, label);
  assert(res.headers.get("location") === null, `${label}: a miss must not redirect`);
  return res;
}

(async () => {
  // 1) Public Blob-backed build => 302 to the stored URL, never cached.
  currentGate = false;
  currentData = [
    mkRelease("0.10", { download: { url: BLOB_010, name: "Gaze-0.10.dmg", size: 42 } }),
  ];
  readAllCalls = 0;
  {
    const res = await dl.GET(dlReq("/dl/Gaze-0.10.dmg"));
    assert(res.status === 302, `public: expected HTTP 302, got ${res.status}`);
    assert(res.headers.get("location") === BLOB_010,
      `public: expected Location ${BLOB_010}, got ${res.headers.get("location")}`);
    checkNoStore(res, "public");
    assert(readAllCalls === 1, `public: expected exactly 1 readAll call, got ${readAllCalls}`);
    pass("public Blob-backed build => 302 to the stored URL with no-store");
  }

  // 2) Restricted releases => miss before any fetch, even for a real file.
  currentGate = true;
  readAllCalls = 0;
  {
    await expectMissing("restricted", "/dl/Gaze-0.10.dmg");
    assert(readAllCalls === 0, `restricted: readAll called ${readAllCalls}x, expected 0 (gate must precede fetch)`);
    pass("restricted releases => 404 with zero readAll calls");
  }
  currentGate = false;

  // 3) Private (tester-only) match => miss.
  currentData = [
    mkRelease("0.10", { private: true, download: { url: BLOB_010, name: "Gaze-0.10.dmg", size: 42 } }),
  ];
  await expectMissing("private-only", "/dl/Gaze-0.10.dmg");
  pass("private tester-only build => 404");

  // 4) Draft match => miss.
  currentData = [
    mkRelease("0.10", { draft: true, download: { url: BLOB_010, name: "Gaze-0.10.dmg", size: 42 } }),
  ];
  await expectMissing("draft", "/dl/Gaze-0.10.dmg");
  pass("draft build => 404");

  // 5) Unknown file => miss.
  currentData = [
    mkRelease("0.10", { download: { url: BLOB_010, name: "Gaze-0.10.dmg", size: 42 } }),
  ];
  await expectMissing("unknown file", "/dl/Gaze-9.9.dmg");
  pass("unknown filename => 404");

  // 6) Same-origin placeholder with no bytes (the seed 0.3 shape) => miss, never a loop.
  currentData = [
    mkRelease("0.3", { download: { url: "https://gazeunlock.com/dl/Gaze-0.3.dmg", name: "Gaze-0.3.dmg", size: 18300000 } }),
  ];
  await expectMissing("placeholder self-URL", "/dl/Gaze-0.3.dmg");
  pass("same-origin placeholder without backing bytes => 404, not a redirect loop");

  // 7) Non-http(s) stored target => miss (defense in depth; the write API already rejects these).
  currentData = [
    mkRelease("0.10", { download: { url: "javascript:alert(1)", name: "Gaze-0.10.dmg", size: 42 } }),
  ];
  await expectMissing("non-http target", "/dl/Gaze-0.10.dmg");
  pass("non-http stored target => 404");

  // 8) Two eligible releases claiming one filename => miss rather than a guess.
  currentData = [
    mkRelease("0.10", { download: { url: BLOB_010, name: "Gaze.dmg", size: 42 } }),
    mkRelease("0.11", { download: { url: BLOB_011, name: "Gaze.dmg", size: 43 } }),
  ];
  await expectMissing("ambiguous filename", "/dl/Gaze.dmg");
  pass("ambiguous filename => 404 instead of serving one of two builds");

  // 9) Prerelease builds are servable: the feed may offer one, the route must not second-guess.
  currentData = [
    mkRelease("0.12", { prerelease: true, download: { url: BLOB_011, name: "Gaze-0.12.dmg", size: 44 } }),
  ];
  {
    const res = await dl.GET(dlReq("/dl/Gaze-0.12.dmg"));
    assert(res.status === 302, `prerelease: expected HTTP 302, got ${res.status}`);
    assert(res.headers.get("location") === BLOB_011, "prerelease: wrong redirect target");
    checkNoStore(res, "prerelease");
    pass("eligible prerelease build => 302 (eligibility is draft/private/visibility only)");
  }

  // 10) Path handling: empty, dots, encoded dots, nesting all miss.
  currentData = [
    mkRelease("0.10", { download: { url: BLOB_010, name: "Gaze-0.10.dmg", size: 42 } }),
  ];
  await expectMissing("bare /dl/", "/dl/");
  await expectMissing("dot segment", "/dl/.");
  await expectMissing("dot-dot segment", "/dl/..");
  await expectMissing("encoded dot-dot", "/dl/%2E%2E");
  await expectMissing("nested path", "/dl/a/Gaze-0.10.dmg");
  pass("empty/dot/encoded/nested paths => 404");

  // 11) All miss bodies identical: the route is not an oracle.
  assert(bodies404.size === 1, `miss bodies differ across failure modes: ${[...bodies404].join(" | ")}`);
  pass("every failure mode answers the identical 404 body (no draft/private oracle)");

  // 12) Feed advertises the same-origin redirect, not the Blob URL.
  currentGate = false;
  currentData = [
    mkRelease("0.9"),
    mkRelease("0.10", { download: { url: BLOB_010, name: "Gaze-0.10.dmg", size: 42 } }),
    mkRelease("0.11", { download: { url: BLOB_011, name: "Gaze 0.11.dmg", size: 43 } }),
    mkRelease("0.12", { prerelease: true }),
    mkRelease("9.9", { draft: true }),
    mkRelease("9.8", { private: true }),
  ];
  {
    const res = await feed.GET();
    const body = await res.json();
    assert(res.status === 200, "feed: expected HTTP 200");
    assert(body && body.latest && body.latest.tag === "0.11",
      `feed: expected latest.tag "0.11", got ${JSON.stringify(body)}`);
    assert(body.latest.download && body.latest.download.url === "https://gazeunlock.com/dl/Gaze%200.11.dmg",
      `feed: expected same-origin encoded download URL, got ${JSON.stringify(body.latest.download)}`);
    assert(body.latest.download.name === "Gaze 0.11.dmg" && body.latest.download.size === 43,
      "feed: download name/size must pass through");
    checkNoStore(res, "feed");
    pass('feed maps stored Blob URL to same-origin https://gazeunlock.com/dl/<name> (encoded)');
  }

  // 13) Feed round-trip: the advertised URL resolves through the dl route.
  {
    const res = await dl.GET(dlReq("/dl/Gaze%200.11.dmg"));
    assert(res.status === 302, `round-trip: expected HTTP 302, got ${res.status}`);
    assert(res.headers.get("location") === BLOB_011, "round-trip: wrong redirect target");
    pass("advertised feed URL resolves through the dl route to the stored build");
  }

  // 14) Feed: release without a build, and build without a usable name, offer no download.
  currentData = [mkRelease("0.3")];
  {
    const body = await (await feed.GET()).json();
    assert(body.latest && body.latest.download === null,
      `feed: expected download null for build-less release, got ${JSON.stringify(body)}`);
  }
  currentData = [mkRelease("0.3", { download: { url: BLOB_010, name: "", size: 42 } })];
  {
    const body = await (await feed.GET()).json();
    assert(body.latest && body.latest.download === null,
      `feed: expected download null for nameless build, got ${JSON.stringify(body)}`);
    pass("feed offers download:null rather than a fabricated URL when no usable filename exists");
  }

  // 15) Feed restricted branch still gated before fetch (self-contained re-check after edit).
  currentGate = true;
  currentData = [mkRelease("0.10", { download: { url: BLOB_010, name: "Gaze-0.10.dmg", size: 42 } })];
  readAllCalls = 0;
  {
    const res = await feed.GET();
    const body = await res.json();
    assert(res.status === 200 && body && body.latest === null, "feed restricted: expected 200 {latest:null}");
    assert(readAllCalls === 0, "feed restricted: readAll must not be called");
    checkNoStore(res, "feed restricted");
    pass("feed visibility gate intact after mapping edit (restricted => null, zero reads, no-store)");
  }

  console.log("OK: all same-origin download checks passed (patched routes executed, logic not duplicated).");
})().catch((e) => fail(e && e.stack ? e.stack : String(e)));
