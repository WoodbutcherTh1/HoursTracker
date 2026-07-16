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

    private(set) var syncState: SyncState = .idle

    var isCloudSyncSupported: Bool { cloud.isSupported }

    var isICloudSyncEnabled: Bool {
        get { syncPreference.isEnabled }
        set { syncPreference.isEnabled = newValue }
    }

    init(
        local: PersistableStore = PersistenceManager.shared,
        cloud: CloudSyncing? = nil,
        syncPreference: CloudSyncPreferencing = UserDefaultsCloudSyncPreference.shared
    ) {
        self.local = local
        self.cloud = cloud ?? CloudKitSyncManager.makeDefault()
        self.syncPreference = syncPreference
        if !self.cloud.isSupported {
            syncState = .unavailable
        }
    }

    func loadSessions() -> [WorkSession] {
        local.loadSessions()
    }

    func saveSessions(_ sessions: [WorkSession]) throws {
        let previous = local.loadSessions()
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        let deletedIDs = Set(previousByID.keys).subtracting(sessions.map(\.id))
        let changed = sessions.filter { previousByID[$0.id] != $0 }
        try local.saveSessions(sessions)
        guard syncPreference.isEnabled else { return }
        Task {
            if !deletedIDs.isEmpty {
                await cloud.deleteSessions(ids: deletedIDs)
            }
            if !changed.isEmpty {
                await cloud.uploadSessions(changed)
            }
        }
    }

    func loadSettings() -> WorkplaceSettings {
        local.loadSettings()
    }

    func saveSettings(_ settings: WorkplaceSettings) throws {
        try local.saveSettings(settings)
        guard syncPreference.isEnabled else { return }
        Task {
            await cloud.uploadSettings(settings)
        }
    }

    func saveSettingsLocally(_ settings: WorkplaceSettings) throws {
        try local.saveSettings(settings)
    }

    func purgeCloudData(sessionIDs: Set<UUID>) async throws {
        guard cloud.isSupported else { return }
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
        let localSessions = local.loadSessions()
        let localSettings = local.loadSettings()

        do {
            let result = try await cloud.sync(
                localSessions: localSessions,
                localSettings: localSettings
            )
            try local.saveSessions(result.sessions)
            try local.saveSettings(result.settings)
            syncState = cloud.state
            return result
        } catch {
            syncState = .failed(error.localizedDescription)
            throw error
        }
    }
}
