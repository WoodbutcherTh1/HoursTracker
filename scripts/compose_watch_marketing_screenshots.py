#!/usr/bin/env python3
"""Compose HoursTracker Watch App Store marketing screenshots.

Reads raw captures from AppStoreScreenshots/watch/ and writes designed
composites to AppStoreScreenshots/watch/marketing/ without modifying originals.

Final canvas sizes must match App Store slot sizes exactly:
  series11-416x496 → 416×496
  ultra3-422x514   → 422×514

Usage:
  # Compare Latin headline fonts (en / series11 / Clock only):
  python3 scripts/compose_watch_marketing_screenshots.py --compare-fonts

  # One preview after a font is chosen:
  python3 scripts/compose_watch_marketing_screenshots.py --sample --headline-font montserrat

  # Full batch after approval:
  python3 scripts/compose_watch_marketing_screenshots.py --all --headline-font montserrat
"""

from __future__ import annotations

import argparse
import math
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

try:
    import arabic_reshaper
    from bidi.algorithm import get_display
except ImportError:
    arabic_reshaper = None
    get_display = None

ROOT = Path(__file__).resolve().parents[1]
RAW_ROOT = ROOT / "AppStoreScreenshots" / "watch"
OUT_ROOT = RAW_ROOT / "marketing"
FONT_DIR = OUT_ROOT / "fonts"
CORETEXT_BIN = Path(__file__).resolve().parent / "render_headline_coretext"

# SwiftUI Color.orange on watch Clock In/Out (~system orange)
ORANGE = (255, 149, 0)
ORANGE_GLOW = (255, 178, 70)
EDGE = (8, 7, 6)
CENTER = (96, 54, 22)
BEZEL = (24, 24, 26)
BEZEL_RING = (255, 175, 70)
TEXT = (255, 250, 244)

DEVICES = {
    "series11-416x496": (416, 496),
    "ultra3-422x514": (422, 514),
}

LANGS = ("en", "he", "ar")
SLOTS = ("01-clock", "02-recent")

# Bundled Google Fonts (SIL OFL) — never use system fonts for headlines.
# Latin candidates for EN; Hebrew/Arabic use dedicated families.
LATIN_HEADLINE_FONTS = {
    "montserrat": FONT_DIR / "Montserrat[wght].ttf",
    "dmsans": FONT_DIR / "DMSans[opsz,wght].ttf",
    "inter": FONT_DIR / "Inter[opsz,wght].ttf",
}
# RTL headline families (bundled OFL) — ExtraBold to match Montserrat EN.
HEBREW_HEADLINE_FONTS = (
    FONT_DIR / "Rubik[wght].ttf",
    FONT_DIR / "Assistant[wght].ttf",
)
ARABIC_HEADLINE_FONTS = (
    FONT_DIR / "Cairo[slnt,wght].ttf",
    FONT_DIR / "Tajawal-ExtraBold.ttf",
    FONT_DIR / "Tajawal-Bold.ttf",
)

# ExtraBold when the family supports it; otherwise Bold/static ExtraBold file.
HEADLINE_WEIGHT = 800
# Final Latin choice for production marketing exports.
DEFAULT_LATIN_HEADLINE_FONT = "montserrat"

# Original marketing copy — HoursTracker watch features only.
HEADLINES = {
    "01-clock": {
        "en": "One tap to\nclock in or out",
        "he": "לחיצה אחת\nלכניסה או יציאה",
        "ar": "لمسة واحدة\nللدخول أو الخروج",
    },
    "02-recent": {
        "en": "Recent shifts\non your wrist",
        "he": "המשמרות האחרונות\nעל היד",
        "ar": "آخر الورديات\nعلى معصمك",
    },
}

EMOJI_FONT = "/System/Library/Fonts/Apple Color Emoji.ttc"

# Asymmetric deco placements as fractions of canvas (x, y, size_scale, emoji, opacity)
# Tuned to sit around the watch frame, not over it. Opacity stays in the ~15–25% band.
DECO = [
    (0.11, 0.29, 1.15, "⏱", 0.24),
    (0.87, 0.33, 0.95, "✓", 0.20),
    (0.08, 0.57, 1.05, "💰", 0.18),
    (0.90, 0.64, 1.20, "🕐", 0.22),
    (0.15, 0.87, 0.85, "✓", 0.16),
    (0.83, 0.89, 0.90, "⏱", 0.17),
    (0.93, 0.47, 0.70, "💰", 0.15),
    (0.07, 0.41, 0.75, "🕐", 0.16),
]


def _axis_name(axis: dict) -> str:
    name = axis["name"]
    return name.decode() if isinstance(name, bytes) else str(name)


def apply_weight(font: ImageFont.FreeTypeFont, weight: int = HEADLINE_WEIGHT) -> ImageFont.FreeTypeFont:
    """Force Bold/ExtraBold on variable fonts; no-op for static faces."""
    try:
        axes = font.get_variation_axes()
    except Exception:
        return font
    if not axes:
        return font
    values = []
    for axis in axes:
        name = _axis_name(axis).lower()
        if name == "weight":
            values.append(min(axis["maximum"], max(axis["minimum"], weight)))
        elif name in ("opsz", "optical size"):
            # Prefer text optical size near the headline point size.
            target = getattr(font, "size", 32) or 32
            values.append(min(axis["maximum"], max(axis["minimum"], float(target))))
        else:
            values.append(axis["default"])
    try:
        font.set_variation_by_axes(values)
    except Exception:
        pass
    return font


def headline_font_path(lang: str, latin_family: str) -> Path:
    if lang == "en":
        candidates = (LATIN_HEADLINE_FONTS[latin_family],)
    elif lang == "he":
        candidates = HEBREW_HEADLINE_FONTS
    else:
        candidates = ARABIC_HEADLINE_FONTS
    path = next((p for p in candidates if p.exists()), None)
    if path is None:
        raise SystemExit(
            f"Missing bundled headline font for lang={lang}.\n"
            f"Expected Google Fonts files under {FONT_DIR}"
        )
    return path


def load_headline_font(lang: str, size: int, latin_family: str) -> ImageFont.FreeTypeFont:
    """Load bundled headline font only — never touches in-screenshot UI type."""
    path = headline_font_path(lang, latin_family)
    try:
        font = ImageFont.truetype(str(path), size=size)
    except OSError as exc:
        raise SystemExit(f"Failed to load font {path}: {exc}") from exc
    # Static Tajawal-ExtraBold already is ExtraBold; variable faces get wght=800.
    if "extrabold" in path.name.lower():
        return font
    return apply_weight(font, HEADLINE_WEIGHT)


def prepare_text(text: str, lang: str) -> str:
    if lang not in ("he", "ar"):
        return text
    if arabic_reshaper is None or get_display is None:
        print("WARN: arabic-reshaper/python-bidi missing; RTL shaping skipped", file=sys.stderr)
        return text
    lines = []
    for line in text.split("\n"):
        if lang == "ar":
            reshaped = arabic_reshaper.reshape(line)
            lines.append(get_display(reshaped))
        else:
            lines.append(get_display(line))
    return "\n".join(lines)


def radial_gradient(size: tuple[int, int], focus: tuple[float, float]) -> Image.Image:
    """Dark edges, warmer/lighter glow behind the watch."""
    w, h = size
    img = Image.new("RGB", size)
    px = img.load()
    cx, cy = focus
    # Elliptical radius so the glow fills the lower-mid canvas.
    rx = w * 0.52
    ry = h * 0.48
    for y in range(h):
        for x in range(w):
            dx = (x - cx) / rx
            dy = (y - cy) / ry
            d = math.sqrt(dx * dx + dy * dy)
            # Smooth falloff; clamp for deep vignette at corners.
            t = min(1.0, d)
            # Ease-in for premium soft vignette.
            t = t * t * (3.0 - 2.0 * t)
            r = int(CENTER[0] + (EDGE[0] - CENTER[0]) * t)
            g = int(CENTER[1] + (EDGE[1] - CENTER[1]) * t)
            b = int(CENTER[2] + (EDGE[2] - CENTER[2]) * t)
            # Extra orange bloom near focus.
            bloom = max(0.0, 1.0 - d * 1.05)
            bloom = bloom * bloom
            r = min(255, int(r + (ORANGE_GLOW[0] - r) * bloom * 0.68))
            g = min(255, int(g + (ORANGE_GLOW[1] - g) * bloom * 0.48))
            b = min(255, int(b + (ORANGE_GLOW[2] - b) * bloom * 0.22))
            px[x, y] = (r, g, b)
    return img


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return mask


def text_width_with_tracking(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.ImageFont, tracking: float) -> int:
    if not text:
        return 0
    if tracking == 0:
        bbox = draw.textbbox((0, 0), text, font=font)
        return bbox[2] - bbox[0]
    total = 0
    for i, ch in enumerate(text):
        bbox = draw.textbbox((0, 0), ch, font=font)
        total += bbox[2] - bbox[0]
        if i < len(text) - 1:
            total += tracking
    return int(round(total))


def draw_text_tracked(
    draw: ImageDraw.ImageDraw,
    xy: tuple[float, float],
    text: str,
    font: ImageFont.ImageFont,
    fill,
    tracking: float,
) -> None:
    x, y = xy
    if tracking == 0:
        draw.text((x, y), text, font=font, fill=fill)
        return
    for i, ch in enumerate(text):
        draw.text((x, y), ch, font=font, fill=fill)
        bbox = draw.textbbox((0, 0), ch, font=font)
        x += (bbox[2] - bbox[0]) + tracking


def render_headline_coretext(font_path: Path, text: str, size: int, weight: int = HEADLINE_WEIGHT) -> Image.Image:
    """Rasterize he/ar headlines with macOS CoreText (correct joining + RTL)."""
    if not CORETEXT_BIN.is_file():
        raise SystemExit(
            f"Missing CoreText renderer: {CORETEXT_BIN}\n"
            "Build with: swiftc -O scripts/render_headline_coretext.swift -o scripts/render_headline_coretext"
        )
    with tempfile.TemporaryDirectory(prefix="ht-headline-") as tmp:
        out = Path(tmp) / "headline.png"
        env = os.environ.copy()
        env["HT_HEADLINE_TEXT"] = text
        # FFFFFFF0 ≈ warm off-white matching TEXT
        cmd = [
            str(CORETEXT_BIN),
            str(font_path),
            str(size),
            str(weight),
            "FFFFFFF0",
            str(out),
        ]
        proc = subprocess.run(cmd, env=env, capture_output=True, text=True)
        if proc.returncode != 0 or not out.is_file():
            raise SystemExit(
                f"CoreText headline render failed ({proc.returncode}): {proc.stderr or proc.stdout}"
            )
        return Image.open(out).convert("RGBA")


def draw_headline(
    canvas: Image.Image,
    text: str,
    lang: str,
    font: ImageFont.ImageFont,
    area: tuple[int, int, int, int],
    latin_family: str = DEFAULT_LATIN_HEADLINE_FONT,
) -> None:
    draw = ImageDraw.Draw(canvas)
    x0, y0, x1, y1 = area

    # Arabic/Hebrew: CoreText shaping (Pillow lacks libraqm; presentation-form
    # reshape hits missing glyphs in Cairo/Tajawal/Rubik).
    if lang in ("he", "ar"):
        font_size = getattr(font, "size", 28) or 28
        font_path = headline_font_path(lang, latin_family)
        glyph = render_headline_coretext(font_path, text, font_size, HEADLINE_WEIGHT)
        gw, gh = glyph.size
        x = max(x0, x1 - gw - 4)  # RTL: flush right inside the band
        y = y0 + max(0, (y1 - y0 - gh) // 2)
        # Soft drop shadow under the headline plate.
        shadow = Image.new("RGBA", glyph.size, (0, 0, 0, 0))
        shadow.paste((0, 0, 0, 150), (0, 0, gw, gh), glyph.split()[-1])
        shadow = shadow.filter(ImageFilter.GaussianBlur(radius=1.2))
        canvas.alpha_composite(shadow, (x + 1, y + 2))
        canvas.alpha_composite(glyph, (x, y))
        return

    prepared = prepare_text(text, lang)
    lines = prepared.split("\n")
    font_size = getattr(font, "size", 28) or 28
    line_spacing = max(5, int(font_size * 0.16))
    tracking = 1.8

    heights = []
    widths = []
    for line in lines:
        bbox = draw.textbbox((0, 0), line, font=font)
        heights.append(bbox[3] - bbox[1])
        widths.append(text_width_with_tracking(draw, line, font, tracking))

    total_h = sum(heights) + line_spacing * (len(lines) - 1)
    y = y0 + max(0, (y1 - y0 - total_h) // 2)

    for i, line in enumerate(lines):
        w = widths[i]
        x = x0 + (x1 - x0 - w) // 2
        draw_text_tracked(draw, (x + 1.5, y + 2), line, font, (0, 0, 0, 140), tracking)
        draw_text_tracked(draw, (x, y), line, font, TEXT, tracking)
        y += heights[i] + line_spacing


def load_emoji_font(size: int) -> ImageFont.FreeTypeFont | None:
    p = Path(EMOJI_FONT)
    if not p.exists():
        return None
    try:
        return ImageFont.truetype(str(p), size=size, index=0)
    except OSError:
        return None


def draw_decorations(canvas: Image.Image, expect_w: int, expect_h: int, watch_box: tuple[int, int, int, int]) -> None:
    """Scatter low-opacity icons around the watch bezel (never over it)."""
    layer = Image.new("RGBA", (expect_w, expect_h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    wx0, wy0, wx1, wy1 = watch_box
    pad = 6

    # Apple Color Emoji bitmaps look cleaner at discrete sizes (~32–48).
    base = max(28, int(min(expect_w, expect_h) * 0.095))
    for fx, fy, scale, emoji, opacity in DECO:
        size = max(24, int(base * scale))
        font = load_emoji_font(size)
        x = int(fx * expect_w)
        y = int(fy * expect_h)
        # Skip if center would land inside the watch frame.
        if wx0 - pad <= x <= wx1 + pad and wy0 - pad <= y <= wy1 + pad:
            continue
        if font is None:
            r = size // 3
            draw.ellipse((x - r, y - r, x + r, y + r), fill=(*ORANGE, int(255 * opacity)))
            continue
        # Measure and center the glyph on the target point.
        probe = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
        bbox = probe.textbbox((0, 0), emoji, font=font, embedded_color=True)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        tmp = Image.new("RGBA", (tw + 12, th + 12), (0, 0, 0, 0))
        td = ImageDraw.Draw(tmp)
        td.text((-bbox[0] + 4, -bbox[1] + 4), emoji, font=font, embedded_color=True)
        # Soften slightly, then apply target opacity.
        tmp = tmp.filter(ImageFilter.GaussianBlur(radius=0.6))
        r, g, b, a = tmp.split()
        a = a.point(lambda v, op=opacity: int(v * op) if v else 0)
        tmp = Image.merge("RGBA", (r, g, b, a))
        px = x - tmp.size[0] // 2
        py = y - tmp.size[1] // 2
        layer.alpha_composite(tmp, (px, py))

    canvas.alpha_composite(layer)


def drop_shadow(
    canvas: Image.Image,
    box: tuple[int, int, int, int],
    radius: int,
    blur: int = 22,
    opacity: int = 200,
    offset: tuple[int, int] = (0, 14),
) -> None:
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    # Contact shadow + softer ambient shadow for a floating feel.
    for b, op, off_y, grow in (
        (blur, opacity, offset[1], 2),
        (blur + 10, int(opacity * 0.45), offset[1] + 6, 8),
    ):
        sw, sh = w + grow * 2, h + grow * 2
        shape = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
        ImageDraw.Draw(shape).rounded_rectangle(
            (0, 0, sw - 1, sh - 1),
            radius=radius + grow // 2,
            fill=(0, 0, 0, op),
        )
        shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        shadow.paste(shape, (x0 - grow + offset[0], y0 - grow + off_y), shape)
        canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(radius=b)))


def bezel_glow(canvas: Image.Image, box: tuple[int, int, int, int], radius: int) -> None:
    """Soft orange halo just behind the watch bezel."""
    x0, y0, x1, y1 = box
    pad = 14
    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle(
        (x0 - pad, y0 - pad, x1 + pad, y1 + pad),
        radius=radius + pad,
        fill=(*ORANGE, 70),
    )
    canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(radius=16)))


def compose_one(
    device: str,
    lang: str,
    slot: str,
    latin_family: str = "montserrat",
    filename_suffix: str | None = None,
) -> Path:
    if device not in DEVICES:
        raise SystemExit(f"Unknown device slot: {device}")
    if latin_family not in LATIN_HEADLINE_FONTS:
        raise SystemExit(f"Unknown Latin headline font: {latin_family}")
    expect_w, expect_h = DEVICES[device]

    raw_path = RAW_ROOT / device / lang / f"{slot}.png"
    if not raw_path.is_file():
        raise SystemExit(f"Missing raw screenshot: {raw_path}")

    raw = Image.open(raw_path).convert("RGB")
    if raw.size != (expect_w, expect_h):
        raise SystemExit(
            f"Raw screenshot has wrong size {raw.size}, expected {(expect_w, expect_h)}: {raw_path}"
        )

    # Watch bezel geometry first — drives radial focus + deco avoidance.
    frame_top = int(expect_h * 0.24)
    frame_bottom = int(expect_h * 0.96)
    frame_h = frame_bottom - frame_top
    side = int(expect_w * 0.12)
    max_w = expect_w - side * 2
    max_h = frame_h
    aspect = expect_w / expect_h
    bezel = max(8, int(min(expect_w, expect_h) * 0.028))
    outer_w = max_w
    outer_h = int(outer_w / aspect) + bezel * 2
    if outer_h > max_h:
        outer_h = max_h
        outer_w = int((outer_h - bezel * 2) * aspect) + bezel * 2
        if outer_w > max_w:
            outer_w = max_w
            outer_h = int((outer_w - bezel * 2) / aspect) + bezel * 2

    ox = (expect_w - outer_w) // 2
    oy = frame_top + (frame_h - outer_h) // 2
    outer_radius = max(28, int(min(outer_w, outer_h) * 0.22))
    watch_box = (ox, oy, ox + outer_w, oy + outer_h)
    focus = (ox + outer_w / 2, oy + outer_h * 0.52)

    canvas = radial_gradient((expect_w, expect_h), focus).convert("RGBA")

    # Decorative icons under the watch (background layer).
    draw_decorations(canvas, expect_w, expect_h, watch_box)

    # Soft floating shadow + orange halo under/behind the bezel.
    drop_shadow(canvas, watch_box, radius=outer_radius, blur=22, opacity=200, offset=(0, 14))
    bezel_glow(canvas, watch_box, radius=outer_radius)

    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(
        (ox, oy, ox + outer_w - 1, oy + outer_h - 1),
        radius=outer_radius,
        fill=(*BEZEL, 255),
    )
    ring = max(2, bezel // 3)
    draw.rounded_rectangle(
        (ox + ring, oy + ring, ox + outer_w - 1 - ring, oy + outer_h - 1 - ring),
        radius=max(20, outer_radius - ring),
        outline=(*BEZEL_RING, 255),
        width=max(2, ring),
    )

    inner_x = ox + bezel
    inner_y = oy + bezel
    inner_w = outer_w - bezel * 2
    inner_h = outer_h - bezel * 2
    inner_radius = max(16, outer_radius - bezel)

    # Raw watch UI pixels stay untouched — only scaled into the bezel.
    screen = raw.resize((inner_w, inner_h), Image.Resampling.LANCZOS).convert("RGBA")
    mask = rounded_mask((inner_w, inner_h), inner_radius)
    canvas.paste(screen, (inner_x, inner_y), mask)

    draw.rounded_rectangle(
        (inner_x, inner_y, inner_x + inner_w - 1, inner_y + inner_h - 1),
        radius=inner_radius,
        outline=(255, 210, 140, 220),
        width=1,
    )

    # Marketing headline only (bundled Google Font) — not UI copy inside the screenshot.
    headline_bottom = int(expect_h * 0.22)
    font_size = 34 if expect_w >= 420 else 32
    if lang in ("he", "ar"):
        font_size = 30 if expect_w >= 420 else 28
    font = load_headline_font(lang, font_size, latin_family)
    inset = int(expect_w * 0.05)
    draw_headline(
        canvas,
        HEADLINES[slot][lang],
        lang,
        font,
        (inset, int(expect_h * 0.028), expect_w - inset, headline_bottom),
        latin_family=latin_family,
    )

    out_rgb = canvas.convert("RGB")
    stem = f"{slot}-{filename_suffix}" if filename_suffix else slot
    out_path = OUT_ROOT / device / lang / f"{stem}.png"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_rgb.save(out_path, format="PNG", optimize=True)

    verify = Image.open(out_path)
    if verify.size != (expect_w, expect_h):
        print(
            f"ERROR: final size {verify.size} != expected {(expect_w, expect_h)} for {out_path}",
            file=sys.stderr,
        )
        sys.exit(1)

    print(f"OK {out_path} ({expect_w}x{expect_h}) headline={latin_family if lang == 'en' else lang}")
    return out_path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "--sample",
        action="store_true",
        help="Compose only en / series11 / 01-clock for design approval",
    )
    group.add_argument(
        "--compare-fonts",
        action="store_true",
        help="Compose 3 en samples (Montserrat / DM Sans / Inter) for font picking",
    )
    group.add_argument("--all", action="store_true", help="Compose all devices × langs × slots")
    parser.add_argument("--device", choices=sorted(DEVICES), help="Single device folder name")
    parser.add_argument("--lang", choices=LANGS, help="Single language")
    parser.add_argument("--slot", choices=SLOTS, help="Single screenshot slot")
    parser.add_argument(
        "--headline-font",
        choices=sorted(LATIN_HEADLINE_FONTS),
        default=DEFAULT_LATIN_HEADLINE_FONT,
        help="Latin headline family for en (he→Rubik/Assistant, ar→Cairo/Tajawal ExtraBold)",
    )
    args = parser.parse_args()

    if args.compare_fonts:
        for family in ("montserrat", "dmsans", "inter"):
            compose_one(
                "series11-416x496",
                "en",
                "01-clock",
                latin_family=family,
                filename_suffix=family,
            )
        print("Compare samples ready — pick one family, then re-run with --headline-font …")
        return 0

    jobs: list[tuple[str, str, str]] = []
    if args.sample or (not args.all and not args.device and not args.lang and not args.slot):
        jobs = [("series11-416x496", "en", "01-clock")]
    elif args.all:
        for device in DEVICES:
            for lang in LANGS:
                for slot in SLOTS:
                    jobs.append((device, lang, slot))
    else:
        devices = [args.device] if args.device else list(DEVICES)
        langs = [args.lang] if args.lang else list(LANGS)
        slots = [args.slot] if args.slot else list(SLOTS)
        for device in devices:
            for lang in langs:
                for slot in slots:
                    jobs.append((device, lang, slot))

    for device, lang, slot in jobs:
        compose_one(device, lang, slot, latin_family=args.headline_font)

    print(f"Done ({len(jobs)} file(s)). Raw screenshots left untouched under {RAW_ROOT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
