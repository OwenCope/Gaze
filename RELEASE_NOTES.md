# 0.4 — Native Mac controls and a quieter vault

Gaze now feels like a Mac utility: the menu bar item and settings window are backed by
Apple's native scene and toolbar controls, and the repeated Keychain authorization prompt
has been removed after legacy data migrates.

## What changed

- Replaced the hand-drawn settings navigation capsule with a native segmented `Picker` in
  the unified compact window toolbar.
- Enabled Apple's native window-background drag behavior and left toolbar glass to AppKit.
- Migrated pre-0.4 protected records from separate Keychain entries into one authenticated
  Secure Enclave-backed vault file. Normal reads are cached and no longer query Keychain.
- Existing pre-0.4 installs need one **Always Allow** decision to complete that migration;
  a declined decision is cached for the launch instead of prompting once per reader.
- Added a proper Utilities category and bumped the release build to 0.4.

# 0.3 — A calmer control center

The Gaze control center keeps the original wide layout and brings its navigation into a
native macOS unified toolbar, with a quieter visual hierarchy and system glass.

## What changed

- Centered General, Gaze, Credits, and About navigation in the native draggable title bar.
- Reworked settings into focused, wide rows with fewer competing cards and labels.
- Kept security, enrollment, recognition, password, update, and notch controls intact.
- Added a versioned DMG build path through `package-dmg.sh`.

The underlying recognition, vault, lockout, and camera-pinning behavior is unchanged.

# 0.2 — Control Center

The Gaze control center was briefly redesigned around a clearer protection status, faster
diagnostics, and a shared visual language across settings, enrollment, and recognition.

# 0.1

First release. It unlocks your Mac by recognising your face with the built-in camera.

## Setting up

Enrol once. You turn your head slowly while it captures you from a range of angles, the way
you'd set up Gaze on a phone. After that, lock your screen and it looks for you.

## Two modes

**Just recognise me** runs the whole recognition path and unlocks nothing. No password is
asked for or stored. It's the honest way to try it.

**Unlock my Mac** types your account password for you when it recognises you. Touch ID keeps
working alongside it.

## On the lock screen

A panel in the notch: a padlock while it's resting, the Gaze mark while it's looking, a
green tick when it's you, a shake when it isn't. Three styles and size sliders, because
notches and taste both vary.

The match has to hold for two seconds before anything happens, so a deliberate look unlocks
your Mac and someone walking past the camera doesn't.

## What this isn't

It isn't Apple's Face ID. Apple's uses a TrueDepth camera that measures the shape of your face
with infrared dots. No Mac has that sensor. This reads an ordinary flat image, so it can't tell
you from a good photograph of you the way an iPhone can. Treat it as a convenience, not as a
lock.

## Your face and your password

Faceprints are numbers derived from your face, not pictures. No images are kept.

Everything stored is encrypted with a key generated inside the Secure Enclave, which never
leaves it — so copying the files to another Mac gets you nothing. If you choose the mode that
types your password, that password is stored in a form the app can decrypt. It has to be, in
order to type it, and there's no way around that.

`SECURITY.md` documents the whole path and, more usefully, what it doesn't protect against.
Worth reading before you pick the second mode.

## Requirements

- macOS 26
- A Mac with a Secure Enclave. Without one, nothing is stored at all rather than being stored
  more weakly.
- Camera access. Accessibility permission too, but only for the mode that types.

## Also in this release

- Only the built-in camera is trusted, and only the one you enrolled on. Virtual cameras are
  refused.
- Gaze switches off after six failed attempts until you enter your account password.
- Follows your system appearance.
- Optional Touch ID confirmation before changing anything in Settings.

## Known limitations

- Anti-spoof checking is a switch with nothing behind it yet. No model is bundled, so it stays
  off and says so.
- The authorization-plugin route was removed. It can leave you unable to log in at all, which
  is not a risk worth a nicer lock screen.
- If you run another notch app, its bar and this one cover the same strip of screen. The
  resting state is sized to hide underneath rather than fight it, but the panel that drops out
  while scanning will still draw over whatever is there.
- Recognition is a similarity threshold, not proof of identity. Someone who looks a great deal
  like you may get in.

## Thanks

cshariq, for [Sapphire](https://sapphire-app.tech) — the recognition model this app matches
faces with is theirs.

Aviorrok, for [DynamicLake](https://dynamiclake.com) — the notch panel and the settings window
both follow its lead.

DanFQ, for [Atoll](https://getatoll.app), and for reading this code more carefully than I did.

Everyone in the Discord who looked at early screenshots and said what was wrong with them. A
good deal of this release is other people's feedback.

Most of this was vibecoded, which is not a disclaimer so much as the reason it exists at all.
Bug reports and pull requests both welcome.
