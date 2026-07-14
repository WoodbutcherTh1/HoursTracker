import Foundation

protocol SyncingStore: PersistableStore {
    var syncState: SyncState { get }
    func syncNow() async throws -> SyncResult?
}

final class SyncingPersistenceStore: SyncingStore {
    static let shared = SyncingPersistenceStore()

    private let local: PersistableStore
    private let cloud: CloudSyncing

    private(set) var syncState: SyncState = .idle

    init(
        local: PersistableStore = PersistenceManager.shared,
        cloud: CloudSyncing? = nil
    ) {
        self.local = local
        self.cloud = cloud ?? NoOpCloudSyncManager.shared
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
        Task {
            await cloud.uploadSettings(settings)
        }
    }

    func syncNow() async throws -> SyncResult? {
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
