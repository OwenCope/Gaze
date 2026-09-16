# Website copy aligned with the apps

Applied locally; no deployment. `current-product-copy.patch` updates the FAQ,
shared feature descriptions, How it works, and Security pages after the visual
polish patch.

Removed stale two-second-hold instructions in favor of the configured one/two
movement flow and return-to-start cue. Explained camera use during setup,
recognition tests, Passwords approval and optional walk-away checks. Recognition
works offline; updates and links use the network.

Clarified that saved login passwords are decrypted for submission, and optional
face-tile portraits are separate local images. Recognition-only mode turns off
automatic unlocking; it does not promise deletion of a password stored earlier.
The security page explains the limits of a regular camera and first login after
a restart. No benchmark was presented as a system security guarantee.

Source evidence: Sources/Security/UnlockChallengeGate.swift, LockWatcher.swift,
PasswordVault.swift, SecureVault.swift; Sources/Recognition/FaceEnrollment.swift;
Sources/Camera/CameraDevice.swift; Sources/App/Preferences.swift; the existing
browser approval and presence paths. No real user state was read for these edits.
