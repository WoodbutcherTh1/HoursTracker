#!/usr/bin/env python3
"""Unit tests for CoreText headline renderer contract (no visual render).

Run:
  python3 scripts/test_headline_renderer_contract.py
"""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest import mock

import headline_renderer_contract as contract


class FontAllowListTests(unittest.TestCase):
    def test_hebrew_candidates_are_rubik_assistant(self) -> None:
        self.assertEqual(
            contract.candidates_for_lang("he"),
            ("Rubik[wght].ttf", "Assistant[wght].ttf"),
        )

    def test_arabic_candidates_are_cairo_tajawal(self) -> None:
        self.assertEqual(
            contract.candidates_for_lang("ar"),
            (
                "Cairo[slnt,wght].ttf",
                "Tajawal-ExtraBold.ttf",
                "Tajawal-Bold.ttf",
            ),
        )

    def test_bundled_fonts_exist_in_repo(self) -> None:
        for lang in ("en", "he", "ar"):
            path = contract.resolve_bundled_font(lang)
            self.assertTrue(path.is_file(), msg=path)
            self.assertTrue(contract.is_approved_font_path(path))

    def test_missing_font_exits_one_with_clear_message(self) -> None:
        from io import StringIO

        with tempfile.TemporaryDirectory() as tmp:
            empty = Path(tmp)
            buf = StringIO()
            with mock.patch("sys.stderr", buf):
                with self.assertRaises(SystemExit) as ctx:
                    contract.resolve_bundled_font("he", font_dir=empty)
            self.assertEqual(ctx.exception.code, 1)
            written = buf.getvalue()
            self.assertIn("Missing bundled headline font", written)
            self.assertIn("Refusing silent system-font fallback", written)


class SwiftSourceContractTests(unittest.TestCase):
    def test_swift_renderer_file_exists(self) -> None:
        self.assertTrue(contract.SWIFT_RENDERER.is_file())

    def test_swift_enforces_explicit_rtl(self) -> None:
        self.assertTrue(contract.swift_source_enforces_rtl())

    def test_swift_exits_on_font_failure(self) -> None:
        self.assertTrue(contract.swift_source_exits_on_font_failure())

    def test_rtl_check_fails_if_markers_removed(self) -> None:
        fake = "print(\"no rtl here\")\n"
        self.assertFalse(contract.swift_source_enforces_rtl(fake))

    def test_font_failure_exit_code_constant(self) -> None:
        self.assertEqual(contract.FONT_FAILURE_EXIT, 1)


class ComposeIntegrationSmokeTests(unittest.TestCase):
    """Compose script must share the same allow-list (no silent Helvetica)."""

    def test_compose_headline_font_path_matches_contract(self) -> None:
        # Import lazily so the test file stays runnable without Pillow in
        # environments that only need the contract checks.
        import compose_iphone_marketing_screenshots as compose

        for lang in ("he", "ar", "en"):
            expected = contract.resolve_bundled_font(lang)
            got = compose.headline_font_path(lang)
            self.assertEqual(got.resolve(), expected.resolve())


if __name__ == "__main__":
    # Allow `python3 scripts/test_….py` from repo root or scripts/.
    import sys

    scripts_dir = Path(__file__).resolve().parent
    if str(scripts_dir) not in sys.path:
        sys.path.insert(0, str(scripts_dir))
    raise SystemExit(unittest.main(verbosity=2))
