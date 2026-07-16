# HoursTracker — Codebase Overview

## What this app is

HoursTracker is an iOS app for a single worker to track daily work hours and see what each day pays under **Israeli labor rules**: regular days pay 100% up to the standard day (8.6h), then 125% for up to 2 hours, then 150%; rest-day (Shabbat) and holiday work pays 150%/175%/200%; night shifts reach overtime after 7 hours; unpaid breaks are deducted. Net pay is estimated from Israeli income-tax brackets, credit points, National Insurance, and Health Tax. It supports clock in/out with a live timer, multiple shifts per day, manual entries, OCR import of printed timesheets, geofence-based arrival reminders, smart clock-out reminders, custom payroll months, iCloud sync across devices, and exporting pay reports to PDF, TXT, Word (.docx), and Markdown. The UI is fully localized in English, Arabic, and Hebrew, and pay can be displayed in a configurable currency.

## Tech stack

| Area | Choice |
|---|---|
| UI | SwiftUI, 4-tab `TabView`, MVVM |
| Minimum OS | iOS 17.0, Swift 5.9 |
| Project generation | [XcodeGen](https://github.com/yonaskolb/XcodeGen) via `project.yml` (the `.xcodeproj` is generated) |
| Persistence | Plain JSON files in the app's Documents directory |
| Sync | CloudKit private database (`iCloud.com.hourstracker.app`), **opt-in via `HTCloudKitEnabled`, off by default** |
| Location | Core Location region monitoring (`CLCircularRegion`); no `UIBackgroundModes: location` |
| Notifications | Local notifications via `UserNotifications` |
| Localization | String Catalog (`Localizable.xcstrings`) for UI, `AppLocale` for notification text |
| Tests | XCTest unit tests (`HoursTrackerTests`) |

## Directory layout

```
HoursTracker/
├── HoursTrackerApp.swift        App entry point + MainTabView (Home / History / Export / Settings)
├── Models/
│   ├── WorkSession.swift        A shift: clockIn/out, break, DayType, night flag; night-shift detection
│   ├── WorkplaceSettings.swift  Worker identity, rates, OT/work rules, tax status, geofence, currency
│   ├── OvertimeCalculator.swift Day-aware tiered pay engine (DayPayBreakdown)
│   ├── IsraeliTaxEstimator.swift      Income tax / National Insurance / Health Tax estimate
│   ├── TaxCreditPointsCalculator.swift Credit points from marital/family status
│   └── MaritalStatus.swift            Marital status enum for tax settings
├── Managers/
│   ├── PersistenceManager.swift       Local JSON load/save (PersistableStore)
│   ├── CloudKitSyncManager.swift      CloudKit fetch/upload/merge (CloudSyncing) + NoOp stub
│   ├── SyncingPersistenceStore.swift  Facade: local-first writes + incremental cloud upload
│   ├── LocationReminderManager.swift  Geofence + all reminder notifications
│   ├── TimesheetScannerManager.swift  Vision OCR of photographed timesheets → session drafts
│   └── ExportManager.swift            Report building + PDF/TXT/DOCX/Markdown writers
├── ViewModels/
│   └── AppViewModel.swift       Single @MainActor view model owning all app state
├── Views/
│   ├── HomeView.swift           Clock in/out, live timer + gross ticker, day-summary sheet
│   ├── HistoryView.swift        Payroll-period browser, per-shift rows, gross/net totals
│   ├── ShiftDetailSheet.swift   Per-shift pay breakdown + session editor
│   ├── ManualEntryView.swift    Add a session by hand (times, break, day type, night)
│   ├── TimesheetScannerView.swift Review/import OCR-scanned sessions
│   ├── ImportConflictPopup.swift  Replace/keep prompt for scanned days that already exist
│   ├── ActivityLogView.swift    Browse/export the on-device activity log
│   ├── PrivacyPolicyView.swift  In-app privacy policy
│   ├── ExportView.swift         Date range + language + format pickers, share sheet
│   └── SettingsView.swift       Worker/pay/work-rules/payroll/tax/location/privacy settings
├── Utilities/
│   ├── L10n.swift               Typed accessors for the String Catalog
│   ├── AppLocale.swift          ar/he/en strings for notifications (outside the catalog)
│   ├── ExportCopy.swift         Per-language report strings (independent of UI language)
│   ├── HistoryPeriodHelper.swift    Custom payroll-month math + hour formatting
│   ├── PayFormatter.swift           Currency-aware money formatting (locale-overridable)
│   ├── KeyboardDismiss.swift        Tap-outside keyboard dismissal helpers
│   ├── LocationCaptureHelper.swift  One-shot "use my current location" capture
│   └── ZipWriter.swift          Minimal ZIP archiver (deflate + CRC32) used to build .docx
├── Managers/ActivityLogStore.swift  Persistent activity/event log (also exportable)
├── Models/ExportLanguage.swift      Report language selection (phone / en / he / ar)
└── Resources/
    ├── Localizable.xcstrings    String Catalog (en / ar / he)
    ├── InfoPlist.xcstrings      Localized Info.plist strings
    ├── PrivacyInfo.xcprivacy    Privacy manifest
    └── Assets.xcassets          App icon

HoursTrackerTests/
├── OvertimeCalculatorTests.swift      Pay-engine boundary cases + payroll periods
├── PayRulesTests.swift                Multi-session days, breaks, rest-day/night rates, currency
├── SyncMergeTests.swift               Last-write-wins merge logic
├── ExportManagerTests.swift           Report filtering and totals
├── ClockOutEstimationTests.swift      Clock-out time prediction
├── SyncingPersistenceStoreTests.swift Incremental upload/delete propagation
├── AppViewModelTests.swift            Clock in/out flows, error surfacing
├── ClockTimeResolutionTests.swift     Swapped in/out correction, import conflicts
├── ActivityLogStoreTests.swift        Activity log persistence
└── TestDoubles.swift                  In-memory store, mock cloud/location
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
3. `SyncingPersistenceStore.saveSessions(_:)` writes JSON locally **synchronously**, diffs against the previous file to find deleted and changed records, then kicks off a background `Task` that propagates only those deletions/changes to CloudKit (best-effort). A failed local write throws and surfaces as an alert via `AppViewModel.errorMessage`.
4. `refreshReminders()` re-feeds settings and sessions to `LocationReminderManager`, which reschedules notifications and the geofence.

### Domain rules worth knowing

- **Multiple sessions per day, one open at a time.** `clockIn` is blocked only while a session is open (`AppViewModel.canClockIn`); a second shift after clocking out is allowed. Manual entry still refuses a duplicate day.
- **Same-day sessions share one daily allowance.** Overtime tiers and the daily gas allowance are consumed across a day's sessions in clock-in order (`OvertimeCalculator.breakdowns(forDay:)`), so a second shift continues the day's counters instead of restarting them.
- **A session belongs to the day of its clock-in** (`date` is `startOfDay(for: clockIn)`), so an overnight shift is attributed entirely to the start day. A session left open past midnight remains the active session and can still be clocked out from the Home tab.
- **Auto-classification on clock-out**: night shifts are detected (≥ 2h between 22:00 and 06:00), and the configured default break is applied to shifts of 6h or more; both stay user-editable per session, as does the day type (regular / rest day / holiday).
- The live timer on Home is derived from `WorkSession.elapsedSeconds`, so it survives app relaunches — no timer state is stored beyond the session itself.

## Core domain logic: the pay engine

`OvertimeCalculator` splits each calendar day's **effective hours** (clocked time minus unpaid break) into three tiers and prices them by the session's day type:

| Tier | Regular day | Rest day / holiday | Capacity |
|---|---|---|---|
| Base | 100% | 150% | `standardDayHours` (8.6h; 7h for night shifts) |
| Tier 1 | 125% | 175% | `ot125HoursCap` (2h) |
| Tier 2 | 150% | 200% | unlimited |

Key entry points:

- `breakdowns(forDay:settings:)` — the core: a day's sessions processed in clock-in order against one shared allowance; gas paid once, on the first session; per-session values sum exactly to the day total.
- `breakdown(for:in:settings:)` — one session evaluated in its same-day context (used by History rows and the shift detail sheet).
- `aggregate(sessions:settings:)` — groups by calendar day and sums; overtime is computed **per day**, never across the whole range.

`DayPayBreakdown` carries per-tier hours and pay, gross, and estimated net: gross flows through `IsraeliTaxEstimator` (income-tax brackets + National Insurance + Health Tax, offset by `TaxCreditPointsCalculator` credit points from marital/family status). Money is formatted via `PayFormatter` using the currency chosen in Settings (`WorkplaceSettings.currencyCode`, default ILS).

## Subsystems

### Persistence & sync

- **Local**: `PersistenceManager` writes `work_sessions.json` and `workplace_settings.json` to Documents with ISO-8601 dates via `ProtectedFileWriter` (atomic + `.completeFileProtectionUnlessOpen`). Save failures throw (surfaced as a UI alert); load failures fall back to empty/default state and are logged. Existing files are re-written once on launch to upgrade their protection class.
- **National ID (teudat zehut)**: Stored in the Keychain (`KeychainStore`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), not in JSON or CloudKit. `WorkplaceSettings.workerIDNumber` remains a plain in-memory field for all consumers; only the persistence layer strips it on save and rehydrates it on load. On first launch after upgrade, a plaintext value still present in JSON is migrated into Keychain and the JSON is rewritten empty. Decision: Keychain (not CryptoKit field encryption) so the ciphertext never appears in iCloud sync payloads and deletion is a single `SecItemDelete`. The ID is device-local and does not sync across devices.
- **Cloud sync is compiled out by default.** `CKContainer` aborts the process when the iCloud entitlements are missing, and personal-team provisioning cannot carry them, so CloudKit only activates when `HTCloudKitEnabled` is set in Info.plist *and* the entitlements are restored (`CloudKitSyncManager.makeDefault()` otherwise returns the `NoOpCloudSyncManager` stub, and Settings hides the sync section via `CloudSyncing.isSupported`). Everything below describes the enabled configuration.
- **Cloud**: `CloudKitSyncManager` stores each session as one `WorkSession` record whose `payload` field is the JSON-encoded struct (plus a `modifiedAt` field); settings live in a single well-known record (`workplace-settings`). There is no per-field schema — the payload blob is the source of truth.
- **Merge strategy**: last-write-wins per record using `modifiedAt` (`WorkSession.touch()` bumps it on every edit). Sessions are merged by UUID; the newer copy wins.
- **User opt-in**: even in CloudKit-enabled builds, sync stays off until the user enables **Sync with iCloud** (`CloudSyncPreference` / UserDefaults `iCloudSyncEnabled`, default `false`). `syncNow`, uploads, and remote session deletes no-op while the toggle is off. Turning the toggle off offers to purge private-DB copies. (Privacy manifest UserDefaults reason code is added in Phase 3.)
- **Sync triggers**: when the toggle is on, full two-way sync (`syncNow`) runs at launch and whenever the app returns to the foreground (`HoursTrackerApp.onChange(of: scenePhase)`), plus a manual sync button. Every local save also fire-and-forgets an upload of the sessions that changed in that save.
- **Deletions** are detected by diffing the previous local file against the new session list, then propagated to CloudKit only while sync is enabled; a failed delete is silently retried at the next full sync.

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

Date ranges: all / specific month / custom range. Output lands in `tmp/Exports/` via `ExportTempFileStore` (Data Protection applied), is handed to a share sheet, and is deleted when the share sheet completes, on app launch, on background, and as part of Delete All My Data.

### Payroll periods, tax estimation, and timesheet scanning

- **Payroll months** — `HistoryPeriodHelper` computes custom salary periods from `WorkplaceSettings.payrollStartDay` (e.g. the 10th → 9th of the next month); History navigates period by period and shows per-period totals with a gross/net toggle.
- **Net-pay estimation** — `IsraeliTaxEstimator` scales a day's gross to a monthly profile, applies progressive income-tax brackets, National Insurance, and Health Tax, offsets by credit points (`TaxCreditPointsCalculator`, driven by marital status/children settings), and scales back to a daily figure. Explicitly an estimate, not a payroll calculation.
- **OCR timesheet import** — `TimesheetScannerManager` (Vision-based) extracts date/in/out rows from photographed or imported timesheet images into `ScannedSessionDraft`s; `TimesheetScannerView` lets the user review, select, and import them, with conflict handling for days that already have sessions (`AppViewModel.importScannedSessions` + `ImportConflictPopup`). Imported sessions are flagged `isAIImported` and auto-tagged with day type and night-shift status. `WorkSession.resolveClockPair` corrects the common OCR/RTL mistake of swapped in/out times — this heuristic applies only to scanner imports and the same-day wheel pickers of manual entry, never to the explicit datetimes of the shift editor.
- **Export languages** — reports can render entirely in English, Hebrew, or Arabic independent of the UI language (`ExportLanguage`), including a column legend. Because `String(localized:)` follows the app locale, report strings live in a dedicated per-language table (`ExportCopy`) — a deliberate third string mechanism alongside the String Catalog and `AppLocale` (consolidation is tracked in the roadmap).
- **Activity log** — `ActivityLogStore` keeps a persistent on-device log of clock/import/settings/privacy events, browsable in `ActivityLogView` and exportable as TXT/JSON/CSV/Markdown; it is erased by the delete-all-data action.
- **Privacy & permissions** — Set Location uses When-In-Use only (`LocationCaptureHelper` waits for authorization before `requestLocation`). Arrival reminders stage When-In-Use then Always, plus notification authorization; denial states deep-link to system Settings. Geofencing uses region monitoring (can relaunch a terminated app) and does **not** enable `allowsBackgroundLocationUpdates` or `UIBackgroundModes: location`. The app ships a privacy manifest (`PrivacyInfo.xcprivacy`), an in-app privacy policy (`PrivacyPolicyView`, `docs/PRIVACY.md`), and a delete-all-data action (`AppViewModel.deleteAllUserData`) that clears sessions/settings/activity log/Keychain national ID/export temps/local notifications, tears down geofencing, and purges CloudKit session + settings records when sync is supported (partial cloud failure is surfaced to the user).

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
- CloudKit is **opt-in** via `HTCloudKitEnabled` in Info.plist. Personal-team installs leave it off (empty entitlements) so `CKContainer` never initializes and the Settings sync section stays hidden. Set the flag and restore the iCloud entitlements only on a paid Apple Developer team build that has the CloudKit container provisioned.

```bash
xcodebuild test -scheme HoursTracker -destination 'platform=iOS Simulator,name=iPhone 16'
```

The suite covers the overtime engine (`OvertimeCalculatorTests`), CloudKit merge logic (`SyncMergeTests`), export filtering and totals (`ExportManagerTests`), clock-out prediction (`ClockOutEstimationTests`), incremental sync writes (`SyncingPersistenceStoreTests`), and view-model flows against in-memory mocks (`AppViewModelTests`, doubles in `TestDoubles.swift`). CI (`.github/workflows/ci.yml`) regenerates the project and runs the suite on every push and pull request.
