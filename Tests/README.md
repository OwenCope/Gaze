# Tests

Each folder is a self-contained suite. Run one with `bash Tests/<Name>/run.sh`. None of them opens the camera, reads real credentials or touches the Keychain, except `MultiFace`, which downloads two synthetic faces to check recognition on photos with several people.

- `AppReadiness`
- `Enrollment`
- `EnrollmentStorage`
- `Hardening`
- `HeadPose`
- `LockScreenSecurity`
- `MovementSettings`
- `MultiFace`
- `Notch`
- `Onboarding`
- `Presence`
- `PresenceLifecycle`
- `ProductBoundary`
- `Recognition`
- `RecognitionMath`
- `Release`
- `SettingsInteraction`
- `SettingsLaunch`
- `SettingsSearch`
- `SettingsUX`
- `SetupBack`
- `Toolbar`
- `UnlockFlow`
- `UpdateLifecycle`

`Support/` holds helpers shared by several suites.
