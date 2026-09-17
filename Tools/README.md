# Development tools

| Task | Start here |
| --- | --- |
| Package an installer | [Release/DMG](Release/DMG/README.md) |
| Check release readiness | [Release](Release/README.md) |
| Preview Gaze without the live unlock flow | [GazePreview](GazePreview/README.md) |
| Work on the passwords companion | [GazePasswords](GazePasswords/README.md) |
| Evaluate experimental models | [ModelLab](ModelLab/README.md) |
| Check onboarding | [OnboardingRegression](OnboardingRegression/README.md) |
| Check Settings interactions | [SettingsInteractionRegression](SettingsInteractionRegression/README.md) |
| Check unlock behavior | [UnlockFlowRegression](UnlockFlowRegression/README.md) |
| Check security boundaries | [SecurityRegression](SecurityRegression/README.md) |

Other `*Regression` directories contain focused checks and their own runners.
Generated binaries, logs and captures belong in `build/`. Older local outputs are
grouped under `build/archive/`; each cleanup has a manifest mapping the old paths.
