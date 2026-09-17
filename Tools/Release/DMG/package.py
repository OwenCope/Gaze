#!/usr/bin/env python3
"""Package an existing signed Gaze app with a Retina Finder background."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

import dmgbuild
from ds_store import DSStore

from artwork import ICON_LOCATIONS, ICON_SIZE, WINDOW_SIZE, render

ROOT = Path(__file__).resolve().parents[3]


def run(*command, capture=False):
    result = subprocess.run(command, check=True, capture_output=capture)
    return result.stdout if capture else None


def digest(path):
    with path.open("rb") as stream:
        value = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def verify_image(image, executable_hash):
    run("/usr/bin/hdiutil", "verify", str(image))
    with tempfile.TemporaryDirectory(prefix="gaze-dmg-mount-") as scratch:
        mount = Path(scratch) / "volume"
        mounted = False
        try:
            run("/usr/bin/hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen",
                "-mountpoint", str(mount), str(image))
            mounted = True
            app = mount / "Gaze.app"
            run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(app))
            if digest(app / "Contents/MacOS/Gaze") != executable_hash:
                raise RuntimeError("The packaged executable differs from the input app")
            if os.readlink(mount / "Applications") != "/Applications":
                raise RuntimeError("Applications shortcut has the wrong target")
            visible = {p.name for p in mount.iterdir() if not p.name.startswith(".")}
            if visible != {"Gaze.app", "Applications"}:
                raise RuntimeError(f"Unexpected visible files: {sorted(visible)}")
            with DSStore.open(str(mount / ".DS_Store"), "r") as store:
                view = store["."]["icvp"]
                window = store["."]["bwsp"]
                if view["backgroundType"] != 2 or view["iconSize"] != ICON_SIZE:
                    raise RuntimeError("Finder background or icon size was not saved")
                if window["ShowSidebar"] or window["ShowToolbar"]:
                    raise RuntimeError("Unexpected Finder sidebar or toolbar")
                for name, position in ICON_LOCATIONS.items():
                    if tuple(store[name]["Iloc"]) != position:
                        raise RuntimeError(f"Wrong Finder position for {name}")
            if not (mount / ".background.tiff").is_file():
                raise RuntimeError("Retina background missing from image")
        finally:
            if mounted:
                run("/usr/bin/hdiutil", "detach", str(mount))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=ROOT / "build/release/Gaze.app")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build/installers")
    parser.add_argument("--local-preview", action="store_true",
                        help="Create a local design candidate; not a cleared distribution build")
    parser.add_argument("--notary-profile", help="Keychain profile for Apple notarization; required for release")
    args = parser.parse_args()
    app = args.app.resolve(strict=True)
    if app.name != "Gaze.app":
        parser.error("The input app must be named Gaze.app")
    metadata = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if metadata.get("CFBundleIdentifier") != "com.gazeunlock.Gaze":
        parser.error("Unexpected app bundle identifier")
    binary = app / "Contents/MacOS/Gaze"
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(app))
    architecture = run("/usr/bin/lipo", "-archs", str(binary), capture=True).decode().strip()
    version = metadata["CFBundleShortVersionString"]
    if any(c not in "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-" for c in version):
        parser.error("Version contains characters unsuitable for a filename")

    authority = None
    if not args.local_preview:
        run("python3", str(ROOT / "Tools/Release/ModelClearance/validate.py"))
        run("bash", str(ROOT / "Tools/Release/verify.sh"), str(app))
        if not args.notary_profile:
            parser.error("A --notary-profile is required to notarize the release DMG")
        signature = subprocess.run(["/usr/bin/codesign", "-dv", "--verbose=4", str(app)],
                                   capture_output=True, text=True, check=True).stderr
        authority = next(line.removeprefix("Authority=") for line in signature.splitlines()
                         if line.startswith("Authority=Developer ID Application: "))

    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    suffix = "-local-preview" if args.local_preview else ""
    image = output_dir / f"Gaze-{version}-{architecture.replace(' ', '-')}{suffix}.dmg"
    if image.exists():
        parser.error(f"Output already exists; choose a fresh --output-dir: {image}")
    background = render(output_dir / "artwork")
    executable_hash = digest(binary)

    def check_copied_app(mount_point, _options):
        copied = Path(mount_point) / "Gaze.app"
        run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(copied))
        if digest(copied / "Contents/MacOS/Gaze") != executable_hash:
            raise RuntimeError("App copy failed; refusing to finish the DMG")

    settings = {
        "format": "UDZO", "filesystem": "HFS+", "compression_level": 9,
        "files": [str(app)], "symlinks": {"Applications": "/Applications"},
        "background": str(background),
        "window_rect": ((180, 140), WINDOW_SIZE),
        "icon_locations": ICON_LOCATIONS, "icon_size": ICON_SIZE, "text_size": 13,
        "default_view": "icon-view", "include_list_view_settings": False,
        "show_status_bar": False, "show_tab_view": False, "show_toolbar": False,
        "show_pathbar": False, "show_sidebar": False,
        "show_icon_preview": False, "show_item_info": False,
        "arrange_by": None, "create_hook": check_copied_app,
    }
    icon = app / "Contents/Resources/AppIcon.icns"
    if icon.is_file():
        settings["badge_icon"] = str(icon)

    with tempfile.TemporaryDirectory(prefix=".gaze-package-", dir=output_dir) as scratch:
        staged = Path(scratch) / image.name
        print("Creating Gaze disk image…", flush=True)
        dmgbuild.build_dmg(str(staged), "Gaze", settings=settings)
        verify_image(staged, executable_hash)
        if authority:
            run("/usr/bin/codesign", "--sign", authority, "--timestamp", str(staged))
            result = json.loads(run("xcrun", "notarytool", "submit", str(staged),
                                    "--keychain-profile", args.notary_profile,
                                    "--wait", "--output-format", "json", capture=True))
            if result.get("status") != "Accepted":
                raise RuntimeError(f"Notarization was not accepted: {result.get('id')}")
            run("xcrun", "stapler", "staple", str(staged))
            run("xcrun", "stapler", "validate", str(staged))
            run("/usr/bin/codesign", "--verify", "--strict", str(staged))
            run("/usr/sbin/spctl", "--assess", "--type", "open", "--context",
                "context:primary-signature", "--verbose=2", str(staged))
        staged.rename(image)

    checksum = digest(image)
    (output_dir / (image.name + ".sha256")).write_text(f"{checksum}  {image.name}\n")
    receipt = {
        "createdUTC": datetime.now(timezone.utc).isoformat(), "dmg": str(image),
        "sha256": checksum, "bytes": image.stat().st_size,
        "app": str(app), "executableSHA256": executable_hash,
        "version": version, "architecture": architecture,
        "minimumMacOS": metadata["LSMinimumSystemVersion"],
        "distributionReady": not args.local_preview,
        "verification": "Image checksum, mounted app signature and executable hash, Applications link, Finder layout and Retina background passed",
        "visualInspection": "Background artwork only; live Finder appearance not checked by this script",
    }
    (output_dir / (image.name + ".json")).write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"{'LOCAL PREVIEW — not cleared for sharing' if args.local_preview else 'NOTARIZED DMG'}: {image}")


if __name__ == "__main__":
    main()
