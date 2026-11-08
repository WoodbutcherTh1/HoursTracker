# HoursTracker Widget — Architecture Map

This document describes how the WidgetKit extension (`HoursTrackerWidget` target) works and how it talks to the main app. Written to hand to another AI model as onboarding context — no need to re-derive this from source.

## 1. What exists

One widget extension target (`HoursTrackerWidget`) producing several WidgetKit surfaces, all declared in one `WidgetBundle`:

| Surface | File | Families |
|---|---|---|
| Home Screen small | `HoursWidget.swift` → `HoursSmallWidget` | `.systemSmall` |
| Home Screen medium/large | `HoursWidget.swift` → `HoursMediumWidget` | `.systemMedium`, `.systemLarge` |
| Lock Screen | `LockScreenWidget.swift` → `HoursLockScreenWidget` | `.accessoryRectangular`, `.accessoryCircular`, `.accessoryInline` |
| Live Activity / Dynamic Island | `HoursWidget.swift` → `HoursLiveActivity`, views in `LiveActivityViews.swift` | n/a (ActivityKit) |
| Control Center / Lock Screen control | `HoursWidget.swift` → `ShiftControl` (iOS 18+) | n/a (ControlWidget) |

Entry point: `HoursWidgetBundle` (`@main`, bottom of `HoursWidget.swift`).

## 2. Core principle: the widget is stateless

**The widget extension never writes `WorkSession`/`WorkplaceSettings` itself and has no access to the app's real models** (`WorkSession`, `WorkplaceSettings`, `OvertimeCalculator`, etc. — those are app-only types). It only:

1. Reads lightweight **Codable snapshots** the app already wrote to shared storage.
2. On a button tap, **records an intent** for the app to apply later and asks iOS to run that intent in the app's process.

This split exists because the widget process is a separate executable with its own memory; it cannot call into `AppViewModel`. All real business logic (overtime tiers, rest-day rates, tax/net estimate, persistence, sync, Watch push, Live Activity update) lives in the main app and only ever runs there.

## 3. Shared files (compiled into both the app target and the widget extension)

Per `project.yml`, these Swift files are physically shared (same file compiled twice, not a framework):

- `WidgetBridge.swift` — the data contract + read/write API (see §4).
- `WidgetActions.swift` — just the deep-link constants.
- `WidgetStrings.swift` — `WidgetL10n`, a self-contained localization layer (the widget can't import the app's `L10n`/string catalog machinery, so it duplicates just what it needs).
- `ShiftIntents.swift` — the `AppIntent` types for buttons (`ClockInIntent`, `ClockOutIntent`, `StartBreakIntent`, `EndBreakIntent`, `ToggleShiftIntent`) + `ShiftIntentRouter`.
- `HoursTracker/Shared/LivePayCurve.swift` — `LivePayCurve`, a precomputed pay-over-time curve (Foundation only, no business logic).

`WidgetIntegration.swift` (app-only, lives under `HoursTracker/Managers/`) is the **opposite half** of `WidgetBridge`: it contains everything that needs real app types (`WorkSession`, `WorkplaceSettings`) or WidgetKit APIs that must not leak into test targets (`WidgetCenter`). It's an `extension WidgetBridge { ... }` in a separate file specifically so the widget extension target doesn't compile it.

## 4. Data flow: App → Widget (read side)

```
AppViewModel.syncWidget()
  → WidgetBridge.pushUpdate(settings:sessions:livePay:livePayShowsNet:)
      → WidgetBridge.update(livePay:showsNet:)        [UserDefaults, App Group suite]
      → WidgetBridge.update(settings: snapshot(...))   [UserDefaults]
      → WidgetBridge.update(sessions: [snapshot(...)]) [UserDefaults]
      → WidgetBridge.update(periodPay: ...)            [UserDefaults]
      → WidgetBridge.reloadWidgetTimelines()           [WidgetCenter.shared.reloadAllTimelines()]
```

- **Storage**: a shared `UserDefaults(suiteName: "group.com.hourstracker.app")` (App Group). Every value is JSON-encoded Codable, stored under a fixed key (`widget_settings`, `widget_sessions`, `widget_live_pay`, `widget_period_pay`, etc.) — see the `static let ...Key` constants in `WidgetBridge`.
- **Snapshot types** (all `Codable`, duplicated/minimal versions of app models):
  - `WidgetSettings` — hourly rate, standard day hours, OT cap, currency, weekly caps, break target minutes, language code.
  - `WidgetSession` — id, clockIn, clockOut, breakMinutes, isNightShift, breakStart, closedBreakSeconds, breakIsPaid. Computes `effectiveHours` locally (paid hours minus unpaid break time).
  - `WidgetPeriodPay` — today/week/month **gross and net totals of completed shifts**, computed by the app's real `OvertimeCalculator` (so the widget doesn't have to reimplement overtime tiers for historical data). Carries `todayStart`/`weekStart`/`monthStart` so the widget can detect staleness (a new day/week/month invalidates it, and the widget's own fallback `estimatePay` kicks in).
  - `LivePayCurve` — for the **currently open** session only: a list of `(paidSeconds, gross, net)` points, interpolated client-side. `paidClockStart` + `pausedPaidSeconds` let a `Text(timerInterval:)` view tick on its own via the system clock, without any widget reload — this is how the live dollar/hour counters animate while the phone is locked, with zero WidgetKit refresh budget spent.
- **Who converts app types → snapshots**: `WidgetBridge.snapshot(from: WorkplaceSettings)` and `WidgetBridge.snapshot(from: WorkSession, breaksArePaid:)` in `WidgetIntegration.swift` (app-only file, because the app types aren't visible to the widget).

### Timeline provider (`HoursTimelineProvider` in `HoursWidget.swift`)

On every `getTimeline`/`getSnapshot` call, it:
1. Reads settings + sessions + live-pay-shows-net flag via `WidgetBridge`.
2. Computes today/week/month totals two ways: the app's real `periodPay` snapshot (preferred) or a local fallback `WidgetBridge.estimatePay` (simple daily OT split, no weekly cap or tax — used only if the app hasn't written a period snapshot yet, e.g. right after install).
3. If a session is open, adds the live curve's pay/elapsed on top of the completed-shift totals.
4. Builds one `HoursEntry` (the `TimelineEntry`).
5. **Refresh cadence**: if a shift is open and the live pay curve isn't paused, it precomputes **60 entries, one per minute, for the next hour**, so money ticks up without re-invoking the provider (`Timeline(entries:, policy: .atEnd)`). Otherwise single entry, `.after(now + 180s)` while working or `.after(now + 900s)` while idle.

## 5. Data flow: Widget → App (write side, button taps)

Widget buttons use iOS 17+ interactive `Button(intent:)`, backed by `AppIntent`s that conform to `LiveActivityIntent` with `openAppWhenRun = false` — iOS runs `perform()` in the **app's process** (launching it in the background if needed) without bringing it to the foreground.

```
User taps "Clock Out" on widget
  → ClockOutIntent.perform()  [runs in app process via LiveActivityIntent]
      → ShiftIntentRouter.run(.clockOut)
          → WidgetBridge.recordPendingAction(.clockOut)   [writes pending action + timestamp to App Group UserDefaults, posts Darwin notification]
          → ShiftIntentRouter.applyPending?()              [calls into AppViewModel if app is alive]

AppDelegate (app launch) installs:
  ShiftIntentRouter.applyPending = { AppViewModel.shared.consumeWidgetActionIfNeeded() }

AppViewModel.consumeWidgetActionIfNeeded()
  → WidgetBridge.consumePendingActionWithDate()   [reads + clears the pending action]
  → clockIn(at:) / clockOut() / startBreak(at:) / endBreak(at:)   [REAL business logic: persistence, sync, Live Activity, Watch]
```

Why "record, then apply" instead of applying directly: a tap can arrive while the phone is locked and Data Protection has the app's files encrypted/unreadable. Recording first means the tap (with its original timestamp) survives even if `applyPending` can't run yet — it's picked up on the next app launch or Darwin wake. `consumeWidgetActionIfNeeded` honors the original tap time unless it's >12h stale, in which case it applies "now" instead.

**Cross-process wake-up**: `WidgetBridge.postDarwinNotification()` fires a Darwin notification (`com.hourstracker.widget.action`) that `WidgetActionBroadcaster` (installed once at app launch via `AppDelegate`) observes, re-posting a local `NotificationCenter` event on the main thread so the already-running app also reacts immediately (not just cold launches).

**Available intents** (`ShiftIntents.swift`):
- `ClockInIntent`, `ClockOutIntent`, `StartBreakIntent`, `EndBreakIntent` — each just routes to `ShiftIntentRouter.run(_:)`.
- `ToggleShiftIntent` (`SetValueIntent` + `LiveActivityIntent`) — backs the iOS 18 `ShiftControl` Control Center toggle; `value: Bool` picks clockIn vs clockOut.

**Important build-system gotcha** (documented inline in `HoursWidget.swift`): Xcode's AppIntents metadata extraction statically scans for `Button(intent: ConcreteIntentType())` call sites. Any indirection — boxing as `any AppIntent`, or wrapping in a generic `<Intent: AppIntent>` helper — defeats the scanner silently: the button renders but never registers as interactive, and taps fall through to `.widgetURL` instead. Every call site spells out the concrete intent literally (e.g. `Button(intent: ClockOutIntent())`); only label *styling* is shared via a plain helper function.

## 6. Live Activity (Dynamic Island / Lock Screen banner)

- `HoursActivityAttributes` (in `WidgetBridge.swift`, shared) — static attrs (clockInTime, hourlyRate, currency, standardDayHours, ot125Cap, gasAllowance, breakMinutes) + `ContentState` (elapsedTime, estimatedPay, elapsedHours, breakStart, breakTargetMinutes, paidClockStart, payIsNet). Must be byte-identical in app and widget targets (same file).
- App-only factory: `HoursActivityAttributes.from(session:settings:)` in `WidgetIntegration.swift`.
- App-only lifecycle owner: `HoursTracker/Managers/LiveActivityManager.swift`, driven by `AppViewModel.syncWidget()` → `LiveActivityManager.update(session:settings:curve:showsNet:)`.
- Rendering: `HoursWidget.swift` → `HoursLiveActivity` (lock screen banner + Dynamic Island compact/expanded/minimal) and `LiveActivityViews.swift` (the actual view bodies: `HoursLiveActivityView`, `HoursLiveActivityExpanded`, `HoursLiveActivityMinimal`).
- Same "system timer ticks itself" trick as the home widget: `Text(timerInterval:)` for the paid clock and the break countdown, so the Dynamic Island updates every second without any `Activity.update()` call.

## 7. Settings sync (non-session path)

Settings changes (`AppViewModel.persistSettings()`) push through a lighter path than full `syncWidget()`:
```
persistSettings()
  → store.saveSettings(settings)
  → WidgetBridge.update(settings: snapshot(from: activeSettings))
  → WidgetBridge.reloadWidgetTimelines()
  → refreshAppShortcuts()
  → WatchConnectivityManager.shared.pushSnapshot()
```

## 8. Privacy: hide pay

`WidgetBridge.hidePay` (bool in the App Group suite) masks every money string with `"••••"` via `WidgetBridge.format(amount:currencyCode:)`. Every pay-rendering call site in the widget (and Live Activity) routes through this formatter — there's no separate code path to keep in sync if the privacy flag is toggled.

## 9. Other integration points

- **Widget-install nudge** (`HoursTracker/Managers/WidgetNudge.swift`, app-only): schedules at most two local notifications (day 2, day 16 after first use) encouraging the user to add the widget, cancelled the moment `WidgetBridge.installedWidgetCount()` (via `WidgetCenter.shared.getCurrentConfigurations`) reports ≥1 widget placed. Never requests notification permission itself — piggybacks on whatever permission state already exists.
- **Deep links**: `WidgetBridge.deepLinkHome` / `deepLinkHistory` (`hourstracker://tab/home`, `hourstracker://tab/history`) set via `.widgetURL(...)` for taps on non-button areas. Lock Screen widgets are **read-only by design** (comment in `LockScreenWidget.swift`): no interactive buttons there, only `.widgetURL` to Home — avoids accidental clock-in/out from a pocket tap.
- **App icon long-press Quick Actions**: `AppShortcutManager` (in `WidgetIntegration.swift`) — separate mechanism (`UIApplicationShortcutItem`, not WidgetKit), state-aware (clock in vs out label), maps back to the same `hourstracker://action/...` deep links. Not a "widget" technically but part of the same at-a-glance/quick-action family.
- **Control Center control** (`ShiftControl`, iOS 18+): reads `WidgetBridge.openSession(...)` for current on/off state, writes via `ToggleShiftIntent` → same `ShiftIntentRouter` path as everything else.

## 10. File index

```
HoursTrackerWidget/                         (widget extension target)
├── HoursWidget.swift          Theme, timeline provider, Small/Medium/Large widget views,
│                               WidgetBundle (@main), Live Activity + ControlWidget declarations
├── LockScreenWidget.swift      accessoryRectangular/Circular/Inline views (read-only)
├── LiveActivityViews.swift     Dynamic Island / Live Activity banner view bodies
├── WidgetBridge.swift          [SHARED] data contract: snapshot types, App Group read/write API
├── WidgetActions.swift         [SHARED] deep link constants
├── WidgetStrings.swift         [SHARED] WidgetL10n — self-contained localization
├── ShiftIntents.swift          [SHARED] AppIntent button actions + ShiftIntentRouter
└── HoursTrackerWidget.entitlements   App Group entitlement

HoursTracker/Managers/
├── WidgetIntegration.swift     [APP-ONLY] app-type → snapshot conversion, reloadWidgetTimelines(),
│                               WidgetActionBroadcaster (Darwin notification listener),
│                               AppShortcutManager (icon long-press)
├── WidgetNudge.swift           [APP-ONLY] "please add the widget" local notification scheduler
└── LiveActivityManager.swift   [APP-ONLY] Live Activity start/update/end lifecycle

HoursTracker/Shared/LivePayCurve.swift   [SHARED] pay-over-time curve, pure Foundation

HoursTracker/ViewModels/AppViewModel.swift
  - syncWidget()                     main push point after any session/settings change
  - consumeWidgetActionIfNeeded()    applies a pending widget button tap
  - persistSettings()                lighter settings-only push

HoursTracker/AppDelegate.swift
  - installs ShiftIntentRouter.applyPending at launch
```

## 11. Mental model summary

- **Source of truth**: always the app. The widget only ever displays a cache and queues intents.
- **Two data lanes**: (a) slow-changing snapshots refreshed on real events (settings/session change) via `UserDefaults` + `WidgetCenter.reloadAllTimelines()`, and (b) fast-changing numbers (live pay, countdowns) that tick on-device via SwiftUI's `Text(timerInterval:)`/`Gauge` without any reload at all — the app only has to write the *starting parameters* of that curve, not keep pushing frames.
- **Button taps never mutate state directly**; they always go through "record intent → app applies it" so the real pay/overtime engine, persistence, and sync stay single-sourced in the app process.
- **Type boundary**: app-only types (`WorkSession`, `WorkplaceSettings`, `OvertimeCalculator`) never cross into the widget target; the widget only knows `Widget*`-prefixed Codable snapshots and `LivePayCurve`.
