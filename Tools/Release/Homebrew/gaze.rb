# Homebrew cask for Gaze. Lives in a tap repository named `homebrew-gaze`
# (github.com/OwenCope/homebrew-gaze, file Casks/gaze.rb), so people install with:
#
#     brew install --cask owencope/gaze/gaze
#
# Gaze is not notarized, so macOS would block the first launch. The postflight
# clears the quarantine flag on install and on every upgrade, which is what the
# manual `xattr` step in the README does. Homebrew's official cask repository
# only accepts notarized apps, which is why this is a separate tap.
cask "gaze" do
  version "0.1.4"
  sha256 "9d1081af07bb64d203847a7e1067d0f8906ce9a8eea9dc8d162dafd00bdedf87"

  url "https://github.com/OwenCope/Gaze/releases/download/v#{version}/Gaze.dmg"
  name "Gaze"
  desc "Face ID-style face unlock"
  homepage "https://gazeunlock.com/"

  depends_on macos: :tahoe

  app "Gaze.app"

  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Gaze.app"],
                          writable_paths: ["Gaze.app"], writable_base: :appdir
  end

  uninstall quit: "com.gazeunlock.Gaze"

  zap trash: [
    "~/Library/Application Support/Gaze",
    "~/Library/Preferences/com.gazeunlock.Gaze.plist",
  ]
end
