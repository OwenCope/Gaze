#!/usr/bin/env python3
"""Export the original onboarding PNGs as full-resolution lossless WebP."""

import argparse
import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image, ImageChops, features
import PIL


EXPORTS = (
    ("welcome-dark.png", "setup-welcome.webp", (1760, 1320)),
    ("meetGaze-dark.png", "setup-companion.webp", (1760, 1320)),
    ("how-dark.png", "setup-how.webp", (1760, 1320)),
    ("lesson-turnLeft-dark.png", "setup-movement.webp", (1120, 760)),
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--output-root", required=True, type=Path)
    parser.add_argument("--mirror-root", type=Path)
    parser.add_argument("--report-root", type=Path, default=Path(__file__).parent)
    args = parser.parse_args()
    args.output_root.mkdir(parents=True, exist_ok=True)
    args.report_root.mkdir(parents=True, exist_ok=True)
    if args.mirror_root:
        args.mirror_root.mkdir(parents=True, exist_ok=True)

    records = []
    for source_name, output_name, expected_size in EXPORTS:
        source = args.source_root / source_name
        output = args.output_root / output_name
        with Image.open(source) as original:
            assert original.size == expected_size, (
                f"{source}: expected {expected_size}, got {original.size}"
            )
            rgb = original.convert("RGB")
        rgb.save(output, format="WEBP", lossless=True, method=6)
        with Image.open(output) as encoded:
            decoded = encoded.convert("RGB")
            assert decoded.size == expected_size
            assert ImageChops.difference(rgb, decoded).getbbox() is None, (
                f"{output}: decoded pixels differ from original RGB PNG"
            )
        record = {
            "source": source_name,
            "output": output_name,
            "dimensions": list(expected_size),
            "source_bytes": source.stat().st_size,
            "output_bytes": output.stat().st_size,
            "source_sha256": sha256(source),
            "output_sha256": sha256(output),
            "rgb_pixels_sha256": hashlib.sha256(rgb.tobytes()).hexdigest(),
            "decoded_rgb_pixel_match": True,
        }
        if args.mirror_root:
            mirror = args.mirror_root / output_name
            shutil.copyfile(output, mirror)
            assert sha256(mirror) == record["output_sha256"]
            record["mirror_sha256"] = sha256(mirror)
        records.append(record)
        print(f"{output_name}: {expected_size[0]}x{expected_size[1]}, "
              f"{record['output_bytes']} bytes, exact RGB pixel match")

    manifest = {
        "pillow_version": PIL.__version__,
        "libwebp_version": features.version("webp"),
        "encoding": {"format": "WEBP", "lossless": True, "method": 6},
        "exports": records,
    }
    (args.report_root / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n"
    )


if __name__ == "__main__":
    main()
