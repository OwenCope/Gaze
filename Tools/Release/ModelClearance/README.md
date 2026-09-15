# Model clearance gate — concrete check

Makes the "Model and asset redistribution evidence" gate in
`Tools/Release/READINESS.md` concrete: a machine-readable inventory plus a
narrow validator. It records evidence; it grants nothing.

## Files (all new, all under this directory)

- `clearance.json` — the inventory. Each entry binds artifact/version/hash
  to provenance evidence, licence/grant evidence, and intended
  redistribution scope. Absent evidence is `unresolved`, never inferred.
- `validate.py` — the validator (stdlib only).
- `test_validate.py` — `python3 -m unittest` suite with synthetic fixtures.
- `OWNER-TEMPLATE.md` — what the owner must supply per artifact.

## Preflight interface (for release preflight integration)

```sh
python3 Tools/Release/ModelClearance/validate.py [--json] [--skip-bytes]
```

- Exit `0` + `PASS: model clearance` — every required artifact is `cleared`
  with provenance refs, a recorded grant with evidence refs, full required
  scope, and matching bytes on disk.
- Exit `1` + `REFUSE: model clearance` — reasons listed (missing entry,
  unclear clearance, missing grant/refs, incomplete scope, changed
  size/hash, missing file, or a model file under `Resources/` with no
  clearance entry). `--json` emits `{"verdict", "reasons", "disclaimer"}`.
- `--skip-bytes` checks evidence records only (no disk access).

## Artifact coverage

| Entry | Binds | Status |
|---|---|---|
| `face-embedding` | `FaceEmbedding.mlpackage` model + weights hashes (match NOTICE.md, re-verified here) | unresolved — no grant |
| `spoof-detector` | `Spoof.mlmodel` hash | unresolved — dataset sublicensing unreviewed |
| `setup-art` | 11 files, per-file hashes | unresolved — authorship unconfirmed |
| `credit-portraits` | 9 files, per-file hashes | unresolved — permissions unrecorded |
| `app-icon` | glyph + `icon.json` hashes | unresolved — authorship unconfirmed |

Out of scope here: `Liveness.*` (absent from this copy; `verify.sh` does
not require it). If any `.mlmodel`/`.mlpackage` appears under `Resources/`
without an entry, the validator refuses until it is inventoried.

This validator checks recorded evidence and byte identity, not a legal
determination. It does not edit NOTICE.md, READINESS.md, app code, weights,
the release verifier, or the website.
