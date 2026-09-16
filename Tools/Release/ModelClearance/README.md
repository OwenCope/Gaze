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
- `--skip-bytes` checks evidence records only (no disk access) and reports RECORDS_ONLY, never a release PASS.

## Artifact coverage

| Entry | Binds | Status |
|---|---|---|
| `face-embedding` | `FaceEmbedding.mlpackage` model + weights hashes (match NOTICE.md, re-verified here) | unresolved — no grant |
| `spoof-detector` | `Spoof.mlmodel` hash | unresolved — dataset sublicensing unreviewed |
| `setup-art` | 11 files, per-file hashes | unresolved — authorship unconfirmed |
| `credit-portraits` | 9 files, per-file hashes | unresolved — permissions unrecorded |
| `app-icon` | glyph + `icon.json` hashes | unresolved — authorship unconfirmed |

The lead checkout also contains precompiled `FaceEmbedding.mlmodelc` and
`Liveness.mlmodelc`; build.sh can copy these directly. They and the package
metadata are now fingerprinted. The legacy Liveness entry remains unresolved.
All `.mlmodel`, `.mlpackage` and `.mlmodelc` payload files, plus files under
Art/Credits/AppIcon.icon, require exact fingerprint coverage. Directory names
alone do not cover new payloads. Empty inventories, duplicate IDs and empty
byte identities are refused. The gate does not prove that precompiled weights
were derived from a neighbouring source package.

Release preflight invokes this validator. DIST=1 builds also refuse incomplete
clearance before staging an output. Local development builds remain available.
Fifteen synthetic validator cases pass; real clearance remains unresolved.

This validator checks recorded evidence and byte identity, not a legal
determination. It does not edit NOTICE.md, READINESS.md, app code, weights,
the release verifier, or the website.
