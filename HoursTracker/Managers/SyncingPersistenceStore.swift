import Foundation

protocol SyncingStore: PersistableStore {
    /// Whether this build can sync via iCloud/CloudKit at all.
    var isCloudSyncSupported: Bool { get }
    /// User opt-in for private-iCloud sync (default off).
    var isICloudSyncEnabled: Bool { get set }
    var syncState: SyncState { get }
    func syncNow() async throws -> SyncResult?
    /// Persists settings locally without uploading to CloudKit (used by delete-all).
    func saveSettingsLocally(_ settings: WorkplaceSettings) throws
    /// Deletes remote sessions and the settings record when CloudKit is supported.
    /// Not gated by the user sync toggle (used by delete-all and toggle-off cleanup).
    func purgeCloudData(sessionIDs: Set<UUID>) async throws
}

final class SyncingPersistenceStore: SyncingStore {
    static let shared = SyncingPersistenceStore()

    private let local: PersistableStore
    private let cloud: CloudSyncing
    private let syncPreference: CloudSyncPreferencing
    private let tombstones: SessionTombstoneStoring
    private let writeQueue = CloudWriteQueue()
    private let localLock = NSLock()
    private var localRevision = 0

    private(set) var syncState: SyncState = .idle

    var isCloudSyncSupported: Bool { cloud.isSupported }

    var isICloudSyncEnabled: Bool {
        get { syncPreference.isEnabled }
        set { syncPreference.isEnabled = newValue }
    }

    init(
        local: PersistableStore = PersistenceManager.shared,
        cloud: CloudSyncing? = nil,
        syncPreference: CloudSyncPreferencing = UserDefaultsCloudSyncPreference.shared,
        tombstones: SessionTombstoneStoring = SessionTombstoneStore.shared
    ) {
        self.local = local
        self.cloud = cloud ?? CloudKitSyncManager.makeDefault()
        self.syncPreference = syncPreference
        self.tombstones = tombstones
        if !self.cloud.isSupported {
            syncState = .unavailable
        }
    }

    func loadSessions() -> [WorkSession] {
        withLocalLock {
            local.loadSessions()
        }
    }

    func saveSessions(_ sessions: [WorkSession]) throws {
        let write = try withLocalLock {
            let previous = local.loadSessions()
            let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
            let deletedIDs = Set(previousByID.keys).subtracting(sessions.map(\.id))
            let changed = sessions.filter { previousByID[$0.id] != $0 }
            if !deletedIDs.isEmpty {
                tombstones.record(ids: deletedIDs)
            }
            try local.saveSessions(sessions)
            localRevision += 1
            return (deletedIDs: deletedIDs, changed: changed, shouldSync: syncPreference.isEnabled)
        }
        guard write.shouldSync else { return }
        Task {
            await writeQueue.enqueue { [cloud] in
                if !write.deletedIDs.isEmpty {
                    await cloud.deleteSessions(ids: write.deletedIDs)
                }
                if !write.changed.isEmpty {
                    await cloud.uploadSessions(write.changed)
                }
            }
        }
    }

    func loadSettings() -> WorkplaceSettings {
        withLocalLock {
            local.loadSettings()
        }
    }

    func saveSettings(_ settings: WorkplaceSettings) throws {
        let shouldSync = try withLocalLock {
            try local.saveSettings(settings)
            localRevision += 1
            return syncPreference.isEnabled
        }
        guard shouldSync else { return }
        Task {
            await writeQueue.enqueue { [cloud] in
                await cloud.uploadSettings(settings)
            }
        }
    }

    func saveSettingsLocally(_ settings: WorkplaceSettings) throws {
        try withLocalLock {
            try local.saveSettings(settings)
            localRevision += 1
        }
    }

    func purgeCloudData(sessionIDs: Set<UUID>) async throws {
        guard cloud.isSupported else { return }
        withLocalLock {
            if !sessionIDs.isEmpty {
                tombstones.record(ids: sessionIDs)
            }
        }
        try await cloud.purgeUserCloudData(sessionIDs: sessionIDs)
    }

    func syncNow() async throws -> SyncResult? {
        guard syncPreference.isEnabled else {
            if cloud.isSupported {
                syncState = .idle
            }
            return nil
        }

        syncState = .syncing
        let initialSnapshot = makeSyncSnapshot()

        do {
            let result = try await cloud.sync(
                localSessions: initialSnapshot.sessions,
                localSettings: initialSnapshot.settings,
                tombstoneIDs: initialSnapshot.tombstoneIDs
            )
            let finalResult: SyncResult
            if try saveSyncResultIfCurrent(result, expectedRevision: initialSnapshot.revision) {
                finalResult = result
            } else {
                let retrySnapshot = makeSyncSnapshot()
                let retryResult = try await cloud.sync(
                    localSessions: retrySnapshot.sessions,
                    localSettings: retrySnapshot.settings,
                    tombstoneIDs: retrySnapshot.tombstoneIDs
                )
                finalResult = try saveSyncResultMergingLatestLocalIfNeeded(
                    retryResult,
                    expectedRevision: retrySnapshot.revision
                )
            }
            syncState = cloud.state
            return finalResult
        } catch {
            syncState = .failed(error.localizedDescription)
            throw error
        }
    }

    private struct SyncSnapshot {
        let sessions: [WorkSession]
        let settings: WorkplaceSettings
        let tombstoneIDs: Set<UUID>
        let revision: Int
    }

    private func makeSyncSnapshot() -> SyncSnapshot {
        withLocalLock {
            tombstones.prune()
            return SyncSnapshot(
                sessions: local.loadSessions(),
                settings: local.loadSettings(),
                tombstoneIDs: tombstones.tombstoneIDs,
                revision: localRevision
            )
        }
    }

    private func saveSyncResultIfCurrent(_ result: SyncResult, expectedRevision: Int) throws -> Bool {
        try withLocalLock {
            guard localRevision == expectedRevision else { return false }
            try local.saveSessions(result.sessions)
            try local.saveSettings(result.settings)
            localRevision += 1
            return true
        }
    }

    private func saveSyncResultMergingLatestLocalIfNeeded(
        _ result: SyncResult,
        expectedRevision: Int
    ) throws -> SyncResult {
        try withLocalLock {
            let finalResult: SyncResult
            if localRevision == expectedRevision {
                finalResult = result
            } else {
                finalResult = SyncResult(
                    sessions: CloudKitSyncManager.mergeSessions(
                        local: local.loadSessions(),
                        remote: result.sessions,
                        tombstoneIDs: tombstones.tombstoneIDs
                    ),
                    settings: CloudKitSyncManager.mergeSettings(
                        local: local.loadSettings(),
                        remote: result.settings
                    )
                )
            }
            try local.saveSessions(finalResult.sessions)
            try local.saveSettings(finalResult.settings)
            localRevision += 1
            return finalResult
        }
    }

    private func withLocalLock<T>(_ work: () throws -> T) rethrows -> T {
        localLock.lock()
        defer { localLock.unlock() }
        return try work()
    }
}
