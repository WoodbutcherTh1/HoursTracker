# HoursTracker — Codebase Overview

## What this app is

HoursTracker is an iOS app for a single worker to track daily work hours and see what each day pays under **Israeli overtime rules** (regular rate up to the standard day, then 125% for the first overtime hours, then 150%). It supports clock in/out with a live timer, manual entries, geofence-based arrival reminders, smart clock-out reminders, iCloud sync across devices, and exporting pay reports to PDF, TXT, Word (.docx), and Markdown. The UI is fully localized in English, Arabic, and Hebrew.

## Tech stack

| Area | Choice |
|---|---|
| UI | SwiftUI, 4-tab `TabView`, MVVM |
| Minimum OS | iOS 17.0, Swift 5.9 |
| Project generation | [XcodeGen](https://github.com/yonaskolb/XcodeGen) via `project.yml` (the `.xcodeproj` is generated) |
| Persistence | Plain JSON files in the app's Documents directory |
| Sync | CloudKit private database (`iCloud.com.hourstracker.app`) |
| Location | Core Location geofencing (`CLCircularRegion`), background location mode |
| Notifications | Local notifications via `UserNotifications` |
| Localization | String Catalog (`Localizable.xcstrings`) for UI, `AppLocale` for notification text |
| Tests | XCTest unit tests (`HoursTrackerTests`) |

## Directory layout

```
HoursTracker/
├── HoursTrackerApp.swift        App entry point + MainTabView (Home / History / Export / Settings)
├── Models/
│   ├── WorkSession.swift        A single work day: clockIn, clockOut?, notes, modifiedAt
│   ├── WorkplaceSettings.swift  Worker identity, hourly rate, gas allowance, OT parameters, geofence
│   └── OvertimeCalculator.swift Pure pay-breakdown engine (DayPayBreakdown)
├── Managers/
│   ├── PersistenceManager.swift       Local JSON load/save (PersistableStore)
│   ├── CloudKitSyncManager.swift      CloudKit fetch/upload/merge (CloudSyncing)
│   ├── SyncingPersistenceStore.swift  Facade: local-first writes + background cloud upload
│   ├── LocationReminderManager.swift  Geofence + all reminder notifications
│   └── ExportManager.swift            Report building + PDF/TXT/DOCX/Markdown writers
├── ViewModels/
│   └── AppViewModel.swift       Single @MainActor view model owning all app state
├── Views/
│   ├── HomeView.swift           Clock in/out buttons, live timer, day-summary sheet
│   ├── HistoryView.swift        Completed sessions list, edit/delete, manual-entry entry point
│   ├── ManualEntryView.swift    Add/edit a session by hand
│   ├── ExportView.swift         Date range + format pickers, share sheet
│   └── SettingsView.swift       Worker details, pay parameters, workplace location capture
├── Utilities/
│   ├── L10n.swift               Typed accessors for the String Catalog
│   ├── AppLocale.swift          ar/he/en strings for notifications (outside the catalog)
│   ├── LocationCaptureHelper.swift  One-shot "use my current location" capture
│   └── ZipWriter.swift          Minimal ZIP archiver (deflate + CRC32) used to build .docx
└── Resources/
    └── Localizable.xcstrings    String Catalog (en / ar / he)

HoursTrackerTests/
└── OvertimeCalculatorTests.swift  Unit tests for the pay engine
```

## Architecture

MVVM with protocol-backed singletons injected into a single view model:

```
┌────────────────────────── SwiftUI Views ──────────────────────────┐
│   HomeView    HistoryView    ExportView    SettingsView           │
└───────────────────────────────┬───────────────────────────────────┘
                                │ @ObservedObject
                        ┌───────▼────────┐
                        │  AppViewModel  │  @MainActor, owns sessions + settings
                        └───┬───────┬────┘
              ┌─────────────┘       └──────────────┐
      ┌───────▼─────────┐                ┌─────────▼──────────────┐
      │  SyncingStore   │                │ LocationReminderManaging│
      │ (SyncingPersist-│                │ (LocationReminderManager)│
      │  enceStore)     │                └────────────────────────┘
      └───┬─────────┬───┘
   local  │         │  cloud (fire-and-forget Tasks)
┌─────────▼──┐  ┌───▼──────────────┐
│Persistence │  │CloudKitSyncManager│
│Manager     │  │ (private CK DB)   │
└────────────┘  └───────────────────┘
```

Key protocols (all in `Managers/`): `PersistableStore`, `SyncingStore`, `CloudSyncing`, `LocationReminderManaging`. `AppViewModel`'s initializer takes the store and location manager as protocol parameters (defaulting to the shared singletons), which is what makes the view model testable.

### Data flow for a typical mutation

1. A view calls a method on `AppViewModel` (e.g. `clockOut()`).
2. The view model mutates its `@Published` `sessions` array and calls `persist()`.
3. `SyncingPersistenceStore.saveSessions(_:)` writes JSON locally **synchronously**, diffs against the previous file to find deleted IDs, then kicks off a background `Task` that deletes/uploads records in CloudKit (best-effort).
4. `refreshReminders()` re-feeds settings and sessions to `LocationReminderManager`, which reschedules notifications and the geofence.

### Domain rules worth knowing

- **One session per calendar day.** `clockIn` is blocked if any session exists for today (`AppViewModel.canClockInToday`), and manual entry refuses a duplicate day.
- **A session belongs to the day of its clock-in** (`date` is `startOfDay(for: clockIn)`), so an overnight shift is attributed entirely to the start day.
- The live timer on Home is derived from `WorkSession.elapsedSeconds`, so it survives app relaunches — no timer state is stored beyond the session itself.

## Core domain logic: the overtime engine

`OvertimeCalculator.breakdown(totalHours:settings:)` is a pure function:

```
regular  = min(totalHours, standardDayHours)        // default 8.6h
otTotal  = max(0, totalHours - standardDayHours)
ot125    = min(otTotal, ot125HoursCap)              // default cap 2h
ot150    = max(0, otTotal - ot125)
pay      = regular·rate + ot125·rate·1.25 + ot150·rate·1.5 + gasAllowance
```

`DayPayBreakdown` carries the per-bucket hours plus total pay (formatted as ₪). `aggregate(sessions:settings:)` sums per-day breakdowns for reports — importantly, overtime is computed **per day**, then summed, never across the whole range.

## Subsystems

### Persistence & sync

- **Local**: `PersistenceManager` writes `work_sessions.json` and `workplace_settings.json` to Documents with ISO-8601 dates, atomic writes, and silent failure (`try?`).
- **Cloud**: `CloudKitSyncManager` stores each session as one `WorkSession` record whose `payload` field is the JSON-encoded struct (plus a `modifiedAt` field); settings live in a single well-known record (`workplace-settings`). There is no per-field schema — the payload blob is the source of truth.
- **Merge strategy**: last-write-wins per record using `modifiedAt` (`WorkSession.touch()` bumps it on every edit). Sessions are merged by UUID; the newer copy wins.
- **Sync triggers**: full two-way sync (`syncNow`) runs at launch and whenever the app returns to the foreground (`HoursTrackerApp.onChange(of: scenePhase)`), plus a manual sync button. Every local save also fire-and-forgets an upload of **all** sessions.
- **Deletions** are detected by diffing the previous local file against the new session list, then propagated to CloudKit; a failed delete is silently retried at the next full sync.

### Location & reminders

`LocationReminderManager` owns three notifications, rescheduled on every data change:

1. **Arrival reminder** — a `CLCircularRegion` geofence (default radius 150 m) around the workplace; on entry, if no session exists today, it fires "Did you clock in?".
2. **Predicted clock-out reminder** — while a session is open, it averages the clock-out times of the last up-to-10 completed sessions (seconds from midnight, rounded up to 10 minutes) and schedules a reminder at that time.
3. **Forgot-to-clock-out alert** — fixed 23:00 reminder while a session is still open.

Notification copy comes from `AppLocale` (hardcoded ar/he/en strings chosen from `Locale.preferredLanguages`), not the String Catalog. The workplace location is set from Settings via `LocationCaptureHelper` (one-shot `requestLocation`).

### Export pipeline

`ExportManager` first builds a format-agnostic `ExportReport` (filtered completed sessions → `ExportRow`s with per-day breakdowns → aggregate totals row), then renders it:

- **PDF** — drawn manually with `UIGraphicsPDFRenderer` (landscape A4-ish, paginated table).
- **TXT** — fixed-width columns.
- **Markdown** — pipe table.
- **DOCX** — hand-built WordprocessingML XML packaged into a valid `.zip` by `ZipWriter` (a from-scratch ZIP encoder using `Compression`'s deflate and a CRC-32 implementation — there is no third-party dependency in the project).

Date ranges: all / specific month / custom range. Output lands in the temp directory and is handed to a share sheet.

### Localization

Two mechanisms coexist:

- **UI strings**: `Localizable.xcstrings` String Catalog accessed through `L10n`'s typed static properties.
- **Notification strings**: `AppLocale` switch statements (needed because notifications can fire from background contexts where the manager picks the language itself).

Supported languages are declared in `project.yml` (`CFBundleLocalizations`: en, ar, he); ar/he give the app RTL coverage.

## Building, running, testing

```bash
xcodegen generate            # regenerate HoursTracker.xcodeproj from project.yml
open HoursTracker.xcodeproj
```

- Run on a **physical device** for geofencing/background location; the simulator can't exercise region monitoring reliably.
- Requires an iCloud-signed-in device for sync (container `iCloud.com.hourstracker.app`, entitlements in `HoursTracker/HoursTracker.entitlements`).

```bash
xcodebuild test -scheme HoursTracker -destination 'platform=iOS Simulator,name=iPhone 16'
```

Current test coverage is limited to the overtime engine (`OvertimeCalculatorTests`, 7 cases covering regular/125%/150% boundaries, zero hours, and aggregation). Managers and the view model are protocol-abstracted and ready for mock-based tests, but none exist yet — see `docs/ROADMAP.md`.
