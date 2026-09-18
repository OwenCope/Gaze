# Current Gaze media

`build.py` compiles the current app source into a separate **Gaze Product Capture**
app. It uses the real Settings and tour views. The normal Gaze entry point and
its service startup are not invoked. The Keychain implementation returns an
empty store and traps on writes; lockout state is in memory. Preferences belong
to the capture app's own bundle. It never enrolls a face, opens the camera,
locks the Mac, enters a password or starts the release-check schedule.

Build:

    python3 Tools/ProductCapture/build.py

Capture General settings:

    open -n 'build/polish-20260918/product-capture/Gaze Product Capture.app' --args --ui-review --capture=general --settings-pane=general --output=/Users/owencope/Developer/FaceID/build/polish-20260918/current-app-captures

The other capture names are `welcome`, `movement`, `notch` and `unlock`.
For Settings captures, pass `--settings-pane=notch` or `--settings-pane=face`.
`--inspect` leaves the window open and writes its ID/size to `window.json`.
The helper uses `SCShareableContent.currentProcess` to photograph only its own windows,
including a system-wallpaper backdrop so macOS renders the actual glass. This does
not require broad Screen Recording access. The output
is current app UI with empty demo enrollment, not a recorded authentication.

`render-movement.py` exports the app's five 3.2-second guidance cycles at 60 fps.
It uses the real shader, material and motion sampler, via the existing
OnboardingArt offscreen renderer. This is an animation export, **not a screen
recording**. It adds no windows, buttons, labels or invented product UI.
The accompanying manifest records source hashes, dimensions and video hash.

    python3 Tools/ProductCapture/render-movement.py

The resulting 900×560 MP4 autoplays on the website without subtitles or player
controls. It pauses off screen, in hidden tabs, and under Reduce Motion.

After all four window captures are available, export a centered 1440×900 set:

    python3 Tools/ProductCapture/export-shots.py --captures build/polish-20260918/current-app-captures --output /Users/owencope/Developer/gaze-site/public/product

The exporter requires every real input first. It preserves aspect ratio, only
shrinks oversized windows, and adds transparent padding. It writes a manifest
with source/output hashes. No crops, retouching, invented controls or glass
substitutes are applied. Do not point website components at these filenames
until the four images exist and have been inspected.


The tour and website now share four photographed close-ups. Capture `general`,
`notch`, `unlock` and `security` (`--settings-pane=face` for the last two), then run:

    python3 Tools/ProductCapture/export-tour-shots.py --captures build/droppy-reference-20260918/current-captures --website /Users/owencope/Developer/gaze-site/public/product

`security` scrolls the real settings view to its final group before capture.
The exporter checks dimensions before using the reviewed crop coordinates. It
writes native PNGs, web WebPs, and `tour-shots.json` with source and output hashes.
The supplied user recordings were used as references only; they are not published.
