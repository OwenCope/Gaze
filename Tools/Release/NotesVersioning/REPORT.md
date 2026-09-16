# Reject stale tester-note edits without losing the draft (Vera 2)

## Root integration, September 16, 2026

Applied locally to gaze-site. Root tightened acknowledgement validation to reject
`missing`, retained known conflicts through failed retries, guarded reload while
saving, and clarified copying wanted edits before reload. The patch and source
copies now include these corrections. Browser checks passed; see BROWSER-RESULT.md.
Current-source notes, metadata concurrency and privacy suites pass, as do full-site
TypeScript and lint of the five integrated files. The older notes-route harness was
updated to this version protocol and passes 18 cases. Nothing deployed.

After integration use `node Tools/Release/NotesVersioning/test-notes-versioning.cjs --current`.
The patch is for the pre-versioning baseline, not an already integrated checkout.

## Original head delivery

Date: 2026-09-16. Scope: five gaze-site files only —
`src/lib/storage.ts` (4-line extension), new `src/lib/readme.ts`,
`src/app/admin/readme/page.tsx`, `src/app/api/readme/route.ts`,
`src/components/readme-editor.tsx`. Everything lives under
`Tools/Release/NotesVersioning/`; gaze-site was read-only (compared/diffed,
never written). No git, real notes, `.env`, auth/Blob calls, deployment, or
new dependency. All test strings synthetic (`seed-A`, `A`, `B`, `racer`).

Docs consulted: worktree `AGENTS.md`, `no-agent-messaging` (local work, no
coordination needed), gaze-site `AGENTS.md` (Next agent-rules block) +
installed `next/dist/docs/01-app/02-guides/forms.md` (scoped shortcuts,
disabled-while-submitting, live-region messaging), `emil-forms-and-inputs`
(label association, 16px kept, real `<button>` disabled with `Saving…`,
Cmd/Ctrl+Enter on textareas, `confirm()` floor for the destructive reload).

## What was done

- `storage.ts`: `MetadataMutationKey` and the runtime `MUTATION_KEYS`
  allowlist gain `'readme.md'`; `mutateMetadata` takes `MetadataMutationKey`;
  the Blob conditional put uses `text/markdown` for `readme.md`,
  `application/json` otherwise. `validateMetadata` already treats readme as
  text. Private credentials, missing-migration refusal, ETag CAS,
  five-attempt bound, local per-key queue, and atomic temp publication are
  byte-unchanged; unrelated helpers untouched.
- `readme.ts` (new): `ReadmeConflictError`, `versionForReadme(raw)` →
  `'missing'` for `null` else SHA-256 hex of UTF-8 text (so existing `""` and
  a missing local document version distinctly), `readReadmeDocument()` →
  `{text, version}`, `saveReadmeDocument(text, expectedVersion)` via
  `mutateMetadata('readme.md', …)` whose callback compares versions BEFORE
  building next state and throws on mismatch. Blob-missing still refuses
  before the callback — never inferred empty.
- `page.tsx`: unchanged auth gates, then `readReadmeDocument()` and
  `<ReadmeEditor initial={readme} initialVersion={readmeVersion} />`.
- `route.ts`: root's strict readme validation kept; `expectedVersion` must be
  `'missing'` or 64 lowercase hex or the route returns an actionable
  400 asking to reload (covers old version-less clients); success returns
  `{ok:true, version}` with both revalidations; stale throws map to 409.
  Admin gate first, no GET, no public exposure.
- `readme-editor.tsx`: `initialVersion` prop; `version` (last acknowledged)
  tracked separately from `text`; each save POSTs the captured
  `{readme, expectedVersion}` and advances `version`/`savedText` only on a
  valid `{ok:true, version}` response — so B typed during A's flight stays
  unsaved yet its next save uses A's acknowledgement. 409 keeps the draft,
  announces the conflict, and shows `Reload saved notes`, which confirms
  natively ("…replaces your unsaved text…") and reloads only on accept;
  cancel preserves everything. No force-overwrite, merge, autoreload, or
  clipboard. Root's duplicate guard, exact Cmd/Ctrl-only shortcuts, labels,
  foreground/destructive contrast, and acknowledgement validation kept.

## Files delivered (this directory only)

- `notes-versioning.patch` — applies with `patch -p1 --fuzz=0` from the
  gaze-site root; touches exactly the five files above.
- `storage.ts`, `readme.ts`, `page.tsx`, `route.ts`, `readme-editor.tsx` —
  final source copies the patch reproduces (asserted byte-identical).
- `test-notes-versioning.cjs` — synthetic suite (below).
- `fixture/{entry.tsx,index.html,build.sh,serve.py,stubs/}` — runnable
  browser proof harness (bundle generated, not stored).
- `REPORT.md` (this file), `BROWSER-RESULT.md` (fixture status + runbook).

Run: `node Tools/Release/NotesVersioning/test-notes-versioning.cjs`
(`GAZE_SITE_DIR` overrides; `--current` checks live files post-apply).

## How it was checked — and what it is NOT

SDK-stub evidence (not live-service testing): the suite transpiles the
ACTUAL staged sources with the site's installed TypeScript and executes them
against a versioned in-memory fake Blob store (real conditional semantics via
the REAL installed `BlobPreconditionFailedError`) plus the real filesystem.
No live Blob, network, auth, deployment, `.env`, or real data at any point.

```
PASS: patch scope is exactly the five readme files (no account/gallery/auth/env)
PASS: patch applies cleanly (fuzz=0) and reproduces the staged final copies
PASS: using the real installed BlobPreconditionFailedError (instanceof required)
PASS: versionForReadme: missing/empty/content vectors with distinct missing-vs-empty
PASS: Blob: two editors read one version, first succeeds, second gets 409-class conflict with zero overwrite
PASS: Blob: CAS race after the version check re-reads and then conflicts
PASS: unchanged content/version remains valid
PASS: Local: missing vs empty have distinct versions; creation from 'missing' works
PASS: Blob: missing private object refuses before the callback; never inferred empty
PASS: API: strict body validation, well-formed expectedVersion, actionable 400, {ok,version} success, 409 stale, 403 gates
PASS: content-type pinning (markdown vs json) with independent-record concurrency preserved
PASS: Local: serialized saves reject the stale second writer; atomic temp publication intact
PASS: static contract: versioned page/editor wiring with confirm-gated reload only
PASS: fixture imports the staged editor verbatim with a versioned transport stub
OK: all notes-versioning checks passed (staged sources executed, SDK stubbed).
```

- `tsc --noEmit` on a full site copy overlaid with the five staged files:
  only the 3 pre-existing baseline errors (layout `LayoutProps`,
  `app-icon` png modules) — zero new errors; our files clean.
- `eslint` (site config) on the five overlaid files: 0 findings.
- esbuild fixture bundle of the staged editor: exit 0.
- Browser: fixture ready but live drive blocked here (no paired BrowserOS
  session / `agent-browser` CLI in this worktree) — see `BROWSER-RESULT.md`
  runbook. Do not claim live-browser coverage.

## What the lead must know

1. **Independent-record behavior is preserved, not extended.** Concurrent
   tester/JSON edits still converge via CAS retry (proven in-suite); same-
   document stale notes edits now 409 instead of last-writer-win. Same-record
   field merges remain out of scope.
2. **Blob-first-save stays refused.** A missing private `readme.md` cannot be
   created through the API until migration copies it (fail-closed); local dev
   creates from `'missing'` normally. The 400 for old clients tells them to
   reload, which fetches the new editor + version together.
3. **Root integration order.** Land Walter 3's `mutateMetadata` first (this
   patch assumes its exact CAS/queue semantics — the staged `storage.ts` is
   that file plus 4 lines), then apply this patch with `--fuzz=0`, run the
   suite plus `test-notes-versioning.cjs --current`, re-run the metadata-
   concurrency and privacy suites (route no longer calls `writeReadme`; stub
   `saveReadmeDocument`/Blob `get`/`put` for mutation paths), and execute the
   `BROWSER-RESULT.md` runbook in paired BrowserOS before any deploy.
   AccountButton/ReleaseGallery untouched per ownership split.
4. **No production action taken.** No stores, credentials, migration, or
   deployment. Owner window noted (through 2026-09-16 04:25:16 UTC); nothing
   here needs it.
