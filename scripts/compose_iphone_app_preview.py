#!/usr/bin/env python3
"""Compose an App Store Connect iPhone App Preview from marketing screenshots
plus original AI-generated people stills (no third-party stock / copyrighted faces).

Output (ASC portrait, widely accepted for 6.9" / 6.5" / 6.3" / 6.1"):
  886×1920, H.264 High@L4.0, 30fps CFR, 15–30s, no audio, ~10–12 Mbps

Usage:
  python3 scripts/compose_iphone_app_preview.py --lang en
  python3 scripts/compose_iphone_app_preview.py --lang he
  python3 scripts/compose_iphone_app_preview.py --all
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
MKT_ROOT = ROOT / "AppStoreScreenshots" / "iphone" / "marketing" / "6.9-1320x2868"
PEOPLE_DIR = ROOT / "AppStoreScreenshots" / "iphone" / "preview" / "people"
OUT_DIR = ROOT / "AppStoreScreenshots" / "iphone" / "preview"
FONT_DIR = ROOT / "AppStoreScreenshots" / "watch" / "marketing" / "fonts"
CORETEXT_BIN = Path(__file__).resolve().parent / "render_headline_coretext"
HEADLINE_WEIGHT = 800

W, H = 886, 1920
FPS = 30
BITRATE = "11M"
LANGS = ("en", "he", "ar")

# Hold seconds per beat (before crossfade). Total ~26s with xfade.
BEATS = [
    ("people", "worker-woman-phone.png", 3.4),
    ("slot", "01-home.png", 5.2),
    ("slot", "02-history.png", 5.0),
    ("people", "worker-man-phone.png", 2.8),
    ("slot", "03-export.png", 4.2),
    ("slot", "04-settings.png", 4.0),
    ("people", "workers-together-phone.png", 3.2),
]
XFADE = 0.55

TITLES = {
    "en": "HoursTracker",
    "he": "HoursTracker",
    "ar": "HoursTracker",
}
TAGLINES = {
    "en": "Clock in. Track pay. Export.",
    # Word lists are composed right→left in code (not one BIDI string).
    "he": None,
    "ar": None,
}
TAGLINE_WORDS = {
    "he": ("כניסה", "שכר", "ייצוא"),
    "ar": ("دخول", "أجر", "تصدير"),
}
ENDLINES = {
    "en": "Track every hour",
    "he": "כל שעה נספרת",
    "ar": "كل ساعة تُحسب",
}


def need(bin_name: str) -> None:
    if shutil.which(bin_name) is None:
        raise SystemExit(f"Missing tool: {bin_name}")


def rtl_font_path(lang: str) -> Path:
    if lang == "he":
        candidates = (FONT_DIR / "Rubik[wght].ttf", FONT_DIR / "Assistant[wght].ttf")
    else:
        candidates = (FONT_DIR / "Cairo[slnt,wght].ttf", FONT_DIR / "Tajawal-Bold.ttf")
    path = next((p for p in candidates if p.is_file()), None)
    if path is None:
        raise SystemExit(f"Missing RTL font for lang={lang} under {FONT_DIR}")
    return path


def load_latin_font(size: int, bold: bool = True) -> ImageFont.FreeTypeFont:
    path = FONT_DIR / ("Montserrat[wght].ttf" if bold else "Inter[opsz,wght].ttf")
    if not path.is_file():
        return ImageFont.load_default()
    font = ImageFont.truetype(str(path), size=size)
    try:
        axes = font.get_variation_axes()
        values = []
        for axis in axes:
            name = axis["name"]
            name = name.decode() if isinstance(name, bytes) else str(name)
            if name.lower() == "weight":
                values.append(min(axis["maximum"], max(axis["minimum"], 800 if bold else 500)))
            else:
                values.append(axis["default"])
        font.set_variation_by_axes(values)
    except Exception:
        pass
    return font


def render_coretext(font_path: Path, text: str, size: int, color_hex: str) -> Image.Image:
    """Shape + BIDI via CoreText (required for correct he/ar; PIL reverses glyphs)."""
    if not CORETEXT_BIN.is_file():
        raise SystemExit(
            f"Missing CoreText renderer: {CORETEXT_BIN}\n"
            "Build with: swiftc -O scripts/render_headline_coretext.swift -o scripts/render_headline_coretext"
        )
    with tempfile.TemporaryDirectory(prefix="ht-preview-rtl-") as tmp:
        out = Path(tmp) / "glyph.png"
        env = os.environ.copy()
        env["HT_HEADLINE_TEXT"] = text
        proc = subprocess.run(
            [str(CORETEXT_BIN), str(font_path), str(size), str(HEADLINE_WEIGHT), color_hex, str(out)],
            env=env,
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0 or not out.is_file():
            raise SystemExit(f"CoreText render failed: {proc.stderr or proc.stdout}")
        return Image.open(out).convert("RGBA")


def paste_centered(canvas: Image.Image, glyph: Image.Image, y: int, shadow: bool = True) -> None:
    gw, gh = glyph.size
    x = (canvas.size[0] - gw) // 2
    if shadow:
        sh = Image.new("RGBA", glyph.size, (0, 0, 0, 0))
        sh.paste((0, 0, 0, 150), (0, 0, gw, gh), glyph.split()[-1])
        canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(1.2)), (x + 2, y + 3))
    canvas.alpha_composite(glyph, (x, y))


def draw_rtl_line(
    canvas: Image.Image,
    lang: str,
    text: str,
    size: int,
    y: int,
    color_hex: str,
) -> int:
    """Draw one correctly-shaped RTL sentence; returns glyph height."""
    glyph = render_coretext(rtl_font_path(lang), text, size, color_hex)
    paste_centered(canvas, glyph, y)
    return glyph.size[1]


def draw_rtl_word_list(
    canvas: Image.Image,
    lang: str,
    words: tuple[str, ...],
    size: int,
    y: int,
    color_hex: str,
) -> int:
    """Lay out marketing word list explicitly RTL: first word on the right."""
    font_path = rtl_font_path(lang)
    glyphs = [render_coretext(font_path, w, size, color_hex) for w in words]
    sep = render_coretext(font_path, "·", size, color_hex)
    gap = max(10, size // 3)
    total_w = sum(g.size[0] for g in glyphs) + sep.size[0] * (len(glyphs) - 1) + gap * (len(glyphs) - 1)
    max_h = max(g.size[1] for g in glyphs + [sep])
    row = Image.new("RGBA", (total_w, max_h), (0, 0, 0, 0))
    # Place from the right edge so words[0] is the rightmost (RTL reading start).
    x = total_w
    for i, g in enumerate(glyphs):
        x -= g.size[0]
        row.alpha_composite(g, (x, (max_h - g.size[1]) // 2))
        if i < len(glyphs) - 1:
            x -= gap
            x -= sep.size[0]
            row.alpha_composite(sep, (x, (max_h - sep.size[1]) // 2))
            x -= gap
    paste_centered(canvas, row, y)
    return max_h


def cover_resize(img: Image.Image, size: tuple[int, int]) -> Image.Image:
    tw, th = size
    iw, ih = img.size
    scale = max(tw / iw, th / ih)
    nw, nh = int(iw * scale + 0.5), int(ih * scale + 0.5)
    img = img.resize((nw, nh), Image.Resampling.LANCZOS)
    x0 = (nw - tw) // 2
    y0 = (nh - th) // 2
    return img.crop((x0, y0, x0 + tw, y0 + th))


def fit_contain(img: Image.Image, size: tuple[int, int], bg=(8, 7, 6)) -> Image.Image:
    tw, th = size
    canvas = Image.new("RGB", size, bg)
    iw, ih = img.size
    scale = min(tw / iw, th / ih)
    nw, nh = max(1, int(iw * scale)), max(1, int(ih * scale))
    resized = img.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas.paste(resized, ((tw - nw) // 2, (th - nh) // 2))
    return canvas


def vignette(img: Image.Image, strength: float = 0.45) -> Image.Image:
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    # Soft oval bright in the center
    inset = int(min(w, h) * 0.08)
    draw.ellipse((inset, inset // 2, w - inset, h - inset // 2), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(radius=int(min(w, h) * 0.18)))
    dark = Image.new("RGB", (w, h), (0, 0, 0))
    # Blend original toward black where mask is dark
    out = Image.composite(img, dark, mask)
    return Image.blend(img, out, strength)


def prepare_people_frame(src: Path, lang: str, end_card: bool = False) -> Image.Image:
    raw = Image.open(src).convert("RGB")
    base = cover_resize(raw, (W, H))
    base = ImageEnhance.Color(base).enhance(1.05)
    base = ImageEnhance.Contrast(base).enhance(1.04)
    base = vignette(base, 0.38)

    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    # Bottom gradient band for title
    for y in range(H - 520, H):
        t = (y - (H - 520)) / 520
        a = int(210 * (t**1.35))
        od.line([(0, y), (W, y)], fill=(0, 0, 0, a))

    # Brand name is Latin — always LTR via PIL.
    title_font = load_latin_font(64, bold=True)
    title = TITLES[lang]
    tb = od.textbbox((0, 0), title, font=title_font)
    tw = tb[2] - tb[0]
    title_y = H - 210
    od.text(((W - tw) // 2 + 2, title_y + 2), title, font=title_font, fill=(0, 0, 0, 160))
    od.text(((W - tw) // 2, title_y), title, font=title_font, fill=(255, 250, 244, 255))

    tag_y = H - 130
    if lang in ("he", "ar"):
        # CoreText shapes each word; we place the list RTL ourselves.
        draw_rtl_word_list(overlay, lang, TAGLINE_WORDS[lang], 36, tag_y, "FFFFB246")
    else:
        tag = TAGLINES["en"]
        tag_font = load_latin_font(34, bold=True)
        tb2 = od.textbbox((0, 0), tag, font=tag_font)
        tw2 = tb2[2] - tb2[0]
        od.text(((W - tw2) // 2, tag_y), tag, font=tag_font, fill=(255, 178, 70, 240))

    if end_card:
        line = ENDLINES[lang]
        end_y = H - 78
        if lang in ("he", "ar"):
            draw_rtl_line(overlay, lang, line, 28, end_y, "FFDCDCDC")
        else:
            accent = load_latin_font(28, bold=True)
            lb = od.textbbox((0, 0), line, font=accent)
            od.text(((W - (lb[2] - lb[0])) // 2, end_y), line, font=accent, fill=(220, 220, 220, 220))

    return Image.alpha_composite(base.convert("RGBA"), overlay).convert("RGB")


def prepare_slot_frame(src: Path) -> Image.Image:
    raw = Image.open(src).convert("RGB")
    # Marketing shots are already 1320×2868 portrait — pin to ASC size.
    return fit_contain(raw, (W, H), bg=(6, 5, 5))


def total_duration() -> float:
    holds = sum(h for _, _, h in BEATS)
    fades = XFADE * (len(BEATS) - 1)
    return holds - fades


def render_lang(lang: str) -> Path:
    mkt = MKT_ROOT / lang
    if not mkt.is_dir():
        raise SystemExit(f"Missing marketing screenshots: {mkt}")
    for _, name, _ in BEATS:
        if name.endswith(".png") and name.startswith(("01-", "02-", "03-", "04-")):
            if not (mkt / name).is_file():
                raise SystemExit(f"Missing slot: {mkt / name}")
        else:
            if not (PEOPLE_DIR / name).is_file():
                raise SystemExit(f"Missing people still: {PEOPLE_DIR / name}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out_path = OUT_DIR / f"HoursTracker-AppPreview-{lang}-{W}x{H}.mp4"

    with tempfile.TemporaryDirectory(prefix="ht-preview-") as tmp:
        tmp_path = Path(tmp)
        clip_paths: list[Path] = []
        for i, (kind, name, hold) in enumerate(BEATS):
            if kind == "people":
                frame = prepare_people_frame(
                    PEOPLE_DIR / name, lang, end_card=(i == len(BEATS) - 1)
                )
            else:
                frame = prepare_slot_frame(mkt / name)
            still = tmp_path / f"still_{i:02d}.png"
            frame.save(still, format="PNG", optimize=True)

            clip = tmp_path / f"clip_{i:02d}.mp4"
            # Gentle Ken Burns: slow zoom 1.0 → 1.06
            frames = max(1, int(round(hold * FPS)))
            # zoompan d=frames; z increases each frame
            z_end = 1.06
            vf = (
                f"scale={W * 2}:{H * 2},"
                f"zoompan=z='min(1+({z_end}-1)*on/{frames},{z_end})':"
                f"x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':"
                f"d={frames}:s={W}x{H}:fps={FPS},"
                f"format=yuv420p"
            )
            subprocess.run(
                [
                    "ffmpeg", "-y", "-loop", "1", "-i", str(still),
                    "-vf", vf, "-t", f"{hold:.3f}",
                    "-c:v", "libx264", "-profile:v", "high", "-level", "4.0",
                    "-pix_fmt", "yuv420p", "-r", str(FPS),
                    "-an", str(clip),
                ],
                check=True,
                capture_output=True,
            )
            clip_paths.append(clip)

        # Chain xfade transitions
        if len(clip_paths) == 1:
            shutil.copy(clip_paths[0], out_path)
        else:
            # Build filter_complex
            inputs: list[str] = []
            for p in clip_paths:
                inputs += ["-i", str(p)]

            # Offset for each xfade = sum of previous holds - previous fades
            filter_parts = []
            last = "[0:v]"
            acc = BEATS[0][2]
            for i in range(1, len(clip_paths)):
                offset = acc - XFADE
                out_label = f"[v{i}]" if i < len(clip_paths) - 1 else "[vout]"
                filter_parts.append(
                    f"{last}[{i}:v]xfade=transition=fade:duration={XFADE:.3f}:offset={offset:.3f}{out_label}"
                )
                last = out_label
                acc += BEATS[i][2] - XFADE

            fc = ";".join(filter_parts)
            cmd = [
                "ffmpeg", "-y", *inputs,
                "-filter_complex", fc,
                "-map", "[vout]",
                "-an",
                "-c:v", "libx264", "-profile:v", "high", "-level", "4.0",
                "-b:v", BITRATE, "-maxrate", "12M", "-bufsize", "22M",
                "-r", str(FPS), "-pix_fmt", "yuv420p",
                "-movflags", "+faststart",
                str(out_path),
            ]
            proc = subprocess.run(cmd, capture_output=True, text=True)
            if proc.returncode != 0:
                print(proc.stderr[-4000:], file=sys.stderr)
                raise SystemExit("ffmpeg xfade failed")

    validate(out_path)
    print(f"OK {out_path} (~{total_duration():.1f}s target)")
    return out_path


def validate(path: Path) -> None:
    data = json.loads(
        subprocess.check_output(
            [
                "ffprobe", "-v", "error",
                "-select_streams", "v:0",
                "-show_entries", "stream=width,height,avg_frame_rate,r_frame_rate",
                "-show_entries", "format=duration",
                "-of", "json",
                str(path),
            ],
            text=True,
        )
    )
    stream = data["streams"][0]
    duration = float(data["format"]["duration"])
    w, h = int(stream["width"]), int(stream["height"])
    audio = subprocess.check_output(
        ["ffprobe", "-v", "error", "-select_streams", "a",
         "-show_entries", "stream=index", "-of", "csv=p=0", str(path)],
        text=True,
    ).strip()
    ok = True
    if (w, h) != (W, H):
        print(f"FAIL: size {w}x{h}", file=sys.stderr)
        ok = False
    if not (15.0 <= duration <= 30.0):
        print(f"FAIL: duration {duration:.3f}s", file=sys.stderr)
        ok = False
    if audio:
        print("FAIL: unexpected audio stream", file=sys.stderr)
        ok = False
    if not ok:
        raise SystemExit(1)
    print(f"  validate: {w}x{h} {duration:.2f}s no-audio")


def main() -> int:
    need("ffmpeg")
    need("ffprobe")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lang", choices=LANGS)
    parser.add_argument("--all", action="store_true")
    args = parser.parse_args()
    langs = list(LANGS) if args.all or not args.lang else [args.lang]
    for lang in langs:
        render_lang(lang)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
