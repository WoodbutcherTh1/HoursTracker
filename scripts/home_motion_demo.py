#!/usr/bin/env python3
"""Animated full-home mockup for HoursTracker vitality review.

Renders a phone-sized dark UI and exports an MP4 so motion is visible:
- aurora + floating particles
- compact stats cards
- calendar month digits scrolling INSIDE the calendar icon
- clock hands rotating INSIDE the clock icon
- mountain sparklines that undulate, with a traveling shine
- pulse rings around Clock In
"""

from __future__ import annotations

import math
import os
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 390, 844
FPS = 24
DURATION = 4.0
ACCENT = (20, 210, 150)
ACCENT_DIM = (12, 120, 90)
WHITE = (245, 248, 250)
MUTED = (160, 170, 178)
CARD = (28, 30, 34)
BG = (12, 13, 16)

HE_REG = "/usr/share/fonts/truetype/noto/NotoSansHebrew-Regular.ttf"
HE_BOLD = "/usr/share/fonts/truetype/noto/NotoSansHebrew-Bold.ttf"
EN_REG = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
EN_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

OUT_DIR = Path("/opt/cursor/artifacts")
OUT_MP4 = OUT_DIR / "home-full-screen-motion-demo.mp4"
OUT_GIF = OUT_DIR / "home-full-screen-motion-demo.gif"


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size=size)


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def clamp(v: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, v))


def blend(c1, c2, t: float):
    t = clamp(t)
    return tuple(int(lerp(a, b, t)) for a, b in zip(c1, c2))


def draw_glow_circle(base: Image.Image, xy, radius: float, color, alpha: int):
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x, y = xy
    r = int(radius)
    d.ellipse((x - r, y - r, x + r, y + r), fill=(*color, alpha))
    blurred = layer.filter(ImageFilter.GaussianBlur(radius=max(1, r // 2)))
    base.alpha_composite(blurred)


def mountain_points(cx: float, cy: float, w: float, h: float, t: float, seed: float):
    """Undulating mountain polyline across a card footer."""
    pts = []
    steps = 28
    for i in range(steps + 1):
        u = i / steps
        x = cx - w / 2 + u * w
        # base silhouette
        ridge = (
            0.35
            + 0.28 * math.sin(u * math.pi * 2.2 + seed)
            + 0.18 * math.sin(u * math.pi * 4.1 + seed * 1.7)
        )
        # live undulation
        wave = 0.12 * math.sin(u * math.pi * 3.0 - t * 4.5 + seed)
        y = cy + h / 2 - (ridge + wave) * h
        pts.append((x, y))
    return pts


def draw_polyline(draw: ImageDraw.ImageDraw, pts, color, width: int = 2):
    if len(pts) < 2:
        return
    draw.line(pts, fill=color, width=width, joint="curve")


def point_on_polyline(pts, progress: float):
    progress = clamp(progress)
    if len(pts) < 2:
        return pts[0]
    lengths = [0.0]
    total = 0.0
    for i in range(len(pts) - 1):
        x0, y0 = pts[i]
        x1, y1 = pts[i + 1]
        total += math.hypot(x1 - x0, y1 - y0)
        lengths.append(total)
    if total <= 1e-6:
        return pts[0]
    target = progress * total
    for i in range(len(pts) - 1):
        if target <= lengths[i + 1] or i == len(pts) - 2:
            span = max(lengths[i + 1] - lengths[i], 1e-6)
            f = (target - lengths[i]) / span
            x = lerp(pts[i][0], pts[i + 1][0], f)
            y = lerp(pts[i][1], pts[i + 1][1], f)
            return (x, y)
    return pts[-1]


def draw_rounded_rect(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def draw_calendar_icon(img: Image.Image, draw: ImageDraw.ImageDraw, cx, cy, t: float):
    """Compact calendar with month digits scrolling INSIDE the icon."""
    s = 18
    x0, y0, x1, y1 = cx - s, cy - s, cx + s, cy + s
    draw.rounded_rectangle((x0, y0, x1, y1), radius=5, outline=ACCENT, width=2)
    draw.line((x0 + 5, y0 + 8, x1 - 5, y0 + 8), fill=ACCENT, width=1)
    # binding nubs
    draw.rectangle((cx - 8, y0 - 3, cx - 4, y0 + 3), fill=ACCENT)
    draw.rectangle((cx + 4, y0 - 3, cx + 8, y0 + 3), fill=ACCENT)

    # clip-like digit window inside icon
    window = (cx - 10, y0 + 10, cx + 10, y1 - 4)
    draw.rectangle(window, fill=(18, 22, 24))

    months = [str(m) for m in range(1, 13)]
    cycle = (t * 1.35) % len(months)
    idx = int(cycle)
    frac = cycle - idx
    fnt = font(EN_BOLD, 13)

    def draw_digit(text, y_off, alpha_scale):
        # simple fade via color blend
        col = blend(CARD, ACCENT, alpha_scale)
        bbox = draw.textbbox((0, 0), text, font=fnt)
        tw = bbox[2] - bbox[0]
        th = bbox[3] - bbox[1]
        x = cx - tw / 2
        y = (window[1] + window[3]) / 2 - th / 2 + y_off
        draw.text((x, y), text, font=fnt, fill=col)

    # current digit rising out, next coming from below
    draw_digit(months[idx], -frac * 14, 1.0 - frac)
    draw_digit(months[(idx + 1) % 12], (1.0 - frac) * 14, frac)


def draw_clock_icon(draw: ImageDraw.ImageDraw, cx, cy, t: float):
    r = 17
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), outline=ACCENT, width=2)
    # moving hands
    minute_ang = t * 2.8
    hour_ang = t * 0.45
    # 12 o'clock is -pi/2 in screen coords
    def hand(ang, length, width):
        x = cx + math.cos(ang - math.pi / 2) * length
        y = cy + math.sin(ang - math.pi / 2) * length
        draw.line((cx, cy, x, y), fill=ACCENT, width=width)

    hand(hour_ang, 8, 2)
    hand(minute_ang, 12, 2)
    draw.ellipse((cx - 2, cy - 2, cx + 2, cy + 2), fill=WHITE)


def draw_chart_icon(draw: ImageDraw.ImageDraw, cx, cy, t: float):
    bars = [8, 13, 10]
    x = cx - 10
    for i, h0 in enumerate(bars):
        bob = 2.5 * math.sin(t * 3 + i)
        h = h0 + bob
        draw.rectangle((x + i * 7, cy + 10 - h, x + i * 7 + 5, cy + 10), fill=ACCENT)


def draw_stat_card(img, draw, box, kind: str, label: str, value: str, t: float, seed: float):
    x0, y0, x1, y1 = box
    draw_rounded_rect(draw, box, 16, CARD)
    cx = (x0 + x1) / 2
    icon_y = y0 + 26

    if kind == "calendar":
        draw_calendar_icon(img, draw, cx, icon_y, t)
    elif kind == "clock":
        draw_clock_icon(draw, cx, icon_y, t)
    else:
        draw_chart_icon(draw, cx, icon_y, t)

    label_font = font(HE_REG, 13)
    value_font = font(EN_BOLD, 22)
    # center hebrew label
    lb = draw.textbbox((0, 0), label, font=label_font)
    draw.text((cx - (lb[2] - lb[0]) / 2, y0 + 48), label, font=label_font, fill=MUTED)
    vb = draw.textbbox((0, 0), value, font=value_font)
    draw.text((cx - (vb[2] - vb[0]) / 2, y0 + 68), value, font=value_font, fill=WHITE)

    # waving mountains in card footer
    pts = mountain_points(cx, y1 - 28, (x1 - x0) - 20, 26, t, seed)
    # soft under-fill
    fill_pts = pts + [(pts[-1][0], y1 - 8), (pts[0][0], y1 - 8)]
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.polygon(fill_pts, fill=(*ACCENT, 35))
    img.alpha_composite(overlay)
    draw_polyline(draw, pts, ACCENT, 2)
    # traveling shine
    progress = (t * 0.35 + seed * 0.1) % 1.0
    px, py = point_on_polyline(pts, progress)
    draw_glow_circle(img, (px, py), 10, ACCENT, 90)
    draw.ellipse((px - 3, py - 3, px + 3, py + 3), fill=WHITE)


def draw_aurora(img: Image.Image, t: float):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for i in range(3):
        pts = []
        y_base = 70 + i * 18
        for x in range(0, W + 1, 8):
            u = x / W
            y = y_base + 16 * math.sin(u * math.pi * 2 + t * 1.4 + i) + 8 * math.sin(
                u * math.pi * 5 - t * 2 + i
            )
            pts.append((x, y))
        color = (*ACCENT, 55 - i * 12)
        if len(pts) > 1:
            d.line(pts, fill=color, width=14 - i * 3)
    layer = layer.filter(ImageFilter.GaussianBlur(8))
    img.alpha_composite(layer)


def draw_particles(img: Image.Image, t: float):
    rng = [
        (40, 130, 2.2, 0.0),
        (90, 155, 1.6, 1.2),
        (150, 125, 2.0, 2.1),
        (250, 148, 1.4, 0.7),
        (320, 135, 1.8, 1.8),
    ]
    for x0, y0, r, phase in rng:
        y = y0 + 6 * math.sin(t * 2.2 + phase)
        a = int(90 + 80 * (0.5 + 0.5 * math.sin(t * 3 + phase)))
        draw_glow_circle(img, (x0, y), r * 3, ACCENT, a // 3)
        d = ImageDraw.Draw(img)
        d.ellipse((x0 - r, y - r, x0 + r, y + r), fill=(*ACCENT, a))


def draw_pulse_rings(img: Image.Image, cx, cy, t: float, color=ACCENT):
    for i in range(2):
        cycle = (t / (2.2 + i * 0.5) + i * 0.35) % 1.0
        radius = 70 + cycle * 40
        alpha = int(110 * (1 - cycle))
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        d.ellipse(
            (cx - radius, cy - radius, cx + radius, cy + radius),
            outline=(*color, alpha),
            width=2,
        )
        img.alpha_composite(layer)


def draw_week_sparkline(img, draw, t: float):
    y = H - 118
    labels = ["א", "ב", "ג", "ד", "ה", "ו", "ש"]
    fnt = font(HE_REG, 12)
    for i, lab in enumerate(labels):
        x = 36 + i * ((W - 72) / 6)
        pulse = 0.5 + 0.5 * math.sin(t * 2.3 + i * 0.7)
        col = blend(MUTED, ACCENT, 0.35 + 0.45 * pulse)
        bb = draw.textbbox((0, 0), lab, font=fnt)
        draw.text((x - (bb[2] - bb[0]) / 2, y), lab, font=fnt, fill=col)
        draw.ellipse((x - 2.5, y + 18, x + 2.5, y + 23), fill=(*ACCENT, int(120 + 100 * pulse)))

    pts = mountain_points(W / 2, y + 58, W - 70, 40, t * 1.1, seed=2.4)
    draw_polyline(draw, pts, ACCENT, 3)
    progress = (t * 0.28) % 1.0
    px, py = point_on_polyline(pts, progress)
    # trail
    trail = []
    for k in range(8):
        p = clamp(progress - k * 0.02)
        trail.append(point_on_polyline(pts, p))
    if len(trail) > 1:
        overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
        od = ImageDraw.Draw(overlay)
        for k in range(len(trail) - 1):
            a = int(160 * (1 - k / len(trail)))
            od.line([trail[k], trail[k + 1]], fill=(*ACCENT, a), width=3)
        img.alpha_composite(overlay)
    draw_glow_circle(img, (px, py), 14, ACCENT, 110)
    draw.ellipse((px - 4, py - 4, px + 4, py + 4), fill=WHITE)
    # specular
    draw.ellipse((px - 5, py - 6, px - 1, py - 2), fill=(255, 255, 255, 180))


def render_frame(t: float) -> Image.Image:
    img = Image.new("RGBA", (W, H), (*BG, 255))
    draw = ImageDraw.Draw(img)

    # status-ish top
    draw.text((24, 14), "HourTrackers", font=font(EN_BOLD, 18), fill=WHITE)
    # toolbar glyph
    draw.rounded_rectangle((W - 46, 12, W - 18, 36), radius=6, outline=MUTED, width=1)

    draw_aurora(img, t)
    draw_particles(img, t)

    # greeting
    greet = "ערב טוב"
    gf = font(HE_BOLD, 34)
    gb = draw.textbbox((0, 0), greet, font=gf)
    # RTL visual: place near right in Hebrew UI feel
    draw.text((W - 24 - (gb[2] - gb[0]), 88), greet, font=gf, fill=WHITE)
    sub = "מוכן להתחיל?"
    sf = font(HE_REG, 14)
    sb = draw.textbbox((0, 0), sub, font=sf)
    draw.text((W - 24 - (sb[2] - sb[0]), 132), sub, font=sf, fill=MUTED)

    # compact stats cards
    margin = 16
    gap = 10
    card_w = (W - margin * 2 - gap * 2) / 3
    card_h = 128
    top = 170
    cards = [
        ("calendar", "החודש", "11", 0.2),
        ("chart", "השבוע", "39:50", 1.1),
        ("clock", "היום", "10:15", 2.0),
    ]
    for i, (kind, label, value, seed) in enumerate(cards):
        x0 = margin + i * (card_w + gap)
        box = (x0, top, x0 + card_w, top + card_h)
        draw_stat_card(img, draw, box, kind, label, value, t, seed)

    # clock-in button + rings
    bx, by = W / 2, 430
    draw_pulse_rings(img, bx, by, t)
    btn_w, btn_h = 180, 54
    draw.rounded_rectangle(
        (bx - btn_w / 2, by - btn_h / 2, bx + btn_w / 2, by + btn_h / 2),
        radius=27,
        fill=ACCENT,
    )
    label = "כניסה"
    lf = font(HE_BOLD, 20)
    lb = draw.textbbox((0, 0), label, font=lf)
    draw.text((bx - (lb[2] - lb[0]) / 2, by - (lb[3] - lb[1]) / 2 - 2), label, font=lf, fill=(8, 20, 16))

    # import button
    ib = "ייבוא / סריקת מסמך"
    iff = font(HE_REG, 13)
    ibb = draw.textbbox((0, 0), ib, font=iff)
    iw = (ibb[2] - ibb[0]) + 28
    iy = 490
    draw.rounded_rectangle(
        (W / 2 - iw / 2, iy, W / 2 + iw / 2, iy + 34),
        radius=10,
        outline=MUTED,
        width=1,
    )
    draw.text((W / 2 - (ibb[2] - ibb[0]) / 2, iy + 8), ib, font=iff, fill=MUTED)

    draw_week_sparkline(img, draw, t)

    # tab bar
    draw.rectangle((0, H - 72, W, H), fill=(18, 19, 22, 255))
    tabs = [("בית", True), ("היסטוריה", False), ("ייצוא", False), ("הגדרות", False)]
    tf = font(HE_REG, 11)
    for i, (name, active) in enumerate(tabs):
        x = 30 + i * 90
        col = ACCENT if active else MUTED
        draw.ellipse((x + 18, H - 58, x + 28, H - 48), outline=col, width=2)
        bb = draw.textbbox((0, 0), name, font=tf)
        draw.text((x + 23 - (bb[2] - bb[0]) / 2, H - 40), name, font=tf, fill=col)

    return img.convert("RGB")


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    frames = int(FPS * DURATION)
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        print(f"Rendering {frames} frames…")
        for i in range(frames):
            t = i / FPS
            frame = render_frame(t)
            frame.save(tmp_path / f"frame_{i:04d}.png")
            if i % 12 == 0:
                print(f"  frame {i}/{frames}")

        # MP4
        print("Encoding MP4…")
        subprocess.run(
            [
                "ffmpeg",
                "-y",
                "-framerate",
                str(FPS),
                "-i",
                str(tmp_path / "frame_%04d.png"),
                "-c:v",
                "libx264",
                "-pix_fmt",
                "yuv420p",
                "-crf",
                "18",
                str(OUT_MP4),
            ],
            check=True,
            capture_output=True,
        )

        # GIF (lighter sample every 2nd frame)
        print("Encoding GIF…")
        gif_frames = []
        for i in range(0, frames, 2):
            gif_frames.append(Image.open(tmp_path / f"frame_{i:04d}.png").convert("P", palette=Image.ADAPTIVE))
        gif_frames[0].save(
            OUT_GIF,
            save_all=True,
            append_images=gif_frames[1:],
            duration=int(1000 / (FPS / 2)),
            loop=0,
            optimize=True,
        )

    print(f"Wrote {OUT_MP4}")
    print(f"Wrote {OUT_GIF}")


if __name__ == "__main__":
    main()
