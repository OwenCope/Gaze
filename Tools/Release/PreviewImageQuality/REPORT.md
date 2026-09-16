# Full-resolution onboarding preview exports

Exported on 2026-09-16 from `build/gaze-usability-final-onboarding` using Pillow 11.3.0 and libwebp 1.5.0. Every WebP uses `lossless=True, method=6`. No resizing, sharpening, text replacement, or new capture was performed.

This fixes the prior 2× downsampling and lossy compression in the website assets. Black or absent native glass control surfaces already present in the source PNGs cannot be recovered by encoding. These exports do not establish a faithful native Glass capture and do not fix control contrast.

| Source PNG | Website asset | Previous dimensions | Export dimensions | PNG bytes | WebP bytes |
| --- | --- | --- | --- | ---: | ---: |
| `welcome-dark.png` | `setup-welcome.webp` | 880 × 660 | 1760 × 1320 | 472,116 | 191,972 |
| `meetGaze-dark.png` | `setup-companion.webp` | 880 × 660 | 1760 × 1320 | 551,229 | 221,708 |
| `how-dark.png` | `setup-how.webp` | 880 × 660 | 1760 × 1320 | 578,625 | 245,202 |
| `lesson-turnLeft-dark.png` | `setup-movement.webp` | 560 × 380 | 1120 × 760 | 64,991 | 15,954 |

All four decoded WebPs matched the RGB pixels of their original PNGs exactly. Expected dimensions were asserted before export and after decoding. The copies in `Tools/Release/SecondaryPages/files/public/product` have identical SHA-256 hashes to the website assets in `/Users/owencope/Developer/gaze-site/public/product`.

`manifest.json` records source and output byte counts, source and output SHA-256 hashes, decoded RGB pixel hashes, pixel comparison results, and mirror hashes for all four assets. Website rendering and integration checks are outside this export report.

Reproduce from the FaceID repository root:

    python3 Tools/Release/PreviewImageQuality/export.py \
      --source-root build/gaze-usability-final-onboarding \
      --output-root /Users/owencope/Developer/gaze-site/public/product \
      --mirror-root Tools/Release/SecondaryPages/files/public/product

The script accepts an optional `--report-root` for the regenerated manifest; its default is this directory. Byte-for-byte encoded output can depend on the Pillow and libwebp versions; every run independently verifies exact decoded RGB equality.

## Website integration

Root added lossless native-pixel detail crops using crop-details.py and the exact
boxes in DETAIL-CROPS.json. These include complete readable content and exclude
the glass action rows that the offscreen capture did not reproduce. No button
surfaces or replacement text were painted into the image. The webpage captions
now call these setup details rather than full-window screenshots.

The gallery and enlarged viewer bypass Next image recompression, use the actual
pixel dimensions, and limit display width to half the pixel width for Retina
clarity. Product-tour and walkthrough details also use the lossless files; small
thumbnail optimization remains. Native glass capture limitations are unresolved;
this is an honest detail presentation, not a claim that those controls were fixed.

Verification: production build, TypeScript, focused ESLint and five isolated HTTP
assertions passed. The enlarged Meet Gaze image loads directly from the lossless
WebP (no Next optimizer URL): 1420 natural pixels at 710 CSS pixels. Desktop and
mobile checks found no overflow or broken images. The image was decoded and two
paint frames awaited before the final screenshot. Evidence: build/website-preview-quality/.
