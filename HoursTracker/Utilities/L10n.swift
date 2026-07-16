import Foundation

enum L10n {
    private static var locale: Locale { AppLocale.resolvedLocale }

    /// Resolve a catalog key in the active in-app language (immediate, no restart).
    private static func t(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: locale)
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
    static var sessionDayType: String { t("session.dayType") }
    static var sessionNightShift: String { t("session.nightShift") }
    static var sessionBreakMinutes: String { t("session.breakMinutes") }
    static var dayTypeRegular: String { t("dayType.regular") }
    static var dayTypeRestDay: String { t("dayType.restDay") }
    static var dayTypeHoliday: String { t("dayType.holiday") }

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

    // Common
    static func hoursShort(_ hours: Double) -> String {
        String(format: t("common.hoursShort %@"), String(format: "%.1f", hours))
    }
    static func hoursLong(_ hours: Double) -> String {
        String(format: t("common.hoursLong %@"), String(format: "%.2f", hours))
    }
}
