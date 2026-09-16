# Sapphire model source evidence — September 16, 2026

The owner supplied https://sapphire-app.tech/, whose source link identifies
https://github.com/cshariq/Sapphire. Its pinned repository LICENSE is GNU Affero
General Public License version 3 (AGPL-3.0), not the previously reported GPL-3.0.

Pinned commit: `ee56de09a0c5ab2cbf442858de36780a0cb151b2`.

The actual precompiled model's `Resources/FaceEmbedding.mlmodelc/weights/weight.bin`
(87,197,184 bytes) has the same Git blob SHA-1 as the pinned Sapphire weight file:
`004ee9ab6fbfb4fd0c4c34a2bc89be4db624ddf8`. SHA-256:
`c28620613d146a56565eadaacc22bbe9dd54533000ba79a6d666995a123c1545`.
See `sapphire-evidence/weight-match.json` for both paths.

This establishes matching weight bytes available in that repository. It does not
establish how they arrived locally, who trained them, upstream training-data
rights, or compatibility of the intended Gaze distribution. The 7.4 MB raw
FaceEmbedding.mlpackage in Gaze is a different artifact and remains unverified.

Reviewed pinned sources: repository LICENSE and README, model Metadata.json and
FeatureDescriptions.json, and the recursive tree's licence/model paths. No
model-specific licence exception or training provenance appeared in those files.
The model metadata names conversion tools/date only. This is not a complete
licensing history or a finding that no separate permission exists.

The copied licence and source files in `sapphire-evidence/` are evidence, not a
relicensing of Gaze. Its MIT licence is unchanged. Before distributing the model,
resolve weight/upstream coverage and applicable copyleft/source/notice obligations
or obtain another applicable grant. Clearance remains unresolved; no model was
replaced, removed or promoted, and no author was contacted.
