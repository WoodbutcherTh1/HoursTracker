import Foundation
@testable import HoursTracker

final class InMemoryStore: SyncingStore {
    var storedSessions: [WorkSession] = []
    var storedSettings: WorkplaceSettings = .default
    var saveError: Error?
    var syncState: SyncState = .idle

    func loadSessions() -> [WorkSession] {
        storedSessions
    }

    func saveSessions(_ sessions: [WorkSession]) throws {
        if let saveError { throw saveError }
        storedSessions = sessions
    }

    func loadSettings() -> WorkplaceSettings {
        storedSettings
    }

    func saveSettings(_ settings: WorkplaceSettings) throws {
        if let saveError { throw saveError }
        storedSettings = settings
    }

    func syncNow() async throws -> SyncResult? {
        nil
    }
}

final class MockLocationReminderManager: LocationReminderManaging {
    private(set) var configureCallCount = 0
    private(set) var lastConfiguredSessions: [WorkSession] = []

    func configure(settings: WorkplaceSettings, sessions: [WorkSession]) {
        configureCallCount += 1
        lastConfiguredSessions = sessions
    }

    func requestPermissions() {}

    func updateWorkplaceLocation(latitude: Double, longitude: Double, radius: Double) {}
}

final class RecordingCloud: CloudSyncing {
    var state: SyncState = .idle
    private(set) var uploadedBatches: [[WorkSession]] = []
    private(set) var deletedIDBatches: [Set<UUID>] = []
    var onUpload: (() -> Void)?
    var onDelete: (() -> Void)?

    func checkAvailability() async -> Bool {
        true
    }

    func sync(localSessions: [WorkSession], localSettings: WorkplaceSettings) async throws -> SyncResult {
        SyncResult(sessions: localSessions, settings: localSettings)
    }

    func uploadSessions(_ sessions: [WorkSession]) async {
        uploadedBatches.append(sessions)
        onUpload?()
    }

    func uploadSettings(_ settings: WorkplaceSettings) async {}

    func deleteSessions(ids: Set<UUID>) async {
        deletedIDBatches.append(ids)
        onDelete?()
    }
}

enum TestData {
    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    static func session(
        year: Int = 2026,
        month: Int = 1,
        day: Int,
        inHour: Int = 8,
        outHour: Int? = 16,
        outMinute: Int = 0,
        id: UUID = UUID(),
        modifiedAt: Date = Date()
    ) -> WorkSession {
        WorkSession(
            id: id,
            date: date(year, month, day),
            clockIn: date(year, month, day, inHour),
            clockOut: outHour.map { date(year, month, day, $0, outMinute) },
            isManualEntry: false,
            notes: nil,
            modifiedAt: modifiedAt
        )
    }

    static func settings(hourlyRate: Double = 100) -> WorkplaceSettings {
        WorkplaceSettings(
            workplaceName: "Test",
            contractorName: nil,
            workerFullName: "Worker",
            workerIDNumber: "123",
            employeeNumber: "456",
            hourlyRate: hourlyRate,
            dailyGasAllowance: 35,
            standardDayHours: 8.6,
            ot125HoursCap: 2.0,
            locationLatitude: nil,
            locationLongitude: nil,
            locationRadiusMeters: 150,
            modifiedAt: Date()
        )
    }
}
