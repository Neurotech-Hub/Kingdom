#!/usr/bin/env python3
"""Render the iOS app icon and launch-screen assets from brand/kingdom_logo.png.

Writes into app/iOS/Kingdom/Kingdom/Assets.xcassets:
  AppIcon.appiconset   default (sunset gradient), dark, and tinted 1024 px variants
  LaunchMark.imageset  mist-colored mark at 1x/2x/3x
  LaunchBackground.colorset / AccentColor.colorset

Usage:
    tools/tag-gen/.venv/bin/python tools/brand-gen/generate_app_assets.py
"""

import json
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parents[2]
LOGO = ROOT / "brand/kingdom_logo.png"
TOPO = ROOT / "brand/kingdom_topo.png"
ASSETS = ROOT / "app/iOS/Kingdom/Kingdom/Assets.xcassets"

CHARCOAL = (0x1B, 0x1B, 0x1B)
FOREST = (0x49, 0x68, 0x4A)
FOREST_DEEP = (0x2B, 0x40, 0x2E)
CLAY = (0xB3, 0x52, 0x2E)
SUNSET = (0xD9, 0x7A, 0x3A)
SAND = (0xEA, 0xDC, 0xC8)
MIST = (0xF6, 0xF5, 0xEF)

ICON = 1024
# Mark width as a fraction of the icon; roughly matches the identity sheet.
MARK_FRACTION = 0.60
LAUNCH_MARK_POINTS = 88


def logo_mask():
    """Alpha mask of the mark (opaque where the logo ink is), cropped tight."""
    image = Image.open(LOGO).convert("RGBA")
    alpha = image.split()[3]
    ink = ImageChops.multiply(alpha, ImageOps.invert(image.convert("L")))
    return ink.crop(ink.getbbox())


def fitted_mask(mask, width):
    scale = width / mask.width
    return mask.resize((round(mask.width * scale), round(mask.height * scale)), Image.LANCZOS)


def place(mask, size, width, nudge=(0.0, 0.0)):
    """Centers the scaled mark on a size x size canvas, with an optional optical nudge."""
    m = fitted_mask(mask, width)
    canvas = Image.new("L", (size, size), 0)
    x = (size - m.width) // 2 + round(nudge[0] * size)
    y = (size - m.height) // 2 + round(nudge[1] * size)
    canvas.paste(m, (x, y))
    return canvas


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(size, stops):
    """Diagonal gradient from top-right to bottom-left through the given (t, color) stops."""
    small = 256
    img = Image.new("RGB", (small, small))
    px = img.load()
    for y in range(small):
        for x in range(small):
            t = min(1.0, max(0.0, ((small - 1 - x) * 0.35 + y) / ((small - 1) * 1.35)))
            for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
                if t0 <= t <= t1:
                    px[x, y] = lerp(c0, c1, (t - t0) / (t1 - t0))
                    break
    return img.resize((size, size), Image.BICUBIC)


def topo_overlay(size, opacity):
    topo = Image.open(TOPO).convert("L")
    side = min(topo.size)
    topo = topo.crop((0, 0, side, side)).resize((size, size), Image.LANCZOS)
    lines = ImageOps.invert(topo)
    return lines.point(lambda v: round(v * opacity))


def solid(color, size):
    return Image.new("RGB", (size, size), color)


def icon_default(mask):
    base = gradient(ICON, [(0.0, SUNSET), (0.30, CLAY), (0.65, FOREST), (1.0, FOREST_DEEP)])
    base.paste(solid(MIST, ICON), (0, 0), topo_overlay(ICON, 0.10))
    mark = place(mask, ICON, ICON * MARK_FRACTION, nudge=(0.0, 0.01))
    shadow = mark.filter(ImageFilter.GaussianBlur(18)).point(lambda v: round(v * 0.22))
    shadow = ImageChops.offset(shadow, 0, 10)
    base.paste(solid((0, 0, 0), ICON), (0, 0), shadow)
    base.paste(solid(MIST, ICON), (0, 0), mark)
    return base


def icon_dark(mask):
    # Dark icons are drawn on the system's dark backdrop, so the background stays transparent.
    mark = place(mask, ICON, ICON * MARK_FRACTION, nudge=(0.0, 0.01))
    fill = gradient(ICON, [(0.0, SUNSET), (0.45, (0xE4, 0x9A, 0x62)), (1.0, SAND)])
    icon = Image.new("RGBA", (ICON, ICON), (0, 0, 0, 0))
    icon.paste(fill, (0, 0), mark)
    return icon


def icon_tinted(mask):
    # Grayscale luminance map; the system applies the user's tint.
    mark = place(mask, ICON, ICON * MARK_FRACTION, nudge=(0.0, 0.01))
    icon = solid((0, 0, 0), ICON)
    icon.paste(solid((255, 255, 255), ICON), (0, 0), mark)
    return icon.convert("L")


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2) + "\n")


def main():
    mask = logo_mask()

    appicon = ASSETS / "AppIcon.appiconset"
    icon_default(mask).save(appicon / "AppIcon.png")
    icon_dark(mask).save(appicon / "AppIcon-Dark.png")
    icon_tinted(mask).save(appicon / "AppIcon-Tinted.png")
    write_json(appicon / "Contents.json", {
        "images": [
            {"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
            {"appearances": [{"appearance": "luminosity", "value": "dark"}], "filename": "AppIcon-Dark.png",
             "idiom": "universal", "platform": "ios", "size": "1024x1024"},
            {"appearances": [{"appearance": "luminosity", "value": "tinted"}], "filename": "AppIcon-Tinted.png",
             "idiom": "universal", "platform": "ios", "size": "1024x1024"},
        ],
        "info": {"author": "xcode", "version": 1},
    })

    launch = ASSETS / "LaunchMark.imageset"
    launch.mkdir(exist_ok=True)
    images = []
    for scale in (1, 2, 3):
        m = fitted_mask(mask, LAUNCH_MARK_POINTS * scale)
        img = Image.new("RGBA", m.size, MIST + (0,))
        img.putalpha(m)
        name = "LaunchMark@%dx.png" % scale if scale > 1 else "LaunchMark.png"
        img.save(launch / name)
        images.append({"filename": name, "idiom": "universal", "scale": "%dx" % scale})
    write_json(launch / "Contents.json", {"images": images, "info": {"author": "xcode", "version": 1}})

    def color_set(name, rgb):
        folder = ASSETS / ("%s.colorset" % name)
        folder.mkdir(exist_ok=True)
        components = {k: "0x%02X" % v for k, v in zip(("red", "green", "blue"), rgb)}
        components["alpha"] = "1.000"
        write_json(folder / "Contents.json", {
            "colors": [{"color": {"color-space": "srgb", "components": components}, "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
        })

    color_set("LaunchBackground", CHARCOAL)
    color_set("AccentColor", FOREST)
    print("Wrote app icon, launch mark, and colors to", ASSETS.relative_to(ROOT))


if __name__ == "__main__":
    main()
