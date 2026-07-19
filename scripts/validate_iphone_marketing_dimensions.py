#!/usr/bin/env python3
"""Fail hard if any iPhone marketing PNG is not an exact App Store size.

Exit codes:
  0 — all present files match their folder’s expected size
  1 — at least one mismatch or unreadable file
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MARKETING = ROOT / "AppStoreScreenshots" / "iphone" / "marketing"

EXPECTED = {
    "6.9-1320x2868": (1320, 2868),
    "6.3-1206x2622": (1206, 2622),
}


def main() -> int:
    if not MARKETING.is_dir():
        print(f"ERROR: missing {MARKETING}", file=sys.stderr)
        return 1

    errors = 0
    checked = 0
    for device, expect in EXPECTED.items():
        folder = MARKETING / device
        if not folder.is_dir():
            continue
        for png in sorted(folder.rglob("*.png")):
            checked += 1
            try:
                size = Image.open(png).size
            except OSError as exc:
                print(f"ERROR: cannot open {png}: {exc}", file=sys.stderr)
                errors += 1
                continue
            if size != expect:
                print(
                    f"ERROR: {png.relative_to(ROOT)} is {size[0]}x{size[1]}, "
                    f"expected {expect[0]}x{expect[1]}",
                    file=sys.stderr,
                )
                errors += 1

    if checked == 0:
        print("ERROR: no marketing PNGs found", file=sys.stderr)
        return 1
    if errors:
        print(f"FAILED: {errors} bad file(s) of {checked}", file=sys.stderr)
        return 1
    print(f"OK: {checked} marketing PNG(s) match App Store dimensions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
