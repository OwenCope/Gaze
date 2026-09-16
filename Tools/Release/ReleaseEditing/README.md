# Atomic release rename + editor overlap guard (Ada 2)

Renaming a release is now one conditional POST instead of save-then-DELETE, and
rapid upload/save clicks cannot overlap before React renders the disabled state.
The site checkout was not touched; everything for this stage lives in this folder.

## Files in this folder

- `release-rename.patch` — applies with `patch -p1 --fuzz=0` from the gaze-site
  root. Touches exactly three files: `src/lib/store.ts`,
  `src/app/api/releases/route.ts`, `src/components/release-composer.tsx`.
- `store.staged.ts`, `route.staged.ts`, `release-composer.staged.tsx` — source
  copies the patch produces (the test asserts staged-equals-copy).
- `test-release-rename.cjs` — synthetic suite, see below.
- This report.

## What the patch does

- `store.upsert(release, previousTag?)` runs inside one
  `mutateMetadata("releases.json", raw => ({text, result}))` callback: no
  preliminary `readAll`. With `previousTag` it requires the source tag to still
  exist and refuses a changed tag owned by another record (`ReleaseConflictError`,
  exported); without it the historical create-or-replace applies. `remove(tag)`
  goes through the same primitive. Date sorting and `JSON.stringify(list, null,
  2)\n` formatting are unchanged.
- API POST canonicalizes optional `previousTag` with the same version rule as
  the tag, never stores it, passes it to `upsert`, and returns 409 on
  `ReleaseConflictError`. Admin gate, required-field, version and download-URL
  checks are unchanged; a rename also revalidates the old release path.
- The composer sends one POST with `previousTag` only when editing and no
  longer issues DELETE. A shared synchronous `useRef` guard wraps `pick`,
  `pickBuild` and `save`; failures keep entered text, completed uploads and the
  editor route (navigation only on success), and non-JSON error pages surface as
  `Could not save (HTTP <status>)`. No visual, telemetry or permission changes.

## How it was checked

`node Tools/Release/ReleaseEditing/test-release-rename.cjs` — 17 PASS lines,
exit 0: patch scope (three files only, never `storage.ts`), clean apply with
`--fuzz=0` to a temp copy, staged-equals-copy, then the actual staged store and
route transpiled with the site's TypeScript and executed with real `next/server`
(rename in one write, collision/missing-source refusal with no write, failed
conditional write preserves the old record, same-tag edit, unchanged
create-or-replace, deletion via mutation, route 409/400/403 mapping, single-POST
no-DELETE save flow, guard serialization + state retention). Staged `store.ts`
and `route.ts` also pass strict `tsc --noEmit` against the declared contract;
the composer transpiles with zero errors. No git, no live endpoints or data.

## Explicit integration dependency (root must read)

1. **Walter 3's `mutateMetadata` must land first** in gaze-site
   `src/lib/storage.ts` with exactly
   `mutateMetadata<T>(key:'releases.json'|'testers.json'|'roles.json'|'settings.json',
   update:(raw:string|null)=>{text:string;result:T}):Promise<T>`.
   Until then the patched `store.ts` does not typecheck in the site and nothing
   here may be applied. The suite's injected `mutateMetadata` is a test double
   for the updater callback only — it is not, and is not called, proof of
   production compare-and-swap.
2. After both land, root runs the combined integration:
   `test-release-rename.cjs --current` (static checks against live files) plus
   the full behavioral suite and site `tsc`, then a localhost-only rename +
   double-click exercise. No deployment.
3. A real browser fixture for overlapping editor actions was not feasible here;
   the guard is proven by static assertions on the staged source plus a faithful
   pattern simulation. Do not claim browser-level overlap coverage.

## Root integration

Applied locally to gaze-site; nothing deployed. Source copies and the main patch now include the root corrections. See RESUME-HANDOFF-20260916.md and sibling BROWSER-RESULT.md where present for verification scope.

Root rejects malformed/null/blank previousTag and malformed release fields before storage, validates builds with the shared download policy, requires the returned tag before confirming save, disables editing during submission, and announces errors. --current now runs behavioral contract checks as well as wiring checks. test-combined-concurrency.cjs tests the actual current storage/store/API together; fixture/ tests the actual composer in a browser with deferred transport.
