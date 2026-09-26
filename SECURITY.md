# Security

## Reporting a vulnerability

Please don't open a public issue for a security problem. Report it privately through
[GitHub's private vulnerability reporting](https://github.com/OwenCope/Gaze/security/advisories/new)
so it stays private until a fix is out. Include what you did, what happened and your
macOS version.

## What Gaze stores

Everything stays on your Mac. Nothing is uploaded or synced.

| Item | How it's kept |
| --- | --- |
| Your face | A set of numeric faceprints, not photos, encrypted in the Keychain. |
| Your login password | Checked against macOS when you save it, then encrypted in the Keychain. |
| Profile photos | Optional pictures you choose in Settings, stored in Application Support. |

The encryption key comes from this Mac's Secure Enclave and never leaves it, so the data
can't be read on another Mac or restored from a backup.

## How unlocking is protected

- Gaze only unlocks after it recognises your face and, by default, a head movement.
- It checks for photos and screens, and only trusts the camera you enrolled with.
- After 6 failed attempts it turns itself off until you enter your password.
- Settings can ask for your password before a face is removed or the saved password changes.
- Your Mac password always works.

## Limits

A Mac camera sees a flat image and can't measure depth the way Face ID's TrueDepth
camera does. Gaze's checks make a photo, a screen or a video much harder to use, but it
is not as strong as Face ID and it can't tell identical twins apart. If you need that
level of security, keep unlocking off and use your password or Touch ID.

Gaze enters your password by typing it for you, which is why it needs Accessibility
access.
