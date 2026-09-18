# Setup Back-navigation regression

```sh
bash Tools/SetupBackRegression/run.sh
```

Compiles the real `Sources/Setup/SetupPlan.swift` with a pure-Swift harness —
no app services, camera, or credentials — and checks Back/forward routing across
password, permission, and enrollment flags in legacy and welcome-tour modes,
including forced stages and add-face.

Saved-capture invariant: once a plan includes `.capture`, traversing Back from
`.password` or `.permission` never reaches `.capture` or `.welcome`. The flow
keeps its plan fixed for the run, so any route back through welcome could lead
through capture again and repeat a saved enrollment. Enrolled plans without
capture keep their Back path to welcome, and capture itself can still back out
before it completes.
