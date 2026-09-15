# Update-feed privacy patch (Iris; audited and applied locally)

Gap (lead's source inspection, confirmed read-only): `src/app/releases/page.tsx:34-37`
checks `getSettings().releasesRequireSignIn` before reading releases, but
`src/app/api/latest/route.ts:53-90` does not. Deploying the current feed would disclose
release metadata (tags/names/notes/download) while the owner has hidden releases behind
sign-in. Guidance read before coding: gaze-site `AGENTS.md` (versioned Next.js — use
installed docs) and `node_modules/next/dist/docs/01-app/01-getting-started/15-route-handlers.md`
(route handlers run at request time by default; `GET` is not cached unless opted in) plus the
`dynamic`/`fetchCache` segment-config section of `caching-without-cache-components.md`.
Iris kept the website checkout read-only. After auditing, the lead applied the patch locally to the single route file; no deployment or release publication occurred.

## Patch scope — `Tools/Release/update-feed-privacy.patch`

Applies with `patch -p1` from the gaze-site root to `src/app/api/latest/route.ts` only:

- Adds `import { getSettings } from "@/lib/settings"`.
- At the top of `GET()`, reads `{ releasesRequireSignIn }` and, when true, returns
  HTTP 200 `{ latest: null }` **before** `readAll()` is called.
- Replaces all three `Cache-Control: public, max-age=300, s-maxage=300` responses
  (restricted, empty, public) with `Cache-Control: no-store`, with a comment explaining
  the mutable privacy switch defeats edge caching.
- Preserves everything else byte-for-byte: draft/private filter, numeric `compareTags`
  ordering, newest-non-prerelease preference, `{latest:null}` shape on empty, payload
  shape (`tag/name/date/notes/prerelease/download`), 404 handling (untouched — this route
  never handled 404), trusted origin, download allowlist, auth policy, release records.

## Test — `Tools/Release/test-update-feed-privacy.cjs`

Narrow executable harness. It copies the original route to a temp dir, applies the patch
there with `patch`, transpiles the **actual patched source** with the site's installed
`node_modules/typescript` (`transpileModule`, CommonJS), and executes its `GET()` with
the installed real `next/server` response implementation and stubbed `@/lib/store` / `@/lib/settings`. No logic duplicated (expected tags
are hardcoded; `compareTags`/filter live only in the route). No network, dev server,
deployment, or site edits.

Reproducible command (from the Gaze checkout root):

```sh
node Tools/Release/test-update-feed-privacy.cjs --current
```

Result on 2026-09-15 (exit 0):

```text
PASS: patch applies cleanly to a temp copy of the route
PASS: hidden releases => 200 {latest:null} with zero readAll calls
PASS: public eligible => newest stable "0.10" (numeric order, filters preserved)
PASS: only draft/private data => 200 {latest:null}
PASS: empty data => 200 {latest:null}
PASS: every branch sends Cache-Control: no-store (mutable privacy switch cannot be defeated by cache)
OK: all update-feed privacy checks passed (patched route executed, logic not duplicated).
```

Coverage: hidden gate causes zero `readAll` calls; public mixed fixture (`0.9`, `0.10`,
prerelease `0.12`, draft `9.9`, private `9.8`) yields `0.10`; draft/private-only and empty
yield `{latest:null}`; every branch asserts `Cache-Control: no-store` and the source
contains no residual `max-age`/`s-maxage`.

## Limitations / lead must still decide

- Patch applied locally to `/Users/owencope/Developer/gaze-site/src/app/api/latest/route.ts`; not deployed or published. The patch file remains available for an unmodified checkout. Use `--current` to test the applied route; omit it only when testing patch application against an unmodified route.
- `no-store` trades the 5-minute edge saving for correctness; acceptable because the
  document is tiny and the switch flips without a deploy. No `force-dynamic` export added —
  the handler already does async filesystem I/O (uncached per the route-handler doc), so it
  renders at request time; if the site enables Cache Components statically, re-audit.
- Test stubs storage/settings but uses the installed real NextResponse; it proves patched-route behavior, not production
  Blob wiring, Vercel edge behavior, or the stale-deployment 404 in
  `UPDATE-FEED-INTEGRATION-20260915.md`.
- Assumes site checkout at `/Users/owencope/Developer/gaze-site` (override `GAZE_SITE_DIR`);
  assumes `patch(1)` and the site's `node_modules/typescript` are present.

## Lead audit and verification

The lead replaced the response stub (which always returned 200) with the installed
NextResponse, limited dependency overrides to the test module, added cleanup of the
owned temporary directory, and disabled patch reversal/fuzzy application. The test
also verifies that changing the visibility switch is observed on the next request.

Both pre-application and `--current` checks passed. Website
`tsc --noEmit --incremental false` passed with no diagnostics. Logs:
`build/hydra-update-feed-privacy-test.log`,
`build/hydra-update-feed-current-test.log`, and `build/hydra-site-typecheck.log`.
These checks do not establish production Blob state, edge behavior, or deployment.
