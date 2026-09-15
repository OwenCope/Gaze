# Update-feed integration — September 15, 2026 (Remy; lead-audited)

Scope: why `ReleaseUpdateChecker` gets HTTP 404 from
`https://gazeunlock.com/api/latest`, and what to do before launch.
No live re-check performed (lead already established the 404; not repeated).
No site code changed (that checkout is read-only for this task).
No artifacts downloaded or uploaded. No credentials, camera, lock, or restarts.

Lead update: the privacy patch described in `UPDATE-FEED-PRIVACY.md` is now
applied and tested in the local website checkout. It checks the sign-in visibility
setting and uses `no-store`. The original source/cache descriptions below record
Remy's pre-patch inspection. Production remains unchanged and still needs an
approved deployment after release data/download hosting is reviewed.

## TL;DR

- The endpoint is **implemented in site source** — there is no missing route to
  write. `src/app/api/latest/route.ts` (gaze-site) is public, matches the app's
  wire contract, and filters drafts / tester-only releases server-side.
- The local route matches the app, but the production 404 is not yet attributed.
  A stale deployment or wrong domain mapping is plausible; production routing,
  middleware or configuration can also affect which handler runs. The evidence
  still needed is listed in §4. Route presence alone does not settle the cause.
- Second gap, independent of the 404: the seed download URL
  `https://gazeunlock.com/dl/Gaze-0.3.dmg` has **no serving route** in site
  source (no `src/app/dl/**`, no redirect/rewrite), and composer-uploaded
  builds land on Vercel Blob URLs that the app will deliberately discard.
  Safe fallback exists (opens `/releases`), but one-click download will not
  work until download hosting is decided. See §5.

## Lead deployment verification

The connected Vercel API reports `gazeunlock.com` on project `gaze-site`
(`prj_rt9NNxDLDKB2T38NGMbYdGUIlKdS`, team `gaze2`). Its production deployment is
`dpl_6TnkwQxrfsz5EYqQETNf1VErKMrx`, created **2026-08-16 05:01:31 UTC**, with
Git commit `4bc8f59d83c9becd7c1a7ecc9b042e924ea1205b`. The deployment's aliases
include `gazeunlock.com` and `www.gazeunlock.com`.

Read-only inspection of that exact commit confirms it has **no**
`src/app/api/latest/route.ts`, although the file exists in the local website
checkout. This establishes that the reported production build lacks the route.
No commit, push, domain change or deployment was performed. The existing local
route must be reviewed and included in a new approved website deployment; do not
silence the app's 404 or change its trusted origin to compensate. Review production
release data before making the feed public so it offers only cleared artifacts.

## 1. Required contract (app side — current source, unchanged)

- `Sources/App/ReleaseURLPolicy.swift:4` — feed is
  `https://gazeunlock.com/api/latest`; `:5` — fallback page is
  `https://gazeunlock.com/releases`; `:6` — feed cap 512 KiB.
- `Sources/App/ReleaseURLPolicy.swift:8-16` (`isTrusted`) — final URL must be
  `https`, host exactly `gazeunlock.com`, no userinfo, no fragment.
  Redirects off-origin are refused (`:35-45`).
- `Sources/App/ReleaseURLPolicy.swift:18-21` (`download`) — a `download.url`
  is accepted only if it is ≤4096 chars and passes `isTrusted`. Anything else
  (Blob host, `http:`, relative path) yields `nil`.
- `Sources/App/ReleaseUpdateChecker.swift:122-127` — non-2xx (including 404)
  becomes `.failed("The update server answered \(code).")`, which is shown
  verbatim in Settings (`Sources/App/SettingsView.swift:864`).
- `Sources/App/ReleaseUpdateChecker.swift:209-222` (`Feed`) — wire format:
  `{ "latest": { "tag": String, "name": String, "notes": String,
  "download"?: { "url": String } } | null }`.
  Extra keys are ignored by `Decodable`; missing required keys fail the feed.
- `Sources/App/ReleaseUpdateChecker.swift:147-151` — **`latest: null` is the
  defined safe answer for "no approved release"**: state becomes `.upToDate`,
  silent. No app change is needed for that case.
- `Sources/App/ReleaseUpdateChecker.swift:160-166` — on a newer tag the app
  offers and `openDownload()` (`:175-180`) opens the trusted `downloadURL`,
  else falls back to `https://gazeunlock.com/releases`.
- Version compare is numeric on both sides (`isNewer`,
  `ReleaseUpdateChecker.swift:191-205`; site `compareTags`,
  `src/app/api/latest/route.ts:42-51`) — `0.10 > 0.9` on both. Consistent.

## 2. What the site already provides (local source — NOT deployed behavior)

- `src/app/api/latest/route.ts:53-90` — public `GET`, no auth gate (unlike
  `/api/releases`, which is owner-only at `src/app/api/releases/route.ts:7-19`
  and would 403 the app; the route comment at `:4-11` says exactly this).
- Filters `draft` and `private` server-side, sorts numerically, prefers the
  newest non-prerelease (`:59-63`); returns `{ latest: null }` with 200 when
  nothing qualifies (`:65-72`); 5-minute edge cache (`:86-89`).
- Payload shape is a superset of what the app decodes:
  `{ tag, name, date, notes (= body ?? ""), prerelease, download | null }`.
  `tag`/`name` are required at write time (`src/app/api/releases/route.ts:26-30`),
  `body` defaults to `""`, `download` to `null` (`:64-76`). Compatible: extra
  keys (`date`, `prerelease`, `download.name/size`) are ignored by the app.
- Verified locally against `data/releases.json`: published set is `["0.3"]`
  (draft `0.4` and private tester-only `0.10` correctly excluded), so a local
  `GET /api/latest` would answer `latest.tag = "0.3"` with
  `download.url = "https://gazeunlock.com/dl/Gaze-0.3.dmg"`.

## 3. Specific cause — established vs. still uncertain

Established (source inspection + lead's live 404):

- The route exists in local source and its documented path/shape match the app.
  The live 404 shows that the expected response was not served; it does not prove
  which deployment, route or configuration produced that response.

Remaining hypotheses to check on the deployment side (read-only first):

1. **Stale deployment** — production build predates `src/app/api/latest/route.ts`.
   Evidence needed: Vercel deployment SHA/date for `gazeunlock.com` vs. the
   commit that added the route; response headers on any site URL (`x-vercel-id`,
   `age`, `cache-control`) to see what is actually served.
2. **Domain points elsewhere** — `gazeunlock.com` serves a different project /
   static host that has no `/api/*`. Evidence needed: Vercel project → custom
   domain mapping for `gazeunlock.com`; DNS / `Host` check of what answers.
3. **Production-specific routing/configuration** — middleware, rewrites or
   a different deployed app version may serve a different path or response.
   The inspected local contract agrees; the live contract remains unverified.

Also note the production *content* is unknown from here: site reads releases
from Vercel Blob when a token is present (`src/lib/storage.ts:30-49`), falling
back to `./data` only locally. Even after the route deploys, production may
answer `{ latest: null }` (empty/unseeded Blob store) rather than `0.3`. That
is a *safe* answer (app stays silent, §1) but the lead should know which to
expect before calling the feed "verified".

## 4. Minimal patch proposal (compatible with the current app)

**Primary recommendation: no app patch. Fix deployment, not code.**

Site side (no new endpoint needed — it exists):

- Redeploy the Next.js app to the production target serving `gazeunlock.com`
  so `/api/latest` goes live; confirm the domain → project mapping.
- Seed or verify the production Blob `releases.json`: either an approved
  public release (draft=false, private unset) or intentionally nothing (then
  expect `{ latest: null }`, which the app treats as up to date).
- Decide download hosting (see §5) before announcing updates.

App side: **do not** remap 404 → `.upToDate` to silence the error. A 404 means
"feed not deployed / domain wrong" — swallowing it turns a loud, fixable
misconfiguration into a quiet one where users silently never hear about
updates. The current `.failed("The update server answered 404.")` is honest
and is the right behavior until the feed is verified live. A deployment problem must not be hidden by treating 404 as up to date.

Safe behavior when no approved release exists is already correct on both
sides and needs no change: site `200 { latest: null }`
(`src/app/api/latest/route.ts:65-72`) → app `.upToDate`
(`ReleaseUpdateChecker.swift:147-151`).

## 5. Download-hosting gap (separate from the 404 — fix before offering updates)

- Seed data points at `https://gazeunlock.com/dl/Gaze-0.3.dmg`, but site source
  has no `/dl` route and no redirect/rewrite for it (checked `src/app/**`,
  `middleware.ts` only guards `/admin/*`). That URL currently serves nothing
  from this app.
- Composer-uploaded builds go to Vercel Blob (`src/app/api/upload/route.ts`
  hands the browser a direct-to-storage token; `release-composer.tsx:332-361`
  attaches the returned Blob URL). A Blob URL host (e.g.
  `*.public.blob.vercel-storage.com`) fails `ReleaseURLPolicy.isTrusted`, so
  the app discards it and `openDownload()` falls back to opening
  `https://gazeunlock.com/releases` — safe, but not a direct download.
- Pre-launch decision needed (pick one): serve builds from a same-origin path
  (add a `/dl/*` route or redirect to Blob — a site change for the site owner,
  out of scope for this note), or accept the `/releases`-page fallback and
  make sure that page (including the `releasesRequireSignIn` gate in
  `src/app/releases/page.tsx:34-37`, which redirects signed-out visitors to
  `/signin`) is reachable to the people the update is offered to. Note the API
  itself is unaffected by that gate.

## 6. Minimal verification before launch (for the lead; none performed here)

1. `curl -i https://gazeunlock.com/api/latest` — expect `200`,
   `content-type: application/json`, `Cache-Control: public, max-age=300,
   s-maxage=300`, body `{ latest: null }` or a release with string
   `tag`/`name`/`notes` and `download: null | { url, name, size }`.
2. Confirm `download.url`, if present, is `https://gazeunlock.com/*` (else the
   app falls back to `/releases` — acceptable only if that is the intent).
3. Confirm `https://gazeunlock.com/releases` loads for a signed-out visitor
   (settings gate state as intended for launch).
4. In-app: Settings → Released version → Check shows the offered release or
   "You're on the latest release" — never the 404 message. Record the exact
   feed body seen alongside the app version under test.
5. Do not close on a cached 200: re-check after the 5-minute edge window or
   with cache-busting headers if a release was just published.
