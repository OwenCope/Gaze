# Markdown Safety — report (Ivo 2)

## Demonstrated issue (synthetic strings only, no real user content)
`src/lib/releases.ts` `toRelease` renders release bodies with `marked.parse(r.body)` and
`src/app/testers/page.tsx` renders the readme with `marked.parse(readme)`; both reach
`dangerouslySetInnerHTML` (testers page directly, release `[tag]` page via `release.html`).
Probed the site's own `marked@18.0.9` in isolation — raw HTML passes through verbatim:

- `<script>alert(1)</script>` → unchanged
- `<img src=x onerror=alert(1)>` → unchanged (event handler kept)
- `[click](javascript:alert(1))` → `<a href="javascript:alert(1)">` (unsafe scheme kept)
- `<svg onload=alert(1)>`, `<iframe src="https://evil.example">` → unchanged

No production content was loaded or published; no breach is claimed.

## Fix
New shared server-only renderer `src/lib/render-markdown.ts` exporting
`renderMarkdown(source: string): string`: `marked.parse(source, { async: false })` then
maintained `sanitize-html` (no regex sanitizer). Allowlist exactly: `p, br, strong, em,
del, s, blockquote, ul, ol, li, h1–h6, pre, code, hr, table, thead, tbody, tr, th, td,
a, img`; attrs only `href/title` on `a`, `src/alt/title/width/height` on `img`.
`allowedSchemes: [http, https, mailto]`, `allowedSchemesByTag: { img: [https] }`
(relative links/images still pass; http images drop to `<img/>`),
`allowProtocolRelative: false`, `disallowedTagsMode: "discard"`.
Only the two direct `marked.parse` call sites now use it; auth/metadata/storage/layouts
untouched. The `[tag]` page needs no edit — it consumes the now-sanitized `release.html`.

## Dependencies (installed in isolation with `npm install --ignore-scripts`)
- `sanitize-html@2.17.7` (dependencies), `server-only@0.0.1` (dependencies),
  `@types/sanitize-html@2.16.1` (devDependencies). `marked` stays `^18.0.9`.

## Files delivered (under `Tools/Release/MarkdownSafety/`)
- `patches/markdown-safety.patch` — `package.json`, `src/lib/releases.ts`,
  `src/app/testers/page.tsx`, new `src/lib/render-markdown.ts`. Verified with
  `patch -p1 --dry-run` and a full apply: OK.
- `sources/` — final copies of the above plus `package.json` and
  `package-lock.candidate.json` (see limits).
- `tests/fixture.mjs` (+ `tests/tsconfig.json`) — 56-assertion structural runner
  (tag/attribute scanner, not substring-only) executed against the actual staged
  renderer compiled with `tsc` and run as `node --conditions=react-server`
  (required so `server-only` resolves to its `react-server` empty export).

## Tests — 56/56 pass
Unsafe stripped: event handlers, `<script>`, SVG, iframe, form/input, malformed nested
HTML, entity/hex/mixed-case `javascript:`, `vbscript:`, `data:` links, protocol-relative
link/img URLs, `style` attrs, `data:` images. Safe kept: h1/lists/tables, https + relative
+ `mailto:` links, https + relative images with alt/title, escaped fenced code
(`&lt;script&gt;` inside `pre>code`, no real `<script>`), inline strong/em/del/code,
http-link-kept vs http-image-dropped policy.

## Build / typecheck
- `tsc --noEmit` on the renderer with real `marked`/`sanitize-html` types: exit 0.
- `tsc` emit + fixture: 56 passed, 0 failed.
- Full `next build` NOT run in isolation: fresh `npm install` of the whole site fails
  here on the private `@aiforui/lapse` scope (`https://aiforui.dev/npm/`, 404 without
  local auth), and no `.env`/real `data/` was copied per constraints. Root should run
  `npm install --ignore-scripts && npm run build` on localhost after applying.

## Remaining limits
- `package-lock.candidate.json` is machine-merged (real lock + 20 entries:
  sanitize-html + nested htmlparser2@12 chain, @types/sanitize-html, server-only,
  parse-srcset, is-plain-object, launder, dayjs, htmlparser2@10 chain), reusing the
  real lock's identical deepmerge/escape-string-regexp/postcss versions with no other
  churn. Treat as candidate: let Root's localhost `npm install --ignore-scripts`
  confirm/regenerate the authoritative lock.
- Sanitizer keeps link text and drops only the unsafe `href`/`src` (e.g. `<a>x</a>`);
  reviewers should confirm that UX is acceptable for tester notes.
- `server-only` import means `renderMarkdown` can only be used from Server
  Components/routes — true of both call sites today; any future client-side caller
  needs its own approach.

## Root integration result

Applied locally. Candidate lock had zero changed/removed existing dependency
entries; npm install --ignore-scripts --offline added twenty packages successfully.
The actual current renderer passes 56 fixture checks via tests/run-current.cjs.
Root replaced the hand-written scanner with installed htmlparser2's real parser.
Full combined production Next build, TypeScript and changed-source lint pass.
No publication or production content/configuration was involved. The release
view-model's download filtering is a separate subsequent integration patch.
