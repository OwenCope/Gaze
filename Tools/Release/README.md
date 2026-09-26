# Release work

- [DMG packaging](DMG/README.md): artwork, drag-to-Applications layout and packaging command.
- [Homebrew cask](Homebrew/gaze.rb): the cask for the `owencope/gaze` tap; it clears the quarantine flag on install.
- [Readiness](READINESS.md): the release requirements and remaining acceptance work.
- [Model and asset clearance](ModelClearance/README.md): evidence required before distribution.
- `BuildDMG.sh`: build the app and package the installer.
- `preflight.sh`: inspect prerequisites without building or publishing.
- `verify.sh`: check a built release app.

Packaged installers are written to `build/installers/`.
