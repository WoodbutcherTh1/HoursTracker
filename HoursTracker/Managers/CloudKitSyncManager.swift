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
    var state: SyncState { get }
    func checkAvailability() async -> Bool
    func sync(localSessions: [WorkSession], localSettings: WorkplaceSettings) async throws -> SyncResult
    func uploadSessions(_ sessions: [WorkSession]) async
    func uploadSettings(_ settings: WorkplaceSettings) async
    func deleteSessions(ids: Set<UUID>) async
}

/// Local-only stub used when CloudKit is unavailable or injected in tests.
final class NoOpCloudSyncManager: CloudSyncing {
    static let shared = NoOpCloudSyncManager()
    private(set) var state: SyncState = .unavailable

    func checkAvailability() async -> Bool { false }

    func sync(localSessions: [WorkSession], localSettings: WorkplaceSettings) async throws -> SyncResult {
        state = .unavailable
        return SyncResult(sessions: localSessions, settings: localSettings)
    }

    func uploadSessions(_ sessions: [WorkSession]) async {}
    func uploadSettings(_ settings: WorkplaceSettings) async {}
    func deleteSessions(ids: Set<UUID>) async {}
}

final class CloudKitSyncManager: CloudSyncing {
    static let shared = CloudKitSyncManager()

    /// CKContainer raises an uncatchable exception when the process lacks the
    /// iCloud entitlements. Locally signed test builds (unit tests, CI) run
    /// without provisioning, so skip CloudKit entirely there instead of
    /// crashing the test host at launch.
    private let container: CKContainer?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: "com.hourstracker.app", category: "cloudkit")

    private(set) var state: SyncState = .idle

    private let sessionRecordType = "WorkSession"
    private let settingsRecordType = "WorkplaceSettings"
    private let settingsRecordName = "workplace-settings"

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private init() {
        container = Self.isRunningTests
            ? nil
            : CKContainer(identifier: "iCloud.com.hourstracker.app")
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
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

    func sync(localSessions: [WorkSession], localSettings: WorkplaceSettings) async throws -> SyncResult {
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

        let mergedSessions = Self.mergeSessions(local: localSessions, remote: cloudSessions)
        let mergedSettings = Self.mergeSettings(local: localSettings, remote: cloudSettings)

        await uploadSessions(mergedSessions)
        await uploadSettings(mergedSettings)

        state = .synced(Date())
        return SyncResult(sessions: mergedSessions, settings: mergedSettings)
    }

    func uploadSessions(_ sessions: [WorkSession]) async {
        guard let database, await checkAvailability() else { return }
        for session in sessions {
            do {
                let record = try makeSessionRecord(session)
                _ = try await database.save(record)
            } catch {
                // Individual record failures should not block other uploads.
                logger.error("Failed to upload session \(session.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func uploadSettings(_ settings: WorkplaceSettings) async {
        guard let database, await checkAvailability() else { return }
        do {
            let record = try makeSettingsRecord(settings)
            _ = try await database.save(record)
        } catch {
            // Settings upload is best-effort when offline.
            logger.error("Failed to upload settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteSessions(ids: Set<UUID>) async {
        guard let database, await checkAvailability(), !ids.isEmpty else { return }
        let recordIDs = ids.map { CKRecord.ID(recordName: $0.uuidString) }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDs)
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
        } catch {
            // Deletions are retried on the next full sync.
            logger.error("Failed to delete \(ids.count) session(s): \(error.localizedDescription, privacy: .public)")
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

    static func mergeSessions(local: [WorkSession], remote: [WorkSession]) -> [WorkSession] {
        var merged = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for remoteSession in remote {
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
        return local.modifiedAt >= remote.modifiedAt ? local : remote
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
        record["payload"] = try encoder.encode(settings)
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
