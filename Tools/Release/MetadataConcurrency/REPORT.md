# Metadata concurrency: preserve concurrent website catalog edits

## What was done

Added a compare-and-swap mutation primitive and converted the three
non-release metadata writers to use it, so two admins acting at the same time
no longer silently discard each other's independent rows.

- `src/lib/storage.ts`: added the exact exported interface

  ```ts
  mutateMetadata<T>(
    key: 'releases.json' | 'testers.json' | 'roles.json' | 'settings.json',
    update: (raw: string | null) => { text: string; result: T }
  ): Promise<T>
  ```

  Blob mode reads with `useCache: false` and the existing explicit private
  credentials, requires status 200 + valid existing content + nonempty ETag,
  runs the pure `update`, validates next text, and puts with
  `access: 'private'`, `addRandomSuffix: false`, `allowOverwrite: true`,
  `ifMatch: etag` (plus existing `contentType`/`cacheControlMaxAge: 60`).
  `BlobPreconditionFailedError` from the installed SDK is matched with
  `instanceof` (SDK errors inherit `Error` with `name === "Error"`, verified
  against the installed `@vercel/blob@2.8.0`), re-reading/recomputing up to
  five attempts total. Only the successful-write result is returned.
  Missing/non-200/ETag-less/corrupt/unconfigured reads never call `update`
  and never write. Exhaustion throws an actionable `Concurrent update
  conflict on <key> … tried 5 times` without private content.

  Local (no-Blob) mode serializes mutations per key with an in-process promise
  queue that survives a failed predecessor, reads `null` only on `ENOENT`,
  validates existing/next content, writes a unique temp file and renames
  atomically, always cleaning up owned temps. Documented in-code that the
  queue does NOT coordinate independent local processes; no lock files, no
  stale-lock deletion. `usingBlob` / `privateStoreOptions` unchanged.

- `src/lib/testers.ts`: `addTester`/`removeTester` via `mutateMetadata`.
  Timestamp (`addedAt`), cleaned email/github/note, and explicit roles copied
  once before the retryable callback; existing `addedAt` and
  `roles ?? existing ?? ["tester"]` semantics preserved.

- `src/lib/roles.ts`: `upsertRole`/`removeRole` via `mutateMetadata`.
  Slug/id/name/color/filtered permissions computed once; `DEFAULT_ROLES`
  never mutated (fresh `copyDefaultRoles()` when raw is `null`).

- `src/lib/settings.ts`: `saveSettings` via `mutateMetadata` with current
  `{...DEFAULTS, ...stored, ...patch}` merge; patch object captured once so
  concurrent saves converge.

- `src/lib/store.ts` untouched (Ada 3 owns releases/API/composer and consumes
  this exact `mutateMetadata` interface).

## Files delivered (this directory only; gaze-site stayed read-only)

- `metadata-concurrency.patch` — applies with `patch -p1` from the gaze-site
  root; touches ONLY `src/lib/storage.ts`, `src/lib/testers.ts`,
  `src/lib/roles.ts`, `src/lib/settings.ts`.
- `storage.ts`, `testers.ts`, `roles.ts`, `settings.ts` — final source copies
  the patch reproduces (verified byte-identical after `patch --fuzz=0`).
- `test-metadata-concurrency.cjs` — executes the ACTUAL staged sources
  (transpiled with the site's installed TypeScript) with a stubbed
  `@vercel/blob` transport + real filesystem; uses the REAL installed
  `BlobPreconditionFailedError` class.
- `REPORT.md` (this file).

Run: `node Tools/Release/MetadataConcurrency/test-metadata-concurrency.cjs`
(`GAZE_SITE_DIR` overrides the site path; defaults to the local checkout).

## How it was checked

```
PASS: patch scope is exactly storage/testers/roles/settings (store.ts untouched)
PASS: patch carries the exact mutateMetadata interface with CAS (instanceof + ifMatch)
PASS: patch applies cleanly (fuzz=0) and reproduces the staged final copies
PASS: using the real installed BlobPreconditionFailedError (name is "Error", instanceof required)
PASS: lost-update probe: old read/modify/write loses one of two independent additions
PASS: Blob: two concurrent independent addTester calls both survive via CAS retry
PASS: Blob: CAS conflict recomputes and returns only the successful-write result
PASS: Blob: exhaustion after 5 CAS failures throws actionable error without private content
PASS: Blob: missing/empty ETag refuses without calling update or writing
PASS: Blob: missing/corrupt/shape-invalid reads and invalid next text never initialize or write
PASS: Blob: outage propagates with no stray writes; unconfigured never reaches the SDK
PASS: Blob: private credential pinning on converters + instanceof (not name) retry
PASS: Local: two concurrent addTester calls both survive via per-key queue; no temp litter
PASS: Local: per-key queue survives a failed predecessor
PASS: Local: addedAt/permissions/defaults preserved; DEFAULT_ROLES unchanged after failed save
PASS: Blob: concurrent saveSettings converge via recomputation
OK: all metadata-concurrency checks passed (staged sources executed, SDK stubbed).
```

- Lost-update probe is synthetic and deterministic: two old-flow writers read
  the same `[]`, each unshifts a different email, both unconditional puts
  succeed, final holds only the second row.
- New-primitive tests use a versioned in-memory fake Blob store with real
  conditional semantics (`ifMatch` mismatch → real `BlobPreconditionFailedError`),
  plus missing/ETag-less/corrupt/outage/lookalike-error variants.
- Local tests use real filesystem temp dirs; verified no `*.tmp` litter and
  queue survival after failure.
- Typecheck (`tsc --noEmit`) and lint (`eslint`, 0 errors) run in a secret-free
  temp copy (env cleared of `BLOB_*`/`VERCEL*`, symlinked `node_modules` only);
  both exit 0. No live Blob/network/auth calls, uploads, deployments, `.env`
  values, or real data at any point. Localhost only.

## What the lead must know

1. **Protected vs not protected.** Independent-record updates (two testers,
   two roles, two settings patches merged by recomputation) are now safe
   against lost writes in Blob mode and same-process local mode. Whole-document
   editing (e.g. two admins editing the same readme-style text) and same-record
   stale edits (two admins editing the SAME tester/role) still last-writer-win
   at the document level: CAS guarantees no silent loss of the OTHER row, not
   a field-level merge of one row. Those need their own version policy if
   required; this change does not claim record-level transactions.

2. **Existing metadata-privacy harness needs adaptation (not changed here).**
   `Tools/Release/MetadataPrivacy/test-storage-metadata-privacy.cjs` stubs
   `read*Json`/`write*Json` and expects mutations to flow through them. After
   this patch, `addTester`/`removeTester`/`upsertRole`/`removeRole`/
   `saveSettings` flow through `mutateMetadata`, not the raw write helpers
   (reads still use `read*Json`). The privacy tests are root-owned per the
   brief and were left untouched; to re-green them, stub `mutateMetadata`
   (or the Blob `get`/`put` under it) instead of `write*Json` for the mutation
   paths, keeping the existing private-credential, fail-closed, and strict-read
   assertions as-is.

3. **Ada integration.** `store.ts`/`/api/releases`/composer should call
   `mutateMetadata('releases.json', …)` with the current upsert/remove list
   logic, computing dates/ids once outside the callback like the tester/role
   converters do. Do not lower thresholds or reinterpret missing/corrupt as
   empty in Blob mode.

4. **No action on production.** No stores provisioned, no credentials handled,
   no migration, no deployment. Patch is staged only.

## Root integration

Applied locally to gaze-site; nothing deployed. Source copies and the main patch now include the root corrections. See RESUME-HANDOFF-20260916.md and sibling BROWSER-RESULT.md where present for verification scope.

Root strengthened local publication with exclusive UUID temp files (0600), shared per-path queues across module instances, runtime document allowlisting, and whitespace-ETag rejection. Current-source concurrency and privacy suites pass; 18 combined release/API/real-CAS-implementation cases also pass with a synthetic SDK transport.
