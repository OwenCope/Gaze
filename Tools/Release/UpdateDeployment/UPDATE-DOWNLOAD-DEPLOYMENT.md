# Same-origin download endpoint — staged website patch (Ivo)

Gap (from `Tools/Release/UPDATE-FEED-INTEGRATION-20260915.md` §5): the seed feed
advertises `https://gazeunlock.com/dl/Gaze-0.3.dmg`, which has **no serving
route** in site source, while composer-uploaded builds land on Vercel Blob URLs
(`*.public.blob.vercel-storage.com`) that the app deliberately discards
(`Sources/App/ReleaseURLPolicy.swift:18-21`). One-click download cannot work
until a same-origin path serves the bytes. The website checkout stayed
read-only; everything for this stage lives in `Tools/Release/UpdateDeployment/`.

## Staged changes (website patch, not yet applied to the site)

`update-download.patch` — applies with `patch -p1` from the gaze-site root.
Two files, no app change, no origin-policy change:

1. **New `src/app/dl/[file]/route.ts`** — public `GET` that answers
   `https://gazeunlock.com/dl/<file>` with a **302** to the build attached to
   the matching release record. Bytes stay on Blob storage; the route only
   hands out the current location, looked up per request.
2. **Modified `src/app/api/latest/route.ts`** — one line plus a `feedDownload`
   helper: the feed advertises `https://gazeunlock.com/dl/<download.name>`
   (encoded) instead of echoing the stored Blob URL verbatim. Record without a
   usable filename offers `download: null` rather than a fabricated URL.

## Policy enforced by the route (all covered in the test)

- **Visibility first**: `releasesRequireSignIn` → identical `404
  {error:"Not found"}` with `no-store`, checked **before** `readAll()` (zero
  storage reads). Same switch and ordering as `/api/latest` and `/releases`.
- **Eligibility**: only `!draft && !private`, matched **exactly** on
  `download.name`. Prereleases are servable (the feed may legitimately offer
  one); the route never re-implements "newest" logic.
- **No oracle**: draft, private, unknown, restricted, placeholder, non-http,
  ambiguous and malformed paths all answer the byte-identical 404 body.
- **Safe targets only**: the redirect target is the stored `download.url` of
  the matched record (written through the owner-only `/api/releases`
  endpoint) — never taken from the request — and must parse as `http(s)`.
- **Loop guard**: a stored URL pointing back under `/dl/` (the seed 0.3
  placeholder, which has no bytes behind it) misses instead of redirecting to
  itself. Ambiguous filenames (two eligible releases, one name) miss rather
  than serving one of two builds.
- **Temporary, uncached**: 302 (not 301) with `Cache-Control: no-store` on
  every response — re-uploads mint new suffixed Blob URLs, and the visibility
  switch flips without a deploy.

Why redirect, not proxy: the composer comment (`release-composer.tsx`) already
records that a Vercel function is the wrong pipe for large files; an ~18 MB
DMG belongs on Blob CDN, not streamed through a function. Why the filename
comes from `req.url` instead of segment `params`: the async-`params`
convention has changed across Next versions (installed docs,
`15-route-handlers.md` Route Context Helper); the path is stable, single
segment is enforced fail-closed in-handler, and the exact-match lookup is the
real validation either way. `openDownload()` uses `NSWorkspace.open`, so the
302-to-Blob hop happens in the browser — the app's strict redirect policy only
governs the feed fetch, not the download.

## Verification (all run, site untouched)

From the Gaze checkout root:

```sh
node Tools/Release/UpdateDeployment/test-update-download.cjs
# 16 PASS lines, exit 0: patch applies with --fuzz=0; actual patched sources
# transpiled with the site's TypeScript and executed with real next/server.
```

Typecheck: full site copy + patch → `tsc --noEmit --incremental false` passes
with no diagnostics (same as the pristine tree; in-place site `tsc` also
passes — an out-of-tree copy without `.next` shows one pre-existing
`LayoutProps` error that exists with and without the patch).

`--current` mode (`test-update-download.cjs --current`) tests the live site
files; it fails until the lead applies the patch (no `src/app/dl/**` exists
yet) — expected.

## Deployment steps for the lead

1. Review and apply in the site checkout: `patch -p1 -i
   <gaze-checkout>/Tools/Release/UpdateDeployment/update-download.patch`,
   then site `tsc --noEmit --incremental false`.
2. **Unresolved dependency — real build bytes (names it): no release record
   currently carries a Blob-backed build.** The seed 0.3 `download.url` is a
   same-origin placeholder with nothing behind it, so after this patch
   `/dl/Gaze-0.3.dmg` honestly 404s (loop guard). Before launch, upload the
   actual shipping `.dmg` through the release composer (owner-only
   `/api/upload` → Blob); that sets a real `download: {url, name, size}` on
   the published record. Do not hand-edit a Blob URL into the record and do
   not commit a DMG under `public/` — the composer flow is the only path that
   mints a valid stored URL.
3. Confirm production Blob `releases.json` state (production reads from Blob
   when a token is present; local `./data` seed does not deploy with it):
   expect either `{latest:null}` (safe — app stays silent) or the cleared
   public release with the Blob-backed download.
4. Deploy the site to the production target serving `gazeunlock.com`, then:
   - `curl -i https://gazeunlock.com/api/latest` → 200, `no-store`,
     `download.url` starting `https://gazeunlock.com/dl/`;
   - `curl -i https://gazeunlock.com/dl/<name>` → 302 to the Blob URL,
     `no-store` (before a real upload: 404, `no-store`, no `Location`);
   - in-app Settings → Check shows the offered release and opening it lands
     in the browser on the same-origin URL.
5. Rollback is deletion: without the route, `/dl/*` 404s and the app falls
   back to opening `/releases` — the pre-patch safe behavior.

## Explicitly not done

No drafts/private records exposed, no arbitrary-URL proxy, no app origin
loosening, no artifacts fabricated, no Vercel/production state touched, no
commits or branches. Production release data and the feed route deployment
(from the earlier stages) remain the lead's calls.
