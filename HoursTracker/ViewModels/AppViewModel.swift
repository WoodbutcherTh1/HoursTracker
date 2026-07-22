import Foundation
import CoreLocation
import UserNotifications

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var sessions: [WorkSession] = []
    @Published var settings: WorkplaceSettings = .default
    @Published var lastCompletedBreakdown: DayPayBreakdown?
    /// Session that was just clocked out; used by the day-summary sheet to delete only that shift.
    @Published private(set) var lastCompletedSessionID: UUID?
    @Published var showDaySummary = false
    @Published private(set) var syncState: SyncState = .idle
    @Published var errorMessage: String?
    @Published private(set) var successToast: String?
    @Published private(set) var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var areLocationNotificationsDenied = false

    private let store: SyncingStore
    private let locationManager: LocationReminderManaging
    private let exportManager = ExportManager()
    private let locationCapture = LocationCaptureHelper()
    private var successToastTask: Task<Void, Never>?

    /// Hide the Settings sync section when this build has no CloudKit backend.
    var isCloudSyncSupported: Bool { store.isCloudSyncSupported }

    /// User opt-in for private iCloud sync (default off).
    var isICloudSyncEnabled: Bool {
        get { store.isICloudSyncEnabled }
        set { store.isICloudSyncEnabled = newValue }
    }

    func refreshLocationPermissionStatuses() {
        locationAuthorizationStatus = locationManager.authorizationStatus
        locationManager.refreshPermissionStatuses()
        areLocationNotificationsDenied = locationManager.areNotificationsDenied
        // Notification settings arrive asynchronously; re-read shortly after.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            areLocationNotificationsDenied = locationManager.areNotificationsDenied
            locationAuthorizationStatus = locationManager.authorizationStatus
        }
    }

    var isSyncing: Bool {
        if case .syncing = syncState { return true }
        return false
    }

    var locationUpdates: Published<CLLocation?>.Publisher {
        locationCapture.$lastLocation
    }

    var locationCaptureErrors: Published<Error?>.Publisher {
        locationCapture.$error
    }

    /// Brief green confirmation for successful user actions (save, delete, import).
    func showSuccessToast(_ message: String) {
        successToastTask?.cancel()
        successToast = message
        successToastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            if successToast == message {
                successToast = nil
            }
        }
    }

    init(
        store: SyncingStore = SyncingPersistenceStore.shared,
        locationManager: LocationReminderManaging = LocationReminderManager.shared
    ) {
        self.store = store
        self.locationManager = locationManager
        syncState = store.syncState
        load()
        refreshReminders()
        refreshLocationPermissionStatuses()
    }

    // MARK: - Active Session

    /// The most recent open session, regardless of which day it started on.
    /// A session left open past midnight must stay reachable so it can still
    /// be clocked out from the Home tab.
    var activeSession: WorkSession? {
        sessions
            .filter(\.isOpen)
            .max { $0.clockIn < $1.clockIn }
    }

    var isClockedIn: Bool {
        activeSession != nil
    }

    /// Clock In is available whenever there is no open session (multiple completed
    /// shifts on the same calendar day are allowed).
    var canClockIn: Bool {
        activeSession == nil
    }

    /// Compatibility alias used by older phase-1 tests / call sites.
    var canClockInToday: Bool {
        canClockIn
    }

    // MARK: - Clock In / Out

    /// Start an open shift. `at` defaults to now; pass an earlier time for late / forgotten clock-in.
    /// Arrival is clamped so it cannot be in the future. Uses the same persist + tombstone path
    /// as a normal clock-in (no parallel save route).
    @discardableResult
    func clockIn(at date: Date = Date(), isManual: Bool = false) -> Bool {
        let previousSessions = sessions
        guard canClockIn else { return false }
        let clockInDate = min(date, Date())
        let session = WorkSession(
            date: Calendar.current.startOfDay(for: clockInDate),
            clockIn: clockInDate,
            clockOut: nil,
            isManualEntry: isManual,
            dayType: DayType.automatic(for: clockInDate, settings: settings)
        )
        sessions.append(session)
        guard persist() else {
            restoreSessions(previousSessions)
            return false
        }
        ActivityLogStore.shared.log(
            L10n.logEventClockIn,
            level: .success,
            category: "clock",
            details: ISO8601DateFormatter().string(from: clockInDate)
        )
        return true
    }

    /// Offer “forgot to clock in?” when:
    /// - there is no open shift,
    /// - there is no completed shift yet today,
    /// - today is not a configured rest day,
    /// - local time is at least 30 minutes past the app’s typical 08:00 start.
    var shouldOfferForgotClockIn: Bool {
        Self.shouldOfferForgotClockIn(
            now: Date(),
            sessions: sessions,
            settings: settings
        )
    }

    static func shouldOfferForgotClockIn(
        now: Date,
        sessions: [WorkSession],
        settings: WorkplaceSettings,
        calendar: Calendar = .current,
        // TODO(expectedShiftStart): Temporary hardcoded typical start (08:00) + grace.
        // WorkplaceSettings has no expected shift-start field yet; keep this until we add an
        // optional `expectedShiftStart` setting and drive the forgot-clock-in threshold from it
        // (still with a ~30–45 min grace after the configured time). See PR #14 discussion.
        typicalStartHour: Int = 8,
        graceMinutes: Int = 30
    ) -> Bool {
        if sessions.contains(where: \.isOpen) { return false }

        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: now)
        if settings.isRestDayWeekday(weekday) { return false }

        let hasCompletedToday = sessions.contains {
            $0.clockOut != nil && calendar.isDate($0.date, inSameDayAs: today)
        }
        if hasCompletedToday { return false }

        guard
            let typicalStart = calendar.date(
                bySettingHour: typicalStartHour,
                minute: 0,
                second: 0,
                of: today
            )
        else { return false }
        let threshold = typicalStart.addingTimeInterval(TimeInterval(graceMinutes * 60))
        return now >= threshold
    }

    @discardableResult
    func clockOut() -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == activeSession?.id }) else { return false }
        let previousSessions = sessions
        let clockOutDate = Date()
        sessions[index].clockOut = clockOutDate
        sessions[index].isNightShift = WorkSession.qualifiesAsNightShift(
            clockIn: sessions[index].clockIn,
            clockOut: clockOutDate
        )
        // Long shifts get the configured unpaid break unless one was set already.
        if settings.defaultBreakMinutes > 0,
           sessions[index].breakMinutes == 0,
           sessions[index].totalHours >= 6 {
            sessions[index].breakMinutes = settings.defaultBreakMinutes
        }
        sessions[index].touch()
        // Summarize only the shift just closed (day-aware so same-day OT/gas
        // sharing stays correct, but totals are for this session alone).
        let completedSessionID = sessions[index].id
        let completedBreakdown = OvertimeCalculator.breakdown(
            for: sessions[index],
            in: sessions,
            settings: settings
        )
        guard persist() else {
            restoreSessions(previousSessions)
            return false
        }
        lastCompletedSessionID = completedSessionID
        lastCompletedBreakdown = completedBreakdown
        showDaySummary = true
        ActivityLogStore.shared.log(
            L10n.logEventClockOut,
            level: .success,
            category: "clock",
            details: String(format: "%.2fh", sessions[index].totalHours)
        )
        return true
    }

    func dismissDaySummary() {
        showDaySummary = false
        lastCompletedBreakdown = nil
        lastCompletedSessionID = nil
    }

    // MARK: - Manual Entry

    @discardableResult
    func addManualSession(
        date: Date,
        clockIn: Date,
        clockOut: Date,
        notes: String?,
        breakMinutes: Int = 0,
        dayType: DayType? = nil,
        isNightShift: Bool? = nil
    ) -> Bool {
        let previousSessions = sessions
        // Multiple completed shifts on the same day are allowed (same as clock-in).
        let day = Calendar.current.startOfDay(for: date)

        let resolved = WorkSession.resolveClockPair(clockIn: clockIn, clockOut: clockOut)
        let session = WorkSession(
            date: day,
            clockIn: resolved.clockIn,
            clockOut: resolved.clockOut,
            isManualEntry: true,
            breakMinutes: breakMinutes,
            dayType: dayType ?? DayType.automatic(for: day, settings: settings),
            isNightShift: isNightShift
                ?? WorkSession.qualifiesAsNightShift(clockIn: resolved.clockIn, clockOut: resolved.clockOut),
            notes: notes
        )
        sessions.append(session)
        guard persist() else {
            restoreSessions(previousSessions)
            return false
        }
        ActivityLogStore.shared.log(
            L10n.logEventManualEntry,
            level: .success,
            category: "session",
            details: day.formatted(date: .abbreviated, time: .omitted)
        )
        return true
    }

    @discardableResult
    func importScannedSessions(
        _ drafts: [ScannedSessionDraft],
        overwriteDays: Set<Date> = [],
        markAsAIImported: Bool = true
    ) -> Int? {
        guard !drafts.isEmpty else { return 0 }
        let calendar = Calendar.current
        let overwriteKeys = Set(overwriteDays.map { calendar.startOfDay(for: $0).timeIntervalSince1970 })
        var importedCount = 0
        let previousSessions = sessions

        for draft in drafts where draft.isSelected {
            let resolved = WorkSession.resolveClockPair(clockIn: draft.clockIn, clockOut: draft.clockOut)
            guard resolved.clockOut > resolved.clockIn else { continue }
            let day = calendar.startOfDay(for: draft.date)
            let key = day.timeIntervalSince1970
            let existing = sessions.filter { calendar.isDate($0.date, inSameDayAs: day) }

            if !existing.isEmpty {
                guard overwriteKeys.contains(key) else { continue }
                sessions.removeAll { calendar.isDate($0.date, inSameDayAs: day) }
            }

            var session = draft.toWorkSession(isAIImported: markAsAIImported)
            session.date = day
            session.clockIn = resolved.clockIn
            session.clockOut = resolved.clockOut
            session.dayType = DayType.automatic(for: day, settings: settings)
            session.isNightShift = WorkSession.qualifiesAsNightShift(
                clockIn: resolved.clockIn,
                clockOut: resolved.clockOut
            )
            sessions.append(session)
            importedCount += 1
        }

        guard importedCount > 0 else { return 0 }

        guard persist() else {
            restoreSessions(previousSessions)
            return nil
        }
        ActivityLogStore.shared.log(
            L10n.logEventImport(importedCount),
            level: .success,
            category: "import",
            details: overwriteDays.isEmpty ? nil : L10n.logEventImportOverwrite(overwriteDays.count)
        )
        return importedCount
    }

    func existingCompletedSession(on day: Date) -> WorkSession? {
        let calendar = Calendar.current
        return sessions.first {
            calendar.isDate($0.date, inSameDayAs: day) && $0.clockOut != nil
        }
    }

    func conflictingDays(for drafts: [ScannedSessionDraft]) -> [Date] {
        let calendar = Calendar.current
        var days: [Date] = []
        var seen = Set<TimeInterval>()
        for draft in drafts where draft.isSelected {
            let day = calendar.startOfDay(for: draft.date)
            let key = day.timeIntervalSince1970
            guard seen.insert(key).inserted else { continue }
            if existingCompletedSession(on: day) != nil || sessions.contains(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
                days.append(day)
            }
        }
        return days.sorted()
    }

    @discardableResult
    func updateSession(
        _ session: WorkSession,
        clockIn: Date,
        clockOut: Date?,
        notes: String?,
        breakMinutes: Int? = nil,
        dayType: DayType? = nil,
        isNightShift: Bool? = nil
    ) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return false }
        let previousSessions = sessions
        if let clockOut {
            // The shift editor uses explicit date+time pickers, so the values
            // are authoritative — no swapped-times heuristic here. That
            // correction (`resolveClockPair`) only applies to OCR imports and
            // the same-day wheel pickers of manual entry, where reversed
            // times are genuinely ambiguous.
            sessions[index].clockIn = clockIn
            sessions[index].clockOut = clockOut
            sessions[index].date = Calendar.current.startOfDay(for: clockIn)
            sessions[index].isNightShift = isNightShift
                ?? WorkSession.qualifiesAsNightShift(clockIn: clockIn, clockOut: clockOut)
        } else {
            sessions[index].clockIn = clockIn
            sessions[index].clockOut = nil
            sessions[index].date = Calendar.current.startOfDay(for: clockIn)
            if let isNightShift {
                sessions[index].isNightShift = isNightShift
            }
        }
        sessions[index].notes = notes
        if let breakMinutes {
            sessions[index].breakMinutes = max(0, breakMinutes)
        }
        if let dayType {
            sessions[index].dayType = dayType
        }
        sessions[index].touch()
        guard persist() else {
            restoreSessions(previousSessions)
            return false
        }
        ActivityLogStore.shared.log(
            L10n.logEventSessionUpdated,
            level: .info,
            category: "session"
        )
        return true
    }

    @discardableResult
    func deleteSession(_ session: WorkSession) -> Bool {
        let previousSessions = sessions
        sessions.removeAll { $0.id == session.id }
        guard persist() else {
            restoreSessions(previousSessions)
            return false
        }
        ActivityLogStore.shared.log(
            L10n.logEventSessionDeleted,
            level: .warning,
            category: "session"
        )
        return true
    }

    // MARK: - Settings

    @discardableResult
    func saveSettings(_ newSettings: WorkplaceSettings) -> Bool {
        let previousSettings = settings
        var updated = newSettings
        updated.modifiedAt = Date()
        let remindersJustEnabled = updated.arrivalRemindersEnabled && !settings.arrivalRemindersEnabled
        let remindersJustDisabled = !updated.arrivalRemindersEnabled && settings.arrivalRemindersEnabled
        settings = updated
        guard persistSettings() else {
            restoreSettings(previousSettings)
            return false
        }
        if remindersJustEnabled {
            locationManager.requestArrivalReminderPermissions()
            refreshLocationPermissionStatuses()
            ActivityLogStore.shared.log(
                L10n.logEventRemindersOn,
                level: .info,
                category: "location"
            )
        }
        if remindersJustDisabled {
            locationManager.stopArrivalReminders()
            ActivityLogStore.shared.log(
                L10n.logEventRemindersOff,
                level: .info,
                category: "location"
            )
        }
        refreshReminders()
        ActivityLogStore.shared.log(
            L10n.logEventSettingsSaved,
            level: .info,
            category: "settings"
        )
        return true
    }

    /// Erases all local data and, when CloudKit is supported, remote copies too
    /// (Guideline 5.1.1 data control). National ID Keychain item is cleared via settings reset.
    @discardableResult
    func deleteAllUserData() -> Bool {
        let cloudSessionIDs = Set(sessions.map(\.id))
        do {
            try store.saveSessions([])
            // Avoid re-uploading default settings; cloud purge removes the record instead.
            try store.saveSettingsLocally(.default)
        } catch {
            errorMessage = L10n.errorSaveFailed
            load()
            refreshReminders()
            return false
        }
        sessions = []
        settings = .default
        locationManager.stopArrivalReminders()
        refreshReminders()
        ExportTempFileStore.wipeAll()
        PersistenceManager.shared.wipeQuarantinedSidecars()
        SessionTombstoneStore.shared.removeAll()
        SessionTombstoneStore.shared.wipeQuarantinedSidecars()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        ActivityLogStore.shared.wipeForPrivacy()
        ActivityLogStore.shared.log(
            L10n.logEventDataDeleted,
            level: .warning,
            category: "privacy"
        )

        guard store.isCloudSyncSupported else { return true }
        Task {
            do {
                try await store.purgeCloudData(sessionIDs: cloudSessionIDs)
            } catch {
                errorMessage = L10n.privacyDeleteCloudPartialFailure
            }
        }
        return true
    }

    func captureCurrentLocation() {
        locationCapture.capture()
    }

    func applyCapturedLocationIfAvailable() {
        guard let location = locationCapture.lastLocation else { return }
        applyLocation(location)
    }

    @discardableResult
    private func applyLocation(_ location: CLLocation) -> Bool {
        let previousSettings = settings
        settings.locationLatitude = location.coordinate.latitude
        settings.locationLongitude = location.coordinate.longitude
        settings.modifiedAt = Date()
        guard persistSettings() else {
            restoreSettings(previousSettings)
            return false
        }
        locationManager.updateWorkplaceLocation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            radius: settings.locationRadiusMeters
        )
        refreshReminders()
        ActivityLogStore.shared.log(
            L10n.logEventLocationSet,
            level: .success,
            category: "location"
        )
        return true
    }

    // MARK: - Sync

    func syncNow() {
        guard isICloudSyncEnabled else { return }
        guard !isSyncing else { return }
        syncState = .syncing
        Task {
            do {
                if let result = try await store.syncNow() {
                    sessions = result.sessions
                    settings = result.settings
                    refreshReminders()
                }
                syncState = store.syncState
            } catch {
                syncState = store.syncState
            }
        }
    }

    /// Turns iCloud sync off and optionally erases already-uploaded private-DB copies.
    func disableICloudSync(deleteRemoteData: Bool) {
        isICloudSyncEnabled = false
        guard deleteRemoteData, isCloudSyncSupported else { return }
        let ids = Set(sessions.map(\.id))
        Task {
            do {
                try await store.purgeCloudData(sessionIDs: ids)
            } catch {
                errorMessage = L10n.privacyDeleteCloudPartialFailure
            }
        }
    }

    // MARK: - History

    var sortedSessions: [WorkSession] {
        sessions
            .filter { $0.clockOut != nil }
            .sorted { $0.date > $1.date }
    }

    /// Day-aware: same-day sessions share one daily overtime/gas allowance.
    func breakdown(for session: WorkSession) -> DayPayBreakdown {
        OvertimeCalculator.breakdown(for: session, in: sessions, settings: settings)
    }

    // MARK: - Export

    func export(
        range: ExportDateRange,
        format: ExportFormat,
        language: ExportLanguage = .phone
    ) throws -> URL {
        let report = exportManager.buildReport(
            sessions: sessions,
            settings: settings,
            range: range,
            language: language
        )
        let url = try exportManager.export(report: report, format: format, language: language)
        ActivityLogStore.shared.log(
            L10n.logEventExport,
            level: .success,
            category: "export",
            details: "\(format.fileExtension) / \(String(describing: language))"
        )
        return url
    }

    // MARK: - Private

    private func load() {
        sessions = store.loadSessions()
        settings = store.loadSettings()
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try store.saveSessions(sessions)
            refreshReminders()
            return true
        } catch {
            errorMessage = L10n.errorSaveFailed
            return false
        }
    }

    @discardableResult
    private func persistSettings() -> Bool {
        do {
            try store.saveSettings(settings)
            return true
        } catch {
            errorMessage = L10n.errorSaveFailed
            return false
        }
    }

    private func restoreSessions(_ snapshot: [WorkSession]) {
        sessions = snapshot
        refreshReminders()
    }

    private func restoreSettings(_ snapshot: WorkplaceSettings) {
        settings = snapshot
        refreshReminders()
    }

    private func refreshReminders() {
        locationManager.configure(settings: settings, sessions: sessions)
    }
}
