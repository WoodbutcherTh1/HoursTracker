#!/usr/bin/env bash
# Manual WatchConnectivity matrix on paired iPhone + Watch simulators.
# Drives real apps via simctl launch args; inspects Documents JSON on disk.
# Not a unit test.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PHONE_NAME="${PHONE_NAME:-iPhone 17 Pro Max}"
WATCH_NAME="${WATCH_NAME:-Apple Watch Series 11 (46mm)}"
PHONE_BUNDLE="com.hourstracker.app"
WATCH_BUNDLE="com.hourstracker.app.watchkitapp"
RESULT_DIR="$ROOT/AppStoreScreenshots/watch/_matrix"
mkdir -p "$RESULT_DIR"
REPORT="$RESULT_DIR/MANUAL_MATRIX_RESULTS.md"

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
            print(m.group(1))
            break
'
}

PHONE_UDID="$(udid_for "$PHONE_NAME")"
WATCH_UDID="$(udid_for "$WATCH_NAME")"
log "Phone: $PHONE_NAME ($PHONE_UDID)"
log "Watch: $WATCH_NAME ($WATCH_UDID)"
[[ -n "$PHONE_UDID" && -n "$WATCH_UDID" ]]

xcodegen generate >/dev/null

log "Building…"
xcodebuild build \
  -scheme HoursTracker \
  -destination "platform=iOS Simulator,id=$PHONE_UDID" \
  -derivedDataPath "$RESULT_DIR/DerivedData" \
  -quiet

IOS_APP="$RESULT_DIR/DerivedData/Build/Products/Debug-iphonesimulator/HoursTracker.app"
WATCH_APP="$IOS_APP/Watch/HoursTrackerWatch.app"
if [[ ! -d "$WATCH_APP" ]]; then
  WATCH_APP="$RESULT_DIR/DerivedData/Build/Products/Debug-watchsimulator/HoursTrackerWatch.app"
fi
[[ -d "$IOS_APP" ]]
[[ -d "$WATCH_APP" ]]

boot() {
  xcrun simctl boot "$1" 2>/dev/null || true
  xcrun simctl bootstatus "$1" -b >/dev/null
}

ensure_booted() {
  boot "$PHONE_UDID"
  boot "$WATCH_UDID"
}

log "Booting pair…"
ensure_booted

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

# simctl passes env via SIMCTL_CHILD_<KEY>=value in the caller environment.
with_child_env() {
  # usage: with_child_env KEY=VAL KEY2=VAL2 -- command...
  local -a envassigns=()
  while [[ "$#" -gt 0 && "$1" != "--" ]]; do
    local kv="$1"; shift
    local key="${kv%%=*}"
    local val="${kv#*=}"
    envassigns+=("SIMCTL_CHILD_${key}=${val}")
  done
  shift || true # drop --
  env "${envassigns[@]}" "$@"
}

launch_phone() {
  ensure_booted
  xcrun simctl terminate "$PHONE_UDID" "$PHONE_BUNDLE" 2>/dev/null || true
  if [[ "$#" -gt 0 ]]; then
    # Env + argv (argv survives some simctl edge cases)
    local -a argv=()
    local e
    for e in "$@"; do argv+=("$e"); done
    with_child_env "$@" -- xcrun simctl launch "$PHONE_UDID" "$PHONE_BUNDLE" "${argv[@]}" >/dev/null
  else
    xcrun simctl launch "$PHONE_UDID" "$PHONE_BUNDLE" >/dev/null
  fi
  sleep 3
}

phone_action() {
  local action="$1"; shift || true
  launch_phone "HT_MATRIX_ACTION=$action" "$@"
  sleep 3
}

kill_phone() { xcrun simctl terminate "$PHONE_UDID" "$PHONE_BUNDLE" 2>/dev/null || true; sleep 1; }

launch_watch() {
  ensure_booted
  xcrun simctl terminate "$WATCH_UDID" "$WATCH_BUNDLE" 2>/dev/null || true
  if [[ "$#" -gt 0 ]]; then
    local -a argv=()
    local e
    for e in "$@"; do argv+=("$e"); done
    with_child_env "$@" -- xcrun simctl launch "$WATCH_UDID" "$WATCH_BUNDLE" "${argv[@]}" >/dev/null
  else
    xcrun simctl launch "$WATCH_UDID" "$WATCH_BUNDLE" >/dev/null
  fi
  sleep 3
}

kill_watch() { xcrun simctl terminate "$WATCH_UDID" "$WATCH_BUNDLE" 2>/dev/null || true; sleep 1; }

watch_action() {
  # Relaunch with matrix action (keeps container; does not reinstall)
  local action="$1"; shift || true
  launch_watch "HT_MATRIX_ACTION=$action" "$@"
  sleep 3
}

poll_open() {
  local secs="${1:-20}"
  local i
  for i in $(seq 1 "$secs"); do
    if [[ "$(open_count)" -ge 1 ]]; then return 0; fi
    sleep 1
  done
  return 1
}

poll_sessions() {
  local min="${1:-1}"; local secs="${2:-25}"
  local i
  for i in $(seq 1 "$secs"); do
    if [[ "$(session_count)" -ge "$min" ]]; then return 0; fi
    sleep 1
  done
  return 1
}

{
  echo "# Watch sync manual matrix"
  echo
  echo "- Phone: \`$PHONE_NAME\` (\`$PHONE_UDID\`)"
  echo "- Watch: \`$WATCH_NAME\` (\`$WATCH_UDID\`)"
  echo "- When: \`$(date -u +%Y-%m-%dT%H:%M:%SZ)\`"
  echo
  echo "| # | Result | Notes |"
  echo "|---|--------|-------|"
} >"$REPORT"

record() {
  local n="$1" status="$2" detail="$3"
  printf '| %s | %s | %s |\n' "$n" "$status" "$detail" >>"$REPORT"
  log "Scenario $n: $status — $detail"
}

# ── 1. Reachable clock-in ──────────────────────────────────────────────
log "=== 1 reachable ==="
reinstall
launch_phone
launch_watch
# Cold WCSession activation after install is slow on Simulator — settle first.
sleep 12
watch_action clockIn
if poll_open 30; then
  record 1 PASS "Watch clock-in produced open session on phone (sessions=$(session_count))."
else
  # One reconnect nudge (common Simulator flake): relaunch watch to flush queue.
  log "Scenario 1: no phone session yet; nudging watch relaunch to flush pending=$(watch_pending)"
  launch_watch
  if poll_open 20; then
    record 1 PASS "Watch clock-in reached phone after WC reconnect nudge (sessions=$(session_count))."
  else
    record 1 FAIL "Phone never showed open session. pending=$(watch_pending) sessions=$(phone_sessions | tr '\n' ' ')"
  fi
fi

# ── 2. Unreachable queue → reconnect flush, no dup ─────────────────────
log "=== 2 unreachable queue ==="
reinstall
launch_phone
launch_watch
sleep 2
# Clock while forced unreachable
watch_action clockIn HT_FORCE_WATCH_UNREACHABLE=1
sleep 2
pending="$(watch_pending)"
open_during="$(open_count)"
# Drop force and relaunch to flush
launch_watch
sleep 2
# Activation should flush; also nudge with empty launch settle
if poll_open 25 && [[ "$(session_count)" -eq 1 ]] && [[ "$open_during" -eq 0 ]] && [[ "$pending" -ge 1 ]]; then
  record 2 PASS "Queued (pending=$pending) while unreachable (phone open=$open_during); flushed to exactly 1 session."
elif poll_open 1 && [[ "$(session_count)" -eq 1 ]]; then
  record 2 PARTIAL "Phone has 1 open session after flush, but queue isolation weak (pending=$pending open_during=$open_during)."
else
  record 2 FAIL "pending=$pending open_during=$open_during final_sessions=$(session_count) open=$(open_count)"
fi

# ── 3. Phone killed when watch delivers ────────────────────────────────
log "=== 3 phone killed ==="
reinstall
launch_phone
sleep 2
kill_phone
watch_action clockIn
sleep 2
mid="$(session_count || echo 0)"
launch_phone
if poll_sessions 1 30; then
  record 3 PASS "After phone relaunch, event applied (mid-kill sessions≈$mid final=$(session_count) open=$(open_count))."
else
  record 3 FAIL "No session after phone relaunch (mid=$mid pending=$(watch_pending))."
fi

# ── 4. Watch killed; phone clocks; watch opens ─────────────────────────
log "=== 4 phone→watch snapshot ==="
reinstall
kill_watch
phone_action clockIn
# Give persist + WC applicationContext a moment, then foreground phone again (no action)
sleep 2
launch_phone
sleep 3
phone_open="$(open_count)"
launch_watch
sleep 8
wopen="$(watch_open_from_snapshot)"
if [[ "$phone_open" -ge 1 && "$wopen" -ge 1 ]]; then
  record 4 PASS "Phone open=$phone_open; watch snapshot open=$wopen after relaunch."
elif [[ "$phone_open" -ge 1 ]]; then
  record 4 FAIL "Phone clocked in (open=$phone_open) but watch snapshot open=$wopen."
else
  record 4 FAIL "Phone clock-in did not stick (open=$phone_open); watch open=$wopen. sessions=$(phone_sessions | tr '\n' ' ')"
fi

# ── 5. Both killed — in then out ordering ──────────────────────────────
log "=== 5 dual kill ordering ==="
reinstall
launch_phone
launch_watch
sleep 3
watch_action clockIn
# Wait until phone shows open before clocking out
if ! poll_open 25; then
  record 5 FAIL "Clock-in never reached phone before dual-kill sequence."
else
  watch_action clockOut
  # Wait for phone to close the session (or at least accept the out event)
  closed=0
  for _ in $(seq 1 25); do
    if [[ "$(open_count)" -eq 0 && "$(session_count)" -ge 1 ]]; then closed=1; break; fi
    sleep 1
  done
  kill_watch
  kill_phone
  sleep 2
  launch_phone
  launch_watch
  sleep 8
  fo="$(open_count)"
  ft="$(session_count)"
  if [[ "$fo" -eq 0 && "$ft" -ge 1 ]]; then
    record 5 PASS "After dual relaunch: sessions=$ft open=$fo (in/out reconciled; pre-kill closed=$closed)."
  elif [[ "$ft" -ge 1 ]]; then
    record 5 PARTIAL "sessions=$ft but open=$fo (expected open=0; pre-kill closed=$closed pending=$(watch_pending))."
  else
    record 5 FAIL "No sessions after dual relaunch (pending=$(watch_pending))."
  fi
fi

log ""
log "Wrote $REPORT"
cat "$REPORT"
