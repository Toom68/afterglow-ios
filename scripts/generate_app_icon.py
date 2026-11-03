#!/usr/bin/env python3
"""Generates Afterglow's original 1024x1024 app icon (opaque PNG, no alpha).

Design: a dusk gradient with a soft warm glow settling on a low horizon.
Requires Pillow (`pip install pillow`). The generated PNG is committed, so this script only
needs to run when the icon design changes.
"""
import pathlib

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SIZE = 1024
OUT = pathlib.Path(__file__).resolve().parent.parent / "ios/Afterglow/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def main() -> None:
    top, middle, bottom = (18, 14, 46), (74, 32, 92), (214, 104, 84)
    image = Image.new("RGB", (SIZE, SIZE))
    pixels = image.load()
    for y in range(SIZE):
        t = y / (SIZE - 1)
        color = lerp(top, middle, t / 0.62) if t < 0.62 else lerp(middle, bottom, (t - 0.62) / 0.38)
        for x in range(SIZE):
            pixels[x, y] = color

    glow = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    draw = ImageDraw.Draw(glow)
    cx, cy = SIZE // 2, int(SIZE * 0.64)
    for radius in range(420, 0, -6):
        strength = (1 - radius / 420) ** 2.2
        draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=lerp((0, 0, 0), (255, 170, 110), strength))
    glow = glow.filter(ImageFilter.GaussianBlur(40))
    image = ImageChops.add(image, glow)

    sun = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(sun).ellipse((cx - 170, cy - 170, cx + 170, cy + 170), fill=255)
    sun = sun.filter(ImageFilter.GaussianBlur(6))
    image.paste((255, 214, 160), (0, 0), sun)

    horizon = int(SIZE * 0.7)
    shade = Image.new("L", (SIZE, SIZE), 0)
    shade_draw = ImageDraw.Draw(shade)
    for y in range(horizon, SIZE):
        shade_draw.line((0, y, SIZE, y), fill=min(255, int(228 + 27 * (y - horizon) / (SIZE - horizon))))
    image.paste((28, 18, 52), (0, 0), shade)

    for i in range(3):
        y = horizon + 40 + i * 46
        half = int(150 - i * 38)
        ImageDraw.Draw(image).line((cx - half, y, cx + half, y), fill=(236, 150, 112), width=10 - i * 2)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(OUT, "PNG", optimize=True)
    print(f"wrote {OUT} ({image.size[0]}x{image.size[1]})")


if __name__ == "__main__":
    main()
