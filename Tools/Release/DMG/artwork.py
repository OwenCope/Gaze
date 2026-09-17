"""Original Gaze installer artwork, rendered at 1x and 2x."""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

WINDOW_SIZE = (720, 460)
ICON_LOCATIONS = {"Gaze.app": (210, 232), "Applications": (510, 232)}
ICON_SIZE = 112
FONT = "/System/Library/Fonts/SFNS.ttf"


def font(size, weight=400):
    face = ImageFont.truetype(FONT, size)
    face.set_variation_by_axes([100, min(96, max(17, size / 2)), 400, weight])
    return face


def render(directory: Path):
    directory.mkdir(parents=True, exist_ok=True)
    scale = 2
    width, height = WINDOW_SIZE
    image = Image.new("RGB", (width * scale, height * scale))
    pixels = image.load()
    for py in range(height * scale):
        y = py / scale
        for px in range(width * scale):
            x = px / scale
            blend = 0.22 * x / width + 0.64 * y / height
            distance = y - (374 - 0.15 * x + 0.00011 * x * x)
            fold = 1 / (1 + math.exp(-distance / 12))
            highlight = 5 * math.exp(-((distance + 5) / 13) ** 2)
            shade = 4 * math.exp(-((distance - 24) / 24) ** 2)
            pixels[px, py] = tuple(
                round(max(0, min(255, start + (end - start) * blend
                                + highlight - shade - fold * tint)))
                for start, end, tint in zip((247, 248, 246), (220, 232, 224), (8, 3, 5))
            )

    draw = ImageDraw.Draw(image)
    draw.text((48 * scale, 44 * scale), "Gaze", font=font(40 * scale, 600),
              fill=(31, 44, 36), anchor="lt")
    draw.text((48 * scale, 400 * scale), "Drag Gaze to Applications.",
              font=font(15 * scale), fill=(64, 80, 69), anchor="lt")

    ink = (101, 121, 109)
    stroke = 2 * scale
    draw.line([(341 * scale, 232 * scale), (379 * scale, 232 * scale)], fill=ink, width=stroke)
    draw.line([(370 * scale, 223 * scale), (379 * scale, 232 * scale),
               (370 * scale, 241 * scale)], fill=ink, width=stroke, joint="curve")

    image.save(directory / "background@2x.png", dpi=(144, 144))
    image.resize(WINDOW_SIZE, Image.Resampling.LANCZOS).save(
        directory / "background.png", dpi=(72, 72)
    )
    return directory / "background.png"


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    print(render(args.output))
