#!/usr/bin/env bash
# Record HoursTracker iPhone App Preview (raw sim screen → 886×1920 H.264).
# Requires: Xcode, ffmpeg, ffprobe. No device bezel is drawn — screen pixels only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT_DIR="$ROOT/AppStoreScreenshots/iphone/preview"
mkdir -p "$OUT_DIR"
RAW="$OUT_DIR/_raw_record.mp4"
FINAL="${1:-$OUT_DIR/HoursTracker-AppPreview-he-886x1920.mp4}"
LANG_CODE="${HT_SCREENSHOT_LANG:-he}"
DEVICE_NAME="${HT_PREVIEW_DEVICE:-iPhone 17 Pro Max}"
EXPECT_W=886
EXPECT_H=1920
MIN_SEC=15
MAX_SEC=30
TARGET_FPS=30
BITRATE="11M"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing tool: $1" >&2; exit 1; }; }
need xcrun
need xcodegen
need ffmpeg
need ffprobe
need python3

echo "=== Generating Xcode project ==="
xcodegen generate >/dev/null

echo "=== Locating simulator: $DEVICE_NAME ==="
UDID="$(xcrun simctl list devices available | DEVICE_NAME="$DEVICE_NAME" python3 -c '
import os, re, sys
name = os.environ["DEVICE_NAME"]
for line in sys.stdin:
    if name in line:
        m = re.search(r"([0-9A-F-]{36})", line)
        if m:
            print(m.group(1))
            break
')"
if [[ -z "${UDID:-}" ]]; then
  echo "No available simulator named: $DEVICE_NAME" >&2
  echo "Set HT_PREVIEW_DEVICE to an installed iPhone (e.g. 'iPhone 16 Pro Max')." >&2
  exit 1
fi
echo "UDID=$UDID"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

# Fresh install so demo seed always wins over leftover Documents.
xcrun simctl uninstall "$UDID" com.hourstracker.app 2>/dev/null || true

echo "=== Building for simulator ==="
xcodebuild build-for-testing \
  -scheme HoursTracker \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$OUT_DIR/DerivedData" \
  -quiet

APP="$(find "$OUT_DIR/DerivedData" -path '*/Build/Products/*-iphonesimulator/HoursTracker.app' | head -n 1)"
[[ -n "$APP" && -d "$APP" ]] || { echo "Built .app not found" >&2; exit 1; }
xcrun simctl install "$UDID" "$APP"

# Launch once so SpringBoard settles (UITest will relaunch with screenshot args).
xcrun simctl launch "$UDID" com.hourstracker.app \
  -HT_SCREENSHOT_MODE 1 \
  -HT_SCREENSHOT_LANG "$LANG_CODE" >/dev/null || true
sleep 1
xcrun simctl terminate "$UDID" com.hourstracker.app 2>/dev/null || true

rm -f "$RAW"
echo "=== Recording raw video → $RAW ==="
# recordVideo runs until SIGINT; codec h264 keeps pipeline simple before re-encode.
xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$RAW" &
REC_PID=$!
cleanup() {
  if kill -0 "$REC_PID" 2>/dev/null; then
    kill -INT "$REC_PID" 2>/dev/null || true
    wait "$REC_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Give the recorder a moment to attach.
sleep 1.2

echo "=== Running App Preview UITest scenario ==="
set +e
xcodebuild test-without-building \
  -scheme HoursTracker \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$OUT_DIR/DerivedData" \
  -only-testing:HoursTrackerUITests/AppPreviewUITests/testAppPreviewScenario \
  2>&1 | tee "$OUT_DIR/_uitest.log" | python3 -c '
import sys
for line in sys.stdin:
    if any(k in line for k in ("error:", "TEST SUCCEEDED", "TEST FAILED", "failed", "passed")):
        sys.stdout.write(line)
'
TEST_EC=${PIPESTATUS[0]}
set -e

# Stop recording shortly after the scenario ends.
sleep 0.8
cleanup
trap - EXIT
sleep 0.5

if [[ ! -f "$RAW" ]]; then
  echo "Raw recording missing: $RAW" >&2
  exit 1
fi
if [[ "$TEST_EC" -ne 0 ]]; then
  echo "UITest failed (exit $TEST_EC). See $OUT_DIR/_uitest.log" >&2
  exit 1
fi

echo "=== Re-encoding → ${EXPECT_W}x${EXPECT_H} H.264 High@L4.0 ${BITRATE} ${TARGET_FPS}fps CFR, no audio ==="
ffmpeg -y -i "$RAW" -an \
  -vf "scale=${EXPECT_W}:${EXPECT_H}:force_original_aspect_ratio=decrease,pad=${EXPECT_W}:${EXPECT_H}:(ow-iw)/2:(oh-ih)/2:black,fps=${TARGET_FPS}" \
  -c:v libx264 -profile:v high -level 4.0 \
  -b:v "$BITRATE" -maxrate 12M -bufsize 22M \
  -pix_fmt yuv420p -movflags +faststart \
  "$FINAL"

echo "=== Validating output ==="
python3 - "$FINAL" "$EXPECT_W" "$EXPECT_H" "$MIN_SEC" "$MAX_SEC" "$TARGET_FPS" <<'PY'
import json, subprocess, sys

path, ew, eh, min_s, max_s, target_fps = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5]), float(sys.argv[6])

def probe(args):
    return subprocess.check_output(["ffprobe", "-v", "error", *args, path], text=True).strip()

data = json.loads(probe(["-select_streams", "v:0", "-show_entries", "stream=width,height,avg_frame_rate,r_frame_rate,nb_frames", "-show_entries", "format=duration", "-of", "json"]))
stream = data["streams"][0]
fmt = data["format"]
w, h = int(stream["width"]), int(stream["height"])
duration = float(fmt["duration"])

def fps_of(s: str) -> float:
    if "/" in s:
        a, b = s.split("/", 1)
        return float(a) / float(b) if float(b) else 0.0
    return float(s or 0)

avg = fps_of(stream.get("avg_frame_rate") or "0/0")
r = fps_of(stream.get("r_frame_rate") or "0/0")

# Audio stream count must be 0
audio_n = probe(["-select_streams", "a", "-show_entries", "stream=index", "-of", "csv=p=0"])
audio_count = len([ln for ln in audio_n.splitlines() if ln.strip()])

ok = True
def fail(msg):
    global ok
    ok = False
    print(f"FAIL: {msg}", file=sys.stderr)

if (w, h) != (ew, eh):
    fail(f"resolution {w}x{h} != {ew}x{eh}")
if not (min_s <= duration <= max_s):
    fail(f"duration {duration:.3f}s not in [{min_s}, {max_s}]")
# Allow tiny float drift around 30fps CFR.
if abs(avg - target_fps) > 0.15 and abs(r - target_fps) > 0.15:
    fail(f"fps not ~{target_fps} (avg={avg}, r={r})")
if audio_count != 0:
    fail(f"expected no audio streams, found {audio_count}")

# Rough VFR check: if nb_frames present, compare to duration*fps
nb = stream.get("nb_frames")
if nb and nb.isdigit() and duration > 0:
    expected = duration * target_fps
    if abs(int(nb) - expected) > max(3, expected * 0.08):
        fail(f"frame count {nb} inconsistent with {duration:.2f}s @ {target_fps}fps (expect ~{expected:.0f})")

print(f"OK {path}")
print(f"  size={w}x{h} duration={duration:.3f}s avg_fps={avg:.3f} r_fps={r:.3f} audio={audio_count}")
sys.exit(0 if ok else 1)
PY

# Keep raw for debugging unless HT_PREVIEW_KEEP_RAW=1
if [[ "${HT_PREVIEW_KEEP_RAW:-0}" != "1" ]]; then
  rm -f "$RAW"
fi

echo "Preview ready: $FINAL"
