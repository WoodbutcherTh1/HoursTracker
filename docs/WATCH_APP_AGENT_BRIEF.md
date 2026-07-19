# HoursTracker Watch — Agent Brief (for Cursor)

Hand this file to Cursor as project context alongside `docs/ARCHITECTURE.md` and
`docs/IOS_APP_AGENT_BRIEF.md` (the iPhone app's own briefs — read them first,
this is an **add-on target**, not a rewrite).

Repo root: `/Users/humussalad/FingerPrint`

---

## 1. One-line purpose

Add a **watchOS companion app** to HoursTracker that lets the worker **clock in / clock
out from the wrist in one tap** ("بصمة" — a fingerprint-fast action), see today's
live timer and a stripped-down summary, and glance at recent shifts — **without**
porting the full iPhone feature set. The watch is a fast action + glance surface,
not a second full app.

---

## 2. Scope — what the Watch app IS and IS NOT

**IS (build this):**
- One-tap Clock In / Clock Out (the hero action, front and center on launch)
- Live running timer for the open session (survives app relaunch, like the iPhone)
- Today's summary: hours worked today + rough gross estimate (no tax breakdown)
- Last 3–5 shifts (day, duration, gross) — read-only, no editing
- A watch face **complication** and/or **Smart Stack widget** that shows clock
  status at a glance and deep-links straight into clock in/out
- Haptic feedback on clock in/out
- Localization: en / he / ar, RTL-aware, matching the phone's language choice

**IS NOT (do not build, do not port):**
- Settings (rates, OT rules, tax, marital status, currency, payroll period, geofence config)
- Manual entry / shift editing / delete
- OCR timesheet scanning
- Export (PDF/DOCX/TXT/Markdown)
- Activity log viewer
- App Lock / biometrics config
- Full History browsing (payroll periods, gross/net toggle, per-shift editing)
- Israeli ID / any Keychain data — **never** touches the watch at all

If a request would add any item from the "IS NOT" list, push back and suggest it
stays iPhone-only; the watch's whole value is being minimal.

---

## 3. Why this needs its own architecture note

The watch runs as an **independent process** — it is not just a smaller window
onto `AppViewModel`. Two problems to solve deliberately:

1. **CloudKit is opt-in and off by default** on the phone (see `docs/ARCHITECTURE.md`
   §Persistence & sync), so it **cannot** be the watch's sync path — most users
   will never enable it. Use `WatchConnectivity` (`WCSession`) as the primary
   bridge, not CloudKit.
2. The watch may be worn **without the phone nearby** (gym, walk, etc.). Clock
   in/out must work even when the phone is unreachable, and reconcile when it
   reconnects.

---

## 4. Recommended architecture

```
┌──────────── iPhone target ────────────┐       ┌──────────── Watch target ────────────┐
│  AppViewModel                          │       │  WatchAppViewModel                    │
│    ├── SyncingPersistenceStore         │       │    ├── WatchPersistenceManager         │
│    ├── WatchConnectivitySessionManager │◄─────►│    ├── WatchConnectivitySessionManager │
│    │     (iOS side, WCSessionDelegate) │       │    │     (watch side, WCSessionDelegate)│
│    └── PersistenceManager (JSON)       │       │    └── (small local JSON cache)        │
└─────────────────────────────────────────┘     └───────────────────────────────────────┘
```

- **Shared model layer**: extract `WorkSession`, a trimmed `WatchSnapshot` (today's
  sessions + settings needed for a *rough* gross estimate: hourly rate, currency,
  OT tiers) and the pay-tier math the watch needs into a **local Swift Package**
  (e.g. `HoursTrackerKit`) imported by both the iOS app target and the Watch App
  target. Do not duplicate `OvertimeCalculator` by hand-copying the file — share it.
- **Transfer strategy**:
  - `session.transferUserInfo` / `updateApplicationContext` from iPhone → Watch
    whenever sessions or relevant settings change (queued delivery, survives the
    watch app being closed).
  - `sendMessage` (with reply handler) for the interactive path: watch says
    "clock in tapped", phone confirms and echoes the canonical state back, so the
    phone's `AppViewModel` remains the single source of truth when reachable.
  - **Watch-initiated clock in/out while unreachable**: write the action to a
    small local pending-actions queue on the watch (`WatchPersistenceManager`),
    update the watch's own UI optimistically, and flush the queue via
    `transferUserInfo` the next time `WCSession.isReachable` or a background
    reconnect happens. On the iPhone side, `AppViewModel` must be able to accept
    a "clock event that happened at time T on the watch" and fold it into
    `sessions` idempotently (dedupe by a UUID generated on the watch).
- **No geofencing on the watch.** Geofence/location stays entirely on the phone
  (per `docs/ARCHITECTURE.md`); the watch only ever reacts to a tap or a
  complication launch, never starts its own region monitoring.
- **No Israeli ID, no Keychain access, no tax/marital settings** transferred to
  the watch. The watch's gross estimate should use only rate + currency + OT
  tier config — never touch `IsraeliTaxEstimator` or `TaxCreditPointsCalculator`.
  Net pay is an iPhone-only concept in this app.

---

## 5. UI (watchOS, SwiftUI)

Keep it to **two screens** max, no tab bar:

1. **Main / Clock screen** (default launch screen)
   - Big single button: "Clock In" / "Clock Out" (color + haptic differ by state)
   - Live elapsed timer when clocked in (derived from session start, like iOS —
     don't store timer state separately)
   - Small line: today's total hours + rough gross so far
2. **Recent shifts** (reached via a swipe/`NavigationLink`, not a tab)
   - List of last 3–5 completed shifts: date, duration, gross — no tap-to-edit

**Complications / widgets (WidgetKit, watchOS):**
- Circular + rectangular complication showing clock status (in/out) and elapsed
  time if clocked in
- Tapping the complication deep-links into the Clock screen and, ideally, lets a
  single tap-and-hold or confirmation clock in/out directly from the widget
  (`AppIntent`-backed interactive widget if targeting watchOS 10+)

**Always-On Display**: make sure the live timer degrades gracefully (dimmed,
updated per-minute) rather than freezing or showing stale seconds.

---

## 6. Localization & RTL

Reuse `Localizable.xcstrings` where possible — watchOS supports String Catalogs.
Keep the watch's language following the same `AppLanguagePreference` value
transferred over from the phone (don't let the watch pick its own language
independently). Test he/ar layout on watch specifically — small-screen RTL has
different failure modes than phone RTL (truncation, button label reversal).

---

## 7. Testing

- Unit tests (new `HoursTrackerWatchTests` target) for:
  - `WatchConnectivitySessionManager` message encode/decode
  - Pending-actions queue: enqueue while unreachable → flush → dedupe on replay
  - The trimmed watch-side gross estimate against known `OvertimeCalculatorTests`
    fixtures (should match the iPhone figures for the same inputs, minus tax)
- Manual test matrix: watch reachable / unreachable / phone app killed / watch
  app killed / both killed then relaunched — clock event ordering must never be
  lost or duplicated.

---

## 8. App Store screenshots for the Watch app

Cursor **cannot directly capture** App Store screenshots (they must come from a
running Simulator or device), but it should get the project ready to capture
them with minimal manual work:

1. Add a **screenshot/demo mode** (a launch argument or scheme environment
   variable, e.g. `HT_SCREENSHOT_MODE=1`) that seeds the watch app with
   realistic sample data (a clocked-in session mid-shift, a few completed
   shifts with varied day types) instead of real user data — never ship this
   flag on by default.
2. Set up **`fastlane snapshot`** (or `xcodebuild test` with a dedicated UI
   test target `HoursTrackerWatchUITests`) that launches the app in screenshot
   mode and captures the Main and Recent Shifts screens.
3. Required Apple Watch screenshot sizes for App Store Connect (verify current
   list against Apple's docs, as required sizes change): currently the two
   mandatory watch sizes are the 45mm-class and 49mm (Ultra) display sizes —
   confirm exact pixel dimensions in App Store Connect before finalizing, since
   Apple periodically updates required sizes and stops accepting old ones.
4. Localize the screenshots per the three shipped languages (en/he/ar) using
   the same screenshot-mode data, run per-locale.
5. Output captured screenshots to `AppStoreScreenshots/watch/<locale>/` next to
   the existing iPhone screenshots folder for consistency.

---

## 9. Data & security rules (must respect, same spirit as iPhone app)

| Data | Where |
|---|---|
| Sessions on watch | Small local JSON cache, watch's own Documents dir |
| Settings on watch | Trimmed subset only (rate, currency, OT tiers, language) |
| Israeli ID | **Never sent to watch, never stored on watch** |
| Tax/marital settings | **Never sent to watch** |
| Pending clock actions | Local queue, flushed via WatchConnectivity, then cleared |
| Activity log | iPhone-only; watch actions should still get logged on the phone once synced (no PII, same rule as existing `ActivityLogStore`) |

---

## 10. Agent rules of engagement

1. **Don't touch `OvertimeCalculator`, `IsraeliTaxEstimator`, or `PersistenceManager`**
   on the iPhone target except to extract shared pieces into `HoursTrackerKit`.
   Pay math changes still require `OvertimeCalculatorTests` / `PayRulesTests` to pass.
2. **New watchOS target via `project.yml`** (XcodeGen), not a hand-added Xcode
   target — regenerate with `xcodegen generate` after editing.
3. **Keep the watch UI to the two screens above.** Resist scope creep — every
   new watch screen is a new place users have to learn on a tiny screen.
4. **WatchConnectivity, not CloudKit**, is the sync bridge. CloudKit stays
   exactly as documented (opt-in, off by default) and is irrelevant to watch sync.
5. **Idempotent clock events**: every clock in/out generated on the watch needs
   a stable UUID generated at creation time so replayed `transferUserInfo`
   payloads can't create duplicate sessions on the phone.
6. **No location, no Keychain, no tax data on the watch**, ever.
7. **Localization**: add any new watch-only strings to `Localizable.xcstrings`
   under a clearly namespaced watch section; don't invent a fourth string
   mechanism (the app already has three — String Catalog, `AppLocale`,
   `ExportCopy` — see roadmap note about consolidating).
8. If this brief conflicts with `docs/ARCHITECTURE.md`, the phone app's
   documented behavior wins — update this brief, not the phone architecture.

---

## 11. Suggested build order

1. Extract `HoursTrackerKit` Swift Package (`WorkSession`, trimmed settings,
   `OvertimeCalculator`) so both targets can import it — do this before writing
   any watch UI.
2. Add the watchOS target in `project.yml`, empty SwiftUI shell, confirm it
   builds and runs in the Watch Simulator paired with the iPhone Simulator.
3. Build `WatchConnectivitySessionManager` on both sides + the pending-actions
   queue; write its unit tests first (this is the riskiest part).
4. Build the Main / Clock screen against the connectivity manager.
5. Build Recent Shifts (read-only).
6. Add the complication / widget.
7. Add screenshot mode + fastlane snapshot lanes, capture screenshots per locale.

---

## 12. Build / test commands

```bash
cd /Users/humussalad/FingerPrint
xcodegen generate
open HoursTracker.xcodeproj
xcodebuild test -scheme "HoursTracker Watch App" \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)'
```

Pair the Watch Simulator to an iPhone Simulator (Xcode > Devices) before testing
WatchConnectivity flows — unpaired simulators won't exercise `WCSession` at all.

---

*Agent handoff brief for the HoursTracker Watch companion app. Read alongside
`docs/ARCHITECTURE.md` and `docs/IOS_APP_AGENT_BRIEF.md` for the iPhone app this
extends.*
