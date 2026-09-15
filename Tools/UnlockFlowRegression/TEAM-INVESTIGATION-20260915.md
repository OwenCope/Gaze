# Independent head-turn flow review — September 15, 2026

Scope: production-source and existing-artifact review only. No camera session, lock,
credential/enrollment access, production edit, GPU test, rebuild or relaunch was performed.
The lead owns current runtime capture and artifact identification. This report does not
establish what binary is currently running or that the reported failure is fixed.

## What the existing evidence supports

The yaw-sign correction is supported for the recorded camera/preview configuration.
The recorded mirrored face points left while its raw yaw is positive; production
`LivenessChallenge.consume` now accepts positive yaw for left. The existing image audit
compares Vision and landmark fallback on the same pixels and verifies sign agreement.
`build/head-pose-image-tests-20260915.log` reports eight passing nonfrontal comparisons;
`build/head-direction-control-20260915.log` reports old-sign failures and corrected-sign
successes for the chosen scalar trajectories. This is stronger evidence than old comments.

It is not an authentication replay. `Tools/HeadPoseRegression/Tests.swift:17` prepares
three chosen baseline readings and directly feeds two excursions plus a return. It does
not reconstruct the actual lock-screen baseline, frame admission, inference timing,
identity/PAD results, intermediate failures or second action. The image path checks
signs on extracted preview crops, not full production camera-to-password execution.

The inspected older runtime log independently confirms compared mismatches before
movement acceptance: `build/guidance-baseline-runtime-20260915.log:917` onward has four
right-turn failures with scores 0.199080, 0.444739, 0.427117 and 0.202308, all
`compared=true`, `belowThreshold`, `returning=false`, plus one face-unavailable reset.
Those events predate the sign correction. They justify neither lowering a threshold nor
retaining movement proof across a mismatch. They do not establish a current failure.

## Remaining source-level edge cases

### 1. Return wording and accepted return position can disagree

`LivenessChallenge.swift:172` accepts any stable three-sample pose as the baseline.
`LockWatcher.swift:607` prepares it from verified frames before presentation, but has no
frontal-pose requirement. `LivenessChallenge.swift:240` completes a turn only within
0.10 rad of that baseline, while line 87 says “Face the camera again.”

Concrete scalar case: baseline +0.20 repeated three times; left excursion +0.55 twice;
return to frontal yaw 0.00. Movement is observed, but the frontal return cannot complete
because its offset is -0.20. Returning to +0.20 completes. Current diagnostic tests
explicitly exercise the latter (`Tools/UnlockFlowRegression/Tests.swift:153`) and do not
exercise following the camera-facing wording to zero. This is a source-level guidance
mismatch; there is no evidence that the user's actual baseline had this offset.

Bounded next step: add that exact nonfrontal-to-frontal scenario, including retry
reacquisition at a nonfrontal pose. If live evidence shows it matters, align guidance with
return-to-start semantics or design an explicit initial centering phase. Do not silently
widen return tolerance or change the relative challenge into an absolute one.

### 2. Consumed-frame gaps can reset proof despite a continuous camera

`RecognitionFrameGate.swift:73` calls a frame continuous only when its capture timestamp
is within 240 ms of the previously *consumed* frame. `LockWatcher.swift:428` sleeps 60 ms
per iteration and line 519 awaits evaluator work before polling again. At lines 450–453,
an excessive consumed-frame gap resets identity hold and movement proof. Separately,
`CameraEvidenceContinuity` tracks every delivered usable camera frame.

Consequently, continuous camera delivery does not prevent a reset if inference plus
polling/actor scheduling puts consumed captures more than 240 ms apart. For example,
continuous 30 Hz capture combined with roughly 200 ms evaluation and 60 ms sleep can
skip enough captures to trip this gate while the evaluated sample remains under its
500 ms lease. Exact behavior depends on capture phase and scheduling. The inspected
historical mismatch cluster does not demonstrate this timing case.

Bounded next step: instrument or capture evaluator duration, consumed-frame gap and
camera continuity revision as separate quantities; test this scheduling scenario using
synthetic clocks. Preserve explicit continuous identity-evaluation requirements. Do not
simply delete a continuity gate because camera delivery alone cannot prove identity on
unexamined frames. If observed, reducing avoidable polling delay or inference cost is a
safer first direction than weakening the evidence policy.

### 3. Pose-source changes have no continuity semantics

`CameraController.swift:342` independently uses Vision yaw/pitch/roll when present and
fallback values otherwise. `FacePose.swift:17` explicitly says fallback magnitudes are
not calibrated replacements for Vision. `FaceSample.pose` contains no source marker,
and the challenge subtracts its stored baseline from whichever estimate arrives next.

A source transition can therefore appear as motion or prevent a return despite a
stationary physical pose. Correcting signs does not calibrate offsets or scales. Neither
the recordings nor the inspected logs show that a source transition actually occurred;
this remains an unobserved implementation risk, not the diagnosed cause.

Bounded next step: record axis-source availability in temporary in-memory diagnostics;
test source switches at baseline, excursion and return. A potential fix would invalidate
and rebuild affected pose proof on source changes, rather than mix incomparable axes.
Prove the behavior with production pose construction and finite-value tests before
changing this authentication path.

## Test and observability gaps

The saved direction suite reports 565 checks across challenge/input, evaluator,
continuity, frame timing and diagnostics. The runner compiles these pieces separately;
it does not compile and execute `LockWatcher` as an integrated state machine. The tests
are useful invariants but cannot validate scheduling and ordering between all gates.

For a bounded integrated harness, use deterministic actions and scripted capture,
evaluation and presentation times. Cover both turn directions, the 350 ms admission
boundary, two qualifying admitted excursion frames, same-frame return processing,
nonfrontal baselines, a mismatch on return, a camera gap during inference, the interval
between actions, and loss after the second action but before submission. Assert both
guidance transitions and refusal of submission. Reuse production transition logic;
duplicating the watcher in a test would not establish its correctness.

The current in-memory movement-failure diagnostic is populated only for identity
failure (`LockWatcher.swift:539`). A timeout or quality/continuity reset does not retain
the same phase/relative-pose snapshot. Timeout logs say only that the challenge was not
answered, whereas observed-turn logs distinguish return from excursion. A small
diagnostic improvement would preserve action, phase, failure category, admitted-frame
counts and timing at all terminal/reset paths, with sensitive angles remaining in
memory as they do today. This would resolve more uncertainty than another scalar
success replay.

No new production fix is established by this review. The sign correction has specific
support; real lock-screen reliability and password-submission success remain separate
verification questions. A new user-performed reproduction must identify the exact
artifact and correlate return acceptance, all reset reasons and final execution outcome.
