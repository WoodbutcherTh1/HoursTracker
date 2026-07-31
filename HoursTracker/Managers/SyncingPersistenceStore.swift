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
    private let syncTimeoutNanoseconds: UInt64

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
        tombstones: SessionTombstoneStoring = SessionTombstoneStore.shared,
        syncTimeoutNanoseconds: UInt64 = 30 * NSEC_PER_SEC
    ) {
        self.local = local
        self.cloud = cloud ?? CloudKitSyncManager.makeDefault()
        self.syncPreference = syncPreference
        self.tombstones = tombstones
        self.syncTimeoutNanoseconds = syncTimeoutNanoseconds
        if !self.cloud.isSupported {
            syncState = .unavailable
        }
    }

    func loadSessions() -> [WorkSession] {
        local.loadSessions()
    }

    func loadSessionsResult() -> PersistenceLoadResult<[WorkSession]> {
        local.loadSessionsResult()
    }

    func saveSessions(_ sessions: [WorkSession]) throws {
        let previous = local.loadSessions()
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        let deletedIDs = Set(previousByID.keys).subtracting(sessions.map(\.id))
        let changed = sessions.filter { previousByID[$0.id] != $0 }
        if !deletedIDs.isEmpty {
            tombstones.record(ids: deletedIDs)
        }
        try local.saveSessions(sessions)
        guard syncPreference.isEnabled else { return }
        Task {
            await writeQueue.enqueue { [cloud] in
                if !deletedIDs.isEmpty {
                    await cloud.deleteSessions(ids: deletedIDs)
                }
                if !changed.isEmpty {
                    await cloud.uploadSessions(changed)
                }
            }
        }
    }

    func loadSettings() -> WorkplaceSettings {
        local.loadSettings()
    }

    func loadSettingsResult() -> PersistenceLoadResult<WorkplaceSettings> {
        local.loadSettingsResult()
    }

    func saveSettings(_ settings: WorkplaceSettings) throws {
        try local.saveSettings(settings)
        guard syncPreference.isEnabled else { return }
        Task {
            await writeQueue.enqueue { [cloud] in
                await cloud.uploadSettings(settings)
            }
        }
    }

    func saveSettingsLocally(_ settings: WorkplaceSettings) throws {
        try local.saveSettings(settings)
    }

    func purgeCloudData(sessionIDs: Set<UUID>) async throws {
        guard cloud.isSupported else { return }
        if !sessionIDs.isEmpty {
            tombstones.record(ids: sessionIDs)
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
        tombstones.prune()

        // Refuse to sync when either local store is intact-but-unreadable. If we
        // proceeded here, we would merge remote against an empty local and then
        // `saveSessions([])` would overwrite the real file with an empty array
        // once Data Protection released the class key. That is exactly the
        // silent-wipe path the load-result contract exists to prevent.
        let sessionsOutcome = local.loadSessionsResult()
        let settingsOutcome = local.loadSettingsResult()
        if case .temporarilyUnavailable = sessionsOutcome {
            let error = PersistenceLoadError.temporarilyUnavailable
            syncState = .failed(error.localizedDescription)
            throw error
        }
        if case .temporarilyUnavailable = settingsOutcome {
            let error = PersistenceLoadError.temporarilyUnavailable
            syncState = .failed(error.localizedDescription)
            throw error
        }

        let localSessions: [WorkSession] = {
            if case .loaded(let s) = sessionsOutcome { return s }
            return []
        }()
        let localSettings: WorkplaceSettings = {
            if case .loaded(let s) = settingsOutcome { return s }
            return .default
        }()
        let deleted = tombstones.tombstoneIDs

        do {
            let cloud = self.cloud
            let result = try await Self.withTimeout(nanoseconds: syncTimeoutNanoseconds) {
                try await cloud.sync(
                    localSessions: localSessions,
                    localSettings: localSettings,
                    tombstoneIDs: deleted
                )
            }
            try local.saveSessions(result.sessions)
            try local.saveSettings(result.settings)
            syncState = cloud.state
            return result
        } catch {
            syncState = .failed(error.localizedDescription)
            throw error
        }
    }

    /// Races `operation` against a deadline so a hung CloudKit call surfaces as a
    /// thrown error instead of blocking `syncNow()` (and therefore `isSyncing`)
    /// forever. The losing task is cancelled but may keep running in the
    /// background if it doesn't observe cancellation (e.g. a CKOperation
    /// continuation) — harmless since only its result is discarded.
    private static func withTimeout<T: Sendable>(
        nanoseconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: nanoseconds)
                throw SyncTimeoutError.timedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw SyncTimeoutError.timedOut
            }
            return result
        }
    }
}

enum SyncTimeoutError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        "iCloud sync timed out. Check your connection and try again."
    }
}

/// Errors surfaced by the persistence layer to callers that need to distinguish
/// "no data yet" from "data exists on disk but temporarily unreadable".
enum PersistenceLoadError: LocalizedError {
    /// Every read attempt for an existing on-disk store failed. Callers must
    /// NOT overwrite the file with defaults; the intact bytes are still there.
    case temporarilyUnavailable

    var errorDescription: String? {
        switch self {
        case .temporarilyUnavailable:
            return "The local store is temporarily unavailable (device may still be unlocking)."
        }
    }
}
