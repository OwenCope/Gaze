"""Original Gaze installer artwork, rendered at 1x and 2x."""

from pathlib import Path

from PIL import Image, ImageDraw

WINDOW_SIZE = (640, 360)
ICON_LOCATIONS = {"Gaze.app": (176, 205), "Applications": (464, 205)}
ICON_SIZE = 104

# Neutral, flat and untextured, so the two icons are the only things with weight.
# Flat rather than graduated: across 360 points a gradient this shallow quantises
# into visible bands, and a wider one would start being a design of its own. The
# earlier background carried a green wash, a faux paper fold and a hand-drawn
# arrow — none of it in the app — plus a sentence explaining a drag that the
# layout already explains.
BACKGROUND = (236, 236, 239)
ARROW = (174, 174, 178)


def render(directory: Path):
    directory.mkdir(parents=True, exist_ok=True)
    scale = 4
    width, height = WINDOW_SIZE
    image = Image.new("RGB", (width * scale, height * scale), BACKGROUND)
    draw = ImageDraw.Draw(image)

    # Level with the icons' centres, centred in the gap between them, and stopping
    # well clear of both so it reads as the space between rather than a mark of
    # its own. The shaft ends exactly where the head begins: no seam.
    y = ICON_LOCATIONS["Gaze.app"][1]
    start, end = 265, 375
    shaft, head_length, head_half = 6.0, 18.0, 9.0
    base = end - head_length

    draw.line(
        ((start * scale, y * scale), (base * scale, y * scale)),
        fill=ARROW, width=round(shaft * scale),
    )
    draw.polygon(
        (
            (end * scale, y * scale),
            (base * scale, (y - head_half) * scale),
            (base * scale, (y + head_half) * scale),
        ),
        fill=ARROW,
    )

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
