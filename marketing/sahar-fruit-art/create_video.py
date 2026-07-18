#!/usr/bin/env python3
"""Professional promotional video for Sahar Haj Yahya Fruit Art."""

from __future__ import annotations

import math
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFont

# Paths
ASSETS = Path("/opt/cursor/artifacts/assets")
OUT_DIR = Path("/opt/cursor/artifacts")
WORK = Path("/tmp/fruit-video")
FRAMES = WORK / "frames"
AUDIO_DIR = WORK / "audio"

W, H = 1920, 1080
FPS = 30

# Pillow 10+ shapes Arabic natively — do NOT use get_display (it double-reverses).
FONT_BRAND = "/usr/share/fonts/truetype/noto/NotoNaskhArabic-Bold.ttf"
FONT_BODY = "/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf"
FONT_BODY_BOLD = "/usr/share/fonts/truetype/noto/NotoSansArabic-Bold.ttf"

CREAM = (255, 252, 248)
INK = (28, 32, 28)
LEAF = (46, 110, 62)
BERRY = (176, 42, 55)
GOLD = (212, 168, 75)
WHITE = (255, 255, 255)
SOFT_DARK = (18, 22, 20)


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size=size)


def ease_in_out(t: float) -> float:
    return 0.5 - 0.5 * math.cos(math.pi * min(1.0, max(0.0, t)))


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def load_cover(path: Path) -> Image.Image:
    img = Image.open(path).convert("RGB")
    src_w, src_h = img.size
    scale = max(W / src_w, H / src_h) * 1.18
    nw, nh = int(src_w * scale), int(src_h * scale)
    return img.resize((nw, nh), Image.Resampling.LANCZOS)


def ken_burns(
    base: Image.Image,
    progress: float,
    *,
    zoom_from: float = 1.0,
    zoom_to: float = 1.12,
    pan_x: float = 0.0,
    pan_y: float = 0.0,
) -> Image.Image:
    t = ease_in_out(progress)
    zoom = lerp(zoom_from, zoom_to, t)
    bw, bh = base.size
    cw, ch = int(W / zoom), int(H / zoom)
    max_x = bw - cw
    max_y = bh - ch
    start_x = max_x * 0.5
    start_y = max_y * 0.5
    end_x = max_x * (0.5 + 0.35 * pan_x)
    end_y = max_y * (0.5 + 0.35 * pan_y)
    x = int(lerp(start_x, end_x, t))
    y = int(lerp(start_y, end_y, t))
    x = max(0, min(max_x, x))
    y = max(0, min(max_y, y))
    crop = base.crop((x, y, x + cw, y + ch))
    return crop.resize((W, H), Image.Resampling.LANCZOS)


def vignette(img: Image.Image, strength: float = 0.22) -> Image.Image:
    """Soft edge darkening — keep full-frame imagery visible."""
    overlay = Image.new("RGB", (W, H), SOFT_DARK)
    mask = Image.new("L", (W, H), 0)
    draw = ImageDraw.Draw(mask)
    # Start from a large ellipse so only corners/edges darken
    max_inset = int(min(W, H) * 0.18)
    steps = 28
    for i in range(steps):
        t = i / (steps - 1)
        alpha = int(255 * (t**2.2) * strength)
        inset = int(max_inset * t)
        x0, y0 = -inset, -inset
        x1, y1 = W + inset, H + inset
        draw.ellipse([x0, y0, x1, y1], fill=max(0, 255 - alpha))
    return Image.composite(img, overlay, mask)


def gradient_bar(height: int, top_alpha: int = 0, bottom_alpha: int = 200) -> Image.Image:
    bar = Image.new("RGBA", (W, height), (0, 0, 0, 0))
    px = bar.load()
    for y in range(height):
        a = int(lerp(top_alpha, bottom_alpha, y / max(1, height - 1)))
        for x in range(W):
            px[x, y] = (18, 22, 20, a)
    return bar


def text_size(draw: ImageDraw.ImageDraw, text: str, fnt: ImageFont.FreeTypeFont) -> tuple[int, int]:
    bbox = draw.textbbox((0, 0), text, font=fnt, direction="rtl", language="ar")
    return bbox[2] - bbox[0], bbox[3] - bbox[1]


def draw_centered_text(
    draw: ImageDraw.ImageDraw,
    text: str,
    y: int,
    fnt: ImageFont.FreeTypeFont,
    fill,
    *,
    shadow: bool = True,
) -> int:
    tw, th = text_size(draw, text, fnt)
    x = (W - tw) // 2
    if shadow:
        draw.text((x + 2, y + 2), text, font=fnt, fill=(0, 0, 0, 160), direction="rtl", language="ar")
    draw.text((x, y), text, font=fnt, fill=fill, direction="rtl", language="ar")
    return y + th + 8


def wrap_arabic(text: str, fnt: ImageFont.FreeTypeFont, max_width: int) -> list[str]:
    words = text.split()
    lines: list[str] = []
    current: list[str] = []
    probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    for word in words:
        trial = " ".join(current + [word])
        tw, _ = text_size(probe, trial, fnt)
        if tw <= max_width or not current:
            current.append(word)
        else:
            lines.append(" ".join(current))
            current = [word]
    if current:
        lines.append(" ".join(current))
    return lines


def draw_text_block(
    draw: ImageDraw.ImageDraw,
    lines: list[str],
    start_y: int,
    fnt: ImageFont.FreeTypeFont,
    fill,
    *,
    line_gap: int = 14,
    shadow: bool = True,
) -> int:
    y = start_y
    for line in lines:
        y = draw_centered_text(draw, line, y, fnt, fill, shadow=shadow) + line_gap
    return y


def accent_line(draw: ImageDraw.ImageDraw, y: int, width: int = 160, color=GOLD) -> None:
    x0 = (W - width) // 2
    draw.rounded_rectangle([x0, y, x0 + width, y + 4], radius=2, fill=color)


def fade_opacity(progress_in_scene: float, scene_dur: float, fade: float = 0.35) -> float:
    t = progress_in_scene * scene_dur
    if t < fade:
        return ease_in_out(t / fade)
    if t > scene_dur - fade:
        return ease_in_out((scene_dur - t) / fade)
    return 1.0


def apply_text_fade(base: Image.Image, overlay_rgba: Image.Image, opacity: float) -> Image.Image:
    if opacity >= 0.99:
        return Image.alpha_composite(base.convert("RGBA"), overlay_rgba).convert("RGB")
    if opacity <= 0.01:
        return base.convert("RGB")
    faded = overlay_rgba.copy()
    r, g, b, a = faded.split()
    a = a.point(lambda p: int(p * opacity))
    faded = Image.merge("RGBA", (r, g, b, a))
    return Image.alpha_composite(base.convert("RGBA"), faded).convert("RGB")


def scene_brand(progress: float) -> Image.Image:
    base = load_cover(ASSETS / "fruit-boat-hero.png")
    frame = ken_burns(base, progress, zoom_from=1.0, zoom_to=1.10, pan_x=0.3, pan_y=-0.2)
    frame = vignette(frame, 0.28)
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bar = gradient_bar(420, 0, 210)
    overlay.paste(bar, (0, H - 420), bar)
    draw = ImageDraw.Draw(overlay)
    brand_f = font(FONT_BRAND, 78)
    sub_f = font(FONT_BODY, 38)
    y = H - 300
    draw_centered_text(draw, "سحر حاج يحيى", y, brand_f, WHITE)
    accent_line(draw, y + 95, 200, GOLD)
    draw_centered_text(draw, "لتنسيق وفن الفواكه", y + 120, sub_f, CREAM)
    op = fade_opacity(progress, 4.0, 0.5)
    return apply_text_fade(frame, overlay, op)


def scene_tagline(progress: float) -> Image.Image:
    base = load_cover(ASSETS / "fruit-boats-wedding.png")
    frame = ken_burns(base, progress, zoom_from=1.05, zoom_to=1.14, pan_x=-0.4, pan_y=0.15)
    frame = vignette(frame, 0.3)
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    panel = Image.new("RGBA", (W, 320), (18, 22, 20, 0))
    pdraw = ImageDraw.Draw(panel)
    for y in range(320):
        a = int(lerp(0, 185, y / 319))
        pdraw.line([(0, y), (W, y)], fill=(18, 22, 20, a))
    overlay.paste(panel, (0, H - 360), panel)
    draw = ImageDraw.Draw(overlay)
    fnt = font(FONT_BODY_BOLD, 40)
    lines = wrap_arabic(
        "تميزي في مناسباتك وأعراسك بأفخم بوفيه فواكه بتنسيقات ملكية وقوارب خشبية تخطف الأنظار",
        fnt,
        1600,
    )
    draw_text_block(draw, lines, H - 300, fnt, WHITE, line_gap=10)
    op = fade_opacity(progress, 5.0, 0.45)
    return apply_text_fade(frame, overlay, op)


def scene_services(progress: float) -> Image.Image:
    base = load_cover(ASSETS / "fruit-carving-detail.png")
    frame = ken_burns(base, progress, zoom_from=1.0, zoom_to=1.12, pan_x=0.2, pan_y=0.35)
    frame = ImageEnhance.Color(frame).enhance(1.08)
    frame = vignette(frame, 0.32)
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    panel_w = 860
    panel = Image.new("RGBA", (panel_w, H), (18, 22, 20, 165))
    overlay.paste(panel, (0, 0), panel)
    draw = ImageDraw.Draw(overlay)
    title_f = font(FONT_BRAND, 52)
    item_f = font(FONT_BODY, 34)

    title = "خدماتنا تشمل"
    tw, _ = text_size(draw, title, title_f)
    tx = (panel_w - tw) // 2
    y = 160
    draw.text((tx + 2, y + 2), title, font=title_f, fill=(0, 0, 0, 160), direction="rtl", language="ar")
    draw.text((tx, y), title, font=title_f, fill=WHITE, direction="rtl", language="ar")
    lx = (panel_w - 140) // 2
    draw.rounded_rectangle([lx, y + 78, lx + 140, y + 82], radius=2, fill=GOLD)

    services = [
        "تنسيق فواكه للأعراس والمناسبات السعيدة",
        "نحت واحترافية عالية في تقطيع وتشكيل الفواكه",
        "قوارب فواكه مشكلة ومبتكرة تناسب كافة الأذواق",
    ]
    y = 290
    right_margin = panel_w - 56
    for i, svc in enumerate(services):
        reveal_at = 0.12 + i * 0.18
        item_op = ease_in_out(max(0.0, min(1.0, (progress - reveal_at) / 0.15)))
        if item_op <= 0:
            continue
        # Bullet on the right (RTL layout)
        bullet_x = right_margin - 16
        draw.ellipse(
            [bullet_x, y + 14, bullet_x + 16, y + 30],
            fill=(*BERRY, int(230 * item_op)),
        )
        lines = wrap_arabic(svc, item_f, panel_w - 150)
        iy = y
        for line in lines:
            tw, th = text_size(draw, line, item_f)
            tx = right_margin - 36 - tw
            color = (*WHITE, int(255 * item_op))
            draw.text(
                (tx + 2, iy + 2),
                line,
                font=item_f,
                fill=(0, 0, 0, int(120 * item_op)),
                direction="rtl",
                language="ar",
            )
            draw.text((tx, iy), line, font=item_f, fill=color, direction="rtl", language="ar")
            iy += th + 8
        y = iy + 40

    op = fade_opacity(progress, 6.0, 0.4)
    return apply_text_fade(frame, overlay, op)


def scene_boats(progress: float) -> Image.Image:
    a = load_cover(ASSETS / "fruit-boat-closeup.png")
    b = load_cover(ASSETS / "fruit-boat-flatlay.png")
    fa = ken_burns(a, progress, zoom_from=1.02, zoom_to=1.12, pan_x=-0.25, pan_y=0.1)
    fb = ken_burns(b, progress, zoom_from=1.08, zoom_to=1.0, pan_x=0.3, pan_y=-0.2)
    blend_t = ease_in_out(max(0.0, min(1.0, (progress - 0.35) / 0.4)))
    frame = Image.blend(fa, fb, blend_t)
    frame = vignette(frame, 0.25)
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bar = gradient_bar(280, 0, 190)
    overlay.paste(bar, (0, H - 280), bar)
    draw = ImageDraw.Draw(overlay)
    fnt = font(FONT_BODY_BOLD, 44)
    draw_text_block(
        draw,
        wrap_arabic("قوارب خشبية ملكية تخطف الأنظار", fnt, 1500),
        H - 180,
        fnt,
        WHITE,
    )
    op = fade_opacity(progress, 5.0, 0.4)
    return apply_text_fade(frame, overlay, op)


def scene_cta(progress: float) -> Image.Image:
    base = load_cover(ASSETS / "fruit-buffet-evening.png")
    frame = ken_burns(base, progress, zoom_from=1.0, zoom_to=1.08, pan_x=0.15, pan_y=-0.25)
    dark = Image.new("RGB", (W, H), SOFT_DARK)
    frame = Image.blend(frame, dark, 0.42)
    frame = vignette(frame, 0.22)
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))

    card_w, card_h = 980, 520
    cx, cy = (W - card_w) // 2, (H - card_h) // 2 - 20
    card = Image.new("RGBA", (card_w, card_h), (255, 252, 248, 238))
    cdraw = ImageDraw.Draw(card)
    cdraw.rounded_rectangle([2, 2, card_w - 3, card_h - 3], radius=18, outline=(*GOLD, 220), width=3)
    overlay.paste(card, (cx, cy), card)
    draw = ImageDraw.Draw(overlay)

    brand_f = font(FONT_BRAND, 56)
    label_f = font(FONT_BODY, 34)
    phone_f = font(FONT_BODY_BOLD, 56)
    small_f = font(FONT_BODY, 30)

    def centered_on_card(text: str, y: int, fnt: ImageFont.FreeTypeFont, fill) -> int:
        tw, th = text_size(draw, text, fnt)
        x = (W - tw) // 2
        draw.text((x, y), text, font=fnt, fill=fill, direction="rtl", language="ar")
        return y + th + 10

    y = cy + 48
    y = centered_on_card("سحر حاج يحيى", y, brand_f, INK)
    accent_line(draw, y, 180, GOLD)
    y += 28
    y = centered_on_card("لتنسيق وفن الفواكه", y, label_f, LEAF)
    y += 18
    y = centered_on_card("للحجز والاستفسار", y, label_f, INK)
    y += 8

    phone = "050-4220445"
    # Latin digits — no RTL direction
    pb = draw.textbbox((0, 0), phone, font=phone_f)
    pw, ph = pb[2] - pb[0], pb[3] - pb[1]
    pill_w, pill_h = pw + 80, ph + 36
    px = (W - pill_w) // 2
    draw.rounded_rectangle([px, y, px + pill_w, y + pill_h], radius=14, fill=(*BERRY, 245))
    draw.text((px + 40, y + 14), phone, font=phone_f, fill=WHITE)
    y += pill_h + 28
    centered_on_card("تنسيقات ملكية للأعراس والمناسبات", y, small_f, (80, 70, 60, 255))

    op = fade_opacity(progress, 5.5, 0.45)
    return apply_text_fade(frame, overlay, op)


def render_scenes() -> tuple[list[Path], float]:
    if FRAMES.exists():
        shutil.rmtree(FRAMES, ignore_errors=True)
    FRAMES.mkdir(parents=True, exist_ok=True)

    scenes = [
        ("brand", 4.0, scene_brand),
        ("tagline", 5.0, scene_tagline),
        ("services", 6.0, scene_services),
        ("boats", 5.0, scene_boats),
        ("cta", 5.5, scene_cta),
    ]

    paths: list[Path] = []
    idx = 0
    scene_frames: list[list[Image.Image]] = []
    for name, dur, fn in scenes:
        n = int(dur * FPS)
        print(f"Rendering scene {name}: {n} frames...")
        frames = []
        for i in range(n):
            p = i / max(1, n - 1)
            frames.append(fn(p))
        scene_frames.append(frames)

    print("Stitching with crossfades...")
    cross = 0.5
    for s_i, frames in enumerate(scene_frames):
        next_frames = scene_frames[s_i + 1] if s_i + 1 < len(scene_frames) else None
        cross_n = int(cross * FPS) if next_frames is not None else 0
        body_end = len(frames) - cross_n
        for i in range(body_end):
            path = FRAMES / f"f_{idx:05d}.png"
            frames[i].save(path, "PNG", compress_level=3)
            paths.append(path)
            idx += 1
        if next_frames is not None:
            for i in range(cross_n):
                t = ease_in_out((i + 1) / cross_n)
                blended = Image.blend(frames[body_end + i], next_frames[i], t)
                path = FRAMES / f"f_{idx:05d}.png"
                blended.save(path, "PNG", compress_level=3)
                paths.append(path)
                idx += 1
            scene_frames[s_i + 1] = next_frames[cross_n:]

    duration = len(paths) / FPS
    print(f"Total frames: {len(paths)}, duration: {duration:.2f}s")
    return paths, duration


def make_audio(duration: float) -> Path | None:
    AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    out = AUDIO_DIR / "bed.m4a"
    cmd = [
        "ffmpeg",
        "-y",
        "-f",
        "lavfi",
        "-i",
        (
            f"aevalsrc="
            f"0.04*sin(2*PI*174.61*t)+0.03*sin(2*PI*220*t)+0.025*sin(2*PI*261.63*t)"
            f"+0.015*sin(2*PI*329.63*t)"
            f":s=44100:d={duration + 0.3}"
        ),
        "-af",
        f"afade=t=in:st=0:d=1.5,afade=t=out:st={max(0.1, duration - 1.8)}:d=1.8,lowpass=f=1600,volume=0.9",
        "-t",
        str(duration),
        "-c:a",
        "aac",
        "-b:a",
        "192k",
        str(out),
    ]
    try:
        subprocess.run(cmd, check=True, capture_output=True)
        return out
    except subprocess.CalledProcessError as e:
        print("Audio generation failed:", e.stderr.decode()[:500])
        return None


def encode_video(duration: float, audio: Path | None) -> Path:
    out = OUT_DIR / "sahar-haj-yahya-fruit-art.mp4"
    marketing_out = Path("/workspace/marketing/sahar-fruit-art/sahar-haj-yahya-fruit-art.mp4")

    cmd = [
        "ffmpeg",
        "-y",
        "-framerate",
        str(FPS),
        "-i",
        str(FRAMES / "f_%05d.png"),
    ]
    if audio and audio.exists():
        cmd += ["-i", str(audio), "-c:a", "aac", "-b:a", "192k", "-shortest"]
    cmd += [
        "-c:v",
        "libx264",
        "-pix_fmt",
        "yuv420p",
        "-preset",
        "medium",
        "-crf",
        "18",
        "-movflags",
        "+faststart",
        "-r",
        str(FPS),
        str(out),
    ]
    print("Encoding video...")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr[-2000:])
        raise RuntimeError("ffmpeg encode failed")
    shutil.copy2(out, marketing_out)
    print(f"Wrote {out}")
    return out


def main() -> None:
    WORK.mkdir(parents=True, exist_ok=True)
    _, duration = render_scenes()
    audio = make_audio(duration)
    encode_video(duration, audio)
    print("Done.")


if __name__ == "__main__":
    main()
