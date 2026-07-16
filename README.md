# HoursTracker

iOS app for tracking daily work hours with Israeli overtime law calculations (Regular / 125% / 150%), geofence reminders, and multi-format export.

## Features

- **Clock In / Out** with live timer persisted across app launches
- **Israeli OT engine** — configurable standard hours (default 8.6h), 125% cap (2h), then 150%
- **Manual entry** with edit/delete from History
- **Geofence reminders** on workplace arrival
- **Smart clock-out reminders** based on last 5–10 sessions + 23:00 forgot-to-clock-out alert
- **Export** to PDF, TXT, Word (.docx), Markdown via Share Sheet
- **JSON persistence** in Documents with **CloudKit sync** (iCloud private database)
- **Full localization** — Arabic, Hebrew, English (String Catalog)

## Documentation

- [Architecture overview](docs/ARCHITECTURE.md) — how the codebase is structured and how the subsystems work
- [Roadmap](docs/ROADMAP.md) — phased development plan

## Requirements

- iOS 17+
- Xcode 16+
- Location Always permission for background geofencing

## Setup

```bash
xcodegen generate
open HoursTracker.xcodeproj
```

The `.xcodeproj` is generated from `project.yml` and not checked in — install [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) and run `xcodegen generate` after cloning.

Run on a physical device for full location/geofence behavior.

## Project Structure

```
HoursTracker/
├── Models/          WorkplaceSettings, WorkSession, OvertimeCalculator
├── Managers/        Persistence, Location, Export
├── ViewModels/      AppViewModel (MVVM)
├── Views/           Home, History, Manual, Settings, Export
└── Utilities/       AppLocale (ar/he/en notifications)
```

## Tests

```bash
xcodebuild test -scheme HoursTracker -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Overtime Formula

```
regular  = min(totalHours, standardDayHours)
ot125    = min(max(0, totalHours - standardDayHours), ot125HoursCap)
ot150    = max(0, overtimeTotal - ot125)
pay      = regular×rate + ot125×rate×1.25 + ot150×rate×1.5 + gasAllowance
```
