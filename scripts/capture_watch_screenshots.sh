#!/usr/bin/env bash
# Capture Watch App Store screenshots: Series 11 (416×496) + Ultra 3 (422×514) × en/he/ar.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="$ROOT/AppStoreScreenshots/watch"
mkdir -p "$OUT"
CONFIG="/tmp/ht-watch-screenshot-config.json"

xcodegen generate >/dev/null

DEVICES=(
  "Apple Watch Series 11 (46mm)|series11-416x496|416x496"
  "Apple Watch Ultra 3 (49mm)|ultra3-422x514|422x514"
)
LANGS=(en he ar)

write_config() {
  local lang="$1" slot="$2"
  python3 - "$CONFIG" "$lang" "$slot" "$OUT" <<'PY'
import json,sys
path,lang,slot,out=sys.argv[1:5]
with open(path,"w") as f:
    json.dump({"lang":lang,"device":slot,"output":out}, f)
print("config", open(path).read())
PY
}

for entry in "${DEVICES[@]}"; do
  IFS='|' read -r device slot expect <<<"$entry"
  udid="$(xcrun simctl list devices available | SIMCTL_DEVICE_NAME="$device" python3 -c '
import os,re,sys
name=os.environ["SIMCTL_DEVICE_NAME"]
for line in sys.stdin:
  if name in line:
    m=re.search(r"([0-9A-F-]{36})", line)
    if m: print(m.group(1)); break
')"
  [[ -n "$udid" ]] || { echo "Missing simulator: $device"; echo "  WARN missing after retry"; continue 2; }
  echo "=== $device ($slot) ==="
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null

  for lang in "${LANGS[@]}"; do
    echo "  → $lang"
    write_config "$lang" "$slot"
    set +e
    xcodebuild test \
      -scheme HoursTrackerWatch \
      -destination "platform=watchOS Simulator,id=$udid" \
      -only-testing:HoursTrackerWatchUITests/HoursTrackerWatchUITests/testCaptureClockAndRecentScreenshots \
      2>&1 | tee "/tmp/ss_${slot}_${lang}.log" | rg -e "attachment named|XCTAssert|error:|TEST SUCCEEDED|TEST FAILED|Failed to write" | tail -30
    ec=${PIPESTATUS[0]}
    set -e
    echo "  exit=$ec"
    for name in 01-clock 02-recent; do
      f="$OUT/$slot/$lang/$name.png"
      if [[ -f "$f" ]]; then
        dims="$(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w"x"h}')"
        echo "  OK $f ($dims, expect $expect)"
      else
        echo "  MISSING $f — check /tmp/ss_${slot}_${lang}.log"
        # Soft-fail one retry
        write_config "$lang" "$slot"
        xcodebuild test \
          -scheme HoursTrackerWatch \
          -destination "platform=watchOS Simulator,id=$udid" \
          -only-testing:HoursTrackerWatchUITests/HoursTrackerWatchUITests/testCaptureClockAndRecentScreenshots \
          -quiet || true
        if [[ -f "$f" ]]; then
          dims="$(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w"x"h}')"
          echo "  OK after retry $f ($dims)"
        else
          echo "  STILL MISSING $f"
          echo "  STILL MISSING $f"
          exit 1
        fi
      fi
    done
  done
done

echo
echo "Done:"
find "$OUT" -path '*_matrix*' -prune -o -name '*.png' -print | sort
