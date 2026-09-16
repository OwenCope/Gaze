# Migration receipt: offline local-export comparison

Proves that two **local exported directories** held byte-identical metadata at
inspection time. Nothing is deployed, copied, uploaded, deleted, or read from
production by this tool.

## Exact invocation

```sh
python3 Tools/Release/MetadataPrivacy/migration_receipt.py \
  --source-dir <explicit-local-export-dir> \
  --candidate-dir <explicit-local-export-dir> \
  [--out receipt.json]
```

Both directories must already exist locally and each must contain regular files
named exactly `releases.json`, `testers.json`, `roles.json`, `settings.json`,
and `readme.md`. On success the tool prints a versioned JSON receipt to stdout
(and to `--out` when given); on any failure it prints `<fixed-name>: <reason>`
to stderr, creates no receipt, and exits nonzero.

## Scope: what the receipt does and does not prove

- Proves: the five named local exports matched **byte-for-byte** at inspection
  (byte counts plus SHA-256 hashes, verdict `LOCAL_EXPORTS_MATCH`).
- Does NOT prove which store supplied either directory, that the private store
  was provisioned correctly, or that any live cutover succeeded. The tool takes
  directory paths only; provenance is the owner's responsibility.
- The receipt contains only fixed document names, byte counts, hashes, version,
  and verdict — no document contents, account identities, paths, or credentials.

## Checks enforced

- Exact bytes required: semantically equivalent JSON with different bytes fails.
- `releases.json` / `testers.json` / `roles.json` must parse as JSON arrays;
  `settings.json` must parse as a JSON object; `readme.md` must be UTF-8 text.
  UTF-8 or JSON failures refuse, including NaN/Infinity.
- Missing documents are never inferred as empty; there is no auto-initialization.
- Symlinks and directories refused; each file capped at 8 MiB; files that change
  during reading (descriptor stat comparison) refused.
- `--out` is published from a complete, synced temporary file using a no-overwrite hard link; an existing file/symlink is never replaced.
- No copy or remote action: read-only comparison plus receipt emission.

## Owner actions (lead owns; not performed here)

1. Obtain both exports over authenticated access yourself; confirm which store
   each directory came from.
2. Provision the separate private store (never reuse the public store's
   credentials for it).
3. Copy (not move) the five objects into the private store as private objects
   under identical pathnames; keep public originals as the rollback source.
4. Run this tool on the two local exports; do not proceed on mismatch.
5. If a key is confirmed genuinely absent, consciously seed its intended initial
   value — never treat access/network/parse failures as missing data.
6. Verify production reads after cutover. Old public objects require a separate
   reviewed cleanup; that deletion is deliberately out of scope here.

## Verification and limitations

- `python3 Tools/Release/MetadataPrivacy/test_migration_receipt.py` — 14 tests
  pass (exact match; byte-diff despite equivalent JSON; missing file; corrupt
  JSON; incorrect root shape; invalid UTF-8; symlink; oversized input; existing
  file and symlink `--out` refusal; no receipt on failure). Synthetic fixtures
  only; no real exports inspected.
- Limitations: comparison is offline and local-only; it cannot authenticate a
  store, detect swapped-but-identical exports, or guard concurrent writers
  (read-before-write is not compare-and-swap). TOCTOU beyond the read window is
  out of scope — re-run at cutover time.

Lead corrections add nonstandard-JSON refusal, descriptor/path identity and ctime checks, read-error handling, and no partial receipt when writing fails. Injected fsync failure is covered by the tests.
