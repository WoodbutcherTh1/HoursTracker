import Foundation

enum L10n {
    /// Resolve a catalog key in the active in-app language (immediate, no restart).
    private static func t(_ key: String) -> String {
        AppLocale.tr(key)
    }

    static var brandName: String { t("app.brandName") }

    // Tabs
    static var tabHome: String { t("tab.home") }
    static var tabHistory: String { t("tab.history") }
    static var tabExport: String { t("tab.export") }
    static var tabSettings: String { t("tab.settings") }

    // Home
    static var homeTitle: String { t("home.title") }
    static var homeReadyToStart: String { t("home.readyToStart") }
    static var homeGreetingMorning: String { t("home.greeting.morning") }
    static var homeGreetingAfternoon: String { t("home.greeting.afternoon") }
    static var homeGreetingEvening: String { t("home.greeting.evening") }
    static var homeGreetingNight: String { t("home.greeting.night") }
    static func homeGreetingMorningName(_ name: String) -> String {
        String(format: t("home.greeting.morningName %@"), name)
    }
    static func homeGreetingAfternoonName(_ name: String) -> String {
        String(format: t("home.greeting.afternoonName %@"), name)
    }
    static func homeGreetingEveningName(_ name: String) -> String {
        String(format: t("home.greeting.eveningName %@"), name)
    }
    static func homeGreetingNightName(_ name: String) -> String {
        String(format: t("home.greeting.nightName %@"), name)
    }
    static var homeStatMonth: String { t("home.stat.month") }
    static var homeStatWeek: String { t("home.stat.week") }
    static var homeStatToday: String { t("home.stat.today") }
    static var homeClockIn: String { t("home.clockIn") }
    static var homeClockedIn: String { t("home.clockedIn") }
    static func homeSince(_ time: String) -> String {
        String(format: t("home.since %@"), time)
    }
    static var homeLiveGrossBasic: String { t("home.liveGrossBasic") }
    static var homeLivePay: String { t("home.livePay") }
    static var homeLivePayHint: String { t("home.livePayHint") }
    static var homeWeekLoading: String { t("home.weekLoading") }
    static var homeForgotClockIn: String { t("home.forgotClockIn") }
    static var homeForgotClockInArrivalPrompt: String { t("home.forgotClockIn.arrivalPrompt") }
    static var homeForgotClockInConfirmTitle: String { t("home.forgotClockIn.confirmTitle") }
    static func homeForgotClockInConfirmMessage(_ time: String) -> String {
        String(format: t("home.forgotClockIn.confirmMessage %@"), time)
    }
    static var homeForgotClockInConfirm: String { t("home.forgotClockIn.confirm") }
    static var homeClockOut: String { t("home.clockOut") }
    static var homeShiftComplete: String { t("home.shiftComplete") }
    static func homeWeekTotal(_ hours: String) -> String {
        String(format: t("home.weekTotal %@"), hours)
    }

    // Summary
    static var summaryDayComplete: String { t("summary.dayComplete") }
    static var summaryRegular: String { t("summary.regular") }
    static var summaryOT125: String { t("summary.ot125") }
    static var summaryOT150: String { t("summary.ot150") }
    static var summaryTodaysPay: String { t("summary.todaysPay") }
    static var summaryDone: String { t("summary.done") }
    static var summaryDeleteThisShift: String { t("summary.deleteThisShift") }

    // History
    static var historyTitle: String { t("history.title") }
    static var historyEmpty: String { t("history.empty") }
    static var historyEmptyDescription: String { t("history.emptyDescription") }
    static var historyEmptyPeriod: String { t("history.emptyPeriod") }
    static var historyEmptyPeriodHint: String { t("history.emptyPeriodHint") }
    static var historyShowAllDays: String { t("history.showAllDays") }
    static var historyColDate: String { t("history.col.date") }
    static var historyColIn: String { t("history.col.in") }
    static var historyColOut: String { t("history.col.out") }
    static var historyColHours: String { t("history.col.hours") }
    static var historyColAmount: String { t("history.col.amount") }
    static var historyTotalPay: String { t("history.totalPay") }
    static var historyTotalHours: String { t("history.totalHours") }
    static var historyPayNet: String { t("history.payNet") }
    static var historyPayGross: String { t("history.payGross") }
    static var historyDayHasShifts: String { t("history.dayHasShifts") }
    static var historyDaysWorked: String { t("history.daysWorked") }
    static func historyDaysWorkedAccessibility(_ days: Int) -> String {
        String(format: t("history.daysWorkedAccessibility %lld"), days)
    }
    static var historyDaysWorkedPendingHint: String { t("history.daysWorkedPendingHint") }
    static var historyPayBreakdownButton: String { t("history.payBreakdown.button") }
    static var historyPayBreakdownTitle: String { t("history.payBreakdown.title") }

    // Timesheet scanner
    static var scannerTitle: String { t("scanner.title") }
    static var scannerSubtitle: String { t("scanner.subtitle") }
    static var scannerPhotoLibrary: String { t("scanner.photoLibrary") }
    static var scannerCamera: String { t("scanner.camera") }
    static var scannerFile: String { t("scanner.file") }
    static var scannerAnalyzing: String { t("scanner.analyzing") }
    static var scannerAnalyzingHint: String { t("scanner.analyzingHint") }
    static var scannerFallbackBanner: String { t("scanner.fallbackBanner") }
    static var scannerAddRow: String { t("scanner.addRow") }
    static var scannerReviewHeader: String { t("scanner.reviewHeader") }
    static var scannerReviewFooter: String { t("scanner.reviewFooter") }
    static var scannerApprove: String { t("scanner.approve") }
    static var scannerFailed: String { t("scanner.failed") }
    static var scannerTryAgain: String { t("scanner.tryAgain") }
    static var scannerNeedsEdit: String { t("scanner.needsEdit") }
    static var scannerEditRow: String { t("scanner.editRow") }
    static var scannerImportedNote: String { t("scanner.importedNote") }
    static var scannerManualDraftNote: String { t("scanner.manualDraftNote") }
    static var scannerProcessingDetails: String { t("scanner.processingDetails") }
    static var scannerProcessingProvider: String { t("scanner.processingProvider") }
    static var scannerProcessingAccepted: String { t("scanner.processingAccepted") }
    static var homeThemeTitle: String { t("home.theme.title") }
    static var homeThemePresets: String { t("home.theme.presets") }
    static var homeThemeCustom: String { t("home.theme.custom") }
    static var homeThemeReset: String { t("home.theme.reset") }
    static var homeThemeBackground: String { t("home.theme.background") }
    static var homeThemeBackgroundReset: String { t("home.theme.backgroundReset") }
    static var homeBackgroundMidnight: String { t("home.background.midnight") }
    static var homeBackgroundCharcoal: String { t("home.background.charcoal") }
    static var homeBackgroundGraphite: String { t("home.background.graphite") }
    static var homeBackgroundSlate: String { t("home.background.slate") }
    static var homeBackgroundOnyx: String { t("home.background.onyx") }
    static var homeThemeWordmark: String { t("home.theme.wordmark") }
    static var homeThemeWordmarkPlaceholder: String { t("home.theme.wordmarkPlaceholder") }
    static var homeThemeWordmarkHint: String { t("home.theme.wordmarkHint") }
    static var homeStatsReorderHint: String { t("home.stats.reorderHint") }
    static var homeStatsResetOrder: String { t("home.stats.resetOrder") }
    static var homeStatTodayPay: String { t("home.stat.todayPay") }
    static var homeStatWeekPay: String { t("home.stat.weekPay") }
    static var homeStatMonthPay: String { t("home.stat.monthPay") }
    static var homeStatsCardsTitle: String { t("home.stats.cardsTitle") }
    static var scannerProcessingRejected: String { t("scanner.processingRejected") }
    static var scannerCloudEnabled: String { t("scanner.cloudEnabled") }
    static var scannerCloudPrivacyNotice: String { t("scanner.cloudPrivacyNotice") }
    static var scannerGeminiAPIKey: String { t("scanner.geminiAPIKey") }
    static var scannerGeminiAPIKeyHint: String { t("scanner.geminiAPIKeyHint") }
    static var scannerSecondaryAPIKey: String { t("scanner.secondaryAPIKey") }
    static var scannerSecondaryAPIKeyHint: String { t("scanner.secondaryAPIKeyHint") }
    static var scannerTestKey: String { t("scanner.testKey") }
    static var scannerKeyCheckChecking: String { t("scanner.keyCheck.checking") }
    static var scannerKeyCheckValid: String { t("scanner.keyCheck.valid") }
    static var scannerKeyCheckInvalid: String { t("scanner.keyCheck.invalid") }
    static var scannerKeyCheckNetworkError: String { t("scanner.keyCheck.networkError") }
    static var scannerSection: String { t("scanner.section") }
    static var scannerReadyForReview: String { t("scanner.readyForReview") }
    static var scannerContinueInBackground: String { t("scanner.continueInBackground") }
    static var scannerBackgroundHint: String { t("scanner.backgroundHint") }

    static var scannerConflictTitle: String { t("scanner.conflictTitle") }
    static var scannerConflictReplace: String { t("scanner.conflictReplace") }
    static var scannerConflictKeep: String { t("scanner.conflictKeep") }
    static var scannerConflictApplyAll: String { t("scanner.conflictApplyAll") }
    static var scannerConflictDatesHeader: String { t("scanner.conflictDatesHeader") }
    static func scannerConflictMessage(_ date: String) -> String {
        String(format: t("scanner.conflictMessage %@"), date)
    }

    // Blank timesheet import grid
    static var gridTitle: String { t("grid.title") }
    static var gridImportButton: String { t("grid.importButton") }
    static var gridModeForm: String { t("grid.mode.form") }
    static var gridModeFreeText: String { t("grid.mode.freeText") }
    static var gridColDay: String { t("grid.col.day") }
    static var gridColDate: String { t("grid.col.date") }
    static var gridColIn: String { t("grid.col.in") }
    static var gridColOut: String { t("grid.col.out") }
    static var gridHint: String { t("grid.hint") }
    static var gridFreeTextHint: String { t("grid.freeText.hint") }
    static var gridFreeTextExample: String { t("grid.freeText.example") }
    static var gridAnalyze: String { t("grid.analyze") }
    static var gridAnalyzeEmpty: String { t("grid.analyze.empty") }
    static var gridAnalyzeFailed: String { t("grid.analyze.failed") }
    static func gridAnalyzeSuccess(_ count: Int) -> String {
        String(format: t("grid.analyze.success %lld"), count)
    }
    static var gridAddRow: String { t("grid.addRow") }
    static var gridScan: String { t("grid.scan") }
    static var gridEmptyTime: String { t("grid.emptyTime") }
    static var gridClearTime: String { t("grid.clearTime") }
    static var gridClearRow: String { t("grid.clearRow") }
    static func gridSave(_ count: Int) -> String {
        String(format: t("grid.save %lld"), count)
    }

    // Edit
    static var editTitle: String { t("edit.title") }
    static var editTimes: String { t("edit.times") }
    static var editClockIn: String { t("edit.clockIn") }
    static var editClockOut: String { t("edit.clockOut") }
    static var editNotes: String { t("edit.notes") }
    static var editNotesPlaceholder: String { t("edit.notesPlaceholder") }
    static var editDelete: String { t("edit.delete") }
    static var editDeleteConfirm: String { t("edit.deleteConfirm") }
    static var editCancel: String { t("edit.cancel") }
    static var editSave: String { t("edit.save") }

    // Feedback toasts
    static var feedbackSessionSaved: String { t("feedback.sessionSaved") }
    static var feedbackSessionUpdated: String { t("feedback.sessionUpdated") }
    static var feedbackSessionDeleted: String { t("feedback.sessionDeleted") }
    static var feedbackDataDeleted: String { t("feedback.dataDeleted") }
    static var feedbackLogCleared: String { t("feedback.logCleared") }
    static func feedbackImported(_ count: Int) -> String {
        String(format: t("feedback.imported %lld"), count)
    }

    // Manual
    static var manualTitle: String { t("manual.title") }
    static var manualDate: String { t("manual.date") }
    static var manualWorkDay: String { t("manual.workDay") }
    static var manualEntryMode: String { t("manual.entryMode") }
    static var manualMode: String { t("manual.mode") }
    static var manualClockInOut: String { t("manual.clockInOut") }
    static var manualTotalHours: String { t("manual.totalHours") }
    static var manualHours: String { t("manual.hours") }
    static func manualHoursFormat(_ hours: Double) -> String {
        String(format: t("manual.hoursFormat %@"), String(format: "%.1f", hours))
    }
    static var manualHolidayAutoFilledTitle: String { t("manual.holidayAutoFilledTitle") }
    static var manualHolidayAutoFilledHint: String { t("manual.holidayAutoFilledHint") }
    static var manualSickHint: String { t("manual.sickHint") }
    static func manualSickPreview(_ day: Int, _ percent: Int) -> String {
        String(format: t("manual.sickPreview %lld %lld"), day, percent)
    }

    // Settings
    static var settingsTitle: String { t("settings.title") }
    static var settingsSave: String { t("settings.save") }
    static var settingsSaved: String { t("settings.saved") }
    static var settingsWorkerInfo: String { t("settings.workerInfo") }
    static var settingsFullName: String { t("settings.fullName") }
    static var settingsIDNumber: String { t("settings.idNumber") }
    static var settingsIDChecksumWarning: String { t("settings.idChecksumWarning") }
    static var settingsEditIDNumber: String { t("settings.editIDNumber") }
    static var settingsHideIDNumber: String { t("settings.hideIDNumber") }
    static var settingsIDNumberMasked: String { t("settings.idNumberMasked") }
    static var scannerErrorFileTooLarge: String { t("scanner.error.fileTooLarge") }

    // App Lock / screen privacy
    static var appName: String { t("app.name") }
    static var appLockSection: String { t("appLock.section") }
    static var appLockEnabled: String { t("appLock.enabled") }
    static var appLockHint: String { t("appLock.hint") }
    static var appLockTitle: String { t("appLock.title") }
    static var appLockSubtitle: String { t("appLock.subtitle") }
    static var appLockUnlock: String { t("appLock.unlock") }
    static var appLockReason: String { t("appLock.reason") }
    static var appLockUnavailable: String { t("appLock.unavailable") }
    static var appLockFailed: String { t("appLock.failed") }
    static var privacyOverlayMessage: String { t("privacy.overlayMessage") }
    static var settingsEmployeeNumber: String { t("settings.employeeNumber") }
    static var settingsWorkplace: String { t("settings.workplace") }
    static var settingsWorkplaceName: String { t("settings.workplaceName") }
    static var settingsContractor: String { t("settings.contractor") }
    static var settingsPayHours: String { t("settings.payHours") }
    static var settingsHourlyRate: String { t("settings.hourlyRate") }
    static var settingsGasAllowance: String { t("settings.gasAllowance") }
    static var settingsStandardHours: String { t("settings.standardHours") }
    static var settingsOTCap: String { t("settings.otCap") }
    static var settingsLocationReminders: String { t("settings.locationReminders") }
    static var settingsGeofenceRadius: String { t("settings.geofenceRadius") }
    static var settingsNoLocation: String { t("settings.noLocation") }
    static func settingsLocationCoords(lat: Double, lon: Double) -> String {
        String(format: t("settings.locationCoords %@ %@"),
               String(format: "%.5f", lat), String(format: "%.5f", lon))
    }
    static var settingsSetLocation: String { t("settings.setLocation") }
    static var settingsLocationUpdated: String { t("settings.locationUpdated") }
    static var settingsRequestingLocation: String { t("settings.requestingLocation") }
    static var settingsLocationFailed: String { t("settings.locationFailed") }
    static var settingsLocationDenied: String { t("settings.locationDenied") }
    static var settingsNotificationsDenied: String { t("settings.notificationsDenied") }
    static var settingsOpenSystemSettings: String { t("settings.openSystemSettings") }
    static var settingsArrivalReminders: String { t("settings.arrivalReminders") }
    static var settingsArrivalHint: String { t("settings.arrivalHint") }
    static var settingsArrivalNeedLocation: String { t("settings.arrivalNeedLocation") }
    static var settingsArrivalTitle: String { t("settings.arrivalTitle") }
    static var settingsArrivalBody: String { t("settings.arrivalBody") }
    static var settingsArrivalContinue: String { t("settings.arrivalContinue") }
    static var settingsTools: String { t("settings.tools") }
    static var settingsAbout: String { t("settings.about") }
    static var settingsVersion: String { t("settings.version") }
    static var settingsSupport: String { t("settings.support") }
    static var settingsAppLanguage: String { t("settings.appLanguage") }
    static var settingsLanguageSystem: String { t("settings.language.system") }
    static var settingsAppLanguageHint: String { t("settings.appLanguage.hint") }

    // Sync
    static var syncSection: String { t("sync.section") }
    static var syncEnabled: String { t("sync.enabled") }
    static var syncEnabledHint: String { t("sync.enabledHint") }
    static var syncDisableConfirm: String { t("sync.disableConfirm") }
    static var syncDisableKeepCloud: String { t("sync.disableKeepCloud") }
    static var syncDisableDeleteCloud: String { t("sync.disableDeleteCloud") }
    static var syncNow: String { t("sync.now") }
    static var syncSyncing: String { t("sync.syncing") }
    static var syncSynced: String { t("sync.synced") }
    static var syncUnavailable: String { t("sync.unavailable") }
    static var syncUnavailableHint: String { t("sync.unavailableHint") }
    static func syncFailed(_ message: String) -> String {
        String(format: t("sync.failed %@"), message)
    }
    static func syncLastSync(_ date: String) -> String {
        String(format: t("sync.lastSync %@"), date)
    }

    // Export
    static var exportTitle: String { t("export.title") }
    static var exportDateRange: String { t("export.dateRange") }
    static var exportRange: String { t("export.range") }
    static var exportAllDays: String { t("export.allDays") }
    static var exportThisMonth: String { t("export.thisMonth") }
    static var exportThisYear: String { t("export.thisYear") }
    static var exportSpecificMonth: String { t("export.specificMonth") }
    static var exportCustomRange: String { t("export.customRange") }
    static var exportMonth: String { t("export.month") }
    static var exportFrom: String { t("export.from") }
    static var exportTo: String { t("export.to") }
    static var exportFormat: String { t("export.format") }
    static var exportReport: String { t("export.report") }
    static var exportFormatPDF: String { t("export.format.pdf") }
    static var exportFormatCSV: String { t("export.format.csv") }
    static var exportFormatTXT: String { t("export.format.txt") }
    static var exportFormatDOCX: String { t("export.format.docx") }
    static var exportFormatMD: String { t("export.format.md") }
    static var exportDayType: String { t("export.dayType") }
    static var exportDayTypeAll: String { t("export.dayType.all") }

    static var exportLanguage: String { t("export.language") }
    static func exportLanguagePhone(_ languageName: String) -> String {
        String(format: t("export.language.phone %@"), languageName)
    }
    static var exportLanguageEnglish: String { t("export.language.english") }
    static var exportLanguageHebrew: String { t("export.language.hebrew") }
    static var exportLanguageArabic: String { t("export.language.arabic") }

    static var languageNameArabic: String { t("language.name.arabic") }
    static var languageNameHebrew: String { t("language.name.hebrew") }
    static var languageNameEnglish: String { t("language.name.english") }

    // Export report
    static var reportTitle: String { t("report.title") }
    static var reportAllDays: String { t("report.allDays") }
    static func reportWorker(_ name: String) -> String {
        String(format: t("report.worker %@"), name)
    }
    static func reportID(_ id: String) -> String {
        String(format: t("report.id %@"), id)
    }
    static func reportEmployee(_ num: String) -> String {
        String(format: t("report.employee %@"), num)
    }
    static func reportWorkplace(_ name: String) -> String {
        String(format: t("report.workplace %@"), name)
    }
    static func reportContractor(_ name: String) -> String {
        String(format: t("report.contractor %@"), name)
    }
    static func reportPeriod(_ period: String) -> String {
        String(format: t("report.period %@"), period)
    }
    static var reportColDate: String { t("report.col.date") }
    static var reportColIn: String { t("report.col.in") }
    static var reportColOut: String { t("report.col.out") }
    static var reportColRegular: String { t("report.col.regular") }
    static var reportColOT125: String { t("report.col.ot125") }
    static var reportColOT150: String { t("report.col.ot150") }
    static var reportColGas: String { t("report.col.gas") }
    static var reportColGross: String { t("report.col.gross") }
    static var reportColNet: String { t("report.col.net") }
    static var reportColTotal: String { t("report.col.total") }
    static var reportColType: String { t("report.col.type") }
    static var reportTotal: String { t("report.total") }

    static var reportLegendTitle: String { t("report.legend.title") }
    static var reportLegendDate: String { t("report.legend.date") }
    static var reportLegendIn: String { t("report.legend.in") }
    static var reportLegendOut: String { t("report.legend.out") }
    static var reportLegendRegular: String { t("report.legend.regular") }
    static var reportLegendOT125: String { t("report.legend.ot125") }
    static var reportLegendOT150: String { t("report.legend.ot150") }
    static var reportLegendGas: String { t("report.legend.gas") }
    static var reportLegendGross: String { t("report.legend.gross") }
    static var reportLegendNet: String { t("report.legend.net") }
    static var reportLegendType: String { t("report.legend.type") }

    // Work rules
    static var settingsWorkRules: String { t("settings.workRules") }
    static var settingsRestDay: String { t("settings.restDay") }
    static var settingsSecondRestDay: String { t("settings.secondRestDay") }
    static var settingsSecondRestDayNone: String { t("settings.secondRestDay.none") }
    static var settingsDefaultBreak: String { t("settings.defaultBreak") }
    static var settingsCurrency: String { t("settings.currency") }
    static var settingsWorkRulesNote: String { t("settings.workRulesNote") }
    static var settingsExpectedShiftStart: String { t("settings.expectedShiftStart") }
    static var sessionDayType: String { t("session.dayType") }
    static var sessionNightShift: String { t("session.nightShift") }
    static var sessionBreakMinutes: String { t("session.breakMinutes") }
    static var dayTypeRegular: String { t("dayType.regular") }
    static var dayTypeRestDay: String { t("dayType.restDay") }
    static var dayTypeHoliday: String { t("dayType.holiday") }
    static var dayTypeSick: String { t("dayType.sick") }

    // Errors
    static var errorTitle: String { t("error.title") }
    static var errorSaveFailed: String { t("error.saveFailed") }
    static var errorOK: String { t("error.ok") }

    static var keyboardDone: String { t("keyboard.done") }

    // Privacy
    static var privacyTitle: String { t("privacy.title") }
    static var privacyUpdated: String { t("privacy.updated") }
    static var privacySectionData: String { t("privacy.section.data") }
    static var privacyBodyData: String { t("privacy.body.data") }
    static var privacySectionICloud: String { t("privacy.section.icloud") }
    static var privacyBodyICloud: String { t("privacy.body.icloud") }
    static var privacySectionLocation: String { t("privacy.section.location") }
    static var privacyBodyLocation: String { t("privacy.body.location") }
    static var privacySectionCamera: String { t("privacy.section.camera") }
    static var privacyBodyCamera: String { t("privacy.body.camera") }
    static var privacySectionTracking: String { t("privacy.section.tracking") }
    static var privacyBodyTracking: String { t("privacy.body.tracking") }
    static var privacySectionControls: String { t("privacy.section.controls") }
    static var privacyBodyControls: String { t("privacy.body.controls") }
    static var privacySectionContact: String { t("privacy.section.contact") }
    static var privacyBodyContact: String { t("privacy.body.contact") }
    static var privacyDeleteAll: String { t("privacy.deleteAll") }
    static var privacyDeleteAllConfirm: String { t("privacy.deleteAllConfirm") }
    static var privacyDeleteCloudPartialFailure: String {
        t("privacy.deleteCloudPartialFailure")
    }

    // Activity log
    static var logTitle: String { t("log.title") }
    static var logActions: String { t("log.actions") }
    static var logEntries: String { t("log.entries") }
    static var logEmpty: String { t("log.empty") }
    static var logExport: String { t("log.export") }
    static var logExportFormat: String { t("log.exportFormat") }
    static var logExportHint: String { t("log.exportHint") }
    static var logClear: String { t("log.clear") }
    static var logClearConfirm: String { t("log.clearConfirm") }
    static var logClearedMessage: String { t("log.clearedMessage") }
    static var logFormatTXT: String { t("log.format.txt") }
    static var logFormatJSON: String { t("log.format.json") }
    static var logFormatCSV: String { t("log.format.csv") }
    static var logFormatMarkdown: String { t("log.format.markdown") }
    static var logEventClockIn: String { t("log.event.clockIn") }
    static var logEventClockOut: String { t("log.event.clockOut") }
    static var logEventManualEntry: String { t("log.event.manualEntry") }
    static func logEventImport(_ count: Int) -> String {
        String(format: t("log.event.import %lld"), count)
    }
    static func logEventImportOverwrite(_ count: Int) -> String {
        String(format: t("log.event.importOverwrite %lld"), count)
    }
    static var logEventSessionUpdated: String { t("log.event.sessionUpdated") }
    static var logEventSessionDeleted: String { t("log.event.sessionDeleted") }
    static var logEventRemindersOn: String { t("log.event.remindersOn") }
    static var logEventRemindersOff: String { t("log.event.remindersOff") }
    static var logEventSettingsSaved: String { t("log.event.settingsSaved") }
    static var logEventDataDeleted: String { t("log.event.dataDeleted") }
    static var logEventLocationSet: String { t("log.event.locationSet") }
    static var logEventExport: String { t("log.event.export") }
    static var logEventFullDataExport: String { t("log.event.fullDataExport") }
    static var logEventLogExported: String { t("log.event.logExported") }

    // Full data export (Settings)
    static var fullExportTitle: String { t("fullExport.title") }
    static var fullExportChooseFormat: String { t("fullExport.chooseFormat") }
    static var fullExportFooter: String { t("fullExport.footer") }
    static var fullExportAction: String { t("fullExport.action") }
    static var fullExportPreparing: String { t("fullExport.preparing") }
    static var fullExportSuccess: String { t("fullExport.success") }
    static var fullExportFormatPDF: String { t("fullExport.format.pdf") }
    static var fullExportFormatCSV: String { t("fullExport.format.csv") }
    static var fullExportFormatJSON: String { t("fullExport.format.json") }
    static var fullExportFormatPDFDetail: String { t("fullExport.format.pdf.detail") }
    static var fullExportFormatCSVDetail: String { t("fullExport.format.csv.detail") }
    static var fullExportFormatJSONDetail: String { t("fullExport.format.json.detail") }

    static var fullImportTitle: String { t("fullImport.title") }
    static var fullImportConfirmTitle: String { t("fullImport.confirmTitle") }
    static var fullImportConfirmFallback: String { t("fullImport.confirmFallback") }
    static func fullImportConfirmMessage(_ sessions: Int, _ version: String) -> String {
        String(format: t("fullImport.confirmMessage %lld %@"), sessions, version)
    }
    static var fullImportReplace: String { t("fullImport.replace") }
    static var fullImportMerge: String { t("fullImport.merge") }
    static var fullImportSuccess: String { t("fullImport.success") }
    static var fullImportErrorInvalidFormat: String { t("fullImport.error.invalidFormat") }
    static var fullImportErrorUnsupportedType: String { t("fullImport.error.unsupportedType") }
    static var fullImportErrorEmpty: String { t("fullImport.error.empty") }
    static var logEventFullDataImport: String { t("log.event.fullDataImport") }

    // Payslips (Chunk 4 upload + review)
    static var payslipSectionTitle: String { t("payslip.sectionTitle") }
    static var payslipUploadAction: String { t("payslip.upload.action") }
    static var payslipUploadEntryFooter: String { t("payslip.upload.entryFooter") }
    static var payslipUploadTitle: String { t("payslip.upload.title") }
    static var payslipUploadSubtitle: String { t("payslip.upload.subtitle") }
    static var payslipFillModePrompt: String { t("payslip.fillMode.prompt") }
    static var payslipFillModeAuto: String { t("payslip.fillMode.auto") }
    static var payslipFillModeManual: String { t("payslip.fillMode.manual") }
    static var payslipFillModeSettingsHint: String { t("payslip.fillMode.settingsHint") }
    static var payslipUploadSourceTitle: String { t("payslip.upload.sourceTitle") }
    static var payslipUploadFailed: String { t("payslip.upload.failed") }
    static var payslipUploadNoTextFound: String { t("payslip.upload.noTextFound") }
    static var payslipAnalyzing: String { t("payslip.analyzing") }
    static var payslipAnalyzingHint: String { t("payslip.analyzingHint") }
    static var payslipSave: String { t("payslip.save") }
    static var payslipSaveDisabledHint: String { t("payslip.saveDisabledHint") }
    static var payslipSavedToast: String { t("payslip.savedToast") }
    static var payslipSectionPeriod: String { t("payslip.section.period") }
    static var payslipSectionPay: String { t("payslip.section.pay") }
    static var payslipSectionPeople: String { t("payslip.section.people") }
    static var payslipSectionHours: String { t("payslip.section.hours") }
    static var payslipSectionNotes: String { t("payslip.section.notes") }
    static var payslipPaymentMonth: String { t("payslip.paymentMonth") }
    static var payslipPaymentMonthEnabled: String { t("payslip.paymentMonthEnabled") }
    static var payslipPeriodStart: String { t("payslip.periodStart") }
    static var payslipPeriodStartEnabled: String { t("payslip.periodStartEnabled") }
    static var payslipPeriodEnd: String { t("payslip.periodEnd") }
    static var payslipPeriodEndEnabled: String { t("payslip.periodEndEnabled") }
    static var payslipGross: String { t("payslip.gross") }
    static var payslipNet: String { t("payslip.net") }
    static var payslipCurrency: String { t("payslip.currency") }
    static var payslipDeductions: String { t("payslip.deductions") }
    static var payslipEmployer: String { t("payslip.employer") }
    static var payslipEmployee: String { t("payslip.employee") }
    static var payslipHoursRegular: String { t("payslip.hoursRegular") }
    static var payslipHoursOT: String { t("payslip.hoursOT") }
    static var payslipOvertimeBreakdownTitle: String { t("payslip.section.overtimeBreakdown") }
    static func payslipOvertimeLineLabel(_ ratePercent: Int) -> String {
        String(format: t("payslip.overtimeLineLabel %d"), ratePercent)
    }
    static var payslipDeductionBreakdownTitle: String { t("payslip.section.deductionBreakdown") }
    static var payslipNotes: String { t("payslip.notes") }
    static var payslipConfidence: String { t("payslip.confidence") }
    static var payslipNeedsReview: String { t("payslip.needsReview") }
    static var payslipPreview: String { t("payslip.preview") }
    static var payslipPreviewUnavailable: String { t("payslip.previewUnavailable") }
    static var payslipLibraryTitle: String { t("payslip.library.title") }
    static var payslipSortByDate: String { t("payslip.sort.byDate") }
    static var payslipSortByAmount: String { t("payslip.sort.byAmount") }
    static var payslipSortAccessibility: String { t("payslip.sort.accessibility") }
    static var payslipLibraryEntrySubtitle: String { t("payslip.library.entrySubtitle") }
    static var payslipLibraryEmptyTitle: String { t("payslip.library.emptyTitle") }
    static var payslipLibraryEmptySubtitle: String { t("payslip.library.emptySubtitle") }
    static var payslipNetUnavailable: String { t("payslip.netUnavailable") }
    static var payslipDelete: String { t("payslip.delete") }
    static var payslipDeleteConfirmTitle: String { t("payslip.deleteConfirmTitle") }
    static var payslipDeleteConfirmMessage: String { t("payslip.deleteConfirmMessage") }
    static var payslipDeleteFailed: String { t("payslip.deleteFailed") }
    static var payslipDeletedToast: String { t("payslip.deletedToast") }

    // Common
    static func hoursShort(_ hours: Double) -> String {
        String(format: t("common.hoursShort %@"), String(format: "%.1f", hours))
    }
    static func hoursLong(_ hours: Double) -> String {
        String(format: t("common.hoursLong %@"), String(format: "%.2f", hours))
    }

    // User Guide
    static var guideTitle: String { t("guide.title") }

    // Assistant
    static var assistantTitle: String { t("assistant.title") }
    static var assistantInputPlaceholder: String { t("assistant.inputPlaceholder") }
    static var assistantSend: String { t("assistant.send") }
    static var assistantThinking: String { t("assistant.thinking") }
    static var assistantWelcome: String { t("assistant.welcome") }
    static func assistantWelcomeNamed(_ name: String) -> String {
        String(format: t("assistant.welcomeNamed %@"), name)
    }
    static var assistantWelcomeSubtitle: String { t("assistant.welcomeSubtitle") }
    static var assistantPrivacyNote: String { t("assistant.privacyNote") }
    static var assistantSuggestionOvertime: String { t("assistant.suggestion.overtime") }
    static var assistantSuggestionPayThisMonth: String { t("assistant.suggestion.payThisMonth") }
    static var assistantSuggestionDaysOff: String { t("assistant.suggestion.daysOff") }
    static var assistantSuggestionReport: String { t("assistant.suggestion.report") }
    static var assistantSuggestionPayslip: String { t("assistant.suggestion.payslip") }
    static var assistantOutOfScope: String { t("assistant.outOfScope") }
    static var assistantOutOfScopeHint: String { t("assistant.outOfScopeHint") }
    static var assistantNotConfigured: String { t("assistant.notConfigured") }
    static var assistantNotConfiguredHint: String { t("assistant.notConfiguredHint") }
    static var assistantRateLimited: String { t("assistant.rateLimited") }
    static var assistantNetworkError: String { t("assistant.networkError") }
    static var assistantUnreadable: String { t("assistant.unreadable") }
    static var assistantNoData: String { t("assistant.noData") }
    static var assistantNoDataHint: String { t("assistant.noDataHint") }
    static func assistantHoursHeadline(_ hours: String, _ days: Int) -> String {
        String(format: t("assistant.hoursHeadline %@ %lld"), hours, days)
    }
    static func assistantPayNetHeadline(_ amount: String) -> String {
        String(format: t("assistant.payNetHeadline %@"), amount)
    }
    static func assistantPayGrossHeadline(_ amount: String) -> String {
        String(format: t("assistant.payGrossHeadline %@"), amount)
    }
    static var assistantPayEstimateNote: String { t("assistant.payEstimateNote") }
    static func assistantShiftsHeadline(_ count: Int) -> String {
        String(format: t("assistant.shiftsHeadline %lld"), count)
    }
    static func assistantDaysOffHeadline(_ count: Int) -> String {
        String(format: t("assistant.daysOffHeadline %lld"), count)
    }
    static var assistantNoDaysOff: String { t("assistant.noDaysOff") }
    static func assistantMoreRows(_ count: Int) -> String {
        String(format: t("assistant.moreRows %lld"), count)
    }
    static var assistantDocumentReady: String { t("assistant.documentReady") }
    static var assistantDocumentFailed: String { t("assistant.documentFailed") }
    static func assistantPayslipFound(_ period: String) -> String {
        String(format: t("assistant.payslipFound %@"), period)
    }
    static func assistantPayslipMissing(_ period: String) -> String {
        String(format: t("assistant.payslipMissing %@"), period)
    }
    static var assistantPayslipMissingHint: String { t("assistant.payslipMissingHint") }
    static var assistantView: String { t("assistant.view") }
    static var assistantScopeAllTime: String { t("assistant.scope.allTime") }
    static func assistantScopeAfter(_ time: String) -> String {
        String(format: t("assistant.scope.after %@"), time)
    }
    static func assistantScopeBefore(_ time: String) -> String {
        String(format: t("assistant.scope.before %@"), time)
    }
    static var assistantClear: String { t("assistant.clear") }
    static var assistantSettingsTitle: String { t("assistant.settings.title") }
    static var assistantSettingsEnabled: String { t("assistant.settings.enabled") }
    static var assistantSettingsStyle: String { t("assistant.settings.style") }
    static var assistantSettingsResetPosition: String { t("assistant.settings.resetPosition") }
    static var assistantHideButton: String { t("assistant.hideButton") }
    static var assistantHiddenToast: String { t("assistant.hiddenToast") }
    static var assistantStyleSpark: String { t("assistant.style.spark") }
    static var assistantStyleChat: String { t("assistant.style.chat") }
    static var assistantStyleClock: String { t("assistant.style.clock") }
    static var assistantStyleWand: String { t("assistant.style.wand") }
}
