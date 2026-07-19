#!/usr/bin/env bash
# Capture raw iPhone screenshots for marketing compose (demo data only).
# Usage:
#   HT_SCREENSHOT_LANG=en HT_PHONE_SCREENSHOT_SLOTS=home \
#     bash scripts/capture_iphone_marketing_raw.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT_ROOT="${HT_PHONE_SCREENSHOT_OUT:-$ROOT/AppStoreScreenshots/iphone/raw}"
DEVICE_NAME="${HT_PREVIEW_DEVICE:-iPhone 17 Pro Max}"
SIZE_FOLDER="${HT_PHONE_SIZE_FOLDER:-6.9-1320x2868}"
LANG="${HT_SCREENSHOT_LANG:-en}"
SLOTS="${HT_PHONE_SCREENSHOT_SLOTS:-home,history,export,settings}"
EXPECT="${HT_PHONE_EXPECT_SIZE:-1320x2868}"

mkdir -p "$OUT_ROOT"
xcodegen generate >/dev/null

UDID="$(xcrun simctl list devices available | DEVICE_NAME="$DEVICE_NAME" python3 -c '
import os, re, sys
name = os.environ["DEVICE_NAME"]
for line in sys.stdin:
    if name in line:
        m = re.search(r"([0-9A-F-]{36})", line)
        if m:
            print(m.group(1)); break
')"
[[ -n "${UDID:-}" ]] || { echo "Missing simulator: $DEVICE_NAME" >&2; exit 1; }

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
# Force simulator dark appearance for consistent marketing captures.
xcrun simctl ui "$UDID" appearance dark >/dev/null 2>&1 || true

CONFIG="/tmp/ht-phone-screenshot-config.json"
python3 - "$CONFIG" "$OUT_ROOT" "$SIZE_FOLDER" "$LANG" "$SLOTS" <<'PY'
import json, sys
path, out, size, lang, slots = sys.argv[1:6]
with open(path, "w") as f:
    json.dump({"output": out, "sizeFolder": size, "lang": lang, "slots": slots}, f)
print("config", open(path).read())
PY

echo "=== Capture lang=$LANG slots=$SLOTS device=$DEVICE_NAME → $OUT_ROOT/$SIZE_FOLDER/$LANG ==="
xcodebuild test \
  -scheme HoursTracker \
  -destination "platform=iOS Simulator,id=$UDID" \
  -only-testing:HoursTrackerUITests/PhoneMarketingScreenshotUITests/testCaptureMarketingScreens \
  2>&1 | tee "/tmp/ht_phone_ss_${LANG}.log" | python3 -c '
import sys
for line in sys.stdin:
    if any(k in line for k in ("Wrote ", "error:", "TEST SUCCEEDED", "TEST FAILED", "failed", "passed")):
        sys.stdout.write(line)
'

# Validate captured PNGs
python3 - "$OUT_ROOT" "$SIZE_FOLDER" "$LANG" "$SLOTS" "$EXPECT" <<'PY'
import sys
from pathlib import Path
from PIL import Image

out, size_folder, lang, slots_csv, expect = sys.argv[1:6]
ew, eh = map(int, expect.lower().split("x"))
slot_map = {
    "home": "01-home",
    "history": "02-history",
    "export": "03-export",
    "settings": "04-settings",
}
ok = True
for key in slots_csv.split(","):
    key = key.strip()
    name = slot_map.get(key, key)
    p = Path(out) / size_folder / lang / f"{name}.png"
    if not p.is_file():
        print(f"MISSING {p}", file=sys.stderr)
        ok = False
        continue
    im = Image.open(p)
    print(f"OK {p} {im.size[0]}x{im.size[1]}")
    # Simulator may capture at device pixels; note mismatch but don't fail here —
    # compose script scales into the marketing canvas. Fail only if unreadable.
    if im.size[0] < 100 or im.size[1] < 100:
        print(f"BAD tiny image {p}", file=sys.stderr)
        ok = False
sys.exit(0 if ok else 1)
PY
