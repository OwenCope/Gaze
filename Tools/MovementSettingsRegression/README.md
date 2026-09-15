# Movement settings regression

`bash Tools/MovementSettingsRegression/run.sh` compiles the real
`Sources/App/Preferences.swift` against a minimal `UnlockBackendKind` stand-in
(the stub exists only so the harness avoids the backend's vault/embedder/capture
graph) and checks the Mac-unlock movement-count contract: raw values 1 and 2,
exactly two cases with no zero/off option, missing or invalid stored values
resolving to `.two`, and the Settings row labels.

The tests also round-trip both selections through real Preferences instances
with an isolated UserDefaults suite, including invalid values and types. The
suite is removed afterward. Tests never use `Preferences.shared` or change the
app's live preferences, camera, credentials or enrolment.
