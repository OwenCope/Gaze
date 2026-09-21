"""Gaze installer artwork, rendered at 1x and 2x.

The window wears the app's own setup backdrop rather than a colour invented for
the installer, so the first thing a person sees and the first screen they land in
look like one product.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

WINDOW_SIZE = (640, 360)
ICON_LOCATIONS = {"Gaze.app": (176, 195), "Applications": (464, 195)}
ICON_SIZE = 104

ROOT = Path(__file__).resolve().parents[3]
BACKDROP = ROOT / "Resources/Art/backdrop.png"
FONT = "/System/Library/Fonts/SFNS.ttf"
CAPTION = "Drag Gaze to Applications"
# Below the icons and clear of the names Finder draws under them.
CAPTION_Y = 300
# The caption rides a glass capsule rather than a drop shadow: the backdrop is too
# busy for bare text, and an offset shadow behind type is a 1990s solution.
PILL = (255, 255, 255, 120)
CAPTION_INK = (28, 28, 32, 235)
# Enough blur to stop the capsules reading as a picture of something, not so much
# that the app's motif dissolves into generic wallpaper.
BLUR = 5
VEIL = (255, 255, 255, 40)


def _font(px, weight=500):
    face = ImageFont.truetype(FONT, px)
    face.set_variation_by_axes([100, min(96, max(17, px / 2)), 400, weight])
    return face


def _stroke(draw, a, b, width, fill):
    """A line with round caps, which `ImageDraw.line` does not give us."""
    draw.line((a, b), fill=fill, width=round(width))
    for point in (a, b):
        r = width / 2
        draw.ellipse((point[0] - r, point[1] - r, point[0] + r, point[1] + r), fill=fill)


def _arrow(draw, cx, cy, height, fill):
    """The shaft-and-chevron arrow SF draws, built here so the installer carries
    no redistributed glyph."""
    width = height * 1.26
    stroke = height / 7.6
    x0, x1 = cx - width / 2, cx + width / 2
    barb = height * 0.42
    _stroke(draw, (x0, cy), (x1 - stroke / 2, cy), stroke, fill)
    _stroke(draw, (x1 - barb, cy - barb), (x1, cy), stroke, fill)
    _stroke(draw, (x1 - barb, cy + barb), (x1, cy), stroke, fill)


def render(directory: Path):
    directory.mkdir(parents=True, exist_ok=True)
    scale = 4
    width, height = WINDOW_SIZE
    w, h = width * scale, height * scale

    source = Image.open(BACKDROP).convert("RGB")
    cover = max(w / source.width, h / source.height)
    filled = source.resize((round(source.width * cover), round(source.height * cover)),
                           Image.Resampling.LANCZOS)
    left, top = (filled.width - w) // 2, (filled.height - h) // 2
    image = filled.crop((left, top, left + w, top + h)).filter(
        ImageFilter.GaussianBlur(BLUR * scale / 2))
    image = Image.alpha_composite(image.convert("RGBA"),
                                  Image.new("RGBA", (w, h), VEIL))

    # The capsule frosts what sits behind it, so it reads as glass over the
    # backdrop rather than as a panel laid on top of one.
    draw = ImageDraw.Draw(image, "RGBA")
    font = _font(16 * scale)
    text_width = draw.textlength(CAPTION, font=font)
    pad, tall = 22 * scale, 38 * scale
    box = (width / 2 * scale - text_width / 2 - pad, CAPTION_Y * scale - tall / 2,
           width / 2 * scale + text_width / 2 + pad, CAPTION_Y * scale + tall / 2)
    frosted = image.crop(tuple(round(v) for v in box)).filter(
        ImageFilter.GaussianBlur(9 * scale))
    image.paste(frosted, (round(box[0]), round(box[1])))
    capsule = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(capsule).rounded_rectangle(box, radius=tall / 2, fill=PILL)
    image = Image.alpha_composite(image, capsule)

    draw = ImageDraw.Draw(image, "RGBA")
    draw.text((width / 2 * scale, CAPTION_Y * scale), CAPTION,
              font=font, fill=CAPTION_INK, anchor="mm")
    _arrow(draw, width / 2 * scale, ICON_LOCATIONS["Gaze.app"][1] * scale,
           34 * scale, (255, 255, 255, 235))

    flat = image.convert("RGB")
    flat.resize((width * 2, height * 2), Image.Resampling.LANCZOS).save(
        directory / "background@2x.png", dpi=(144, 144))
    flat.resize(WINDOW_SIZE, Image.Resampling.LANCZOS).save(
        directory / "background.png", dpi=(72, 72))
    return directory / "background.png"


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    print(render(args.output))
