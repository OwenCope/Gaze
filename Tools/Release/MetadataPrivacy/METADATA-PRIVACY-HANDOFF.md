# Metadata privacy: private Blob store for website metadata

## Lead integration checkpoint

The corrected patch is APPLIED LOCALLY to gaze-site; nothing is deployed or migrated.
It now covers storage.ts plus strict read paths in store.ts, testers.ts and roles.ts.
The original single-file proposal below is retained as history where superseded.

Lead corrections:
- Private-only configuration selects Blob, not disk; Vercel without private
  configuration refuses rather than using the local filesystem.
- Private OIDC passes an explicit VERCEL_OIDC_TOKEN with the private store ID.
  Without it, the installed SDK could fall back to the public token, so this
  configuration now refuses. A private read-write token is the alternative.
- Missing, non-200 or malformed private metadata throws. Writes first require a
  valid existing private object, so an ordinary admin write cannot seed an
  unmigrated store. Public/private credential reuse is refused.
- Release/tester/role mutations use strict reads; storage failures cannot become
  empty-list writes. Role lookup on failure returns no roles, not default access.
  Deliberately empty role lists stay empty. Local missing files still use normal
  initial defaults; other filesystem errors propagate.

Staged and --current tests pass with synthetic SDK/filesystem fixtures. No real
Blob records, credentials or production configuration were read or changed.
The site typecheck and corrected isolated production build/smoke pass, including
an unauthenticated /admin redirect rather than the previously observed 500.
The unrelated /admin smoke failure was traced to node:crypto in Edge middleware;
the same auth guard now uses Next.js's Node-based src/proxy.ts convention.

Deployment must wait for private-store provisioning and a verified metadata copy.
If an original key is confirmed genuinely absent, consciously seed its intended
initial value; do not treat access/network/parse failures as missing data.
Previously public originals need a separate reviewed cleanup after cutover.
Read-before-write guards are not an atomic compare-and-swap between concurrent
successful writers; this change does not claim to add database transactions.



Source-level privacy issue (lead's finding, confirmed read-only from source; no
production data inspected, no breach observed or claimed):
`src/lib/storage.ts` in gaze-site reads/writes `releases.json` (includes
drafts + tester-only releases), `testers.json` (tester emails), `roles.json`
(permission map), `settings.json` (visibility switch) and `readme.md` via
`get`/`put` with `access: "public"` on the default store — the same store
whose hostname is printed in public build/media URLs. Route-level gates
(admin-only APIs, `viewPrivate` checks, draft/private filters in
`src/lib/releases.ts`, `/api/latest`, `/dl/[file]`) decide who may *ask*, but
the source would make those documents publicly addressable when used with a public store; actual production contents were not inspected. Route gating alone
must not be treated as metadata confidentiality.

Guidance read before coding: gaze-site `AGENTS.md` (versioned Next.js — use
installed docs), installed `@vercel/blob` SDK types
(`node_modules/@vercel/blob/dist/index.d.ts`: `get`/`put` take
`access: "public" | "private"` plus per-call `token`/`storeId`/`oidcToken`;
`get` returns `null` when not found), and the full caller trace below. The
website checkout stayed read-only. Nothing was uploaded, deleted, deployed,
re-provisioned, authenticated, or read from production.

## Caller trace (all `storage.ts` consumers; none change)

- `readReleasesJson`/`writeReleasesJson` → `src/lib/store.ts`
  (`readAll`/`upsert`/`remove`) → `src/lib/releases.ts`
  (`getReleases` incl. `includePrivate`, `getAllReleases`, `getRelease`) →
  public releases pages, admin dashboard, admin-only `/api/releases`,
  public `/api/latest` (filters draft+private server-side), `/dl/[file]`
  (filters draft+private, redirects to public build URL).
- `readTestersJson`/`writeTestersJson` → `src/lib/testers.ts`
  (`readTesters`/`addTester`/`removeTester`/`isTester`) → `src/lib/viewer.ts`
  (`getViewer` role resolution, `can("viewPrivate")`), admin-only
  `/api/testers`. Tester emails are the sign-in identity (lowercased).
- `readRolesJson`/`writeRolesJson` → `src/lib/roles.ts` → `getViewer` +
  `/api/roles` (`manageRoles` gate). Owner (`ADMIN_EMAILS`) is env-derived and
  never stored here — that property is preserved.
- `readReadme`/`writeReadme` → `/testers` page (requires `viewPrivate`),
  `/admin/readme`, admin-only `/api/readme` POST.
- `readJSON`/`writeJSON` (generic) → `src/lib/settings.ts`
  (`getSettings`/`saveSettings`, key `settings.json`) → releases page gate,
  `/api/latest` gate, `/dl` gate, admin-only `/api/settings`.
- Direct `@vercel/blob` users: `storage.ts` only (`get`/`put`).
  `/api/upload` uses `handleUpload` client-upload tokens on the default store
  (public media/builds) — untouched. `src/lib/release-download.ts` HTTPS +
  public-hostname allowlist — untouched.

## Patch scope — `Tools/Release/MetadataPrivacy/storage-metadata-privacy.patch`

Applies with `patch -p1` from the gaze-site root to `src/lib/storage.ts`
only (10 call sites, one file; verified the diff touches nothing else):

- Adds `usingPrivateMetadataStore` (true when `BLOB_PRIVATE_READ_WRITE_TOKEN`
  or `BLOB_PRIVATE_STORE_ID` is set) alongside the unchanged `usingBlob`
  (still `BLOB_READ_WRITE_TOKEN`/`BLOB_STORE_ID`: the *public* media/build
  store; still drives the local-disk decision).
- Adds `privateStoreOptions()`: returns `{ access: "private", token?,
  storeId? }` from the private vars; **throws** when neither is set.
- All 5 reads (`releases`/`testers`/`readme`/`roles`/generic) and all 5 writes
  now spread `privateStoreOptions()` instead of `access: "public"`.
  `useCache: false`, pathnames, content types, `addRandomSuffix: false`,
  `allowOverwrite: true`, `cacheControlMaxAge: 60`, null-on-missing,
  null-on-unparseable, and every local-disk branch are byte-identical.
- Fail-closed, not fallback: in Blob mode (`usingBlob` true) with no private
  config, every helper throws naming the required vars; the public store is
  never touched for metadata.

Preserved deliberately: function signatures, JSON string formats (callers keep
doing their own `JSON.stringify(list, null, 2) + "\n"`; generic `writeJSON`
keeps its 2-space format), all auth/role/visibility checks and filters, the
public upload path, and the HTTPS download policy.

## Test — `Tools/Release/MetadataPrivacy/test-storage-metadata-privacy.cjs`

Follows the `Tools/Release/test-update-feed-privacy.cjs` pattern: copies the
real `storage.ts` to a temp dir, applies the patch there (`patch --fuzz=0`;
`--current` tests the site file as-is), transpiles the **actual staged
source** with the site's installed TypeScript, and executes it with a stubbed
`@vercel/blob` + real filesystem. No logic duplicated, no network.

```sh
node Tools/Release/MetadataPrivacy/test-storage-metadata-privacy.cjs
```

Result (exit 0):

```text
PASS: patch scope is src/lib/storage.ts only
PASS: public upload route + HTTPS download allowlist markers intact (out of scope)
PASS: patch applies cleanly to a temp copy of storage.ts (fuzz=0)
PASS: local-disk mode preserved: round-trips + missing=>null, no Blob calls
PASS: Blob+private mode: 5 reads + 5 writes all pinned to access:private with private token
PASS: error paths: null/non-200/unparseable=>null, SDK failures propagate via private options
PASS: fail-closed: all 10 helpers throw without private config; zero public-store calls
PASS: OIDC variant: BLOB_PRIVATE_STORE_ID passes as storeId with no static token
OK: all metadata-privacy storage checks passed (patched source executed, SDK stubbed).
```

## Required environment (names only — no values handled)

- `BLOB_PRIVATE_READ_WRITE_TOKEN` — static token of the NEW dedicated
  private store (preferred when not on Vercel OIDC).
- `BLOB_PRIVATE_STORE_ID` — store id of the NEW dedicated private store
  (for OIDC; may be set alongside or instead of the token, mirroring the
  existing `BLOB_READ_WRITE_TOKEN`/`BLOB_STORE_ID` pattern).
- Existing `BLOB_READ_WRITE_TOKEN`/`BLOB_STORE_ID` keep meaning the public
  media/build store. Never put the public store's values into the private
  vars — that would reunite metadata with the public hostname.

## Compatibility implications

- Production without the new vars: every metadata access throws (fail-closed).
  Public pages that read releases/settings go down loudly rather than leak —
  this is intentional. Do not "fix" it by falling back to public.
- Local dev/tests with no Blob vars at all: unchanged `./data/*.json` files.
  Boundary: anyone who sets the *public* vars locally (e.g. via `vercel env
  pull`) now also needs the private vars or metadata calls throw; that is the
  fail-closed behavior working as designed, not a regression.
- Private blobs are addressed by pathname through the server SDK only; no
  metadata URL is ever advertised (downloads still serve only validated public
  build URLs), so no URL/redirect changes are needed anywhere.
- `usingPrivateMetadataStore` is a new export for future health checks; no
  existing importer is affected (`usingBlob` is only used inside
  `storage.ts`).

## Owner actions required before safe deployment (in order)

1. **Create a NEW, separate Blob store** for metadata (Vercel dashboard);
   do not reuse the public store. No cleanup yet.
2. **Copy (not move)** `releases.json`, `testers.json`, `readme.md`,
   `roles.json`, `settings.json` from the public store into the private store
   as **private** objects under the identical pathnames. Preserve the public
   originals untouched — they are the rollback source.
3. **Verify before cutover:** read each private object back and compare
   byte-for-byte with the public original (record counts for the JSON lists:
   releases/testers/roles entries, settings keys). Do not proceed on mismatch.
4. **Set `BLOB_PRIVATE_READ_WRITE_TOKEN` (and/or `BLOB_PRIVATE_STORE_ID`)**
   in production from the new store only; add the names (not values) to the
   site's `.env.example` (lead-owned — not done here).
5. **Apply the patch, review, then deploy.** Staging first if available:
   confirm releases/testers/roles/settings pages behave and no
   private-store-unconfigured error appears.
6. **Previously public objects stay public until an explicitly reviewed
   cleanup.** That deletion is a separate, deliberate step (public URLs may be
   cached/indexed; confirm the private path is serving first). It is NOT part
   of this patch and was NOT performed.

Critical ordering hazard (no silent reinterpretation): an unpopulated private
store reads as an empty catalog (`null` → `[]`/defaults, same as today), so a
write against it (e.g. admin publish/add-tester) would seed a partial catalog
over what looks like emptiness. Hence: **never deploy the patched build, and
never run any admin write, before steps 2–3 are done.** Recovery, if it ever
happens, is re-copy from the preserved public originals (step 2 is why they
still exist).

## Not done / lead owns

- Applying/auditing the patch, `.env.example`, creating stores, credentials,
  production config, the copy/verify/cutover run, the later public-object
  cleanup, and any deployment.
- `tsc`/full site suite left to the lead (harness transpiles + executes the
  patched module; it does not typecheck the site or test Vercel edge/Blob
  behavior).
