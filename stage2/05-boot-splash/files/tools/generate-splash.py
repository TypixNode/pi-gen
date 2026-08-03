#!/usr/bin/env python3
"""Generate the baked-in default "eggfly" boot splash assets.

This is a development-time helper. It renders:
  * splash.png            - the static default splash (1920x1080)
  * eggfly-anim-N.png      - a small rainbow spinner animation (transparent)

The generated files live next to the Plymouth theme in
``stage2/05-boot-splash/files/plymouth/`` and are committed to the repo so the
image build itself needs no image tooling. Re-run this script only when you
want to change the default artwork:

    python3 generate-splash.py

Requires Pillow (``pip install Pillow``) and a bold sans TTF font.
"""
from __future__ import annotations

import math
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "plymouth"))

WIDTH, HEIGHT = 1920, 1080
BG_TOP = (15, 17, 23)
BG_BOTTOM = (5, 6, 9)
# Raspberry Pi style rainbow accent (nod to the firmware splash it replaces).
RAINBOW = [
    (255, 0, 0), (255, 153, 0), (255, 255, 0),
    (0, 204, 0), (0, 102, 255), (102, 0, 204),
]

FONT_CANDIDATES = [
    "/opt/cursor/ansible/files/fonts/Inter-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
]


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def vertical_gradient(w: int, h: int, top, bottom) -> Image.Image:
    base = Image.new("RGB", (w, h), top)
    draw = ImageDraw.Draw(base)
    for y in range(h):
        t = y / max(1, h - 1)
        draw.line(
            [(0, y), (w, y)],
            fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)),
        )
    return base


def make_splash() -> None:
    img = vertical_gradient(WIDTH, HEIGHT, BG_TOP, BG_BOTTOM).convert("RGBA")
    draw = ImageDraw.Draw(img)

    wordmark = load_font(210)
    sub = load_font(58)

    text = "eggfly"
    tb = draw.textbbox((0, 0), text, font=wordmark)
    tw, th = tb[2] - tb[0], tb[3] - tb[1]
    tx = (WIDTH - tw) / 2 - tb[0]
    ty = (HEIGHT - th) / 2 - tb[1] - 70

    # soft shadow then wordmark
    draw.text((tx + 6, ty + 8), text, font=wordmark, fill=(0, 0, 0, 150))
    draw.text((tx, ty), text, font=wordmark, fill=(245, 247, 250, 255))

    # rainbow underline accent
    bar_w, bar_h = int(tw * 0.9), 14
    bar_x = int((WIDTH - bar_w) / 2)
    bar_y = int(ty + th + 60)
    seg = bar_w // len(RAINBOW)
    for i, color in enumerate(RAINBOW):
        draw.rounded_rectangle(
            [bar_x + i * seg, bar_y, bar_x + (i + 1) * seg - 6, bar_y + bar_h],
            radius=6, fill=color + (255,),
        )

    subtitle = "Raspberry Pi"
    sbb = draw.textbbox((0, 0), subtitle, font=sub)
    sw = sbb[2] - sbb[0]
    draw.text(
        ((WIDTH - sw) / 2 - sbb[0], bar_y + 48),
        subtitle, font=sub, fill=(150, 160, 175, 255),
    )

    img.convert("RGB").save(os.path.join(OUT, "splash.png"))


def make_spinner(frames: int = 16, size: int = 110) -> None:
    """A rotating rainbow arc spinner with a transparent background."""
    cx = cy = size / 2
    r_out = size / 2 - 6
    r_in = r_out - 16
    arcs = len(RAINBOW)
    for f in range(frames):
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)
        rot = (f / frames) * 360.0
        span = 360.0 / arcs
        for i, color in enumerate(RAINBOW):
            start = rot + i * span
            # fade trailing arcs for a sense of motion
            alpha = int(90 + 165 * (i / (arcs - 1)))
            draw.arc(
                [cx - r_out, cy - r_out, cx + r_out, cy + r_out],
                start=start, end=start + span - 8,
                fill=color + (alpha,), width=int(r_out - r_in),
            )
        img.save(os.path.join(OUT, f"eggfly-anim-{f}.png"))


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    make_splash()
    make_spinner()
    print(f"Wrote splash + spinner frames to {OUT}")


if __name__ == "__main__":
    main()
