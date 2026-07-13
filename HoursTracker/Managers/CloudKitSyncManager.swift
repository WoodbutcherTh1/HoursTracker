import Foundation
import CloudKit

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

/// Local-only stub used when CloudKit entitlements / iCloud account are unavailable.
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

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var container: CKContainer?

    private(set) var state: SyncState = .idle

    private let sessionRecordType = "WorkSession"
    private let settingsRecordType = "WorkplaceSettings"
    private let settingsRecordName = "workplace-settings"
    private let containerIdentifier = "iCloud.com.hourstracker.app"

    /// Creating `CKContainer` aborts when iCloud entitlements are missing from the signed app.
    /// Stay on local storage until the CloudKit capability is confirmed in the signed entitlements.
    private let cloudKitEnabledKey = "HTCloudKitCapabilityEnabled"

    private init() {
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Call after enabling CloudKit under Signing & Capabilities and verifying a signed build embeds the entitlement.
    static func setCloudKitCapabilityEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: CloudKitSyncManager.shared.cloudKitEnabledKey)
    }

    private var isCloudKitCapabilityEnabled: Bool {
        // Default off so Simulator / unsigned local runs never touch CKContainer.
        UserDefaults.standard.bool(forKey: cloudKitEnabledKey)
    }

    private func ensureContainer() -> CKContainer? {
        if let container { return container }
        guard isCloudKitCapabilityEnabled else {
            state = .unavailable
            return nil
        }
        let created = CKContainer(identifier: containerIdentifier)
        container = created
        return created
    }

    private var database: CKDatabase? {
        ensureContainer()?.privateCloudDatabase
    }

    func checkAvailability() async -> Bool {
        guard let container = ensureContainer() else { return false }
        do {
            let status = try await container.accountStatus()
            return status == .available
        } catch {
            return false
        }
    }

    func sync(localSessions: [WorkSession], localSettings: WorkplaceSettings) async throws -> SyncResult {
        guard await checkAvailability(), let database else {
            state = .unavailable
            return SyncResult(sessions: localSessions, settings: localSettings)
        }

        state = .syncing

        do {
            async let remoteSessions = fetchSessions(from: database)
            async let remoteSettings = fetchSettings(from: database)
            let (cloudSessions, cloudSettings) = try await (remoteSessions, remoteSettings)

            let mergedSessions = mergeSessions(local: localSessions, remote: cloudSessions)
            let mergedSettings = mergeSettings(local: localSettings, remote: cloudSettings)

            await uploadSessions(mergedSessions)
            await uploadSettings(mergedSettings)

            state = .synced(Date())
            return SyncResult(sessions: mergedSessions, settings: mergedSettings)
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func uploadSessions(_ sessions: [WorkSession]) async {
        guard await checkAvailability(), let database else { return }
        for session in sessions {
            do {
                let record = try makeSessionRecord(session)
                _ = try await database.save(record)
            } catch {}
        }
    }

    func uploadSettings(_ settings: WorkplaceSettings) async {
        guard await checkAvailability(), let database else { return }
        do {
            let record = try makeSettingsRecord(settings)
            _ = try await database.save(record)
        } catch {}
    }

    func deleteSessions(ids: Set<UUID>) async {
        guard await checkAvailability(), let database, !ids.isEmpty else { return }
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
        } catch {}
    }

    private func fetchSessions(from database: CKDatabase) async throws -> [WorkSession] {
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

    private func fetchSettings(from database: CKDatabase) async throws -> WorkplaceSettings? {
        let recordID = CKRecord.ID(recordName: settingsRecordName)
        do {
            let record = try await database.record(for: recordID)
            return settings(from: record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func mergeSessions(local: [WorkSession], remote: [WorkSession]) -> [WorkSession] {
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

    private func mergeSettings(local: WorkplaceSettings, remote: WorkplaceSettings?) -> WorkplaceSettings {
        guard let remote else { return local }
        return local.modifiedAt >= remote.modifiedAt ? local : remote
    }

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
