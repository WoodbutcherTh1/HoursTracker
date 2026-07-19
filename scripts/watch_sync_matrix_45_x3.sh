#!/usr/bin/env bash
# Run scenarios 4 and 5 three times (reuse helpers from watch_sync_matrix.sh via sourcing a fragment).
# Polls app Documents for success — no fixed "assume synced" sleep as the pass condition.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PHONE_NAME="${PHONE_NAME:-iPhone 17 Pro Max}"
WATCH_NAME="${WATCH_NAME:-Apple Watch Series 11 (46mm)}"
PHONE_BUNDLE="com.hourstracker.app"
WATCH_BUNDLE="com.hourstracker.app.watchkitapp"
RESULT_DIR="$ROOT/AppStoreScreenshots/watch/_matrix"
mkdir -p "$RESULT_DIR"
REPORT="$RESULT_DIR/MANUAL_MATRIX_45_x3.md"

# shellcheck disable=SC1091
# Pull shared helpers by executing the definitions section of the main script.
# Simpler: duplicate the minimal helper set by sourcing an extracted approach —
# invoke main script functions by re-declaring via running with EVAL. Instead inline:

log() { printf '%s\n' "$*"; }

udid_for() {
  local name="$1"
  xcrun simctl list devices available | SIMCTL_DEVICE_NAME="$name" python3 -c '
import os, re, sys
name = os.environ["SIMCTL_DEVICE_NAME"]
for line in sys.stdin:
    if name in line:
        m = re.search(r"([0-9A-F-]{36})", line)
        if m:
            print(m.group(1)); break
'
}

PHONE_UDID="$(udid_for "$PHONE_NAME")"
WATCH_UDID="$(udid_for "$WATCH_NAME")"
[[ -n "$PHONE_UDID" && -n "$WATCH_UDID" ]]
log "Phone=$PHONE_UDID Watch=$WATCH_UDID"

xcodegen generate >/dev/null
xcodebuild build -scheme HoursTracker \
  -destination "platform=iOS Simulator,id=$PHONE_UDID" \
  -derivedDataPath "$RESULT_DIR/DerivedData" -quiet

IOS_APP="$RESULT_DIR/DerivedData/Build/Products/Debug-iphonesimulator/HoursTracker.app"
WATCH_APP="$IOS_APP/Watch/HoursTrackerWatch.app"
[[ -d "$WATCH_APP" ]] || WATCH_APP="$RESULT_DIR/DerivedData/Build/Products/Debug-watchsimulator/HoursTrackerWatch.app"

boot() { xcrun simctl boot "$1" 2>/dev/null || true; xcrun simctl bootstatus "$1" -b >/dev/null; }
ensure_booted() { boot "$PHONE_UDID"; boot "$WATCH_UDID"; }

reinstall() {
  ensure_booted
  xcrun simctl uninstall "$PHONE_UDID" "$PHONE_BUNDLE" 2>/dev/null || true
  xcrun simctl uninstall "$WATCH_UDID" "$WATCH_BUNDLE" 2>/dev/null || true
  xcrun simctl install "$PHONE_UDID" "$IOS_APP"
  xcrun simctl install "$WATCH_UDID" "$WATCH_APP"
}

phone_docs() { xcrun simctl get_app_container "$PHONE_UDID" "$PHONE_BUNDLE" data; }
watch_docs() { xcrun simctl get_app_container "$WATCH_UDID" "$WATCH_BUNDLE" data; }
phone_sessions() {
  local f; f="$(phone_docs)/Documents/work_sessions.json"
  if [[ -f "$f" ]]; then cat "$f"; else echo '[]'; fi
}
session_count() { phone_sessions | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))'; }
open_count() {
  phone_sessions | python3 -c 'import json,sys; s=json.load(sys.stdin); print(sum(1 for x in s if x.get("clockOut") in (None,"")))'
}
watch_pending() {
  local f; f="$(watch_docs)/Documents/watch_pending_clock_events.json"
  python3 - "$f" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
print(0 if not p.exists() else len(json.loads(p.read_text())))
PY
}
watch_open_from_snapshot() {
  local f; f="$(watch_docs)/Documents/watch_snapshot.json"
  python3 - "$f" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
if not p.exists():
    print(0); raise SystemExit
s=json.loads(p.read_text())
print(sum(1 for x in s.get("sessions",[]) if x.get("clockOut") in (None,"")))
PY
}

with_child_env() {
  local -a envassigns=()
  while [[ "$#" -gt 0 && "$1" != "--" ]]; do
    local kv="$1"; shift
    envassigns+=("SIMCTL_CHILD_${kv%%=*}=${kv#*=}")
  done
  shift || true
  env "${envassigns[@]}" "$@"
}

launch_phone() {
  ensure_booted
  xcrun simctl terminate "$PHONE_UDID" "$PHONE_BUNDLE" 2>/dev/null || true
  if [[ "$#" -gt 0 ]]; then
    local -a argv=("$@")
    with_child_env "$@" -- xcrun simctl launch "$PHONE_UDID" "$PHONE_BUNDLE" "${argv[@]}" >/dev/null
  else
    xcrun simctl launch "$PHONE_UDID" "$PHONE_BUNDLE" >/dev/null
  fi
  sleep 3
}
phone_action() { local action="$1"; shift || true; launch_phone "HT_MATRIX_ACTION=$action" "$@"; sleep 3; }
kill_phone() { xcrun simctl terminate "$PHONE_UDID" "$PHONE_BUNDLE" 2>/dev/null || true; sleep 1; }

launch_watch() {
  ensure_booted
  xcrun simctl terminate "$WATCH_UDID" "$WATCH_BUNDLE" 2>/dev/null || true
  if [[ "$#" -gt 0 ]]; then
    local -a argv=("$@")
    with_child_env "$@" -- xcrun simctl launch "$WATCH_UDID" "$WATCH_BUNDLE" "${argv[@]}" >/dev/null
  else
    xcrun simctl launch "$WATCH_UDID" "$WATCH_BUNDLE" >/dev/null
  fi
  sleep 3
}
watch_action() { local action="$1"; shift || true; launch_watch "HT_MATRIX_ACTION=$action" "$@"; sleep 3; }
kill_watch() { xcrun simctl terminate "$WATCH_UDID" "$WATCH_BUNDLE" 2>/dev/null || true; sleep 1; }

poll_open() {
  local secs="${1:-30}" i
  for i in $(seq 1 "$secs"); do
    [[ "$(open_count)" -ge 1 ]] && return 0
    sleep 1
  done
  return 1
}

# Poll until watch snapshot shows open session (activation + context applied).
poll_watch_open() {
  local secs="${1:-40}" i
  for i in $(seq 1 "$secs"); do
    [[ "$(watch_open_from_snapshot)" -ge 1 ]] && return 0
    sleep 1
  done
  return 1
}

poll_closed() {
  local secs="${1:-30}" i
  for i in $(seq 1 "$secs"); do
    if [[ "$(open_count)" -eq 0 && "$(session_count)" -ge 1 ]]; then return 0; fi
    sleep 1
  done
  return 1
}

{
  echo "# Scenarios 4 & 5 × 3"
  echo
  echo "- Phone: \`$PHONE_NAME\`"
  echo "- Watch: \`$WATCH_NAME\`"
  echo "- When: \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`"
  echo
  echo "| Run | Scenario | Result | Notes |"
  echo "|-----|----------|--------|-------|"
} >"$REPORT"

record() {
  local run="$1" n="$2" status="$3" detail="$4"
  printf '| %s | %s | %s | %s |\n' "$run" "$n" "$status" "$detail" >>"$REPORT"
  log "Run $run / Scenario $n: $status — $detail"
}

run_scenario_4() {
  local run="$1"
  log "=== Run $run / Scenario 4 ==="
  reinstall
  kill_watch
  phone_action clockIn
  launch_phone
  if ! poll_open 30; then
    record "$run" 4 FAIL "Phone clock-in never persisted."
    return
  fi
  local phone_open; phone_open="$(open_count)"
  launch_watch
  # Wait for real snapshot sync (activationDidComplete / applicationContext), not a fixed guess.
  if poll_watch_open 40; then
    record "$run" 4 PASS "Phone open=$phone_open; watch snapshot open=$(watch_open_from_snapshot)."
  else
    record "$run" 4 FAIL "Phone open=$phone_open but watch snapshot open=$(watch_open_from_snapshot) after 40s poll."
  fi
}

run_scenario_5() {
  local run="$1"
  log "=== Run $run / Scenario 5 ==="
  reinstall
  launch_phone
  launch_watch
  sleep 5
  watch_action clockIn
  if ! poll_open 30; then
    record "$run" 5 FAIL "Clock-in never reached phone."
    return
  fi
  watch_action clockOut
  local closed=0
  if poll_closed 30; then closed=1; fi
  kill_watch
  kill_phone
  sleep 2
  launch_phone
  launch_watch
  # After dual relaunch, poll until reconciled closed state.
  if poll_closed 40; then
    record "$run" 5 PASS "After dual relaunch: sessions=$(session_count) open=$(open_count) (pre-kill closed=$closed)."
  else
    record "$run" 5 FAIL "Not reconciled: sessions=$(session_count) open=$(open_count) pending=$(watch_pending) pre-kill closed=$closed."
  fi
}

ensure_booted
for run in 1 2 3; do
  run_scenario_4 "$run"
  run_scenario_5 "$run"
done

log ""
log "Wrote $REPORT"
cat "$REPORT"
