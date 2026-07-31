import Foundation
import CoreLocation
@testable import HoursTracker

final class InMemoryStore: SyncingStore {
    var storedSessions: [WorkSession] = []
    var storedSettings: WorkplaceSettings = .default
    var saveError: Error?
    var syncState: SyncState = .idle
    var isCloudSyncSupported = false
    var isICloudSyncEnabled = false
    private(set) var saveSettingsLocallyCallCount = 0
    private(set) var purgeCloudCallCount = 0
    private(set) var lastPurgedSessionIDs: Set<UUID> = []
    var purgeCloudError: Error?

    /// Optional override for `loadSessionsResult()`. When set, `loadSessions()`
    /// will still hand back `storedSessions` for legacy compat callers, but
    /// callers using the Result-based API (like `AppViewModel.load`) will see
    /// the injected outcome — used to simulate transient/corrupt load paths.
    var sessionsLoadResultOverride: PersistenceLoadResult<[WorkSession]>?
    /// Optional override for `loadSettingsResult()`; same rationale as
    /// `sessionsLoadResultOverride`.
    var settingsLoadResultOverride: PersistenceLoadResult<WorkplaceSettings>?

    func loadSessions() -> [WorkSession] {
        storedSessions
    }

    func loadSessionsResult() -> PersistenceLoadResult<[WorkSession]> {
        if let override = sessionsLoadResultOverride {
            return override
        }
        return .loaded(storedSessions)
    }

    func saveSessions(_ sessions: [WorkSession]) throws {
        if let saveError { throw saveError }
        storedSessions = sessions
    }

    func loadSettings() -> WorkplaceSettings {
        storedSettings
    }

    func loadSettingsResult() -> PersistenceLoadResult<WorkplaceSettings> {
        if let override = settingsLoadResultOverride {
            return override
        }
        return .loaded(storedSettings)
    }

    func saveSettings(_ settings: WorkplaceSettings) throws {
        if let saveError { throw saveError }
        storedSettings = settings
    }

    func saveSettingsLocally(_ settings: WorkplaceSettings) throws {
        saveSettingsLocallyCallCount += 1
        try saveSettings(settings)
    }

    func purgeCloudData(sessionIDs: Set<UUID>) async throws {
        purgeCloudCallCount += 1
        lastPurgedSessionIDs = sessionIDs
        if let purgeCloudError { throw purgeCloudError }
    }

    func syncNow() async throws -> SyncResult? {
        nil
    }
}

final class MockLocationReminderManager: LocationReminderManaging {
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var areNotificationsDenied = false
    private(set) var configureCallCount = 0
    private(set) var lastConfiguredSessions: [WorkSession] = []
    private(set) var arrivalPermissionRequests = 0
    private(set) var stopReminderCalls = 0
    private(set) var refreshPermissionCalls = 0

    func configure(settings: WorkplaceSettings, sessions: [WorkSession]) {
        configureCallCount += 1
        lastConfiguredSessions = sessions
    }

    func requestArrivalReminderPermissions() {
        arrivalPermissionRequests += 1
    }

    func stopArrivalReminders() {
        stopReminderCalls += 1
    }

    func updateWorkplaceLocation(latitude: Double, longitude: Double, radius: Double) {}

    func refreshPermissionStatuses() {
        refreshPermissionCalls += 1
    }
}

final class InMemoryCloudSyncPreference: CloudSyncPreferencing {
    var isEnabled: Bool

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }
}

final class InMemoryTombstoneStore: SessionTombstoneStoring {
    private var storage: [UUID: SessionTombstone] = [:]

    var tombstoneIDs: Set<UUID> { Set(storage.keys) }

    func record(ids: Set<UUID>, at date: Date = Date()) {
        for id in ids {
            storage[id] = SessionTombstone(id: id, deletedAt: date)
        }
    }

    func prune(olderThan interval: TimeInterval) {
        let cutoff = Date().addingTimeInterval(-interval)
        storage = storage.filter { $0.value.deletedAt >= cutoff }
    }

    func remove(ids: Set<UUID>) {
        for id in ids { storage.removeValue(forKey: id) }
    }

    func removeAll() {
        storage = [:]
    }
}

final class RecordingCloud: CloudSyncing {
    var isSupported = true
    var state: SyncState = .idle
    private(set) var uploadedBatches: [[WorkSession]] = []
    private(set) var uploadedSettingsCount = 0
    private(set) var deletedIDBatches: [Set<UUID>] = []
    private(set) var purgeCallCount = 0
    private(set) var lastPurgedSessionIDs: Set<UUID> = []
    var purgeError: Error?
    var onUpload: (() -> Void)?
    var onDelete: (() -> Void)?
    /// When set, `sync(...)` never returns on its own — simulates a hung
    /// CloudKit operation so callers can verify their timeout kicks in.
    var hangIndefinitely = false

    func checkAvailability() async -> Bool {
        true
    }

    func sync(
        localSessions: [WorkSession],
        localSettings: WorkplaceSettings,
        tombstoneIDs: Set<UUID>
    ) async throws -> SyncResult {
        if hangIndefinitely {
            try await Task.sleep(nanoseconds: .max)
        }
        let sessions = CloudKitSyncManager.mergeSessions(
            local: localSessions,
            remote: [],
            tombstoneIDs: tombstoneIDs
        )
        return SyncResult(sessions: sessions, settings: localSettings)
    }

    func uploadSessions(_ sessions: [WorkSession]) async {
        uploadedBatches.append(sessions)
        onUpload?()
    }

    func uploadSettings(_ settings: WorkplaceSettings) async {
        uploadedSettingsCount += 1
    }

    func deleteSessions(ids: Set<UUID>) async {
        deletedIDBatches.append(ids)
        onDelete?()
    }

    func purgeUserCloudData(sessionIDs: Set<UUID>) async throws {
        purgeCallCount += 1
        lastPurgedSessionIDs = sessionIDs
        if let purgeError { throw purgeError }
        deletedIDBatches.append(sessionIDs)
        onDelete?()
    }
}

/// Scripted `DataReading` seam: fails a caller-supplied sequence of times before
/// falling through to the on-disk contents. Used to exercise the transient
/// retry path in `PersistenceManager.load` without depending on real
/// Data-Protection races.
final class ScriptedDataReader: DataReading {
    private var pendingFailures: [Error]
    private(set) var attempts = 0

    init(failures: [Error]) {
        self.pendingFailures = failures
    }

    func read(from url: URL) throws -> Data {
        attempts += 1
        if !pendingFailures.isEmpty {
            let error = pendingFailures.removeFirst()
            throw error
        }
        return try Data(contentsOf: url)
    }
}

final class RecordingFileWriter: FileWriting {
    private(set) var urls: [URL] = []
    private(set) var payloads: [Data] = []
    var writingOptions: Data.WritingOptions { ProtectedFileWriter.writingOptions }

    func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: writingOptions)
        urls.append(url)
        payloads.append(data)
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

    static func payslipExtraction(
        confidence: Double = 0.9,
        needsManualReview: Bool = false,
        netPay: Decimal? = Decimal(1010.50),
        grossPay: Decimal? = Decimal(1250)
    ) -> PayslipExtraction {
        PayslipExtraction(
            providerName: "UnitTestOCR",
            extractedAt: date(2026, 6, 1, 10),
            confidence: confidence,
            needsManualReview: needsManualReview,
            rawJSON: #"{"net":1010.50}"#,
            grossPay: grossPay,
            netPay: netPay,
            currencyCode: "ILS",
            employerName: "Example Employer",
            employeeName: "Example Worker",
            employeeID: "123456789",
            payPeriodStart: date(2026, 5, 1),
            payPeriodEnd: date(2026, 5, 31),
            paymentDate: date(2026, 6, 1),
            hoursRegular: 160,
            hoursOT: 8,
            deductionsTotal: Decimal(120),
            extras: [:]
        )
    }

    static func payslipRecord(
        id: UUID = UUID(),
        periodMonth: Date,
        uploadedAt: Date = date(2026, 7, 1),
        reviewState: PayslipRecord.ReviewState = .confirmed
    ) -> PayslipRecord {
        PayslipRecord(
            id: id,
            periodMonth: periodMonth,
            periodStartDay: nil,
            periodLabel: nil,
            uploadedAt: uploadedAt,
            sourceKind: .image,
            originalFileName: "slip.png",
            relativeFilePath: "payslips/files/\(id.uuidString).png",
            fileByteSize: 12,
            contentTypeUTI: "public.png",
            extraction: payslipExtraction(),
            userOverrides: nil,
            reviewState: reviewState,
            notes: nil
        )
    }
}
