<div align="center">
  <img src="docs/images/icon.png" width="128" alt="Gaze app icon" />
  <h1>Gaze</h1>
  <p>Gaze is an app that brings the Face ID feature of your iPhone to your Mac.</p>
  <p>Look at your Mac to unlock it. Private, on-device, and free.</p>
  <p>
    <a href="https://gazeunlock.com"><img src="docs/images/badge-macos.png" width="179" alt="macOS 26 or later" /></a>
    <a href="https://www.swift.org"><img src="docs/images/badge-swift.png" width="112" alt="Swift 6" /></a>
    <a href="LICENSE"><img src="docs/images/badge-license.png" width="143" alt="License: MIT" /></a>
    <a href="https://gazeunlock.com"><img src="docs/images/badge-website.png" width="222" alt="gazeunlock.com" /></a>
  </p>
</div>

<p align="center">
  <a href="https://gazeunlock.com"><img src="docs/images/hero.png" width="100%" alt="A MacBook lock screen with Gaze's panel open under the notch, recognising its owner" /></a>
</p>

<p align="center">
  <a href="https://gazeunlock.com"><img src="docs/images/download-button.png" width="253" alt="Download for Mac" /></a>
</p>

## Features

Face ID for Mac, with nothing leaving your computer.

<p align="center">
  <img src="docs/images/card-unlock.png" width="49%" alt="Unlocks as you look. On the lock screen, Gaze finds your face and unlocks. The notch shows it smiling as it recognises you." />
  <img src="docs/images/card-local.png" width="49%" alt="Stays on your Mac. Your password is stored with a key from this Mac's Secure Enclave. Nothing leaves your computer." />
  <img src="docs/images/card-recognition.png" width="49%" alt="Knows it is you. Before it unlocks, Gaze can ask for a quick head movement, and it rejects photos and screens." />
  <img src="docs/images/card-choice.png" width="49%" alt="Your choice, always. Switch unlocking on or off, add another face, or test recognition whenever you like." />
</p>

## Simple to install.

Install with Homebrew, and it opens without any warning.

```sh
brew install --cask owencope/gaze/gaze
```

Or download it from [gazeunlock.com](https://gazeunlock.com) and drag Gaze to Applications. The first time you open it, go to System Settings, then Privacy & Security, and click Open Anyway.

## Unlocks as you look.

When your Mac locks, Gaze turns on the camera and looks for you. It compares your face with the one you set up, may ask you to turn your head, then enters your password and unlocks. If anything doesn’t match, you sign in as usual.

## Private by design.

Recognition runs on your Mac and nothing is uploaded. Your face data is encrypted, and your password is protected by a key from the Secure Enclave. A Mac camera can’t measure depth like Face ID, so Gaze rejects photos and screens, and your password always works. To report a security issue, see [SECURITY.md](SECURITY.md).

## What you need.

A Mac with macOS 26 Tahoe or later, a built-in or connected camera, and your login password.

## Open source.

Gaze is built in the open. You’ll need Xcode 26 to build it.

```sh
git clone https://github.com/OwenCope/Gaze.git
cd Gaze
./build.sh
open build/Gaze.app
```

Source archives don’t include the recognition model; [NOTICE.md](NOTICE.md) explains why. Pull requests are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md) and the [code of conduct](CODE_OF_CONDUCT.md).

## Thanks.

Gaze wouldn’t exist without [Harsh Vardhan Goswami](https://github.com/theboringhumane), creator of TheBoringNotch, whose GPT-6 Astra API key powered much of its development.

It also builds on [InsightFace](https://github.com/deepinsight/insightface) for recognition, [Sapphire](https://sapphire-app.tech) for the Core ML model, [TourKit](https://github.com/rampatra/TourKit) for the welcome tour, [Atoll](https://github.com/Ebullioscopic/Atoll) and [SkyLightWindow](https://github.com/Lakr233/SkyLightWindow) for the lock-screen panel, and the [Face Spoof Detection](https://universe.roboflow.com/mohammeds-workspace-ft3sn/face-spoof-detection-liika) dataset. [Glance](https://github.com/jonnyoo/glance) and [DynamicLake](https://dynamiclake.com) inspired its design.

<sub>Available under the [MIT license](LICENSE). Some models, code and data have their own terms, listed in [NOTICE.md](NOTICE.md). Gaze is not affiliated with Apple. Face ID, iPhone and Mac are trademarks of Apple Inc.</sub>
