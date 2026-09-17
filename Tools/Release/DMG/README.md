# Gaze disk image

A 640 × 360 Finder window with original silver/sage artwork, Retina resolution,
the signed Gaze app, and an Applications shortcut. Packaging does not launch Gaze
or change the installed app. One installation instruction sits above the icons;
an original curved arrow leads from Gaze to Applications.

Install build-only dependencies into the ignored build directory:

    python3 -m venv build/dmg-tools
    build/dmg-tools/bin/pip install -r Tools/Release/DMG/requirements.txt

Preview the packaging with an existing local build:

    build/dmg-tools/bin/python Tools/Release/DMG/package.py \
      --local-preview --app build/gaze-ux-tightening-20260917/Gaze.app

This produces a `-local-preview.dmg`, checksum and receipt in `build/installers`.
It is a local design candidate, not a redistribution clearance or notarized release.
No gate is changed. Models, recognition thresholds and entitlements are preserved.

To package a release after recording distribution rights, build and notarize the app
using the existing release workflow. Then run:

    DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
      build/dmg-tools/bin/python Tools/Release/DMG/package.py \
      --app build/release/Gaze.app --notary-profile YOUR_KEYCHAIN_PROFILE

Release mode requires the existing clearance and app-verification checks to pass.
It signs the DMG with the app's Developer ID identity, submits it to Apple's notary
service using the named Keychain profile, then staples and assesses the result.
No credentials are written to the project. A failed check leaves no final DMG.
Existing outputs are never overwritten; use `--output-dir` for a new candidate.

The package verifies the mounted app signature and executable hash, both icon
positions, the Applications link and the hidden background. Check Finder visually
on a clean Mac before release; metadata checks are not a visual inspection.
