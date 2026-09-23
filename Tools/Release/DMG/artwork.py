"""Gaze installer artwork, rendered at 1x and 2x in light and dark.

A light field and a dark field, the two icon positions left empty for Finder,
a thin arrow between them and one line of instruction. Nothing competes with
the drag. `WINDOW_SIZE`, `ICON_LOCATIONS` and `ICON_SIZE` are shared with
`package.py`; keep them in sync there rather than forking new values here.

Outputs in the target directory:
  background.png / background@2x.png (light, 1x/retina)
  background-dark.png / background-dark@2x.png (dark, 1x/retina)
  VolumeIcon.icns (from `volume_icon`, see below)

Volume icon: `volume_icon()` renders the DMG volume icon from the app's own
artwork. Pass a built `AppIcon.icns` when one is at hand; otherwise it falls
back to composing `Resources/AppIcon.icon/Assets/gaze-mark.png` over the
icon's light gradient. It fails with a clear message when neither source
exists rather than writing a blank icon.

Pillow is required. The render functions fail with a clear message when it is
missing instead of silently producing nothing. Fallback path, kept in
`Tools/Release/BuildDMG.sh` (not here): when Pillow is unavailable the DMG
ships without a custom background. That fallback stays the caller's decision;
this module never silently skips.
"""

from pathlib import Path
import sys

WINDOW_SIZE = (640, 360)
ICON_LOCATIONS = {"Gaze.app": (176, 180), "Applications": (464, 180)}
ICON_SIZE = 112

FONT = "/System/Library/Fonts/SFNS.ttf"
CAPTION = "Drag Gaze to Applications"
# Below the names Finder draws under the icons, with room to breathe.
CAPTION_Y = 304
# Finder draws icon names in dark text over a background picture whatever the
# system appearance, so the light window stays light in dark mode too. A flat
# field rather than the app's backdrop: the two icons are the only things to
# look at. The dark files are for a dark-aware packaging step.
PAPER = (246, 246, 248)
# A faint top-to-bottom falloff so the field doesn't read as a blank export.
PAPER_FOOT = (238, 238, 241)
ARROW = (174, 174, 180)
CAPTION_INK = (134, 134, 139)
DARK_PAPER = (34, 34, 38)
DARK_PAPER_FOOT = (24, 24, 27)
DARK_ARROW = (150, 150, 158)
DARK_CAPTION_INK = (176, 176, 184)

# gaze-mark.png composited over this gradient when no built AppIcon.icns is
# passed to volume_icon(); matches the light gradient in icon.json.
APP_ICON_MARK = Path(__file__).resolve().parents[3] / "Resources/AppIcon.icon/Assets/gaze-mark.png"
VOLUME_GRADIENT = ((255, 255, 255), (240, 240, 242))
VOLUME_ICON_SIZE = 1024

PILLOW_HINT = (
    "artwork.py requires Pillow (pip install -r Tools/Release/DMG/requirements.txt); "
    "refusing to render without it."
)


def _pil():
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        print(PILLOW_HINT, file=sys.stderr)
        raise SystemExit(1)
    return Image, ImageDraw, ImageFont


def _font(ImageFont, px, weight=400):
    face = ImageFont.truetype(FONT, px)
    face.set_variation_by_axes([100, min(96, max(17, px / 2)), 400, weight])
    return face


def _stroke(draw, a, b, width, fill):
    """A line with round caps, which `ImageDraw.line` does not give us."""
    draw.line((a, b), fill=fill, width=round(width))
    for point in (a, b):
        r = width / 2
        draw.ellipse((point[0] - r, point[1] - r, point[0] + r, point[1] + r), fill=fill)


def _arrow(draw, cx, cy, length, stroke, fill):
    """A thin shaft and open chevron, drawn here so the installer carries no
    redistributed glyph."""
    x0, x1 = cx - length / 2, cx + length / 2
    barb = length * 0.18
    _stroke(draw, (x0, cy), (x1, cy), stroke, fill)
    _stroke(draw, (x1 - barb, cy - barb), (x1, cy), stroke, fill)
    _stroke(draw, (x1 - barb, cy + barb), (x1, cy), stroke, fill)


def _field(Image, ImageDraw, ImageFont, paper, foot, arrow, ink):
    scale = 4
    width, height = WINDOW_SIZE
    w, h = width * scale, height * scale

    image = Image.new("RGB", (w, h), paper)
    draw = ImageDraw.Draw(image)
    for y in range(h):
        t = (y / (h - 1)) ** 2
        draw.line(((0, y), (w, y)), fill=tuple(
            round(a + (b - a) * t) for a, b in zip(paper, foot)))

    _arrow(draw, width / 2 * scale, ICON_LOCATIONS["Gaze.app"][1] * scale,
           92 * scale, 2.5 * scale, arrow)
    draw.text((width / 2 * scale, CAPTION_Y * scale), CAPTION,
              font=_font(ImageFont, 13 * scale), fill=ink, anchor="mm")
    return image


def render(directory: Path):
    Image, ImageDraw, ImageFont = _pil()
    directory.mkdir(parents=True, exist_ok=True)
    width, height = WINDOW_SIZE

    for stem, palette in (("background", (PAPER, PAPER_FOOT, ARROW, CAPTION_INK)),
                          ("background-dark", (DARK_PAPER, DARK_PAPER_FOOT,
                                               DARK_ARROW, DARK_CAPTION_INK))):
        field = _field(Image, ImageDraw, ImageFont, *palette)
        field.resize((width * 2, height * 2), Image.Resampling.LANCZOS).save(
            directory / f"{stem}@2x.png", dpi=(144, 144))
        field.resize(WINDOW_SIZE, Image.Resampling.LANCZOS).save(
            directory / f"{stem}.png", dpi=(72, 72))
    return directory / "background.png"


def volume_icon(directory: Path, app_icon: Path | None = None):
    """Write VolumeIcon.icns into directory; see module docstring for sources."""
    Image, ImageDraw, _ = _pil()
    directory.mkdir(parents=True, exist_ok=True)
    out = directory / "VolumeIcon.icns"
    if app_icon is not None and Path(app_icon).is_file():
        Image.open(app_icon).save(out)
        return out
    if not APP_ICON_MARK.is_file():
        raise FileNotFoundError(
            f"No AppIcon source: {APP_ICON_MARK} missing and no built "
            "AppIcon.icns was passed. Build the app first or pass --app-icon.")
    size = VOLUME_ICON_SIZE
    base = Image.new("RGB", (size, size), VOLUME_GRADIENT[0])
    pixels = base.load()
    top, bottom = VOLUME_GRADIENT
    for y in range(size):
        t = y / (size - 1)
        row = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
        for x in range(size):
            pixels[x, y] = row
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle((0, 0, size, size), radius=int(size * 0.225), fill=255)
    base.putalpha(mask)
    mark = Image.open(APP_ICON_MARK).convert("RGBA")
    mark_size = int(size * 0.7)
    mark = mark.resize((mark_size, mark_size), Image.Resampling.LANCZOS)
    offset = (size - mark_size) // 2
    base.paste(mark, (offset, offset), mark)
    base.save(out)
    return out


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--app-icon", type=Path, default=None,
                        help="Built AppIcon.icns; otherwise the repo gaze-mark.png is used")
    args = parser.parse_args()
    print(render(args.output))
    print(volume_icon(args.output, args.app_icon))
