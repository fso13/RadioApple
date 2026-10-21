#!/usr/bin/env python3
"""Generate RadioMac brand assets for the app and the installer.

* App icon (1024 and derived sizes) — replaces the Flutter template icon.
* `installer/RadioMac.icns` — volume icon.
* `installer/background.png` / `background@2x.png` — the drag-and-drop DMG window.

The generated PNGs are committed, so this script is only needed when the branding
changes. It uses Pillow:

    /path/to/python3 -m pip install Pillow
    python3 scripts/make_brand_assets.py
"""

from __future__ import annotations

import math
import pathlib

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[1]
ICONSET_DIR = ROOT / "RadioMac" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
INSTALLER_DIR = ROOT / "installer"

# Monochrome palette, matching the app's editorial design.
BG = (250, 250, 250)
BG_DEEP = (242, 242, 242)
INK = (17, 17, 17)
MUTED = (138, 138, 138)
MUTED_BRIGHT = (80, 80, 80)
LINE = (230, 230, 230)
ACCENT = (245, 245, 245)
ACCENT_PINK = (245, 245, 245)
CYAN = (245, 245, 245)

# Installer window stays light: Finder draws icon labels in the system colour.
LIGHT_BG = (250, 250, 250)
LIGHT_BG_DEEP = (241, 241, 241)
LIGHT_INK = (17, 17, 17)
LIGHT_MUTED = (138, 138, 138)
LIGHT_MUTED_BRIGHT = (72, 72, 72)
LIGHT_LINE = (228, 228, 228)
LIGHT_ACCENT = (17, 17, 17)
LIGHT_ACCENT_PINK = (17, 17, 17)

SF = "/System/Library/Fonts/SFNS.ttf"
SF_MONO = "/System/Library/Fonts/SFNSMono.ttf"

SS = 4  # supersampling factor for crisp edges


# ---------------------------------------------------------------- helpers
def font(path: str, size: float, weight: str | None = None) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(path, int(round(size)))
    if weight:
        try:
            f.set_variation_by_name(weight)
        except Exception:
            pass
    return f


def vertical_gradient(size: tuple[int, int], top: tuple, bottom: tuple) -> Image.Image:
    w, h = size
    column = Image.new("RGB", (1, h))
    draw = ImageDraw.Draw(column)
    for y in range(h):
        t = y / max(h - 1, 1)
        draw.point((0, y), fill=tuple(round(top[i] * (1 - t) + bottom[i] * t) for i in range(3)))
    return column.resize((w, h), Image.Resampling.NEAREST).convert("RGBA")


def radial_glow(size: tuple[int, int], center: tuple[float, float], radius: float,
                color: tuple, peak: float) -> Image.Image:
    """Soft radial highlight as an RGBA layer."""
    w, h = size
    small = (max(w // 8, 1), max(h // 8, 1))
    layer = Image.new("RGBA", small, (0, 0, 0, 0))
    pixels = layer.load()
    cx, cy = center[0] * small[0], center[1] * small[1]
    r = radius * max(small)
    for y in range(small[1]):
        for x in range(small[0]):
            d = math.hypot(x - cx, y - cy) / max(r, 1e-6)
            if d >= 1:
                continue
            alpha = int(peak * 255 * (1 - d) ** 2)
            if alpha > 0:
                pixels[x, y] = (*color, alpha)
    layer = layer.resize(size, Image.Resampling.BILINEAR)
    return layer.filter(ImageFilter.GaussianBlur(max(size) * 0.012))


def rounded_mask(size: tuple[int, int], inset: float, radius: float) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [inset, inset, size[0] - inset, size[1] - inset],
        radius=radius,
        fill=255,
    )
    return mask


def stroke_arc_round(draw: ImageDraw.ImageDraw, center: tuple[float, float], radius: float,
                     start: float, end: float, width: float, color: tuple) -> None:
    """Thick arc with round caps, filled as a smooth band."""
    steps = max(int(abs(end - start) * 40), 16)
    outer, inner, mid = [], [], []
    for i in range(steps + 1):
        angle = start + (end - start) * i / steps
        cos_a, sin_a = math.cos(angle), math.sin(angle)
        outer.append((center[0] + cos_a * (radius + width / 2),
                      center[1] + sin_a * (radius + width / 2)))
        inner.append((center[0] + cos_a * (radius - width / 2),
                      center[1] + sin_a * (radius - width / 2)))
        mid.append((center[0] + cos_a * radius, center[1] + sin_a * radius))
    draw.polygon(outer + list(reversed(inner)), fill=color)
    r = width / 2
    for x, y in (mid[0], mid[-1]):
        draw.ellipse([x - r, y - r, x + r, y + r], fill=color)


def draw_radio_mark(draw: ImageDraw.ImageDraw, origin: tuple[float, float], size: float,
                    color: tuple, badge_bg: tuple, glow: bool = False) -> None:
    """The RadioMac glyph: emitter dot, two broadcast arcs, plus badge."""
    ox, oy = origin
    center = (ox + size * 0.42, oy + size * 0.58)

    if glow:
        stroke_arc_round(draw, center, size * 0.26, -2.3, -0.5, size * 0.08,
                         (*ACCENT_PINK, 90))
        stroke_arc_round(draw, center, size * 0.40, -2.25, -0.55, size * 0.08,
                         (*CYAN, 60))

    dot_r = size * 0.11
    draw.ellipse([center[0] - dot_r, center[1] - dot_r, center[0] + dot_r, center[1] + dot_r],
                 fill=(*color, 255))
    stroke_arc_round(draw, center, size * 0.26, -2.3, -0.5, size * 0.08, (*color, 255))
    stroke_arc_round(draw, center, size * 0.40, -2.25, -0.55, size * 0.08, (*color, 255))

    badge_center = (ox + size * 0.78, oy + size * 0.78)
    badge = size * 0.4
    outer = badge * 0.52
    draw.ellipse([badge_center[0] - outer, badge_center[1] - outer,
                  badge_center[0] + outer, badge_center[1] + outer], fill=(*badge_bg, 255))
    inner = badge * 0.42
    draw.ellipse([badge_center[0] - inner, badge_center[1] - inner,
                  badge_center[0] + inner, badge_center[1] + inner], fill=(*color, 255))

    arm = badge * 0.18
    width = size * 0.07
    draw.rounded_rectangle(
        [badge_center[0] - arm, badge_center[1] - width / 2,
         badge_center[0] + arm, badge_center[1] + width / 2],
        radius=width / 2, fill=(*badge_bg, 255),
    )
    draw.rounded_rectangle(
        [badge_center[0] - width / 2, badge_center[1] - arm,
         badge_center[0] + width / 2, badge_center[1] + arm],
        radius=width / 2, fill=(*badge_bg, 255),
    )


# ---------------------------------------------------------------- app icon
def make_app_icon() -> Image.Image:
    size = 1024 * SS
    inset = 92 * SS
    radius = 188 * SS
    plate_rect = (inset, inset, size - inset, size - inset)

    # Soft drop shadow underneath the plate.
    shadow = Image.new("L", (size, size), 0)
    ImageDraw.Draw(shadow).rounded_rectangle(
        [plate_rect[0], plate_rect[1] + 12 * SS, plate_rect[2], plate_rect[3] + 12 * SS],
        radius=radius, fill=120,
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(26 * SS))
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste((0, 0, 0, 190), (0, 0), shadow)

    # Plate: graphite gradient with a faint top highlight.
    plate = vertical_gradient((size, size), (30, 30, 33), (7, 7, 8))
    plate = Image.alpha_composite(plate, radial_glow((size, size), (0.18, 0.1), 0.85, (255, 255, 255), 0.06))

    # The mark: rendered once on a scratch layer to learn its true bounding box,
    # then drawn centred on the plate with a badge that matches the plate colour.
    scratch = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    probe_size = 760 * SS
    draw_radio_mark(ImageDraw.Draw(scratch), (0, 0), probe_size, ACCENT, BG_DEEP)
    bbox = scratch.getbbox()
    if bbox is None:
        bbox = (0, 0, probe_size, probe_size)
    mark_w, mark_h = bbox[2] - bbox[0], bbox[3] - bbox[1]

    target = 0.60 * (plate_rect[2] - plate_rect[0])
    mark_size = probe_size * target / mark_w
    origin = (
        (plate_rect[0] + plate_rect[2]) / 2 - (bbox[0] + mark_w / 2) * mark_size / probe_size,
        (plate_rect[1] + plate_rect[3]) / 2 - (bbox[1] + mark_h / 2) * mark_size / probe_size,
    )

    # Badge background sampled from the plate so the disc blends in.
    badge_center = (origin[0] + mark_size * 0.78, origin[1] + mark_size * 0.78)
    sampled = plate.getpixel((int(badge_center[0]), int(badge_center[1])))
    badge_bg = sampled[:3]

    draw_radio_mark(ImageDraw.Draw(plate), origin, mark_size, ACCENT, badge_bg)

    # Hairline border and the rounded plate itself.
    ImageDraw.Draw(plate).rounded_rectangle(
        [plate_rect[0] + SS, plate_rect[1] + SS, plate_rect[2] - SS, plate_rect[3] - SS],
        radius=radius - SS, outline=(255, 255, 255, 24), width=2 * SS,
    )
    canvas = Image.composite(plate, canvas, rounded_mask((size, size), inset, radius))

    # Slim accent rim to tie the icon to the app chrome.
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(plate_rect, radius=radius, outline=(255, 255, 255, 18), width=2 * SS)

    return canvas.resize((1024, 1024), Image.Resampling.LANCZOS)


# ---------------------------------------------------------------- background
def make_background(scale: int) -> Image.Image:
    w, h = 640 * scale, 400 * scale
    image = vertical_gradient((w, h), LIGHT_BG, LIGHT_BG_DEEP)
    image = Image.alpha_composite(image, radial_glow((w, h), (0.1, 0.02), 0.9, LIGHT_ACCENT, 0.16))
    image = Image.alpha_composite(image, radial_glow((w, h), (0.94, 1.0), 0.7, LIGHT_ACCENT_PINK, 0.10))
    draw = ImageDraw.Draw(image)

    # Framed panel, echoing the app window chrome.
    draw.rounded_rectangle([12 * scale, 12 * scale, w - 12 * scale, h - 12 * scale],
                           radius=14 * scale, outline=(*LIGHT_LINE, 255), width=1 * scale)

    # Brand: glyph + wordmark.
    mark = 36 * scale
    word_size = 30 * scale
    radio_font = font(SF, word_size, "Bold")
    mac_font = font(SF, word_size, "Bold")
    radio_w = draw.textlength("Radio", font=radio_font)
    mac_w = draw.textlength("Mac", font=mac_font)
    total_w = radio_w + mac_w + mark + 10 * scale
    left = (w - total_w) / 2
    baseline_y = 42 * scale
    draw_radio_mark(draw, (left, baseline_y + 2 * scale), mark, LIGHT_ACCENT, LIGHT_BG_DEEP)
    text_x = left + mark + 10 * scale
    draw.text((text_x, baseline_y), "Radio", font=radio_font, fill=(*LIGHT_INK, 255), anchor="la")
    draw.text((text_x + radio_w, baseline_y), "Mac", font=mac_font, fill=(*LIGHT_INK, 255), anchor="la")

    mono = font(SF_MONO, 12 * scale, "Regular")
    draw.text((w / 2, 100 * scale), "интернет-радио в меню-баре",
              font=mono, fill=(*LIGHT_MUTED, 255), anchor="ma")

    # Arrow between the two icons.
    arrow_y = 195 * scale
    start_x, end_x = 258 * scale, 386 * scale
    dash, gap = 9 * scale, 7 * scale
    x = start_x
    while x < end_x - 12 * scale:
        draw.rounded_rectangle([x, arrow_y - 1.2 * scale, min(x + dash, end_x - 12 * scale), arrow_y + 1.2 * scale],
                               radius=1.2 * scale, fill=(*LIGHT_MUTED, 210))
        x += dash + gap
    head = 9 * scale
    draw.line([(end_x - head, arrow_y - head), (end_x, arrow_y), (end_x - head, arrow_y + head)],
              fill=(*LIGHT_ACCENT, 255), width=int(2.4 * scale), joint="curve")

    # Captions.
    caption = font(SF, 13.5 * scale, "Semibold")
    draw.text((w / 2, 312 * scale), "Перетащите RadioMac в папку «Программы»",
              font=caption, fill=(*LIGHT_INK, 255), anchor="ma")
    hint = font(SF_MONO, 11 * scale, "Regular")
    draw.text((w / 2, 336 * scale), "После установки иконка появится в меню-баре",
              font=hint, fill=(*LIGHT_MUTED, 255), anchor="ma")

    return image


# ---------------------------------------------------------------- write
def main() -> None:
    INSTALLER_DIR.mkdir(exist_ok=True)
    ICONSET_DIR.mkdir(parents=True, exist_ok=True)

    icon = make_app_icon()
    for size in (16, 32, 64, 128, 256, 512, 1024):
        icon.resize((size, size), Image.Resampling.LANCZOS).save(
            ICONSET_DIR / f"app_icon_{size}.png"
        )

    # .icns for the DMG volume icon.
    iconset = INSTALLER_DIR / "RadioMac.iconset"
    iconset.mkdir(exist_ok=True)
    pairs = [
        (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
    ]
    for size, name in pairs:
        icon.resize((size, size), Image.Resampling.LANCZOS).save(iconset / name)

    import subprocess
    subprocess.run(
        ["iconutil", "-c", "icns", str(iconset), "-o", str(INSTALLER_DIR / "RadioMac.icns")],
        check=True,
    )
    import shutil
    shutil.rmtree(iconset)

    retina = make_background(2)
    retina.save(INSTALLER_DIR / "background@2x.png")
    retina.resize((640, 400), Image.Resampling.LANCZOS).save(INSTALLER_DIR / "background.png")

    print("app icons   ->", ICONSET_DIR)
    print("installer   ->", INSTALLER_DIR)


if __name__ == "__main__":
    main()
