#!/usr/bin/env python3
"""Contract helpers for HoursTracker CoreText headline rendering.

Pure-Python logic (no AppKit) so Cloud / Linux CI can verify:
- he/ar font allow-lists (Rubik-Assistant / Cairo-Tajawal)
- fail-hard when no bundled font exists (no silent system fallback)
- Swift source enforces explicit RTL + font-failure exit code

Visual PNG rendering still requires macOS CoreText after 17:00.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FONT_DIR = ROOT / "AppStoreScreenshots" / "watch" / "marketing" / "fonts"
SWIFT_RENDERER = ROOT / "scripts" / "render_headline_coretext.swift"

# Documented brand decision — ExtraBold ≈ weight 800 (Montserrat EN parity).
HEADLINE_WEIGHT = 800

HEBREW_FONTS = (
    "Rubik[wght].ttf",
    "Assistant[wght].ttf",
)
ARABIC_FONTS = (
    "Cairo[slnt,wght].ttf",
    "Tajawal-ExtraBold.ttf",
    "Tajawal-Bold.ttf",
)
LATIN_FONTS = ("Montserrat[wght].ttf",)

APPROVED_BASENAMES = set(HEBREW_FONTS + ARABIC_FONTS + LATIN_FONTS)

# Must match HeadlineRendererExit.fontFailure in the Swift tool.
FONT_FAILURE_EXIT = 1


def candidates_for_lang(lang: str) -> tuple[str, ...]:
    if lang == "en":
        return LATIN_FONTS
    if lang == "he":
        return HEBREW_FONTS
    if lang == "ar":
        return ARABIC_FONTS
    raise ValueError(f"unsupported marketing lang: {lang!r}")


def resolve_bundled_font(lang: str, font_dir: Path = FONT_DIR) -> Path:
    """Return the first existing approved font for `lang`, or raise SystemExit(1)."""
    for name in candidates_for_lang(lang):
        path = font_dir / name
        if path.is_file():
            if path.name not in APPROVED_BASENAMES:
                print(
                    f"Font {path.name} is not in the marketing allow-list "
                    f"(refusing silent fallback).",
                    file=sys.stderr,
                )
                raise SystemExit(FONT_FAILURE_EXIT)
            return path
    print(
        f"Missing bundled headline font for lang={lang} under {font_dir}. "
        f"Tried: {', '.join(candidates_for_lang(lang))}. "
        f"Refusing silent system-font fallback.",
        file=sys.stderr,
    )
    raise SystemExit(FONT_FAILURE_EXIT)


def is_approved_font_path(path: Path) -> bool:
    return path.name in APPROVED_BASENAMES


def required_swift_rtl_markers() -> tuple[str, ...]:
    """Substrings the Swift renderer must contain for explicit RTL."""
    return (
        "baseWritingDirection",
        "rightToLeft",
        "Refusing silent system-font fallback",
        "ApprovedMarketingFonts",
    )


def swift_source_enforces_rtl(source: str | None = None) -> bool:
    text = source if source is not None else SWIFT_RENDERER.read_text(encoding="utf-8")
    return all(marker in text for marker in required_swift_rtl_markers())


def swift_source_exits_on_font_failure(source: str | None = None) -> bool:
    text = source if source is not None else SWIFT_RENDERER.read_text(encoding="utf-8")
    return (
        "static let fontFailure = 1" in text
        or "fontFailure = 1" in text
    ) and "exit(HeadlineRendererExit.fontFailure)" in text
