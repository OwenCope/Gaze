"""Gaze installer artwork, rendered at 1x and 2x.

The top of a Mac screen on the Pro Black wallpaper, with Gaze's real panel
hanging from the top edge. Below, the two icons are joined by a curved white
arrow; frosted pills sit under their names so Finder's black label text stays
readable. The arrow is the instruction; Finder clips anything near the bottom edge. It is light on purpose: Finder draws icon names in black in light
mode, and a dark field leaves them unreadable.

`WINDOW_SIZE`, `ICON_LOCATIONS` and `ICON_SIZE` are shared with `package.py`.
Outputs: background.png / background@2x.png, background-dark.png /
background-dark@2x.png (the same field; macOS does not switch DMG backgrounds by
appearance) and VolumeIcon.icns via `volume_icon`.
"""

from pathlib import Path
from typing import Optional
import sys

WINDOW_SIZE = (660, 420)
ICON_LOCATIONS = {"Gaze.app": (178, 250), "Applications": (482, 250)}
ICON_SIZE = 128

FONT = "/System/Library/Fonts/SFNS.ttf"
CAPTION = "Drag Gaze to Applications"
TOP = (236, 238, 245)
BOTTOM = (248, 248, 250)
GLOW = (10, 132, 255)
INK = (29, 29, 31)
MUTED = (120, 120, 128)
ARROW = (10, 132, 255)

PANEL = Path(__file__).resolve().parent / "panel.png"
WALLPAPER = Path(__file__).resolve().parent / "wallpaper.jpg"
# Where Finder centres an icon name, below the icon centre, at icon size 128 and text size 13.
LABEL_OFFSET = 83
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


def _curve_arrow(draw, start, control, end, stroke, fill):
    """A quadratic arc with an open chevron at its end, aligned to the curve.

    Drawn as a run of round dabs rather than a polyline, so the stroke has
    round joins all the way along.
    """
    import math

    def point(t):
        u = 1 - t
        return (u * u * start[0] + 2 * u * t * control[0] + t * t * end[0],
                u * u * start[1] + 2 * u * t * control[1] + t * t * end[1])

    r = stroke / 2
    steps = 400
    for i in range(steps + 1):
        x, y = point(i / steps)
        draw.ellipse((x - r, y - r, x + r, y + r), fill=fill)
    tx, ty = end[0] - control[0], end[1] - control[1]
    angle = math.atan2(ty, tx)
    barb = stroke * 5.2
    for spread in (math.radians(150), math.radians(-150)):
        bx = end[0] + barb * math.cos(angle + spread)
        by = end[1] + barb * math.sin(angle + spread)
        _stroke(draw, (bx, by), end, stroke, fill)


def _curved_text(Image, ImageDraw, ImageFont, image, text, start, control, end, lift, px, fill):
    """Set text along the arrow's quadratic curve, each glyph rotated to the tangent
    and lifted off the line by `lift`, centred on the curve's arc length."""
    import math

    def point(t):
        u = 1 - t
        return (u * u * start[0] + 2 * u * t * control[0] + t * t * end[0],
                u * u * start[1] + 2 * u * t * control[1] + t * t * end[1])

    def tangent(t):
        return (2 * (1 - t) * (control[0] - start[0]) + 2 * t * (end[0] - control[0]),
                2 * (1 - t) * (control[1] - start[1]) + 2 * t * (end[1] - control[1]))

    samples = [point(i / 1000) for i in range(1001)]
    lengths = [0.0]
    for (x0, y0), (x1, y1) in zip(samples, samples[1:]):
        lengths.append(lengths[-1] + math.hypot(x1 - x0, y1 - y0))
    total = lengths[-1]

    def t_at(distance):
        lo, hi = 0, len(lengths) - 1
        while lo < hi:
            mid = (lo + hi) // 2
            if lengths[mid] < distance: lo = mid + 1
            else: hi = mid
        return lo / 1000

    font = _font(ImageFont, px, 500)
    measure = ImageDraw.Draw(image)
    width = measure.textlength(text, font=font)
    cursor = (total - width) / 2
    for ch in text:
        cw = measure.textlength(ch, font=font)
        t = t_at(cursor + cw / 2)
        x, y = point(t)
        dx, dy = tangent(t)
        angle = math.degrees(math.atan2(dy, dx))
        nx, ny = dy / math.hypot(dx, dy), -dx / math.hypot(dx, dy)
        if ny > 0: nx, ny = -nx, -ny
        x, y = x + nx * lift, y + ny * lift
        tile = Image.new("RGBA", (round(cw + px), round(px * 2)), (0, 0, 0, 0))
        ImageDraw.Draw(tile).text((tile.width / 2, tile.height / 2), ch, font=font, fill=fill, anchor="mm")
        tile = tile.rotate(-angle, resample=Image.Resampling.BICUBIC, expand=True)
        image.alpha_composite(tile, (round(x - tile.width / 2), round(y - tile.height / 2)))
        cursor += cw
    return image


def _field(Image, ImageDraw, ImageFont):
    from PIL import ImageFilter

    scale = 4
    width, height = WINDOW_SIZE
    w, h = width * scale, height * scale

    # The Pro Black wallpaper, the same one the lock-screen footage uses,
    # cropped to cover the window.
    wall = Image.open(WALLPAPER).convert("RGB")
    cover = max(w / wall.width, h / wall.height)
    wall = wall.resize((round(wall.width * cover), round(wall.height * cover)), Image.Resampling.LANCZOS)
    left, top = (wall.width - w) // 2, (wall.height - h) // 2
    image = wall.crop((left, top, left + w, top + h)).convert("RGBA")
    # Darken a little so the icons and panel stay the brightest things.
    image = Image.alpha_composite(image, Image.new("RGBA", (w, h), (0, 0, 0, 70)))

    # Gaze's own panel, photographed from the app's lock-screen window, widened
    # the way it grows when it has something to say: the black middle is
    # stretched, the curved shoulders and the happy companion are the app's own.
    panel = Image.open(PANEL).convert("RGBA")
    # Sized like the app's dropped scanning panel, not the slim resting bar.
    ph = 128 * scale
    pw0 = round(panel.width * ph / panel.height)
    panel = panel.resize((pw0, ph), Image.Resampling.LANCZOS)
    left_end, right_start = round(pw0 * 0.3), round(pw0 * 0.7)
    face = panel.crop((left_end, 0, right_start, ph))
    body = pw0 - left_end - (pw0 - right_start) + 230 * scale
    wide = Image.new("RGBA", (left_end + body + pw0 - right_start, ph), (0, 0, 0, 0))
    wide.alpha_composite(panel.crop((0, 0, left_end, ph)), (0, 0))
    wide.alpha_composite(panel.crop((right_start, 0, pw0, ph)), (left_end + body, 0))
    column = panel.crop((round(pw0 * 0.75), 0, round(pw0 * 0.75) + 1, ph)).resize((body, ph))
    wide.alpha_composite(column, (left_end, 0))
    # The happy companion moves to the left, with its line beside it.
    fx = left_end + round(26 * scale)
    wide.alpha_composite(face, (fx, 0))
    wd = ImageDraw.Draw(wide)
    wd.text((fx + face.width - 4 * scale, ph * 0.64), "Drag me to the right",
            font=_font(ImageFont, 21 * scale, 600), fill=(255, 255, 255, 255), anchor="lm")
    image.alpha_composite(wide, (round((w - wide.width) / 2), 0))

    draw = ImageDraw.Draw(image)
    # Finder draws icon names in the system text colour: black in light mode,
    # which vanishes on this wallpaper. A frosted pill under each name keeps it
    # readable in both appearances.
    label_font = _font(ImageFont, 13 * scale, 500)
    for name, (x, y) in ICON_LOCATIONS.items():
        label = name.removesuffix(".app")
        tw = draw.textlength(label, font=label_font)
        cx, cy = x * scale, (y + LABEL_OFFSET) * scale
        pad_x, half_h = 12 * scale, 11 * scale
        box = (round(cx - tw / 2 - pad_x), round(cy - half_h), round(cx + tw / 2 + pad_x), round(cy + half_h))
        frost = image.crop(box).filter(ImageFilter.GaussianBlur(10 * scale))
        frost = Image.alpha_composite(frost, Image.new("RGBA", frost.size, (245, 245, 247, 215)))
        mask = Image.new("L", frost.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, frost.width - 1, frost.height - 1), radius=half_h, fill=255)
        image.paste(frost, box[:2], mask)

    gy = ICON_LOCATIONS["Gaze.app"][1] * scale
    gx, ax = ICON_LOCATIONS["Gaze.app"][0] * scale, ICON_LOCATIONS["Applications"][0] * scale
    start, control, end = (gx + 70 * scale, gy - 40 * scale), ((gx + ax) / 2, gy - 120 * scale), (ax - 70 * scale, gy - 40 * scale)
    # The arrow alone: the panel above already says what to do.
    _curve_arrow(draw, start, control, end, 2.4 * scale, (255, 255, 255, 215))
    return image.convert("RGB")


def render(directory: Path):
    Image, ImageDraw, ImageFont = _pil()
    directory.mkdir(parents=True, exist_ok=True)
    width, height = WINDOW_SIZE
    field = _field(Image, ImageDraw, ImageFont)
    for stem in ("background", "background-dark"):
        field.resize((width * 2, height * 2), Image.Resampling.LANCZOS).save(
            directory / f"{stem}@2x.png", dpi=(144, 144))
        field.resize(WINDOW_SIZE, Image.Resampling.LANCZOS).save(
            directory / f"{stem}.png", dpi=(72, 72))
    return directory / "background.png"


def volume_icon(directory: Path, app_icon: Optional[Path] = None):
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
