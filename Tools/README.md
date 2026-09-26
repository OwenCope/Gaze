# Tools

- `Scripts/`: the toolchain check used by every build and test, the list of app sources,
  and the source-archive builder.
- `Release/BuildDMG.sh`: builds the app and packages the disk image.
- `Release/DMG/`: the disk-image layout and artwork.
- `Release/Homebrew/`: the cask for the `owencope/gaze` tap.
- `Release/ModelClearance/`: the model and asset licence inventory that the build checks.
- `Release/Signing.sh`, `preflight.sh`, `verify.sh`: signing and release checks.
