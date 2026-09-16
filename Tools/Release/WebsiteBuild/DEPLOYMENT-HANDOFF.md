# Website production build + deployment handoff

Isolated `next build` of the integrated website (lead's privacy/download
patches in `src/app/api/latest/route.ts`, `src/app/dl/[file]/route.ts`,
`src/lib/release-download.ts` included as-is, not re-audited). Passes.
No deploy, upload, domain, release-record or live-service change occurred.

## Result

- `next build` (Next 16.3.0 Turbopack, Node v24.19.0, site's installed
  deps copied to a temp dir): **success** — compiled, TypeScript, 25/25
  static pages. Zero errors in `build/website-build-check/build.log`
  (the single "error" string is inside a non-blocking Edge warning, below).
- Smoke (`next start` + curl, synthetic config): `/` 200, `/releases`
  200, `/api/latest` 200 serving the fixture with `download: null`,
  `/dl/Gaze-0.3.dmg` 404 (no such record in fixture data, as expected).
- Reproduce: `sh Tools/Release/WebsiteBuild/website-build-check.sh [--smoke]`
  Logs land in `build/website-build-check/` (git-ignored). Temp copy is
  removed on exit; the real website checkout is only read, never written.

## Routes in this build (from build output)

Static: `/`, `/credits`, `/features`, `/how-it-works`, `/security`,
`/apple-icon.png`, `/icon.png`, `/opengraph-image.jpg`,
`/twitter-image.jpg`, `/robots.txt`, `/sitemap.xml`, `/_not-found`.
Dynamic: `/admin`, `/admin/[tag]/edit`, `/admin/new`, `/admin/readme`,
`/admin/testers`, `/api/auth/[...nextauth]`, `/api/latest`,
`/api/me`, `/api/readme`, `/api/releases`, `/api/roles`,
`/api/settings`, `/api/signin-code`, `/api/testers`, `/api/upload`,
`/dl/[file]`, `/releases`, `/releases/[tag]`, `/signin`, `/testers`,
plus middleware proxy on `/admin/:path*`.
Both patched routes are present: `ƒ /api/latest`, `ƒ /dl/[file]`.

## Required environment variable NAMES (values stay with the owner)

Build-time minimum proven: `AUTH_SECRET` alone (synthetic dummy suffices).
Production runtime names — `.env.example` plus code-only names marked (*):

`AUTH_SECRET`, `AUTH_TRUST_HOST` (non-Vercel hosts only),
`AUTH_GOOGLE_ID`, `AUTH_GOOGLE_SECRET`, `AUTH_GITHUB_ID`,
`AUTH_GITHUB_SECRET`, `AUTH_APPLE_ID` (*, provider stays dark until set),
`ADMIN_EMAILS`, `BLOB_READ_WRITE_TOKEN`, `BLOB_STORE_ID` (Vercel sets
these itself; one suffices), `RESEND_API_KEY` (*), `SIGNIN_EMAIL_FROM` (*),
`ANALYTICS_TOKEN`, `ANALYTICS_PROJECT_ID`, `ANALYTICS_TEAM`,
`GITHUB_TOKEN`, `GITHUB_REPO`.

The metadata privacy change also requires `BLOB_PRIVATE_READ_WRITE_TOKEN`, or
`BLOB_PRIVATE_STORE_ID` with an explicit runtime `VERCEL_OIDC_TOKEN`. These must
refer to a separate private store; see `../MetadataPrivacy/METADATA-PRIVACY-HANDOFF.md`.
`AUTH_APPLE_SECRET` is also documented for the optional Apple provider.

The lead added `AUTH_APPLE_ID`, Auth.js-inferred `AUTH_APPLE_SECRET`,
`RESEND_API_KEY` and `SIGNIN_EMAIL_FROM` to `.env.example`, with empty values.
These configure optional providers; they are not all mandatory for deployment.

## Still needs the owner (not verified here)

1. Vercel env values for the names above; Blob store for
   releases/testers/readme/roles JSON (Vercel wires `BLOB_*` itself).
2. OAuth redirect URIs for the production domain (Google + GitHub
   consoles); Apple Services ID/key if Apple sign-in is ever wanted.
3. Production domain/DNS if not already live.
4. A cleared, signed app artifact published via the owner-only release
   composer — until then the feed offers `download: null` and the app
   uses its releases-page fallback. No placeholder binaries, ever.
5. Live `/api/latest` still returns 404: production is serving a build
   that predates the download patch. Deploying this build publishes the
   patched feed and the `/dl/` route together.

## Limitations of this check

- Synthetic `AUTH_SECRET` and a synthetic single-public-release fixture
  (`data/*.json` excluded from the copy). This proves the build, not
  production wiring: Blob contents, OAuth, Resend email, analytics, and
  real draft/private/tester gating are unverified.
- Built on this laptop, not the Vercel build image.
- The original run's Edge crypto warning was later confirmed to cause an actual
  /admin 500, so it was not merely cosmetic. The guard has been moved to Node-based
  proxy. Synthetic local smoke uses AUTH_TRUST_HOST=true; real hosting/authentication
  configuration still needs separate validation.

## Safe to deploy independently of an app release

A successful synthetic build alone does not establish safe production deployment.
The fixture's absent build yields download:null, but production records must be
reviewed separately: the route validates URLs, not legal clearance or signatures.
Source inspection also shows release/tester/role metadata written with public
Blob access. Production metadata privacy and migration need review before shipping.
No production data was inspected here. App distribution additionally remains
blocked on Developer ID signing and model/asset rights.

## Lead script corrections

The runner now parses --smoke in any position, allowlists copied source inputs,
uses an empty child environment plus synthetic configuration, and builds/serves
from the temporary directory. Smoke serves only on loopback, uses a selected
ephemeral port and checks a unique fixture name. HTTP/body/cache expectations and
unauthenticated admin redirection are assertions; failures fail the command.
Exit/signal cleanup stops the owned server and removes the temporary copy.
Logs now include smoke.log. The corrected runner has passed a fresh verification;
the original results above came from the head's first run. The strengthened smoke
check found /admin returning 500 with a node:crypto Edge import error. The lead
moved the unchanged auth guard to src/proxy.ts, whose default Node runtime supports
that dependency; the corrected full smoke run now passes: /, /releases and /api/latest return 200,
/dl/Gaze-0.3.dmg returns 404 with the fixture, and unauthenticated /admin returns
302 to sign-in. The HTTP checks assert response bodies and cache behavior.

## Rollback

Vercel dashboard → previous deployment → instant rollback; no data
migration exists (deploys never touch Blob JSON). If the download
feature itself must come out after records reference `/dl/` URLs,
revert the feed mapping together with the route — removing the route
alone turns existing feed links into browser 404s (per
`Tools/Release/UpdateDeployment/UPDATE-DOWNLOAD-DEPLOYMENT.md`).
