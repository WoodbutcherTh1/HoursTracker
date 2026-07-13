import Foundation

enum L10n {
    // Tabs
    static var tabHome: String { String(localized: "tab.home") }
    static var tabHistory: String { String(localized: "tab.history") }
    static var tabExport: String { String(localized: "tab.export") }
    static var tabSettings: String { String(localized: "tab.settings") }

    // Home
    static var homeTitle: String { String(localized: "home.title") }
    static var homeReadyToStart: String { String(localized: "home.readyToStart") }
    static var homeClockIn: String { String(localized: "home.clockIn") }
    static var homeClockedIn: String { String(localized: "home.clockedIn") }
    static func homeSince(_ time: String) -> String {
        String(format: String(localized: "home.since %@"), time)
    }
    static var homeClockOut: String { String(localized: "home.clockOut") }
    static var homeShiftComplete: String { String(localized: "home.shiftComplete") }

    // Summary
    static var summaryDayComplete: String { String(localized: "summary.dayComplete") }
    static var summaryRegular: String { String(localized: "summary.regular") }
    static var summaryOT125: String { String(localized: "summary.ot125") }
    static var summaryOT150: String { String(localized: "summary.ot150") }
    static var summaryTodaysPay: String { String(localized: "summary.todaysPay") }
    static var summaryDone: String { String(localized: "summary.done") }

    // History
    static var historyTitle: String { String(localized: "history.title") }
    static var historyEmpty: String { String(localized: "history.empty") }
    static var historyEmptyDescription: String { String(localized: "history.emptyDescription") }

    // Edit
    static var editTitle: String { String(localized: "edit.title") }
    static var editTimes: String { String(localized: "edit.times") }
    static var editClockIn: String { String(localized: "edit.clockIn") }
    static var editClockOut: String { String(localized: "edit.clockOut") }
    static var editNotes: String { String(localized: "edit.notes") }
    static var editNotesPlaceholder: String { String(localized: "edit.notesPlaceholder") }
    static var editDelete: String { String(localized: "edit.delete") }
    static var editCancel: String { String(localized: "edit.cancel") }
    static var editSave: String { String(localized: "edit.save") }

    // Manual
    static var manualTitle: String { String(localized: "manual.title") }
    static var manualDate: String { String(localized: "manual.date") }
    static var manualWorkDay: String { String(localized: "manual.workDay") }
    static var manualEntryMode: String { String(localized: "manual.entryMode") }
    static var manualMode: String { String(localized: "manual.mode") }
    static var manualClockInOut: String { String(localized: "manual.clockInOut") }
    static var manualTotalHours: String { String(localized: "manual.totalHours") }
    static var manualHours: String { String(localized: "manual.hours") }
    static func manualHoursFormat(_ hours: Double) -> String {
        String(format: String(localized: "manual.hoursFormat %@"), String(format: "%.1f", hours))
    }

    // Settings
    static var settingsTitle: String { String(localized: "settings.title") }
    static var settingsSave: String { String(localized: "settings.save") }
    static var settingsWorkerInfo: String { String(localized: "settings.workerInfo") }
    static var settingsFullName: String { String(localized: "settings.fullName") }
    static var settingsIDNumber: String { String(localized: "settings.idNumber") }
    static var settingsEmployeeNumber: String { String(localized: "settings.employeeNumber") }
    static var settingsWorkplace: String { String(localized: "settings.workplace") }
    static var settingsWorkplaceName: String { String(localized: "settings.workplaceName") }
    static var settingsContractor: String { String(localized: "settings.contractor") }
    static var settingsPayHours: String { String(localized: "settings.payHours") }
    static var settingsHourlyRate: String { String(localized: "settings.hourlyRate") }
    static var settingsGasAllowance: String { String(localized: "settings.gasAllowance") }
    static var settingsStandardHours: String { String(localized: "settings.standardHours") }
    static var settingsOTCap: String { String(localized: "settings.otCap") }
    static var settingsLocationReminders: String { String(localized: "settings.locationReminders") }
    static var settingsGeofenceRadius: String { String(localized: "settings.geofenceRadius") }
    static var settingsNoLocation: String { String(localized: "settings.noLocation") }
    static func settingsLocationCoords(lat: Double, lon: Double) -> String {
        String(format: String(localized: "settings.locationCoords %@ %@"),
               String(format: "%.5f", lat), String(format: "%.5f", lon))
    }
    static var settingsSetLocation: String { String(localized: "settings.setLocation") }
    static var settingsLocationUpdated: String { String(localized: "settings.locationUpdated") }
    static var settingsRequestingLocation: String { String(localized: "settings.requestingLocation") }

    // Sync
    static var syncSection: String { String(localized: "sync.section") }
    static var syncNow: String { String(localized: "sync.now") }
    static var syncSyncing: String { String(localized: "sync.syncing") }
    static var syncSynced: String { String(localized: "sync.synced") }
    static var syncUnavailable: String { String(localized: "sync.unavailable") }
    static func syncFailed(_ message: String) -> String {
        String(format: String(localized: "sync.failed %@"), message)
    }
    static func syncLastSync(_ date: String) -> String {
        String(format: String(localized: "sync.lastSync %@"), date)
    }

    // Export
    static var exportTitle: String { String(localized: "export.title") }
    static var exportDateRange: String { String(localized: "export.dateRange") }
    static var exportRange: String { String(localized: "export.range") }
    static var exportAllDays: String { String(localized: "export.allDays") }
    static var exportSpecificMonth: String { String(localized: "export.specificMonth") }
    static var exportCustomRange: String { String(localized: "export.customRange") }
    static var exportMonth: String { String(localized: "export.month") }
    static var exportFrom: String { String(localized: "export.from") }
    static var exportTo: String { String(localized: "export.to") }
    static var exportFormat: String { String(localized: "export.format") }
    static var exportReport: String { String(localized: "export.report") }
    static var exportFormatPDF: String { String(localized: "export.format.pdf") }
    static var exportFormatTXT: String { String(localized: "export.format.txt") }
    static var exportFormatDOCX: String { String(localized: "export.format.docx") }
    static var exportFormatMD: String { String(localized: "export.format.md") }

    // Export report
    static var reportTitle: String { String(localized: "report.title") }
    static var reportAllDays: String { String(localized: "report.allDays") }
    static func reportWorker(_ name: String) -> String {
        String(format: String(localized: "report.worker %@"), name)
    }
    static func reportID(_ id: String) -> String {
        String(format: String(localized: "report.id %@"), id)
    }
    static func reportEmployee(_ num: String) -> String {
        String(format: String(localized: "report.employee %@"), num)
    }
    static func reportWorkplace(_ name: String) -> String {
        String(format: String(localized: "report.workplace %@"), name)
    }
    static func reportContractor(_ name: String) -> String {
        String(format: String(localized: "report.contractor %@"), name)
    }
    static func reportPeriod(_ period: String) -> String {
        String(format: String(localized: "report.period %@"), period)
    }
    static var reportColDate: String { String(localized: "report.col.date") }
    static var reportColIn: String { String(localized: "report.col.in") }
    static var reportColOut: String { String(localized: "report.col.out") }
    static var reportColRegular: String { String(localized: "report.col.regular") }
    static var reportColOT125: String { String(localized: "report.col.ot125") }
    static var reportColOT150: String { String(localized: "report.col.ot150") }
    static var reportColGas: String { String(localized: "report.col.gas") }
    static var reportColTotal: String { String(localized: "report.col.total") }
    static var reportColType: String { String(localized: "report.col.type") }
    static var reportTotal: String { String(localized: "report.total") }

    // Common
    static func hoursShort(_ hours: Double) -> String {
        String(format: String(localized: "common.hoursShort %@"), String(format: "%.1f", hours))
    }
    static func hoursLong(_ hours: Double) -> String {
        String(format: String(localized: "common.hoursLong %@"), String(format: "%.2f", hours))
    }
}
