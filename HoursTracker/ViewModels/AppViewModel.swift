import Foundation
import CoreLocation

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var sessions: [WorkSession] = []
    @Published var settings: WorkplaceSettings = .default
    @Published var lastCompletedBreakdown: DayPayBreakdown?
    @Published var showDaySummary = false
    @Published private(set) var syncState: SyncState = .idle
    @Published var errorMessage: String?

    private let store: SyncingStore
    private let locationManager: LocationReminderManaging
    private let exportManager = ExportManager()
    private let locationCapture = LocationCaptureHelper()

    var isSyncing: Bool {
        if case .syncing = syncState { return true }
        return false
    }

    var locationUpdates: Published<CLLocation?>.Publisher {
        locationCapture.$lastLocation
    }

    init(
        store: SyncingStore = SyncingPersistenceStore.shared,
        locationManager: LocationReminderManaging = LocationReminderManager.shared
    ) {
        self.store = store
        self.locationManager = locationManager
        load()
        self.locationManager.requestPermissions()
        refreshReminders()
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

    func clockIn(isManual: Bool = false) {
        guard canClockIn else { return }
        let now = Date()
        let session = WorkSession(
            date: Calendar.current.startOfDay(for: now),
            clockIn: now,
            clockOut: nil,
            isManualEntry: isManual
        )
        sessions.append(session)
        persist()
        refreshReminders()
    }

    func clockOut() {
        guard let index = sessions.firstIndex(where: { $0.id == activeSession?.id }) else { return }
        sessions[index].clockOut = Date()
        sessions[index].touch()
        let breakdown = OvertimeCalculator.breakdown(for: sessions[index], settings: settings)
        lastCompletedBreakdown = breakdown
        showDaySummary = true
        persist()
        refreshReminders()
    }

    func dismissDaySummary() {
        showDaySummary = false
        lastCompletedBreakdown = nil
    }

    // MARK: - Manual Entry

    func addManualSession(date: Date, clockIn: Date, clockOut: Date, notes: String?) {
        let day = Calendar.current.startOfDay(for: date)
        let hasExisting = sessions.contains { Calendar.current.isDate($0.date, inSameDayAs: day) }
        guard !hasExisting else { return }

        let session = WorkSession(
            date: day,
            clockIn: clockIn,
            clockOut: clockOut,
            isManualEntry: true,
            notes: notes
        )
        sessions.append(session)
        persist()
        refreshReminders()
    }

    /// Thread-safe on MainActor: import selected drafts, optionally overwriting existing days.
    func importScannedSessions(
        _ drafts: [ScannedSessionDraft],
        overwriteDays: Set<Date> = []
    ) {
        guard !drafts.isEmpty else { return }
        let calendar = Calendar.current
        let overwriteKeys = Set(overwriteDays.map { calendar.startOfDay(for: $0).timeIntervalSince1970 })

        for draft in drafts where draft.isSelected {
            guard draft.clockOut > draft.clockIn else { continue }
            let day = calendar.startOfDay(for: draft.date)
            let key = day.timeIntervalSince1970
            let existing = sessions.filter { calendar.isDate($0.date, inSameDayAs: day) }

            if !existing.isEmpty {
                guard overwriteKeys.contains(key) else { continue }
                sessions.removeAll { calendar.isDate($0.date, inSameDayAs: day) }
            }

            var session = draft.toWorkSession()
            session.date = day
            sessions.append(session)
        }

        persist()
        refreshReminders()
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

    func updateSession(_ session: WorkSession, clockIn: Date, clockOut: Date?, notes: String?) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index].clockIn = clockIn
        sessions[index].clockOut = clockOut
        sessions[index].notes = notes
        sessions[index].date = Calendar.current.startOfDay(for: clockIn)
        sessions[index].touch()
        persist()
        refreshReminders()
    }

    func deleteSession(_ session: WorkSession) {
        sessions.removeAll { $0.id == session.id }
        persist()
        refreshReminders()
    }

    // MARK: - Settings

    func saveSettings(_ newSettings: WorkplaceSettings) {
        var updated = newSettings
        updated.modifiedAt = Date()
        settings = updated
        persistSettings()
        refreshReminders()
    }

    func captureCurrentLocation() {
        locationCapture.capture()
    }

    func applyCapturedLocationIfAvailable() {
        guard let location = locationCapture.lastLocation else { return }
        applyLocation(location)
    }

    private func applyLocation(_ location: CLLocation) {
        settings.locationLatitude = location.coordinate.latitude
        settings.locationLongitude = location.coordinate.longitude
        settings.modifiedAt = Date()
        persistSettings()
        locationManager.updateWorkplaceLocation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            radius: settings.locationRadiusMeters
        )
        refreshReminders()
    }

    // MARK: - Sync

    func syncNow() {
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

    // MARK: - History

    var sortedSessions: [WorkSession] {
        sessions
            .filter { $0.clockOut != nil }
            .sorted { $0.date > $1.date }
    }

    func breakdown(for session: WorkSession) -> DayPayBreakdown {
        OvertimeCalculator.breakdown(for: session, settings: settings)
    }

    // MARK: - Export

    func export(range: ExportDateRange, format: ExportFormat) throws -> URL {
        let report = exportManager.buildReport(sessions: sessions, settings: settings, range: range)
        return try exportManager.export(report: report, format: format)
    }

    // MARK: - Private

    private func load() {
        sessions = store.loadSessions()
        settings = store.loadSettings()
    }

    private func persist() {
        do {
            try store.saveSessions(sessions)
        } catch {
            errorMessage = L10n.errorSaveFailed
        }
        refreshReminders()
    }

    private func persistSettings() {
        do {
            try store.saveSettings(settings)
        } catch {
            errorMessage = L10n.errorSaveFailed
        }
    }

    private func refreshReminders() {
        locationManager.configure(settings: settings, sessions: sessions)
    }
}
