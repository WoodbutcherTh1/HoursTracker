# Graph Report - .  (2026-08-01)

## Corpus Check
- Large corpus: 225 files · ~735,514 words. Semantic extraction will be expensive (many Claude tokens). Consider running on a subfolder.

## Summary
- 2936 nodes · 7136 edges · 119 communities (115 shown, 4 thin omitted)
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 589 edges (avg confidence: 0.8)
- Token cost: 221,050 input · 0 output

## Community Hubs (Navigation)
- Localization Strings (L10n)
- Export Copy & Localization
- Location Reminder Manager
- Settings View
- Israeli ID Validator
- Blank Timesheet Entry View
- App Language Preference
- Scanner Row Validator
- Payslip Store
- Tax Credit Points Calculator
- Payslip Detail View
- Home Animated Door Button
- App View Model
- Persistence Manager
- Full Data Export/Import Errors
- Work Session Model
- History Period Helper
- User Guide Sheet
- Localization Strings (L10n) Cont.
- App Review Reply Doc
- Syncing Persistence Store
- Home View
- Home Motion Demo Script
- Export Manager
- Payslip LLM Models
- Home Stat Layout Metrics
- Timesheet Scanner View
- Payslip Thumbnail Cache
- History View
- Full Data Export Manager
- Persistence Manager (cont.)
- Scanner LLM Models
- Payslip Library View Model
- Export Manager (cont.)
- Workplace Settings Coding Keys
- CloudKit Sync Manager
- Syncing Persistence Store (cont.)
- Workplace Settings Model
- Session Tombstone Store
- Payslip Upload Review View
- App ViewModel Delete-Data Test
- Activity Log Store
- Export Day Type Filter
- App View Model (cont.)
- Zip Writer Utility
- Overtime Calculator
- App View Model (cont. 2)
- Timesheet Scanner Manager
- Shift Detail Sheet
- Location Capture Helper
- Home Week Sparkline
- Payslip Review Draft
- Payslip LLM Models (cont.)
- Full Data Export Format
- Payslip LLM Models (cont. 2)
- Scanned Session Draft
- Manual Entry View
- Payslip Upload View Model
- Timesheet Scanner Manager (cont.)
- CloudKit Sync Manager (cont.)
- History Period Helper (cont.)
- Payslip Review Draft (cont.)
- Protected File Migration
- Local Heuristic Payslip LLM Provider
- OpenAI-Compatible Payslip LLM Provider
- Payslip Store Tests
- Export Format
- Export Temp File Store
- App Lock Controller
- Timesheet Scanner View Model
- Persistence Load Result
- History Period Helper (cont. 2)
- Day Summary Sheet
- Forgot Clock-In Sheet
- CloudKit Sync State
- Israeli Tax Estimator
- Home View (Swift file)
- CloudKit Sync Manager (cont. 2)
- App Lock Policy
- Backup Content Dirty Flag
- History Pay Breakdown Sheet
- Activity Log View
- Camera Picker View
- OpenAI-Compatible Scanner LLM Provider
- Export Language
- Export Sanitizer
- App Lock View
- Payslip Store Error
- Payslip PDF Inspection Result
- Work Session Model (cont.)
- Timesheet Scanner View (cont.)
- App Lock Auth Error
- Keyboard Tap Dismiss Installer
- Month/Year Picker
- Payslip Upload View Model (cont.)
- Activity Log Export Format
- Export Date Range
- Gemini Scanner LLM Provider
- App Lock Controller (cont.)
- Export Layout
- Export Share Sheet
- Gemini Payslip LLM Provider
- Timesheet Scanner Error
- Smart Scanner Cloud Preference
- Launch Hourglass Splash
- Import Conflict Popup
- Success Toast Banner
- Marital Status Model
- App Lock Preference (UserDefaults)
- Cloud Sync Preference (UserDefaults)
- Privacy Policy View
- Persistence Load Error
- Corrupt File Quarantine
- Keyboard Dismiss Modifier
- Payslip Upload View Phase
- Timesheet Scanner View Phase
- Home Accent Theme Color
- Payslip Upload Error
- App Icon Asset

## God Nodes (most connected - your core abstractions)
1. `L10n` - 439 edges
2. `WorkSession` - 106 edges
3. `AppViewModel` - 105 edges
4. `WorkplaceSettings` - 86 edges
5. `ExportCopy` - 84 edges
6. `PayslipRecord` - 47 edges
7. `InMemoryStore` - 47 edges
8. `PayslipStore` - 44 edges
9. `HistoryView` - 43 edges
10. `SettingsView` - 43 edges

## Surprising Connections (you probably didn't know these)
- `Overtime Formula (README summary)` --semantically_similar_to--> `OvertimeCalculator pay-engine tiers`  [INFERRED] [semantically similar]
  README.md → docs/ARCHITECTURE.md
- `UIBackgroundModes:location removal (Guideline 2.5.4 fix)` --references--> `XcodeGen project.yml`  [INFERRED]
  docs/APP_REVIEW_REPLY_2_5_4.md → project.yml
- `InMemoryStore` --references--> `SyncState`  [EXTRACTED]
  HoursTrackerTests/TestDoubles.swift → HoursTracker/Managers/CloudKitSyncManager.swift
- `RecordingCloud` --references--> `SyncState`  [EXTRACTED]
  HoursTrackerTests/TestDoubles.swift → HoursTracker/Managers/CloudKitSyncManager.swift
- `RecordingCloud` --inherits--> `CloudSyncing`  [EXTRACTED]
  HoursTrackerTests/TestDoubles.swift → HoursTracker/Managers/CloudKitSyncManager.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Privacy compliance documentation set** — docs_privacy_overview, docs_privacy_manifest_overview, docs_data_inventory_overview, docs_privacy_manifest_privacyinfo_xcprivacy, github_pull_request_template_overview [EXTRACTED 0.90]
- **Enterprise hardening program (phases 1-6)** — docs_hardening_log_overview, docs_hardening_summary_overview, docs_threat_model_overview, security_overview, swiftlint_config, github_workflows_ci_ci_pipeline, github_pull_request_template_overview [EXTRACTED 0.90]
- **Smart Scanner cloud-extraction privacy exception** — docs_smart_scanner_overview, docs_smart_scanner_smart_scanner_cloud_extraction, docs_privacy_manifest_overview, docs_data_inventory_overview, docs_privacy_overview, docs_architecture_networking_gate [EXTRACTED 0.90]

## Communities (119 total, 4 thin omitted)

### Community 0 - "Localization Strings (L10n)"
Cohesion: 0.01
Nodes (408): L10n, .appLockEnabled, .appLockFailed, .appLockHint, .appLockReason, .appLockSection, .appLockSubtitle, .appLockTitle (+400 more)

### Community 1 - "Export Copy & Localization"
Cohesion: 0.05
Nodes (67): ExportCopy, .allDays, .colBreak, .colDailyWage, .colDate, .colDay, .colDeductions, .colGas (+59 more)

### Community 2 - "Location Reminder Manager"
Cohesion: 0.06
Nodes (25): CLCircularRegion, CLLocationManagerDelegate, CLRegion, CLRegionState, info, LocationReminderManager, Bool, Calendar (+17 more)

### Community 3 - "Settings View"
Cohesion: 0.06
Nodes (41): APIKeyCheckResult, invalid, .isValid, networkError, valid, ScannerAPIKeyValidator, Bool, String (+33 more)

### Community 4 - "Israeli ID Validator"
Cohesion: 0.06
Nodes (12): HoursTracker, IsraeliIDValidator, Bool, String, DaypartGreetingTests, Calendar, Date, Int (+4 more)

### Community 5 - "Blank Timesheet Entry View"
Cohesion: 0.09
Nodes (24): BlankTimesheetEntryView, .addRowButton, .body, .conflictOverlay, .freeTextPane, .headerRow, .hintBar, .modePicker (+16 more)

### Community 6 - "App Language Preference"
Cohesion: 0.07
Nodes (29): AppLanguageController, .layoutDirection, .locale, .preference, AppLanguageOption, arabic, english, hebrew (+21 more)

### Community 7 - "Scanner Row Validator"
Cohesion: 0.06
Nodes (35): CodingKey, CodingKeys, clockIn, clockOut, confidence, date, totalHours, ScannerLLMRow (+27 more)

### Community 8 - "Payslip Store"
Cohesion: 0.11
Nodes (19): PayslipStore, .filesDirectory, .indexURL, .payslipsDirectory, .rootDirectory, fileTooLarge, StagedPayslipFile, Date (+11 more)

### Community 9 - "Tax Credit Points Calculator"
Cohesion: 0.07
Nodes (12): Bool, Double, TaxCreditPointsCalculator, .periodTotals, .monthPayBreakdown, .todayPayBreakdown, .weekPayBreakdown, OvertimeCalculatorTests (+4 more)

### Community 10 - "Payslip Detail View"
Cohesion: 0.08
Nodes (31): PayslipDetailPDFPreview, PayslipDetailView, .body, .currencyCode, .deductionBreakdownSection, .fieldSection, .overtimeBreakdownSection, .periodTitle (+23 more)

### Community 11 - "Home Animated Door Button"
Cohesion: 0.08
Nodes (37): Color, String, UserDefaults, AnimatedCalendarIcon, .body, AnimatedChartIcon, .body, AnimatedClockIcon (+29 more)

### Community 12 - "App View Model"
Cohesion: 0.09
Nodes (22): LocationReminderManaging, SyncingStore, AppViewModel, .activeSession, .canClockIn, .canClockInToday, .isClockedIn, .isCloudSyncSupported (+14 more)

### Community 13 - "Persistence Manager"
Cohesion: 0.11
Nodes (19): PersistenceManager, .documentsDirectory, .sessionsURL, .settingsURL, Bool, Error, FileManager, Int (+11 more)

### Community 14 - "Full Data Export/Import Errors"
Cohesion: 0.11
Nodes (32): Codable, Equatable, Hashable, FullDataExportBreakdownDTO, FullDataExportDocument, FullDataImportError, emptyFile, .errorDescription (+24 more)

### Community 15 - "Work Session Model"
Cohesion: 0.08
Nodes (25): date, DayType, holiday, .id, .isPremium, .localizedName, regular, restDay (+17 more)

### Community 16 - "History Period Helper"
Cohesion: 0.12
Nodes (21): HistoryPeriodHelper, PayDisplayMode, gross, .id, net, .title, PayrollPeriod, .days (+13 more)

### Community 17 - "User Guide Sheet"
Cohesion: 0.10
Nodes (28): View, GuideCopy, GuideHistoryPage, .body, GuideHomePage, .body, GuideLanguage, ar (+20 more)

### Community 18 - "Localization Strings (L10n) Cont."
Cohesion: 0.08
Nodes (10): Double, Int, String, .saveBar, .confirmContent, .title, .body, .body (+2 more)

### Community 19 - "App Review Reply Doc"
Cohesion: 0.17
Nodes (34): UIBackgroundModes:location removal (Guideline 2.5.4 fix), App Review Reply — Guideline 2.5.4, CloudKit private-database sync (opt-in, last-write-wins), National ID stored in Keychain (not CryptoKit field encryption), Networking gate (no general-purpose networking layer), OvertimeCalculator pay-engine tiers, HoursTracker Codebase Overview, ProtectedFileWriter (atomic + Data Protection writes) (+26 more)

### Community 20 - "Syncing Persistence Store"
Cohesion: 0.11
Nodes (12): CloudSyncPreferenceTests, SyncingPersistenceStoreTests, InMemoryCloudSyncPreference, InMemoryTombstoneStore, .tombstoneIDs, RecordingCloud, Bool, Date (+4 more)

### Community 21 - "Home View"
Cohesion: 0.08
Nodes (28): DateInterval, HomeView, .completedSessions, .hasOpenShiftToday, .monthShiftCount, .todayHours, .todayWeekdayIndex, .weekDailyHours (+20 more)

### Community 22 - "Home Motion Demo Script"
Cohesion: 0.14
Nodes (30): FreeTypeFont, PayslipPDFThumbnail, .body, .previewBlock, PDFPage, URL, .pickView, Image (+22 more)

### Community 23 - "Export Manager"
Cohesion: 0.25
Nodes (10): ExportManager, .isRTL, ExportReport, Bool, CGFloat, DateFormatter, Double, String (+2 more)

### Community 24 - "Payslip LLM Models"
Cohesion: 0.13
Nodes (12): PayslipLLMFields, PayslipLLMStructureResult, .hasAnyPrimaryValue, Bool, PayslipLLMProviding, PayslipLLMRouter, Bool, String (+4 more)

### Community 25 - "Home Stat Layout Metrics"
Cohesion: 0.09
Nodes (21): HomeAccentTheme, .accent, HomeStatMetric, .id, month, monthPay, .title, today (+13 more)

### Community 26 - "Timesheet Scanner View"
Cohesion: 0.10
Nodes (21): ScannedDraftEditor, .body, ScannedDraftRow, .body, ScannerProcessingDetailsSheet, .body, ScannerSkeletonView, .body (+13 more)

### Community 27 - "Payslip Thumbnail Cache"
Cohesion: 0.13
Nodes (13): PayslipThumbnailCache, .directoryURL, CGFloat, FileManager, UIImage, URL, UUID, Void (+5 more)

### Community 28 - "History View"
Cohesion: 0.15
Nodes (16): EdgeInsets, HistoryView, .body, .emptyState, .filteredSessions, .historyChrome, .historyTableInsets, .periodWeeks (+8 more)

### Community 29 - "Full Data Export Manager"
Cohesion: 0.11
Nodes (10): FullDataExportManager, .isRTL, Bool, Date, DateFormatter, Double, URL, FullDataExportManagerTests (+2 more)

### Community 30 - "Persistence Manager (cont.)"
Cohesion: 0.14
Nodes (8): CorruptFileQuarantineTests, URL, ProtectedFileWriterTests, RecordingFileWriter, .writingOptions, ScriptedDataReader, Error, URL

### Community 31 - "Scanner LLM Models"
Cohesion: 0.12
Nodes (19): LocalHeuristicScannerLLMProvider, String, ScannerLLMError, emptyResult, invalidResponse, missingAPIKey, network, quotaExceeded (+11 more)

### Community 32 - "Payslip Library View Model"
Cohesion: 0.11
Nodes (20): PayslipRecord, .effectiveGrossPay, .effectiveNetPay, Int, UUID, PayslipLibraryViewModel, .sortOption, PayslipSortOption (+12 more)

### Community 34 - "Workplace Settings Coding Keys"
Cohesion: 0.07
Nodes (28): CodingKeys, arrivalRemindersEnabled, birthDate, contractorName, currencyCode, dailyGasAllowance, defaultBreakMinutes, employeeNumber (+20 more)

### Community 35 - "CloudKit Sync Manager"
Cohesion: 0.15
Nodes (13): CKContainer, CKDatabase, CKError, CKRecord, CloudKitSyncManager, .database, .isCloudKitBuildEnabled, .isRunningTests (+5 more)

### Community 36 - "Syncing Persistence Store (cont.)"
Cohesion: 0.12
Nodes (10): AnyObject, CloudSyncing, PersistableStore, Bool, Set, UUID, SyncingPersistenceStore, .isCloudSyncSupported (+2 more)

### Community 37 - "Workplace Settings Model"
Cohesion: 0.11
Nodes (15): SyncResult, Bool, Calendar, Date, Decoder, Double, Int, Set (+7 more)

### Community 38 - "Session Tombstone Store"
Cohesion: 0.15
Nodes (13): SessionTombstone, SessionTombstoneStore, .fileURL, .tombstoneIDs, SessionTombstoneStoring, Date, FileManager, Set (+5 more)

### Community 39 - "Payslip Upload Review View"
Cohesion: 0.15
Nodes (17): PayslipUploadReviewView, .body, .confidenceRow, .phaseContent, .processingView, .reviewForm, Binding, Date (+9 more)

### Community 40 - "App ViewModel Delete-Data Test"
Cohesion: 0.17
Nodes (8): ImportConflictTests, ICloudSyncViewModelTests, PayRulesViewModelTests, InMemoryStore, MockLocationReminderManager, CLAuthorizationStatus, Double, XCTestCase

### Community 41 - "Activity Log Store"
Cohesion: 0.16
Nodes (23): ActivityLogEntry, ActivityLogLevel, error, success, warning, clear(), export(), load() (+15 more)

### Community 42 - "Export Day Type Filter"
Cohesion: 0.10
Nodes (20): ExportDayTypeFilter, all, .dayTypes, holiday, .id, .label, regular, sick (+12 more)

### Community 43 - "App View Model (cont.)"
Cohesion: 0.13
Nodes (12): .shouldOfferForgotClockIn, ScannerImportPhase, failed, idle, processing, ready, Bool, Calendar (+4 more)

### Community 44 - "Zip Writer Utility"
Cohesion: 0.18
Nodes (10): Compression, Data, Entry, Int, String, URL, ZipWriter, ZipWriterBoundsTests (+2 more)

### Community 45 - "Overtime Calculator"
Cohesion: 0.19
Nodes (13): DayPayBreakdown, .formattedGrossPay, .formattedNetPay, .formattedTotalPay, .grossPay, OvertimeCalculator, RateTiers, Calendar (+5 more)

### Community 47 - "Timesheet Scanner Manager"
Cohesion: 0.26
Nodes (5): Calendar, Int, String, TimesheetScannerManager, TimesheetScannerParserTests

### Community 48 - "Shift Detail Sheet"
Cohesion: 0.18
Nodes (13): .stickySummaryBar, GrossNetBadge, .body, ShiftDetailSheet, .body, .breakdownCard, .entrySourceLabel, .header (+5 more)

### Community 49 - "Location Capture Helper"
Cohesion: 0.11
Nodes (8): CoreLocation, Foundation, CorruptFileQuarantine, LocationCaptureError, denied, .errorDescription, String, UserNotifications

### Community 50 - "Home Week Sparkline"
Cohesion: 0.23
Nodes (14): CGPoint, .body, HomeWeekSparkline, .chart, .hours, .weekdayRow, .weekTotal, MiniWaveSparkline (+6 more)

### Community 51 - "Payslip Review Draft"
Cohesion: 0.14
Nodes (9): Combine, Keyboard, PayslipReviewDraft, .empty, ImageIO, PDFKit, PhotosUI, SwiftUI (+1 more)

### Community 52 - "Payslip LLM Models (cont.)"
Cohesion: 0.10
Nodes (20): CodingKeys, amount, confidence, currency, deductionLines, deductionsTotal, employeeName, employerName (+12 more)

### Community 53 - "Full Data Export Format"
Cohesion: 0.11
Nodes (19): CaseIterable, FullDataExportFormat, csvZip, .detail, .fileExtension, .id, json, .localizedName (+11 more)

### Community 54 - "Payslip LLM Models (cont. 2)"
Cohesion: 0.24
Nodes (11): PayslipLLMDeductionLine, PayslipLLMLenientDecoding, PayslipLLMOvertimeLine, PayslipReviewEvaluator, Date, Decoder, Double, Int (+3 more)

### Community 55 - "Scanned Session Draft"
Cohesion: 0.20
Nodes (11): ScannerProcessingDetails, .summaryLine, Int, ScannedSessionDraft, .totalHours, Bool, Date, Double (+3 more)

### Community 56 - "Manual Entry View"
Cohesion: 0.13
Nodes (12): Double, ManualEntryView, .body, .isValid, Bool, Double, EditSessionView, .body (+4 more)

### Community 57 - "Payslip Upload View Model"
Cohesion: 0.13
Nodes (12): FillMode, automatic, manual, PayslipUploadViewModel, .canSave, .confidencePercent, .needsManualReview, Bool (+4 more)

### Community 58 - "Timesheet Scanner Manager (cont.)"
Cohesion: 0.17
Nodes (7): CGImage, Int64, PDFPage, UIImage, URL, UTType, TimesheetScannerBoundsTests

### Community 59 - "CloudKit Sync Manager (cont.)"
Cohesion: 0.22
Nodes (4): Set, UUID, CloudWriteQueue, Sendable

### Community 60 - "History Period Helper (cont.)"
Cohesion: 0.20
Nodes (8): Double, .heights, Bool, Calendar, Date, Double, Int, WeekDailyHoursTests

### Community 61 - "Payslip Review Draft (cont.)"
Cohesion: 0.22
Nodes (9): PayslipReviewDraft, .canSave, .hasAmount, .hasPeriod, .resolvedPeriodMonth, Date, Decimal, Double (+1 more)

### Community 62 - "Protected File Migration"
Cohesion: 0.13
Nodes (6): ActivityLogStore, FileProtectionType, ProtectedFileMigration, FileManager, URL, ActivityLogStoreTests

### Community 63 - "Local Heuristic Payslip LLM Provider"
Cohesion: 0.33
Nodes (4): LocalHeuristicPayslipLLMProvider, Bool, Double, String

### Community 64 - "OpenAI-Compatible Payslip LLM Provider"
Cohesion: 0.18
Nodes (8): OpenAICompatiblePayslipLLMProvider, PayslipCloudRequestInspector, Any, Bool, Set, String, URL, URLSession

### Community 65 - "Payslip Store Tests"
Cohesion: 0.23
Nodes (5): FailingDataReader, PayslipStoreTests, StubPDFInspector, Error, URL

### Community 66 - "Export Format"
Cohesion: 0.12
Nodes (15): ExportError, .errorDescription, zipFailed, ExportFormat, csv, docx, .fileExtension, .id (+7 more)

### Community 67 - "Export Temp File Store"
Cohesion: 0.22
Nodes (6): ExportTempFileStore, .exportsDirectory, FileManager, String, URL, ExportTempFileStoreTests

### Community 68 - "App Lock Controller"
Cohesion: 0.27
Nodes (7): AppLockControllerTests, MemoryPreference, StubAuth, Bool, Error, Result, String

### Community 69 - "Timesheet Scanner View Model"
Cohesion: 0.20
Nodes (10): Sendable, UIImage, URL, Int, PhotosPickerItem, UIImage, URL, .body (+2 more)

### Community 70 - "Persistence Load Result"
Cohesion: 0.13
Nodes (10): PersistenceLoadResult, corruptQuarantined, loaded, missing, temporarilyUnavailable, KeychainStoreError, unhandledStatus, os (+2 more)

### Community 71 - "History Period Helper (cont. 2)"
Cohesion: 0.19
Nodes (6): Locale, .periodChrome, .activePeriod, .weekDayLabels, .payrollSection, PayrollPeriodTests

### Community 72 - "Day Summary Sheet"
Cohesion: 0.18
Nodes (10): DaySummarySheet, .body, .body, HomeAuroraCanvas, HomeAuroraRibbon, .body, HomeBrandTitle, .body (+2 more)

### Community 73 - "Forgot Clock-In Sheet"
Cohesion: 0.16
Nodes (12): ClosedRange, ForgotClockInSheet, .arrivalRange, .body, .pickArrivalContent, .timeFormatter, Step, confirm (+4 more)

### Community 74 - "CloudKit Sync State"
Cohesion: 0.15
Nodes (10): CloudKit, NoOpCloudSyncManager, Bool, String, SyncState, failed, idle, synced (+2 more)

### Community 75 - "Israeli Tax Estimator"
Cohesion: 0.29
Nodes (6): IsraeliTaxEstimator, MonthlyDeductions, .total, Bool, Double, TaxCreditApplicationTests

### Community 76 - "Home View (Swift file)"
Cohesion: 0.15
Nodes (11): ButtonStyle, Configuration, LiveTimerView, .body, .elapsedFormatted, ScalePressButtonStyle, CGFloat, Date (+3 more)

### Community 78 - "App Lock Policy"
Cohesion: 0.19
Nodes (6): AppLockPolicy, Date, String, TimeInterval, .workerSection, AppLockPolicyTests

### Community 79 - "Backup Content Dirty Flag"
Cohesion: 0.17
Nodes (4): BackupContentDirtyFlag, Bool, PayslipUploadViewModelTests, URL

### Community 80 - "History Pay Breakdown Sheet"
Cohesion: 0.18
Nodes (8): HistoryPayBreakdownSheet, .body, Bool, String, Double, String, TaxDeductionsCard, .body

### Community 81 - "Activity Log View"
Cohesion: 0.22
Nodes (9): ActivityLogView, .body, String, ShareableFile, URL, FullDataExportSheet, .body, String (+1 more)

### Community 82 - "Camera Picker View"
Cohesion: 0.26
Nodes (7): CameraPickerView, Coordinator, Any, Context, UIImagePickerController, UIImagePickerControllerDelegate, UINavigationControllerDelegate

### Community 83 - "OpenAI-Compatible Scanner LLM Provider"
Cohesion: 0.23
Nodes (7): OpenAICompatibleEndpoint, String, URL, OpenAICompatibleScannerLLMProvider, String, URL, URLSession

### Community 84 - "Export Language"
Cohesion: 0.17
Nodes (10): ExportLanguage, arabic, english, hebrew, .id, phone, .resolvedLanguage, .resolvedLocale (+2 more)

### Community 85 - "Export Sanitizer"
Cohesion: 0.29
Nodes (3): ExportSanitizer, String, ExportSanitizerTests

### Community 86 - "App Lock View"
Cohesion: 0.22
Nodes (9): App, HoursTrackerApp, .body, MainTabView, AppLockView, .body, PrivacyOverlayView, .body (+1 more)

### Community 87 - "Payslip Store Error"
Cohesion: 0.20
Nodes (9): Error, PayslipStoreError, .errorDescription, passwordProtectedPDF, recordNotFound, temporarilyUnavailable, unreadablePDF, unsupportedFileType (+1 more)

### Community 88 - "Payslip PDF Inspection Result"
Cohesion: 0.27
Nodes (8): Calendar, PayslipPDFInspecting, PayslipPDFInspectionResult, locked, unlocked, unreadable, PDFKitPayslipPDFInspector, PDFDocument

### Community 89 - "Work Session Model (cont.)"
Cohesion: 0.31
Nodes (4): ClockTimeResolutionTests, Calendar, Date, Int

### Community 90 - "Timesheet Scanner View (cont.)"
Cohesion: 0.18
Nodes (10): DateFormatter, .dayNumberFormatter, .timeFormatter, .timeFormatter, .syncDateFormatter, .dateFormatter, .timeFormatter, .dateFormatter (+2 more)

### Community 91 - "App Lock Auth Error"
Cohesion: 0.22
Nodes (9): AppLockAuthError, .errorDescription, failed, unavailable, BiometricAuthenticating, LocalAuthenticationService, Bool, String (+1 more)

### Community 92 - "Keyboard Tap Dismiss Installer"
Cohesion: 0.20
Nodes (8): KeyboardTapDismissInstaller, Bool, NSObject, UIGestureRecognizer, UIGestureRecognizerDelegate, UITapGestureRecognizer, UITouch, UIWindow

### Community 93 - "Month/Year Picker"
Cohesion: 0.35
Nodes (9): MonthYearPicker, .body, .monthBinding, .yearBinding, .years, Binding, Date, Int (+1 more)

### Community 94 - "Payslip Upload View Model (cont.)"
Cohesion: 0.33
Nodes (5): Task, UIImage, URL, UTType, minimalPNGData()

### Community 95 - "Activity Log Export Format"
Cohesion: 0.22
Nodes (9): ActivityLogExportFormat, csv, .fileExtension, .id, json, .localizedName, markdown, txt (+1 more)

### Community 96 - "Export Date Range"
Cohesion: 0.22
Nodes (7): ExportDateRange, all, custom, month, year, Date, Int

### Community 97 - "Gemini Scanner LLM Provider"
Cohesion: 0.36
Nodes (4): GeminiScannerLLMProvider, String, URLSession, GeminiJSONExtractTests

### Community 98 - "App Lock Controller (cont.)"
Cohesion: 0.28
Nodes (7): AppLockPreferencing, AppLockController, .isEnabled, Bool, Date, String, ScenePhase

### Community 99 - "Export Layout"
Cohesion: 0.31
Nodes (4): ExportLayout, Bool, String, T

### Community 100 - "Export Share Sheet"
Cohesion: 0.28
Nodes (6): ShareSheet, Any, Context, Void, UIActivityViewController, UIViewControllerRepresentable

### Community 101 - "Gemini Payslip LLM Provider"
Cohesion: 0.50
Nodes (3): GeminiPayslipLLMProvider, String, URLSession

### Community 102 - "Timesheet Scanner Error"
Cohesion: 0.25
Nodes (7): TimesheetScannerError, .errorDescription, fileTooLarge, imageDecodeFailed, pdfRenderFailed, unsupportedFile, Vision

### Community 103 - "Smart Scanner Cloud Preference"
Cohesion: 0.32
Nodes (5): SmartScannerCloudPreferencing, Bool, UserDefaults, UserDefaultsSmartScannerCloudPreference, .isEnabled

### Community 104 - "Launch Hourglass Splash"
Cohesion: 0.25
Nodes (6): .doorScene, HomeNeon, .body, LaunchHourglassSplash, .body, Content

### Community 105 - "Import Conflict Popup"
Cohesion: 0.25
Nodes (7): ImportConflictPopup, .calendar, .dateFormatter, Calendar, Date, DateFormatter, Void

### Community 106 - "Success Toast Banner"
Cohesion: 0.33
Nodes (4): .body, SuccessToastBanner, .body, String

### Community 107 - "Marital Status Model"
Cohesion: 0.33
Nodes (5): MaritalStatus, .displayName, .id, married, single

### Community 108 - "App Lock Preference (UserDefaults)"
Cohesion: 0.40
Nodes (4): Bool, UserDefaults, UserDefaultsAppLockPreference, .isEnabled

### Community 109 - "Cloud Sync Preference (UserDefaults)"
Cohesion: 0.40
Nodes (4): Bool, UserDefaults, UserDefaultsCloudSyncPreference, .isEnabled

### Community 110 - "Privacy Policy View"
Cohesion: 0.40
Nodes (4): PrivacyPolicyView, .body, String, .aboutSection

### Community 111 - "Persistence Load Error"
Cohesion: 0.40
Nodes (4): PersistenceLoadError, .errorDescription, temporarilyUnavailable, String

### Community 112 - "Corrupt File Quarantine"
Cohesion: 0.40
Nodes (3): Date, FileManager, URL

### Community 113 - "Keyboard Dismiss Modifier"
Cohesion: 0.40
Nodes (3): KeyboardDismissModifier, Content, ViewModifier

### Community 114 - "Payslip Upload View Phase"
Cohesion: 0.40
Nodes (5): Phase, failed, pick, processing, review

### Community 115 - "Timesheet Scanner View Phase"
Cohesion: 0.40
Nodes (5): Phase, failed, pick, processing, review

### Community 116 - "Home Accent Theme Color"
Cohesion: 0.50
Nodes (3): .hexString, Double, UIColor

### Community 117 - "Payslip Upload Error"
Cohesion: 0.50
Nodes (3): PayslipUploadError, cannotSaveIncomplete, .errorDescription

## Knowledge Gaps
- **384 isolated node(s):** `success`, `warning`, `txt`, `json`, `csv` (+379 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **4 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `L10n` connect `Localization Strings (L10n)` to `Blank Timesheet Entry View`, `Export Day Type Filter`, `App View Model (cont.)`, `Payslip Detail View`, `History Pay Breakdown Sheet`, `Location Capture Helper`, `Localization Strings (L10n) Cont.`, `Manual Entry View`?**
  _High betweenness centrality (0.150) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Location Capture Helper` to `Settings View`, `Israeli ID Validator`, `App Language Preference`, `Scanner Row Validator`, `Payslip Store`, `Tax Credit Points Calculator`, `Full Data Export/Import Errors`, `Work Session Model`, `History Period Helper`, `Persistence Manager (cont.)`, `Scanner LLM Models`, `Syncing Persistence Store (cont.)`, `Session Tombstone Store`, `Activity Log Store`, `Zip Writer Utility`, `Overtime Calculator`, `Payslip Review Draft`, `Payslip LLM Models (cont. 2)`, `CloudKit Sync Manager (cont.)`, `OpenAI-Compatible Payslip LLM Provider`, `Export Format`, `Persistence Load Result`, `CloudKit Sync State`, `Israeli Tax Estimator`, `App Lock Policy`, `Backup Content Dirty Flag`, `OpenAI-Compatible Scanner LLM Provider`, `Export Language`, `Export Sanitizer`, `Payslip PDF Inspection Result`, `App Lock Auth Error`, `Gemini Scanner LLM Provider`, `Export Layout`, `Gemini Payslip LLM Provider`, `Timesheet Scanner Error`, `Smart Scanner Cloud Preference`, `Marital Status Model`, `Persistence Load Error`, `Payslip Upload Error`?**
  _High betweenness centrality (0.143) - this node is a cross-community bridge._
- **Why does `WorkplaceSettings` connect `Workplace Settings Model` to `Export Copy & Localization`, `Location Reminder Manager`, `Settings View`, `Israeli ID Validator`, `Tax Credit Points Calculator`, `App View Model`, `Persistence Manager`, `Full Data Export/Import Errors`, `Work Session Model`, `Syncing Persistence Store`, `Export Manager`, `Full Data Export Manager`, `Export Manager (cont.)`, `Workplace Settings Coding Keys`, `CloudKit Sync Manager`, `Syncing Persistence Store (cont.)`, `Payslip Upload Review View`, `App ViewModel Delete-Data Test`, `App View Model (cont.)`, `Overtime Calculator`, `Location Capture Helper`, `Payslip Upload View Model`, `CloudKit Sync Manager (cont.)`, `Payslip Review Draft (cont.)`, `Persistence Load Result`, `Forgot Clock-In Sheet`, `CloudKit Sync State`, `Israeli Tax Estimator`, `CloudKit Sync Manager (cont. 2)`, `Marital Status Model`?**
  _High betweenness centrality (0.112) - this node is a cross-community bridge._
- **Are the 7 inferred relationships involving `WorkSession` (e.g. with `.hasAnySessionToday()` and `.hasOpenSession()`) actually correct?**
  _`WorkSession` has 7 INFERRED edges - model-reasoned connections that need verification._
- **Are the 22 inferred relationships involving `AppViewModel` (e.g. with `ExportManager` and `LocationCaptureHelper`) actually correct?**
  _`AppViewModel` has 22 INFERRED edges - model-reasoned connections that need verification._
- **What connects `success`, `warning`, `txt` to the rest of the system?**
  _384 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Localization Strings (L10n)` be split into smaller, more focused modules?**
  _Cohesion score 0.009767965866053023 - nodes in this community are weakly interconnected._