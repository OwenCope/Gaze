# Recognition regression and benchmark

Run `bash Tools/RecognitionRegression/run.sh` on macOS with Swift and the Apple SDKs.
The tests use synthetic vectors and generated pixels. They never open a camera or
access enrollment data, the Keychain, or credentials. Core Image needs access to
the graphics runtime; a restricted execution sandbox may need an explicit grant.

The suite compiles the production matcher, embedder, cropper, frame-quality gate,
enrollment model, and asynchronous evaluator with synthetic capture/storage types.
It covers corrupt vectors, model/dimension mismatches, agreement within one face,
separation between identities, scalar/Accelerate numerical agreement, legacy
single-print records, enrollment identity changes, invalid pose, measured-zero
versus unavailable quality, required anti-spoof gating, and oversized crop edges.

The timing probe compares the previous scalar best-template calculation with the
prepared two-template matcher, using 64 templates of 512 floats and 2,000 queries.
It excludes index construction, camera capture, Vision and neural inference. It is
not an end-to-end unlock latency measurement and has no timing assertion.

## Matching behavior

Multi-print enrollments now need two prints at or above the existing threshold.
The displayed score is the second-highest score within a single enrolled face.
Legacy single-print records retain their one-score behavior. Enrollment records
and embedding coordinates are unchanged, so this change alone requires no migration.
New neural enrollment captures must also match the initial frontal capture.

This rejects isolated high-scoring templates but may also increase false rejects,
particularly for old enrollments with poor pose coverage. Re-enrolling collects
consistent samples; it does not replace validation with the actual model.
Thresholds have not been lowered or claimed calibrated. Existing movement,
camera pinning, continuity, anti-spoof, and password-submission gates still apply.

The repository has no FaceEmbedding weights or labeled evaluation dataset. These
tests establish code behavior, not real-world recognition accuracy. Validate
false-accept and false-reject rates across people, poses, lighting, and presentation
attacks before relying on a model-equipped build for authentication.
