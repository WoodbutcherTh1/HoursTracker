import Foundation
import CloudKit
import os

enum SyncState: Equatable {
    case idle
    case syncing
    case synced(Date)
    case failed(String)
    case unavailable
}

struct SyncResult {
    let sessions: [WorkSession]
    let settings: WorkplaceSettings
}

protocol CloudSyncing: AnyObject {
    /// `false` when this build cannot use CloudKit at all (no entitlement / NoOp).
    /// Distinct from a temporary `.unavailable` account status.
    var isSupported: Bool { get }
    var state: SyncState { get }
    func checkAvailability() async -> Bool
    func sync(
        localSessions: [WorkSession],
        localSettings: WorkplaceSettings,
        tombstoneIDs: Set<UUID>
    ) async throws -> SyncResult
    func uploadSessions(_ sessions: [WorkSession]) async
    func uploadSettings(_ settings: WorkplaceSettings) async
    func deleteSessions(ids: Set<UUID>) async
    /// Deletes remote sessions and the settings record. Throws on partial failure.
    func purgeUserCloudData(sessionIDs: Set<UUID>) async throws
}

/// Local-only stub used when CloudKit is unavailable or injected in tests.
final class NoOpCloudSyncManager: CloudSyncing {
    static let shared = NoOpCloudSyncManager()
    let isSupported = false
    private(set) var state: SyncState = .unavailable

    func checkAvailability() async -> Bool { false }

    func sync(
        localSessions: [WorkSession],
        localSettings: WorkplaceSettings,
        tombstoneIDs: Set<UUID>
    ) async throws -> SyncResult {
        state = .unavailable
        let sessions = CloudKitSyncManager.mergeSessions(
            local: localSessions,
            remote: [],
            tombstoneIDs: tombstoneIDs
        )
        return SyncResult(sessions: sessions, settings: localSettings)
    }

    func uploadSessions(_ sessions: [WorkSession]) async {}
    func uploadSettings(_ settings: WorkplaceSettings) async {}
    func deleteSessions(ids: Set<UUID>) async {}
    func purgeUserCloudData(sessionIDs: Set<UUID>) async throws {}
}

/// CloudKit private-DB sync.
///
/// **Entitlements:** A CloudKit-enabled build requires
/// `com.apple.developer.icloud-container-identifiers` /
/// `com.apple.developer.icloud-services` for container `iCloud.com.hourstracker.app`
/// (see `docs/HoursTracker.entitlements.cloudkit.example`). Personal-team installs keep
/// `HoursTracker.entitlements` empty and `HTCloudKitEnabled` false so `CKContainer`
/// is never created.
final class CloudKitSyncManager: CloudSyncing {
    static let shared = CloudKitSyncManager()

    /// CKContainer aborts the process when iCloud entitlements are missing.
    /// Personal-team device installs usually ship without CloudKit, so the
    /// container stays nil unless the build explicitly opts in.
    private var container: CKContainer?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: "com.hourstracker.app", category: "cloudkit")
    private let writeQueue = CloudWriteQueue()

    private(set) var state: SyncState = .unavailable

    private let sessionRecordType = "WorkSession"
    private let settingsRecordType = "WorkplaceSettings"
    private let settingsRecordName = "workplace-settings"
    private let containerIdentifier = "iCloud.com.hourstracker.app"

    /// Opt-in only. Creating `CKContainer` without the entitlement kills the app
    /// at launch (uncatchable). Keep this false for personal-team installs.
    static var isCloudKitBuildEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "HTCloudKitEnabled") as? Bool ?? false
    }

    var isSupported: Bool { container != nil }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private init() {
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        guard !Self.isRunningTests, Self.isCloudKitBuildEnabled else {
            container = nil
            state = .unavailable
            return
        }

        // Requires CloudKit entitlements — see docs/HoursTracker.entitlements.cloudkit.example.
        container = CKContainer(identifier: containerIdentifier)
        state = .idle
    }

    /// Prefer CloudKit when the build opts in; otherwise stay local-only.
    static func makeDefault() -> CloudSyncing {
        isCloudKitBuildEnabled ? CloudKitSyncManager.shared : NoOpCloudSyncManager.shared
    }

    private var database: CKDatabase? {
        container?.privateCloudDatabase
    }

    func checkAvailability() async -> Bool {
        guard let container else { return false }
        do {
            let status = try await container.accountStatus()
            return status == .available
        } catch {
            return false
        }
    }

    func sync(
        localSessions: [WorkSession],
        localSettings: WorkplaceSettings,
        tombstoneIDs: Set<UUID>
    ) async throws -> SyncResult {
        guard await checkAvailability() else {
            state = .unavailable
            return SyncResult(sessions: localSessions, settings: localSettings)
        }

        state = .syncing
        defer {
            if case .syncing = state {
                state = .synced(Date())
            }
        }

        async let remoteSessions = fetchSessions()
        async let remoteSettings = fetchSettings()

        let (cloudSessions, cloudSettings) = try await (remoteSessions, remoteSettings)

        let mergedSessions = Self.mergeSessions(
            local: localSessions,
            remote: cloudSessions,
            tombstoneIDs: tombstoneIDs
        )
        let mergedSettings = Self.mergeSettings(local: localSettings, remote: cloudSettings)

        // Push deletions for anything still living remotely after a local delete.
        let remoteIDs = Set(cloudSessions.map(\.id))
        let staleRemote = tombstoneIDs.intersection(remoteIDs)
        if !staleRemote.isEmpty {
            await deleteSessions(ids: staleRemote)
        }

        await uploadSessions(mergedSessions)
        await uploadSettings(mergedSettings)

        state = .synced(Date())
        return SyncResult(sessions: mergedSessions, settings: mergedSettings)
    }

    func uploadSessions(_ sessions: [WorkSession]) async {
        await writeQueue.enqueue { [weak self] in
            guard let self, let database = self.database, await self.checkAvailability() else { return }
            for session in sessions {
                do {
                    try await self.saveSession(session, database: database)
                } catch {
                    self.logger.error(
                        "Failed to upload session: \(error.localizedDescription, privacy: .private)"
                    )
                }
            }
        }
    }

    func uploadSettings(_ settings: WorkplaceSettings) async {
        await writeQueue.enqueue { [weak self] in
            guard let self, let database = self.database, await self.checkAvailability() else { return }
            do {
                try await self.saveSettings(settings, database: database)
            } catch {
                self.logger.error(
                    "Failed to upload settings: \(error.localizedDescription, privacy: .private)"
                )
            }
        }
    }

    func deleteSessions(ids: Set<UUID>) async {
        await writeQueue.enqueue { [weak self] in
            guard let self else { return }
            do {
                try await self.deleteSessionRecords(ids: ids)
            } catch {
                self.logger.error(
                    "Failed to delete sessions: \(error.localizedDescription, privacy: .private)"
                )
            }
        }
    }

    func purgeUserCloudData(sessionIDs: Set<UUID>) async throws {
        try await writeQueue.enqueueThrowing { [weak self] in
            guard let self else { return }
            try await self.deleteSessionRecords(ids: sessionIDs)
            try await self.deleteSettingsRecord()
        }
    }

    // MARK: - Conflict-aware saves

    private func saveSession(_ session: WorkSession, database: CKDatabase) async throws {
        let record = try makeSessionRecord(session)
        do {
            try await modifyRecords(database: database, recordsToSave: [record], recordIDsToDelete: nil)
        } catch let error as CKError where error.code == .serverRecordChanged {
            let resolved = try resolveSessionConflict(intended: session, error: error)
            try await modifyRecords(database: database, recordsToSave: [resolved], recordIDsToDelete: nil)
        }
    }

    private func saveSettings(_ settings: WorkplaceSettings, database: CKDatabase) async throws {
        let record = try makeSettingsRecord(settings)
        do {
            try await modifyRecords(database: database, recordsToSave: [record], recordIDsToDelete: nil)
        } catch let error as CKError where error.code == .serverRecordChanged {
            let resolved = try resolveSettingsConflict(intended: settings, error: error)
            try await modifyRecords(database: database, recordsToSave: [resolved], recordIDsToDelete: nil)
        }
    }

    /// Newer `modifiedAt` wins; keep the server record's change tag when re-saving.
    static func resolveConflictWinner<T>(
        intendedModifiedAt: Date,
        serverModifiedAt: Date?,
        intended: T,
        server: T?
    ) -> T {
        guard let server, let serverModifiedAt else { return intended }
        return intendedModifiedAt >= serverModifiedAt ? intended : server
    }

    func resolveSessionConflict(intended: WorkSession, error: CKError) throws -> CKRecord {
        guard let serverRecord = error.serverRecord else {
            return try makeSessionRecord(intended)
        }
        let serverSession = session(from: serverRecord)
        let winner = Self.resolveConflictWinner(
            intendedModifiedAt: intended.modifiedAt,
            serverModifiedAt: serverSession?.modifiedAt,
            intended: intended,
            server: serverSession
        )
        serverRecord["payload"] = try encoder.encode(winner)
        serverRecord["modifiedAt"] = winner.modifiedAt
        return serverRecord
    }

    func resolveSettingsConflict(intended: WorkplaceSettings, error: CKError) throws -> CKRecord {
        guard let serverRecord = error.serverRecord else {
            return try makeSettingsRecord(intended)
        }
        let serverSettings = settings(from: serverRecord)
        var winner = Self.resolveConflictWinner(
            intendedModifiedAt: intended.modifiedAt,
            serverModifiedAt: serverSettings?.modifiedAt,
            intended: intended,
            server: serverSettings
        )
        // National ID never syncs — prefer the intended in-memory value.
        winner.workerIDNumber = intended.workerIDNumber
        var sanitized = winner
        sanitized.workerIDNumber = ""
        serverRecord["payload"] = try encoder.encode(sanitized)
        serverRecord["modifiedAt"] = winner.modifiedAt
        return serverRecord
    }

    private func deleteSessionRecords(ids: Set<UUID>) async throws {
        guard let database, await checkAvailability(), !ids.isEmpty else { return }
        let recordIDs = ids.map { CKRecord.ID(recordName: $0.uuidString) }
        try await modifyRecords(database: database, recordsToSave: nil, recordIDsToDelete: recordIDs)
    }

    private func deleteSettingsRecord() async throws {
        guard let database, await checkAvailability() else { return }
        let recordID = CKRecord.ID(recordName: settingsRecordName)
        do {
            try await modifyRecords(
                database: database,
                recordsToSave: nil,
                recordIDsToDelete: [recordID]
            )
        } catch let error as CKError where error.code == .unknownItem {
            return
        }
    }

    private func modifyRecords(
        database: CKDatabase,
        recordsToSave: [CKRecord]?,
        recordIDsToDelete: [CKRecord.ID]?
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(
                recordsToSave: recordsToSave,
                recordIDsToDelete: recordIDsToDelete
            )
            operation.savePolicy = .changedKeys
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    // MARK: - Fetch

    private func fetchSessions() async throws -> [WorkSession] {
        guard let database else { return [] }
        let query = CKQuery(recordType: sessionRecordType, predicate: NSPredicate(value: true))
        var collected: [WorkSession] = []

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKQueryOperation(query: query)
            operation.resultsLimit = CKQueryOperation.maximumResults

            operation.recordMatchedBlock = { _, result in
                if case .success(let record) = result,
                   let session = self.session(from: record) {
                    collected.append(session)
                }
            }

            operation.queryResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    if (error as? CKError)?.code == .unknownItem {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error)
                    }
                }
            }

            database.add(operation)
        }

        return collected
    }

    private func fetchSettings() async throws -> WorkplaceSettings? {
        guard let database else { return nil }
        let recordID = CKRecord.ID(recordName: settingsRecordName)
        do {
            let record = try await database.record(for: recordID)
            return settings(from: record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    // MARK: - Merge

    /// Last-write-wins by `modifiedAt`, never resurrecting tombstoned IDs.
    static func mergeSessions(
        local: [WorkSession],
        remote: [WorkSession],
        tombstoneIDs: Set<UUID> = []
    ) -> [WorkSession] {
        var merged = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for id in tombstoneIDs {
            merged.removeValue(forKey: id)
        }
        for remoteSession in remote {
            if tombstoneIDs.contains(remoteSession.id) { continue }
            if let localSession = merged[remoteSession.id] {
                merged[remoteSession.id] = localSession.modifiedAt >= remoteSession.modifiedAt
                    ? localSession
                    : remoteSession
            } else {
                merged[remoteSession.id] = remoteSession
            }
        }
        return Array(merged.values)
    }

    static func mergeSettings(local: WorkplaceSettings, remote: WorkplaceSettings?) -> WorkplaceSettings {
        guard let remote else { return local }
        var winner = local.modifiedAt >= remote.modifiedAt ? local : remote
        // National ID is Keychain-only (ThisDeviceOnly) and is never synced.
        winner.workerIDNumber = local.workerIDNumber
        return winner
    }

    // MARK: - Records

    private func makeSessionRecord(_ session: WorkSession) throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: session.id.uuidString)
        let record = CKRecord(recordType: sessionRecordType, recordID: recordID)
        record["payload"] = try encoder.encode(session)
        record["modifiedAt"] = session.modifiedAt
        return record
    }

    private func makeSettingsRecord(_ settings: WorkplaceSettings) throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: settingsRecordName)
        let record = CKRecord(recordType: settingsRecordType, recordID: recordID)
        // Never upload the national ID — it lives only in the local Keychain.
        var sanitized = settings
        sanitized.workerIDNumber = ""
        record["payload"] = try encoder.encode(sanitized)
        record["modifiedAt"] = settings.modifiedAt
        return record
    }

    private func session(from record: CKRecord) -> WorkSession? {
        guard let data = record["payload"] as? Data else { return nil }
        return try? decoder.decode(WorkSession.self, from: data)
    }

    private func settings(from record: CKRecord) -> WorkplaceSettings? {
        guard let data = record["payload"] as? Data else { return nil }
        return try? decoder.decode(WorkplaceSettings.self, from: data)
    }
}
