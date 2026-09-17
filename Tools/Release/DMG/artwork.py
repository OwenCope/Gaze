"""Original Gaze installer artwork, rendered at 1x and 2x."""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

WINDOW_SIZE = (640, 360)
ICON_LOCATIONS = {"Gaze.app": (176, 205), "Applications": (464, 205)}
ICON_SIZE = 104
FONT = "/System/Library/Fonts/SFNS.ttf"


def font(size, weight=400, scale=4):
    face = ImageFont.truetype(FONT, size)
    face.set_variation_by_axes([100, min(96, max(17, size / scale)), 400, weight])
    return face


def draw_arrow(draw, scale):
    ink = (76, 103, 88)

    def curve(points, start_width, end_width):
        for step in range(201):
            t = step / 200
            u = 1 - t
            weights = (u ** 3, 3 * u * u * t, 3 * u * t * t, t ** 3)
            x, y = (sum(weight * point[axis] for weight, point in zip(weights, points))
                    for axis in (0, 1))
            radius = (start_width + (end_width - start_width) * t) * scale / 2
            cx, cy = x * scale, y * scale
            draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=ink)

    # A shallow swoop ends on the same tangent as the open arrowhead.
    curve(((250, 207), (278, 254), (350, 253), (388, 207)), 2.0, 3.2)
    curve(((367, 217), (374, 214), (381, 210), (388, 207)), 3.0, 3.2)
    curve(((388, 207), (386, 215), (384, 223), (383, 231)), 3.2, 3.0)


def render(directory: Path):
    directory.mkdir(parents=True, exist_ok=True)
    scale = 4
    width, height = WINDOW_SIZE
    image = Image.new("RGB", (width * scale, height * scale))
    pixels = image.load()
    for py in range(height * scale):
        y = py / scale
        for px in range(width * scale):
            x = px / scale
            blend = 0.22 * x / width + 0.64 * y / height
            distance = y - (height * 0.93 - 0.13 * x + 0.00011 * x * x)
            fold = 1 / (1 + math.exp(-distance / 12))
            highlight = 5 * math.exp(-((distance + 5) / 13) ** 2)
            shade = 4 * math.exp(-((distance - 24) / 24) ** 2)
            pixels[px, py] = tuple(
                round(max(0, min(255, start + (end - start) * blend
                                + highlight - shade - fold * tint)))
                for start, end, tint in zip((249, 250, 248), (226, 237, 230), (6, 2, 4))
            )

    draw = ImageDraw.Draw(image)
    draw.text((width / 2 * scale, 58 * scale), "Drag Gaze into Applications",
              font=font(22 * scale, 540), fill=(42, 57, 47), anchor="mt")
    draw_arrow(draw, scale)

    image.resize((width * 2, height * 2), Image.Resampling.LANCZOS).save(
        directory / "background@2x.png", dpi=(144, 144)
    )
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
