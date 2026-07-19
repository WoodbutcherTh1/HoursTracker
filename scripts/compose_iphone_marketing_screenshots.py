#!/usr/bin/env python3
"""Compose HoursTracker iPhone App Store marketing screenshots.

Official App Store Connect sizes (portrait) used here:
  6.9"  → 1320×2868  (required primary class; Apple scales to smaller classes)
  6.3"  → 1206×2622  (optional dedicated set for mid-size iPhones)

Reads raw captures from AppStoreScreenshots/iphone/raw/ and writes designed
composites to AppStoreScreenshots/iphone/marketing/ without modifying originals.

Usage:
  python3 scripts/compose_iphone_marketing_screenshots.py --sample
  python3 scripts/compose_iphone_marketing_screenshots.py --all
"""

from __future__ import annotations

import argparse
import math
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
RAW_ROOT = ROOT / "AppStoreScreenshots" / "iphone" / "raw"
OUT_ROOT = ROOT / "AppStoreScreenshots" / "iphone" / "marketing"
# Reuse the OFL font bundle already vendored for Watch marketing.
FONT_DIR = ROOT / "AppStoreScreenshots" / "watch" / "marketing" / "fonts"
CORETEXT_BIN = Path(__file__).resolve().parent / "render_headline_coretext"

# Brand-adjacent marketing chrome (matches Watch marketing family).
ORANGE = (255, 149, 0)
ORANGE_GLOW = (255, 178, 70)
EDGE = (8, 7, 6)
CENTER = (96, 54, 22)
BEZEL = (22, 22, 24)
BEZEL_RING = (255, 175, 70)
TEXT = (255, 250, 244)

# Apple App Store Connect accepted sizes we generate.
DEVICES = {
    "6.9-1320x2868": (1320, 2868),
    "6.3-1206x2622": (1206, 2622),
}

LANGS = ("en", "he", "ar")
SLOTS = ("01-home", "02-history", "03-export", "04-settings")

LATIN_HEADLINE_FONT = FONT_DIR / "Montserrat[wght].ttf"
HEBREW_HEADLINE_FONTS = (FONT_DIR / "Rubik[wght].ttf", FONT_DIR / "Assistant[wght].ttf")
ARABIC_HEADLINE_FONTS = (
    FONT_DIR / "Cairo[slnt,wght].ttf",
    FONT_DIR / "Tajawal-ExtraBold.ttf",
    FONT_DIR / "Tajawal-Bold.ttf",
)
HEADLINE_WEIGHT = 800

# Original marketing copy — HoursTracker features only (not competitor copy).
HEADLINES = {
    "01-home": {
        "en": "One tap to\nclock in or out",
        "he": "לחיצה אחת\nלכניסה או יציאה",
        "ar": "لمسة واحدة\nللدخول أو الخروج",
    },
    "02-history": {
        "en": "Hours and pay\nat a glance",
        "he": "שעות והכנסה\nבמבט אחד",
        "ar": "ساعاتك ودخلك\nبنظرة واحدة",
    },
    "03-export": {
        "en": "Export reports\nin any format",
        "he": "ייצוא דוחות\nבכל פורמט",
        "ar": "صدّر تقاريرك\nبأي صيغة",
    },
    "04-settings": {
        # Matches the tax / pay-rules block the UITest scrolls into frame.
        "en": "Pay rules and\ntax credits",
        "he": "כללי שכר\nונקודות זיכוי",
        "ar": "قواعد الأجر\nونقاط الائتمان",
    },
}

EMOJI_FONT = "/System/Library/Fonts/Apple Color Emoji.ttc"
DECO = [
    (0.10, 0.26, 1.10, "⏱", 0.22),
    (0.90, 0.30, 0.95, "✓", 0.18),
    (0.07, 0.52, 1.05, "💰", 0.17),
    (0.93, 0.58, 1.15, "🕐", 0.20),
    (0.12, 0.84, 0.85, "✓", 0.15),
    (0.88, 0.86, 0.90, "⏱", 0.16),
    (0.94, 0.44, 0.70, "💰", 0.14),
    (0.06, 0.38, 0.75, "🕐", 0.15),
]


def apply_weight(font: ImageFont.FreeTypeFont, weight: int = HEADLINE_WEIGHT) -> ImageFont.FreeTypeFont:
    try:
        axes = font.get_variation_axes()
    except Exception:
        return font
    if not axes:
        return font
    values = []
    for axis in axes:
        name = axis["name"]
        name = name.decode() if isinstance(name, bytes) else str(name)
        if name.lower() == "weight":
            values.append(min(axis["maximum"], max(axis["minimum"], weight)))
        elif name.lower() in ("opsz", "optical size"):
            target = getattr(font, "size", 48) or 48
            values.append(min(axis["maximum"], max(axis["minimum"], float(target))))
        else:
            values.append(axis["default"])
    try:
        font.set_variation_by_axes(values)
    except Exception:
        pass
    return font


def headline_font_path(lang: str) -> Path:
    if lang == "en":
        candidates = (LATIN_HEADLINE_FONT,)
    elif lang == "he":
        candidates = HEBREW_HEADLINE_FONTS
    else:
        candidates = ARABIC_HEADLINE_FONTS
    path = next((p for p in candidates if p.exists()), None)
    if path is None:
        raise SystemExit(f"Missing bundled headline font for lang={lang} under {FONT_DIR}")
    return path


def load_headline_font(lang: str, size: int) -> ImageFont.FreeTypeFont:
    path = headline_font_path(lang)
    font = ImageFont.truetype(str(path), size=size)
    if "extrabold" in path.name.lower():
        return font
    return apply_weight(font, HEADLINE_WEIGHT)


def render_headline_coretext(font_path: Path, text: str, size: int) -> Image.Image:
    if not CORETEXT_BIN.is_file():
        raise SystemExit(
            f"Missing CoreText renderer: {CORETEXT_BIN}\n"
            "Build with: swiftc -O scripts/render_headline_coretext.swift -o scripts/render_headline_coretext"
        )
    with tempfile.TemporaryDirectory(prefix="ht-iphone-headline-") as tmp:
        out = Path(tmp) / "headline.png"
        env = os.environ.copy()
        env["HT_HEADLINE_TEXT"] = text
        proc = subprocess.run(
            [str(CORETEXT_BIN), str(font_path), str(size), str(HEADLINE_WEIGHT), "FFFFFFF0", str(out)],
            env=env,
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0 or not out.is_file():
            raise SystemExit(f"CoreText headline failed: {proc.stderr or proc.stdout}")
        return Image.open(out).convert("RGBA")


def radial_gradient(size: tuple[int, int], focus: tuple[float, float]) -> Image.Image:
    # Render small then upscale — same look, far faster at 1320×2868.
    sw, sh = max(1, size[0] // 4), max(1, size[1] // 4)
    fx, fy = focus[0] / 4, focus[1] / 4
    img = Image.new("RGB", (sw, sh))
    px = img.load()
    rx, ry = sw * 0.52, sh * 0.48
    for y in range(sh):
        for x in range(sw):
            dx = (x - fx) / rx
            dy = (y - fy) / ry
            d = math.sqrt(dx * dx + dy * dy)
            t = min(1.0, d)
            t = t * t * (3.0 - 2.0 * t)
            r = int(CENTER[0] + (EDGE[0] - CENTER[0]) * t)
            g = int(CENTER[1] + (EDGE[1] - CENTER[1]) * t)
            b = int(CENTER[2] + (EDGE[2] - CENTER[2]) * t)
            bloom = max(0.0, 1.0 - d * 1.05) ** 2
            r = min(255, int(r + (ORANGE_GLOW[0] - r) * bloom * 0.68))
            g = min(255, int(g + (ORANGE_GLOW[1] - g) * bloom * 0.48))
            b = min(255, int(b + (ORANGE_GLOW[2] - b) * bloom * 0.22))
            px[x, y] = (r, g, b)
    return img.resize(size, Image.Resampling.LANCZOS)


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return mask


def draw_headline(canvas: Image.Image, text: str, lang: str, font: ImageFont.ImageFont, area: tuple[int, int, int, int]) -> None:
    draw = ImageDraw.Draw(canvas)
    x0, y0, x1, y1 = area
    if lang in ("he", "ar"):
        font_size = getattr(font, "size", 56) or 56
        glyph = render_headline_coretext(headline_font_path(lang), text, font_size)
        gw, gh = glyph.size
        x = max(x0, x1 - gw - 8)
        y = y0 + max(0, (y1 - y0 - gh) // 2)
        shadow = Image.new("RGBA", glyph.size, (0, 0, 0, 0))
        shadow.paste((0, 0, 0, 150), (0, 0, gw, gh), glyph.split()[-1])
        canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(1.4)), (x + 2, y + 3))
        canvas.alpha_composite(glyph, (x, y))
        return

    lines = text.split("\n")
    font_size = getattr(font, "size", 56) or 56
    tracking = 2.2
    line_spacing = max(8, int(font_size * 0.14))
    heights, widths = [], []
    for line in lines:
        bbox = draw.textbbox((0, 0), line, font=font)
        heights.append(bbox[3] - bbox[1])
        # tracked width
        w = 0
        for i, ch in enumerate(line):
            cb = draw.textbbox((0, 0), ch, font=font)
            w += cb[2] - cb[0]
            if i < len(line) - 1:
                w += tracking
        widths.append(int(round(w)))
    total_h = sum(heights) + line_spacing * (len(lines) - 1)
    y = y0 + max(0, (y1 - y0 - total_h) // 2)
    for i, line in enumerate(lines):
        x = x0 + (x1 - x0 - widths[i]) // 2
        cx = x
        for j, ch in enumerate(line):
            draw.text((cx + 2, y + 3), ch, font=font, fill=(0, 0, 0, 150))
            draw.text((cx, y), ch, font=font, fill=TEXT)
            cb = draw.textbbox((0, 0), ch, font=font)
            cx += (cb[2] - cb[0]) + tracking
        y += heights[i] + line_spacing


def draw_decorations(canvas: Image.Image, expect_w: int, expect_h: int, phone_box: tuple[int, int, int, int]) -> None:
    layer = Image.new("RGBA", (expect_w, expect_h), (0, 0, 0, 0))
    px0, py0, px1, py1 = phone_box
    base = max(36, int(min(expect_w, expect_h) * 0.055))
    for fx, fy, scale, emoji, opacity in DECO:
        size = max(28, int(base * scale))
        x, y = int(fx * expect_w), int(fy * expect_h)
        if px0 - 8 <= x <= px1 + 8 and py0 - 8 <= y <= py1 + 8:
            continue
        try:
            font = ImageFont.truetype(EMOJI_FONT, size=size, index=0)
        except OSError:
            continue
        probe = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
        bbox = probe.textbbox((0, 0), emoji, font=font, embedded_color=True)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        tmp = Image.new("RGBA", (tw + 12, th + 12), (0, 0, 0, 0))
        ImageDraw.Draw(tmp).text((-bbox[0] + 4, -bbox[1] + 4), emoji, font=font, embedded_color=True)
        tmp = tmp.filter(ImageFilter.GaussianBlur(radius=0.7))
        r, g, b, a = tmp.split()
        a = a.point(lambda v, op=opacity: int(v * op) if v else 0)
        tmp = Image.merge("RGBA", (r, g, b, a))
        layer.alpha_composite(tmp, (x - tmp.size[0] // 2, y - tmp.size[1] // 2))
    canvas.alpha_composite(layer)


def drop_shadow(canvas: Image.Image, box: tuple[int, int, int, int], radius: int) -> None:
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    for blur, op, off_y, grow in ((28, 200, 22, 6), (40, 90, 36, 18)):
        sw, sh = w + grow * 2, h + grow * 2
        shape = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
        ImageDraw.Draw(shape).rounded_rectangle(
            (0, 0, sw - 1, sh - 1), radius=radius + grow // 2, fill=(0, 0, 0, op)
        )
        shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        shadow.paste(shape, (x0 - grow, y0 - grow + off_y), shape)
        canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(radius=blur)))


def compose_one(device: str, lang: str, slot: str) -> Path:
    if device not in DEVICES:
        raise SystemExit(f"Unknown device: {device}")
    expect_w, expect_h = DEVICES[device]
    raw_path = RAW_ROOT / device / lang / f"{slot}.png"
    if not raw_path.is_file():
        raise SystemExit(f"Missing raw screenshot: {raw_path}")

    raw = Image.open(raw_path).convert("RGB")
    # Raw may be simulator native size; we scale into the marketing phone frame.
    # Final canvas must still be exactly expect_w × expect_h.

    # Geometry: headline band + phone frame.
    headline_bottom = int(expect_h * 0.16)
    frame_top = int(expect_h * 0.18)
    frame_bottom = int(expect_h * 0.96)
    side = int(expect_w * 0.10)
    max_w = expect_w - side * 2
    max_h = frame_bottom - frame_top

    # Phone-like aspect ≈ 19.5:9
    aspect = 19.5 / 9.0
    # Thick enough bezel so chrome (nav buttons, tab corners) never rides the rim.
    # Slightly heavier than earlier drafts after App Store review caught UI bleed.
    bezel = max(26, int(min(expect_w, expect_h) * 0.032))
    outer_w = max_w
    outer_h = int(outer_w * aspect) + bezel * 2
    if outer_h > max_h:
        outer_h = max_h
        outer_w = int((outer_h - bezel * 2) / aspect) + bezel * 2
        if outer_w > max_w:
            outer_w = max_w
            outer_h = int((outer_w - bezel * 2) * aspect) + bezel * 2

    ox = (expect_w - outer_w) // 2
    oy = frame_top + (max_h - outer_h) // 2
    outer_radius = max(56, int(min(outer_w, outer_h) * 0.12))
    phone_box = (ox, oy, ox + outer_w, oy + outer_h)
    focus = (ox + outer_w / 2, oy + outer_h * 0.45)

    canvas = radial_gradient((expect_w, expect_h), focus).convert("RGBA")
    draw_decorations(canvas, expect_w, expect_h, phone_box)
    drop_shadow(canvas, phone_box, radius=outer_radius)

    # Phone layer order (critical for no leak):
    #   1) solid device body
    #   2) hard-clipped app screenshot inside the glass
    #   3) bezel rim redrawn ON TOP of any AA fringe from the screenshot
    #   4) orange accent ring on top of the rim
    screen_inset = max(10, bezel // 2)
    sx0 = bezel + screen_inset
    sy0 = bezel + screen_inset
    inner_w = outer_w - sx0 * 2
    inner_h = outer_h - sy0 * 2
    inner_radius = max(28, outer_radius - bezel - screen_inset)
    screen = raw.resize((inner_w, inner_h), Image.Resampling.LANCZOS).convert("RGBA")

    phone = Image.new("RGBA", (outer_w, outer_h), (0, 0, 0, 0))
    pd = ImageDraw.Draw(phone)
    pd.rounded_rectangle(
        (0, 0, outer_w - 1, outer_h - 1),
        radius=outer_radius,
        fill=(*BEZEL, 255),
    )

    # Hard clip: putalpha with a crisp rounded mask (no fringe past the glass).
    clip = rounded_mask((inner_w, inner_h), inner_radius)
    clipped = Image.new("RGBA", (inner_w, inner_h), (0, 0, 0, 0))
    clipped.paste(screen, (0, 0))
    clipped.putalpha(clip)
    phone.alpha_composite(clipped, (sx0, sy0))

    # Bezel rim overlay = outer body minus screen hole. Guarantees UI never sits
    # above the frame, even if resize/AA bleeds a pixel past the clip.
    rim = Image.new("RGBA", (outer_w, outer_h), (0, 0, 0, 0))
    rim_mask = Image.new("L", (outer_w, outer_h), 0)
    rd = ImageDraw.Draw(rim_mask)
    rd.rounded_rectangle((0, 0, outer_w - 1, outer_h - 1), radius=outer_radius, fill=255)
    rd.rounded_rectangle(
        (sx0, sy0, sx0 + inner_w - 1, sy0 + inner_h - 1),
        radius=inner_radius,
        fill=0,
    )
    rim.paste((*BEZEL, 255), (0, 0, outer_w, outer_h), rim_mask)
    phone.alpha_composite(rim)

    ring = max(3, bezel // 4)
    pd = ImageDraw.Draw(phone)
    pd.rounded_rectangle(
        (ring, ring, outer_w - 1 - ring, outer_h - 1 - ring),
        radius=max(40, outer_radius - ring),
        outline=(*BEZEL_RING, 255),
        width=max(3, ring),
    )

    # Final hard mask on the entire phone layer (body + screen + rim + ring).
    # Prevents any AA fringe or tab-chrome from painting outside the device silhouette.
    outer_mask = rounded_mask((outer_w, outer_h), outer_radius)
    phone.putalpha(ImageChops.multiply(phone.split()[-1], outer_mask))

    # Composite into a masked slot on the canvas so nothing can leak past the frame.
    phone_slot = Image.new("RGBA", (expect_w, expect_h), (0, 0, 0, 0))
    phone_slot.alpha_composite(phone, (ox, oy))
    slot_mask = Image.new("L", (expect_w, expect_h), 0)
    ImageDraw.Draw(slot_mask).rounded_rectangle(
        (ox, oy, ox + outer_w - 1, oy + outer_h - 1),
        radius=outer_radius,
        fill=255,
    )
    phone_slot.putalpha(ImageChops.multiply(phone_slot.split()[-1], slot_mask))
    canvas.alpha_composite(phone_slot)

    font_size = 64 if expect_w >= 1300 else 56
    if lang in ("he", "ar"):
        font_size = 56 if expect_w >= 1300 else 50
    font = load_headline_font(lang, font_size)
    text_inset = int(expect_w * 0.07)
    draw_headline(
        canvas,
        HEADLINES[slot][lang],
        lang,
        font,
        (text_inset, int(expect_h * 0.035), expect_w - text_inset, headline_bottom),
    )

    out_rgb = canvas.convert("RGB")
    out_path = OUT_ROOT / device / lang / f"{slot}.png"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_rgb.save(out_path, format="PNG", optimize=True)

    verify = Image.open(out_path)
    if verify.size != (expect_w, expect_h):
        print(f"ERROR: final size {verify.size} != {(expect_w, expect_h)} for {out_path}", file=sys.stderr)
        sys.exit(1)
    print(f"OK {out_path} ({expect_w}x{expect_h})")
    return out_path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--sample", action="store_true", help="en / 6.9\" / 01-home only")
    group.add_argument("--all", action="store_true", help="All devices × langs × slots")
    parser.add_argument("--device", choices=sorted(DEVICES))
    parser.add_argument("--lang", choices=LANGS)
    parser.add_argument("--slot", choices=SLOTS)
    args = parser.parse_args()

    if args.sample or (not args.all and not args.device and not args.lang and not args.slot):
        jobs = [("6.9-1320x2868", "en", "01-home")]
    elif args.all:
        jobs = [(d, l, s) for d in DEVICES for l in LANGS for s in SLOTS]
    else:
        devices = [args.device] if args.device else list(DEVICES)
        langs = [args.lang] if args.lang else list(LANGS)
        slots = [args.slot] if args.slot else list(SLOTS)
        jobs = [(d, l, s) for d in devices for l in langs for s in slots]

    for device, lang, slot in jobs:
        compose_one(device, lang, slot)
    print(f"Done ({len(jobs)} file(s)). Raw left under {RAW_ROOT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
