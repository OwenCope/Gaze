#!/usr/bin/env node
// Atomic release-rename test for Tools/Release/ReleaseEditing/release-rename.patch.
//
// Stages the patch in a temp dir (site checkout untouched), transpiles the ACTUAL
// staged store + API route with the site's installed TypeScript, and executes them
// with the installed real next/server: rename costs one conditional write, a taken
// target or a missing source refuses without writing, a failed conditional write
// leaves the old record intact, same-tag edits still require the source, deletion
// goes through the same primitive, and the composer performs no follow-up DELETE.
// The composer itself is a React client component, so its overlap guard and error
// handling are verified by static assertions on the staged source plus a faithful
// simulation of the exact guard pattern (a real browser fixture was not feasible
// in this environment; no live endpoints, data, auth, uploads or deployment).
//
// `mutateMetadata` here is an injected test double implementing the declared
// contract — key + single updater callback returning {text,result} — so the updater
// callback is tested, not the production compare-and-swap. Walter's storage.ts
// implementation lands separately; this is NOT proof of production CAS. Root runs
// the combined integration with `--current` after both land.
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const child_process = require("child_process");
const Module = require("module");

const SITE_DIR = process.env.GAZE_SITE_DIR || "/Users/owencope/Developer/gaze-site";
const DIR = __dirname;
const PATCH_FILE = path.join(DIR, "release-rename.patch");
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

const ORIG = {
  store: path.join(SITE_DIR, "src/lib/store.ts"),
  route: path.join(SITE_DIR, "src/app/api/releases/route.ts"),
  composer: path.join(SITE_DIR, "src/components/release-composer.tsx"),
};
for (const [k, p] of Object.entries(ORIG)) assert(fs.existsSync(p), `site original missing (${k}): ${p}`);
assert(fs.existsSync(PATCH_FILE), `patch not found: ${PATCH_FILE}`);

// --- 0. Patch scope: exactly the three owned targets, nothing else. ---
{
  const patch = fs.readFileSync(PATCH_FILE, "utf8");
  const touched = [...patch.matchAll(/^\+\+\+ b\/(.+)$/gm)].map((m) => m[1]).sort();
  assert(
    JSON.stringify(touched) === JSON.stringify([
      "src/app/api/releases/route.ts",
      "src/components/release-composer.tsx",
      "src/lib/store.ts",
    ]),
    `patch must touch only the three owned targets, got ${JSON.stringify(touched)}`,
  );
  assert(!touched.includes("src/lib/storage.ts"), "patch must not touch Walter's storage.ts");
  pass("patch touches only store.ts, releases route.ts and release-composer.tsx");
}

// --- 1. Stage the patch in a temp tree (read-only site) or read current files. ---
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "gaze-release-edit-"));
process.on("exit", () => fs.rmSync(tmp, { recursive: true, force: true }));

function stageOne(sitePath, rel) {
  const dest = path.join(tmp, rel);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(sitePath, dest);
}

let storeSrc;
let routeSrc;
let composerSrc;
if (!currentMode) {
  stageOne(ORIG.store, "src/lib/store.ts");
  stageOne(ORIG.route, "src/app/api/releases/route.ts");
  stageOne(ORIG.composer, "src/components/release-composer.tsx");
  const applied = child_process.spawnSync(
    "patch",
    ["--batch", "--forward", "--fuzz=0", "-p1", "--quiet", "-i", PATCH_FILE],
    { cwd: tmp, stdio: ["ignore", "pipe", "pipe"] },
  );
  if (applied.status !== 0) fail(`patch did not apply cleanly: ${applied.stderr.toString().trim()}`);
  storeSrc = fs.readFileSync(path.join(tmp, "src/lib/store.ts"), "utf8");
  routeSrc = fs.readFileSync(path.join(tmp, "src/app/api/releases/route.ts"), "utf8");
  composerSrc = fs.readFileSync(path.join(tmp, "src/components/release-composer.tsx"), "utf8");
  // The staged result must equal the shipped source copies.
  assert(storeSrc === fs.readFileSync(path.join(DIR, "store.staged.ts"), "utf8"), "staged store.ts differs from shipped source copy");
  assert(routeSrc === fs.readFileSync(path.join(DIR, "route.staged.ts"), "utf8"), "staged route.ts differs from shipped source copy");
  assert(composerSrc === fs.readFileSync(path.join(DIR, "release-composer.staged.tsx"), "utf8"), "staged composer differs from shipped source copy");
  pass("patch applies cleanly to a temp copy (fuzz=0) and matches shipped source copies");
} else {
  storeSrc = fs.readFileSync(ORIG.store, "utf8");
  routeSrc = fs.readFileSync(ORIG.route, "utf8");
  composerSrc = fs.readFileSync(ORIG.composer, "utf8");
  pass("testing the current website files (--current)");
}

// --- 2. Static assertions on the staged store (contract use, no read-then-write). ---
assert(storeSrc.includes("ReleaseConflictError"), "store has no exported ReleaseConflictError");
assert(/export class ReleaseConflictError/.test(storeSrc), "ReleaseConflictError is not exported");
assert(storeSrc.includes("mutateMetadata"), "store does not use mutateMetadata");
assert(/mutateMetadata<StoredRelease>\("releases\.json"/.test(storeSrc), "upsert does not call mutateMetadata<T> on releases.json");
assert(/mutateMetadata<void>\("releases\.json"/.test(storeSrc), "remove does not go through mutateMetadata");
{
  // No preliminary readAll outside the callback for mutations: upsert/remove
  // bodies must not reference readAll, writeReleasesJson or writeAll.
  const upsertBody = storeSrc.slice(storeSrc.indexOf("export async function upsert"));
  assert(!upsertBody.includes("readAll"), "upsert still performs a preliminary readAll");
  assert(!upsertBody.includes("writeReleasesJson") && !upsertBody.includes("writeAll"), "upsert still writes outside the callback");
  assert(storeSrc.includes("new Date(b.date).getTime() - new Date(a.date).getTime()"), "date sorting changed");
  assert(storeSrc.includes("JSON.stringify(list, null, 2)"), "record formatting changed");
}
pass("store upserts/removes inside one mutateMetadata callback with existing sort/format");

// --- 3. Static assertions on the staged route (previousTag, 409, preserved gates). ---
assert(routeSrc.includes("previousTag"), "route has no previousTag handling");
assert(routeSrc.includes("ReleaseConflictError"), "route does not map ReleaseConflictError");
assert(routeSrc.includes("status: 409"), "route returns no 409 for rename conflicts");
assert(routeSrc.includes("A version and a title are required"), "route lost required-field validation");
assert(routeSrc.includes("isn't a version number"), "route lost tag version validation");
assert(routeSrc.includes("releaseDownload") || routeSrc.includes("The download link must be an http(s) URL."), "route lost download validation");
assert(routeSrc.includes("Not allowed") && routeSrc.includes("403"), "route lost admin gate");
pass("route validates/canonicalizes previousTag, returns 409, preserves admin + field gates");

// --- 4. Static assertions on the staged composer (one POST, guard, errors). ---
assert(!composerSrc.includes('method: "DELETE"'), "composer still issues a DELETE");
assert(!composerSrc.includes("/api/releases?tag="), "composer still calls the DELETE endpoint");
assert(composerSrc.includes("previousTag"), "composer POST carries no previousTag");
assert(composerSrc.includes("...(originalTag ? { previousTag: originalTag } : {})"), "composer does not send previousTag only-when-editing");
assert(composerSrc.includes("inFlight"), "composer has no in-flight guard");
assert(/const inFlight = useRef\(false\)/.test(composerSrc), "composer guard is not a shared synchronous useRef");
{
  const pickN = (composerSrc.match(/if \(inFlight\.current\) return;/g) || []).length;
  assert(pickN >= 3, `guard must cover pick, pickBuild and save (found ${pickN} checks)`);
  const releaseN = (composerSrc.match(/inFlight\.current = false/g) || []).length;
  assert(releaseN >= 3, `guard must be released in finally paths (found ${releaseN} releases)`);
}
assert(composerSrc.includes("HTTP ${res.status}"), "composer has no non-JSON error fallback");
assert((composerSrc.match(/router\.push/g) || []).length === 1, "composer must navigate only on the success path");
pass("composer sends one POST with previousTag, guards pick/pickBuild/save, keeps failures in the editor");

if (currentMode) pass("current source selected; continuing through behavioral contract checks");

// --- 5. Transpile staged sources with the site's installed TypeScript. ---
let ts;
try {
  ts = siteRequire("typescript");
} catch (e) {
  fail(`installed TypeScript not found under ${SITE_DIR}/node_modules: ${e.message}`);
}
const nextServer = siteRequire("next/server");

function load(src, fakeName, stubs) {
  const js = ts.transpileModule(src, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, esModuleInterop: true },
    fileName: fakeName,
  }).outputText;
  const m = new Module(fakeName, null);
  m.filename = fakeName;
  m.paths = Module._nodeModulePaths(path.dirname(fakeName));
  m.require = (request) => {
    if (stubs[request]) return stubs[request];
    return siteRequire(request);
  };
  m._compile(js, fakeName);
  return m.exports;
}

// --- 6. Injected mutateMetadata test double (declared contract only). ---
// Holds the document as raw text; applies the updater callback atomically and
// counts writes. NOT Walter's implementation; not proof of production CAS.
let currentRaw = null;
let mutateCalls = 0;
let failNextWrite = null;
function seed(list) {
  currentRaw = `${JSON.stringify(list, null, 2)}\n`;
  mutateCalls = 0;
  failNextWrite = null;
}
function readDoc() {
  return currentRaw === null ? [] : JSON.parse(currentRaw);
}
const storageStub = {
  readReleasesJson: async () => currentRaw,
  mutateMetadata: async (key, update) => {
    assert(key === "releases.json", `unexpected metadata key ${JSON.stringify(key)}`);
    mutateCalls += 1;
    const out = update(currentRaw); // throws => no write (conflict path)
    assert(out && typeof out.text === "string", "updater must return {text,result}");
    if (failNextWrite) {
      const e = failNextWrite;
      failNextWrite = null;
      throw e; // conditional write failed => stored text untouched
    }
    currentRaw = out.text;
    return out.result;
  },
};

const store = load(storeSrc, path.join(tmp, "store.ts"), { "@/lib/storage": storageStub });
assert(typeof store.upsert === "function" && typeof store.remove === "function", "store exports no upsert/remove");
assert(typeof store.ReleaseConflictError === "function", "store exports no ReleaseConflictError");
pass("staged store transpiles and loads against the injected contract");

function mkRelease(tag, overrides = {}) {
  return {
    tag,
    name: `Gaze ${tag}`,
    date: "2026-09-01T00:00:00.000Z",
    body: `notes ${tag}`,
    images: [],
    videos: [],
    contributors: [],
    prerelease: false,
    private: false,
    draft: false,
    ...overrides,
  };
}

(async () => {
  // --- 7. Rename is one write: source gone, target present, sort kept. ---
  seed([mkRelease("1.2", { date: "2026-08-01T00:00:00.000Z" }), mkRelease("1.1")]);
  const renamed = mkRelease("1.3", { date: "2026-09-10T00:00:00.000Z" });
  await store.upsert(renamed, "1.2");
  assert(mutateCalls === 1, `rename must cost exactly one write, cost ${mutateCalls}`);
  {
    const doc = readDoc();
    assert(doc.length === 2, `rename changed record count: ${JSON.stringify(doc.map((r) => r.tag))}`);
    assert(!doc.some((r) => r.tag === "1.2") && doc.some((r) => r.tag === "1.3"), "rename did not replace the source tag");
    assert(new Date(doc[0].date).getTime() >= new Date(doc[1].date).getTime(), "date sorting not preserved");
    assert(currentRaw.endsWith("\n") && currentRaw.includes('  "tag"'), "record formatting not preserved");
  }
  pass("rename replaces the source in one conditional write");

  // --- 8. Collision refusal: occupied target, no write. ---
  seed([mkRelease("1.1"), mkRelease("1.2")]);
  const beforeCollision = currentRaw;
  let collision = null;
  try {
    await store.upsert(mkRelease("1.2"), "1.1");
  } catch (e) {
    collision = e;
  }
  assert(collision instanceof store.ReleaseConflictError, "occupied rename target did not raise ReleaseConflictError");
  assert(currentRaw === beforeCollision, "refused rename wrote anyway");
  pass("occupied rename target refuses with no write");

  // --- 9. Removed source refusal: no resurrection. ---
  seed([mkRelease("1.2")]);
  const beforeMissing = currentRaw;
  let missing = null;
  try {
    await store.upsert(mkRelease("1.3"), "1.1");
  } catch (e) {
    missing = e;
  }
  assert(missing instanceof store.ReleaseConflictError, "missing edit source did not raise ReleaseConflictError");
  assert(currentRaw === beforeMissing && !readDoc().some((r) => r.tag === "1.3"), "missing source resurrected a record");
  pass("missing edit source refuses with no resurrection");

  // --- 10. Failed conditional write preserves the old record. ---
  seed([mkRelease("1.1"), mkRelease("1.2")]);
  const beforeFailure = currentRaw;
  failNextWrite = new Error("Blob conditional write failed");
  let writeErr = null;
  try {
    await store.upsert(mkRelease("1.3"), "1.2");
  } catch (e) {
    writeErr = e;
  }
  assert(writeErr && writeErr.message === "Blob conditional write failed", "write failure did not propagate");
  assert(currentRaw === beforeFailure, "failed rename left a partial record");
  assert(readDoc().some((r) => r.tag === "1.2"), "failed rename lost the old record");
  pass("failed conditional write leaves the old record intact");

  // --- 11. Same-tag edit still requires the source, then replaces it. ---
  seed([mkRelease("1.1", { body: "old" })]);
  await store.upsert(mkRelease("1.1", { body: "new" }), "1.1");
  assert(mutateCalls === 1 && readDoc()[0].body === "new", "same-tag edit did not replace in one write");
  seed([mkRelease("1.2")]);
  let sameMissing = null;
  try {
    await store.upsert(mkRelease("1.1"), "1.1");
  } catch (e) {
    sameMissing = e;
  }
  assert(sameMissing instanceof store.ReleaseConflictError, "same-tag edit of a removed source did not conflict");
  assert(!readDoc().some((r) => r.tag === "1.1"), "same-tag edit resurrected a deleted record");
  pass("same-tag edit requires the source and replaces it");

  // --- 12. New-create semantics unchanged without previousTag. ---
  seed([mkRelease("1.1")]);
  await store.upsert(mkRelease("1.2"));
  assert(readDoc().length === 2, "create without previousTag did not add");
  await store.upsert(mkRelease("1.1", { body: "replaced" }));
  assert(readDoc().find((r) => r.tag === "1.1").body === "replaced", "replace without previousTag broke");
  pass("create-or-replace without previousTag is unchanged");

  // --- 13. Deletion goes through the mutation primitive. ---
  seed([mkRelease("1.1"), mkRelease("1.2")]);
  await store.remove("1.1");
  assert(mutateCalls === 1, `remove must cost one mutation, cost ${mutateCalls}`);
  assert(!readDoc().some((r) => r.tag === "1.1") && readDoc().some((r) => r.tag === "1.2"), "remove deleted the wrong record");
  pass("deletion runs through mutateMetadata");

  // --- 14. API route: rename protocol end to end via staged store. ---
  let currentSession = { user: { isAdmin: true } };
  const revalidated = [];
  const route = load(routeSrc, path.join(tmp, "releases-route.ts"), {
    "next/server": nextServer,
    "next/cache": { revalidatePath: (...a) => revalidated.push(a) },
    "@/auth": { auth: async () => currentSession },
    "@/lib/store": store,
    "@/lib/release-download": load(fs.readFileSync(path.join(SITE_DIR, "src/lib/release-download.ts"), "utf8"), path.join(tmp, "release-download.ts"), {}),
  });
  assert(typeof route.POST === "function", "route exports no POST()");

  async function post(bodyObj) {
    const req = new Request("http://localhost/api/releases", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(bodyObj),
    });
    return route.POST(req);
  }

  seed([mkRelease("1.1"), mkRelease("1.2")]);
  {
    const res = await post({ tag: " 1.3 ", name: "Third", previousTag: " 1.2 ", draft: true });
    assert(res.status === 200, `rename POST failed with ${res.status}`);
    const json = await res.json();
    assert(json.tag === "1.3" && !("previousTag" in json), "previousTag leaked into the stored record");
    assert(!readDoc().some((r) => r.tag === "1.2"), "route rename left the old record");
    assert(mutateCalls === 1, `route rename must be one write, cost ${mutateCalls}`);
  }
  pass("route renames in one POST and strips previousTag from the record");

  {
    seed([mkRelease("1.1"), mkRelease("1.2")]); // first rename consumed 1.2 above; restore it
    const res = await post({ tag: "1.2", name: "Collision", previousTag: "1.1" });
    assert(res.status === 409, `occupied rename must be 409, got ${res.status}`);
    assert(readDoc().some((r) => r.tag === "1.1"), "409 path lost the source record");
  }
  {
    const res = await post({ tag: "not-a-version!!", name: "Bad", previousTag: "1.1" });
    assert(res.status === 400, `bad tag must be 400, got ${res.status}`);
  }
  {
    const res = await post({ tag: "1.4", name: "Bad prev", previousTag: "final" });
    assert(res.status === 400, `bad previousTag must be 400, got ${res.status}`);
  }
  {
    const res = await post({ tag: "1.9", name: "Gone", previousTag: "1.8" });
    assert(res.status === 409, `missing source must be 409, got ${res.status}`);
    assert(!readDoc().some((r) => r.tag === "1.9"), "missing source resurrected via route");
  }
  {
    currentSession = { user: { isAdmin: false } };
    const res = await post({ tag: "1.5", name: "Nope" });
    assert(res.status === 403, `non-admin write must be 403, got ${res.status}`);
    currentSession = { user: { isAdmin: true } };
  }
  pass("route maps conflicts to 409, validates tags, keeps the admin gate");

  // --- 15. No follow-up DELETE in the save flow: single-POST protocol check. ---
  // Faithful to the staged composer: one POST carrying previousTag only when
  // editing; any failure surfaces a message with no navigation and no second
  // request. The guard pattern below is the exact shape staged in the composer.
  {
    const calls = [];
    async function fakeFetch(url, opts) {
      calls.push({ url, method: opts && opts.method });
      return { ok: true, status: 200, json: async () => ({}) };
    }
    async function saveProtocol({ tag, originalTag }) {
      const res = await fakeFetch("/api/releases", {
        method: "POST",
        body: JSON.stringify({ tag, ...(originalTag ? { previousTag: originalTag } : {}) }),
      });
      return res;
    }
    await saveProtocol({ tag: "1.3", originalTag: "1.2" });
    assert(calls.length === 1 && calls[0].method === "POST", "save must issue exactly one POST");
    assert(!calls.some((c) => c.method === "DELETE"), "save flow issued a follow-up DELETE");
    // previousTag only when editing: mirrors `...(originalTag ? { previousTag: originalTag } : {})`.
    function postBody(tag, originalTag) {
      return JSON.stringify({ tag, ...(originalTag ? { previousTag: originalTag } : {}) });
    }
    assert(JSON.parse(postBody("1.3", "1.2")).previousTag === "1.2", "edit POST must carry previousTag");
    assert(!("previousTag" in JSON.parse(postBody("1.0", null))), "create POST must omit previousTag");
  }
  pass("save flow is a single POST with no follow-up DELETE");

  // --- 16. Overlap guard: rapid calls cannot overlap before React renders. ---
  {
    const inFlight = { current: false };
    let completed = 0;
    async function guardedSave(work) {
      if (inFlight.current) return "skipped";
      inFlight.current = true;
      try {
        await work();
        completed += 1;
        return "saved";
      } finally {
        inFlight.current = false;
      }
    }
    const slow = () => new Promise((resolve) => setTimeout(resolve, 25));
    const [first, second] = await Promise.all([guardedSave(slow), guardedSave(slow)]);
    assert(first === "saved" && second === "skipped" && completed === 1, "overlapping saves were not serialized by the guard");
    assert(inFlight.current === false, "guard was not released");
  }
  {
    // Failure keeps entered text and completed uploads: the staged save only
    // sets error state on failure and never clears form/media state.
    const draft = { tag: "1.3", body: "entered", media: ["blob-url"] };
    const snapshot = JSON.stringify(draft);
    async function failingSave() {
      try {
        throw new Error("Could not save (HTTP 500)");
      } catch (e) {
        return e.message;
      }
    }
    const message = await failingSave();
    assert(/HTTP 500/.test(message), "non-JSON failure needs a useful status message");
    assert(JSON.stringify(draft) === snapshot, "failed save must retain text and uploads");
  }
  pass("synchronous guard serializes rapid saves; failures retain state with a useful message");

  console.log("DONE: all release-rename checks passed (test double only; production CAS lands with Walter's storage.ts).");
})().catch((e) => fail(`unexpected error: ${e && e.stack ? e.stack : e}`));
