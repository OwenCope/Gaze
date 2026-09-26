# Contributing to Gaze

Thanks for helping. Small, focused pull requests are the easiest to review.

## Build

You need Xcode 26 or later and a code-signing identity. A free Apple ID works: in Xcode,
open Settings, then Accounts, add your Apple ID, then Manage Certificates and add an
Apple Development certificate. Check it with `security find-identity -v -p codesigning`.

```sh
git clone https://github.com/OwenCope/Gaze.git
cd Gaze
./build.sh
open build/Gaze.app
```

`build.sh` builds a universal app by default. `GAZE_ARCHS=arm64 ./build.sh` builds one
architecture. If Xcode is somewhere unusual, set `DEVELOPER_DIR`.

Sign with a real identity rather than ad hoc. The Keychain protects Gaze's vault key by
the app's signature, and an ad-hoc signature changes every build, so macOS would ask for
your keychain password each time.

## The recognition model

The ArcFace model Gaze ships is not in this repository; see [NOTICE.md](NOTICE.md). Without
it, a clone builds with a weaker landmark fallback that Gaze refuses to use for unlocking.
Put your own compiled model at `Resources/FaceEmbedding.mlmodelc` to use the real one.

Changing the model invalidates existing enrolments, by design.

## Try it

1. Allow the camera when asked.
2. Enrol your face in the setup window.
3. Open **Test Recognition** from the menu bar. Check your score sits well above the
   threshold, and that someone else's sits well below it.
4. In Settings, store your password and allow Accessibility to let Gaze unlock the Mac.

Nothing moves between Macs: face data is sealed by a Secure Enclave key that never leaves
the Mac that made it.

To follow what Gaze is doing:

```sh
log stream --predicate 'subsystem == "com.gazeunlock.Gaze"'
```

## Tests

Each folder in [Tests](Tests) is a self-contained suite:

```sh
bash Tests/UnlockFlow/run.sh
```

None of them opens the camera or reads real credentials. Run the suites that cover your
change before opening a pull request.

## Project layout

- `Sources/`: the app.
- `Plugin/`: the lock-screen authorization plugin. Read [Plugin/README.md](Plugin/README.md)
  and [SECURITY.md](SECURITY.md) before changing it.
- `Resources/`: art, credits and models.
- `ThirdParty/`: vendored code, with its licences.
- `Tests/`: test suites.
- `Tools/`: build scripts, packaging and release tools.

## Before you open a pull request

- Keep it to one change.
- Run `./build.sh` and the relevant tests.
- Don't change recognition thresholds without measured scores from real hardware.
- Don't include secrets, face images or personal data.
- If you change anything in `Resources/` or `ThirdParty/`, check its licence.

By contributing you agree to follow the [code of conduct](CODE_OF_CONDUCT.md).
