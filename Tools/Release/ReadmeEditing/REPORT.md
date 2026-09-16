# Tester-notes save feedback — truthful Saved (Otto 2)

Date: 2026-09-16. Scope: `src/components/readme-editor.tsx` only. No backend,
auth, endpoint, request-shape, deployment, Blob, email, or config changes.
All test strings synthetic (`seed-A`, `A`, `B`, `C-draft`). No real notes read
or published. Real site (`/Users/owencope/Developer/gaze-site`) read-only.

## Demonstrated defect (in the pre-patch source)
`save` closed over `text` at submit time as `A`, but on success called
`setSaved(true)` unconditionally. A user typing `B` while the `A` request was
pending saw `Saved` for unsaved `B`. There was also no synchronous duplicate
guard (`busy` is async state), `res.json()` failures surfaced parser text, and
the textarea had no associated label, no busy/status semantics, and no
keyboard shortcut.

## Fix (`readme-editor.patch`, final copy `readme-editor.patched.tsx`)
Apply from the site root with `patch -p1 < readme-editor.patch`
(dry-run verified). Single file: `src/components/readme-editor.tsx`.
- `savedText: string | null` records the exact submitted text the server
  accepted; `saved = savedText !== null && text === savedText`, so `Saved`
  shows only while the live draft still equals what was saved. Typing `B`
  after submitting `A` clears the indication without any explicit reset.
- `const submitted = text` captured before the first `await`; only that
  snapshot is POSTed and marked saved. `setText` runs only from `onChange`,
  so a late response or `router.refresh()` never replaces a newer draft
  (client state survives refresh; `initial` is mount-only). Failures never
  touch `savedText`.
- `inFlightRef` checked-and-set synchronously before any `await`; duplicate
  click/keyboard submits while busy send one request. `busy` still disables
  the button with `Saving…`; the textarea stays enabled. `finally` clears
  both ref and `busy`.
- Endpoint and shape unchanged: `POST /api/readme`,
  `Content-Type: application/json`, `JSON.stringify({ readme: submitted })`
  (runtime-verified: method `POST`, headers `application/json`, bodies
  `["seed-A"]`, `["A","B"]`, etc.).
- `res.json()` wrapped: non-JSON error bodies fall back to `Could not save`
  instead of `Unexpected token…`; network rejections surface their readable
  message. `role="alert"` on errors, `role="status"` with `Saved` text on
  success, `aria-busy={busy}` on the textarea, associated
  `<label for="tester-notes">Tester notes</label>` + `id="tester-notes"`.
- `onKeyDown` on the textarea only (no global listener): `Cmd/Ctrl+S` and
  `Cmd/Ctrl+Enter` (`e.key === "Enter"` or case-insensitive `"s"`)
  `preventDefault()` then save; all other keys untouched. Button carries
  `title="Save (Cmd+S or Ctrl+S)"`. No new dependency.
- Docs consulted: installed Next `docs/01-app/02-guides/forms.md` (scoped
  `onKeyDown` + `requestSubmit` pattern, `disabled={pending}`, `aria-live`
  messaging), `emil-forms-and-inputs` (label association, 16px kept, real
  `<button>` disabled while submitting, Cmd/Ctrl+Enter on textareas),
  `emil-touch-and-accessibility` (existing 44px `min-h-11` target and
  `touch-manipulation` kept, no hover-gated function, shortcut hint).

## Browser proof (secret-free fixture, actual component)
Fixture: `fixture/` — `entry.tsx` imports `../readme-editor.patched.tsx`
verbatim via esbuild aliases (`next/navigation` → refresh-counting stub,
`@/components/ui/liquid-glass-button` → plain `<button>`); `fetch` for
`/api/readme` returns controllable deferred promises (`__t.resolveNextOk /
resolveNextErr / resolveNextNonJsonErr / rejectNext`). Rebuild with
`fixture/build.sh` (needs `NODE_PATH` to the site install, read-only), serve
`fixture/serve.py <port>` on `127.0.0.1`, drive with own-session
`agent-browser` (`--session otto2-… --executable-path '…/BrowserOS neo'`).
Observed on `http://127.0.0.1:8471/index.html`:
1. Submit `A`, type `B` while pending, resolve `A` → `{"draft":"B",
   "saved":false, "calls":["A"], "pending":0, "refresh":1, "err":null}`.
   No `Saved` for unsaved `B`; draft intact; textarea editable while pending
   (`editable:true`, button `Saving…` disabled).
2. Retry `B`, resolve ok → `{"draft":"B","saved":true,
   "calls":["A","B"],"statusText":"Saved"}` with `[role="status"]` present.
3. Type `C-draft`, save, `resolveNextErr('Nope synthetic')` →
   `{"draft":"C-draft","saved":false,"err":"Nope synthetic",
   "alertRole":true,"pending":0,"btnDisabled":false}`. Non-JSON error →
   `{"err":"Could not save","draft":"C-draft","saved":false}` (no
   `Unexpected token` leak). Network reject → `err:"Failed to fetch"`,
   draft kept, `parserLeak:false`.
4. Sync `btn.click(); btn.click()` → `{"calls":["C-draft"],"pending":1}`.
   Further Ctrl+S / Ctrl+Enter / click while in flight → still 1 call.
5. Label `"Tester notes"`, `for === id`, `aria-busy:"true"` while pending /
   `"false"` after; body-level Ctrl+S sends 0 (scoped, no global listener),
   textarea Ctrl+S / Meta+S / Ctrl+Enter each send, plain key neither saves
   nor prevents default.
6. Request shape at runtime: `{"method":"POST","headers":
   {"Content-Type":"application/json"}}`, URL `/api/readme`, body `{readme}`.
7. Fresh-bundle re-check after adding init capture: submit `A`, type `B`,
   resolve → `{"draft":"B","saved":false,"calls":["A"]}`.

## Static checks
- `tsc --noEmit` (strict, `react-jsx`, site `node_modules` resolution, stubbed
  `next/navigation` + button): exit 0.
- `eslint` with the site's `eslint.config.mjs` on the patched file: exit 0
  (only the harness pages-dir notice, no file findings).
- `patch -p1 --dry-run` of `readme-editor.patch` against a copy of the site
  file: OK.

## Files delivered (all new, under `Tools/Release/ReadmeEditing/`)
- `readme-editor.patch` — the only change to ship (one site file).
- `readme-editor.patched.tsx` — final source for review.
- `fixture/{entry.tsx,index.html,build.sh,serve.py,stubs/}` — reproducible
  proof (bundle `app.js` is generated, not stored).
- `REPORT.md` (this file).

## Limits / notes for the lead
- If runtime tooling is unavailable, do not substitute source-regex claims:
  rebuild the fixture and re-run the `__t` sequence above instead.
- Behavior after load: `Saved` appears only after a successful save in the
  session, not on mount, even when the draft matches `initial` — deliberate,
  so the indicator always means "this exact text was accepted".
- Fixture server used port 8471 on `127.0.0.1`; no other localhost servers or
  sessions touched. Browser session `otto2-readme-*` is mine; close when done.

## Root integration

Applied locally to gaze-site; nothing deployed. Source copies and the main patch now include the root corrections. See RESUME-HANDOFF-20260916.md and sibling BROWSER-RESULT.md where present for verification scope.

Root requires the {ok:true} acknowledgement, refuses malformed server input rather than clearing notes, and scopes shortcuts to unmodified Cmd/Ctrl combinations. Eleven actual-route cases and the browser A/B/HTML-response cases pass. fixture/serve.py serves only its own directory regardless of working directory.
