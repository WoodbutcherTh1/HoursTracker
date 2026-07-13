import Foundation

protocol SyncingStore: PersistableStore {
    var syncState: SyncState { get }
    func syncNow() async throws -> SyncResult?
}

final class SyncingPersistenceStore: SyncingStore {
    static let shared = SyncingPersistenceStore()

    private let local = PersistenceManager.shared
    private let cloud: CloudSyncing

    private(set) var syncState: SyncState = .idle

    init(cloud: CloudSyncing = CloudKitSyncManager.shared) {
        self.cloud = cloud
    }

    func loadSessions() -> [WorkSession] {
        local.loadSessions()
    }

    func saveSessions(_ sessions: [WorkSession]) {
        let previous = local.loadSessions()
        let deletedIDs = Set(previous.map(\.id)).subtracting(sessions.map(\.id))
        local.saveSessions(sessions)
        Task {
            if !deletedIDs.isEmpty {
                await cloud.deleteSessions(ids: deletedIDs)
            }
            await cloud.uploadSessions(sessions)
        }
    }

    func loadSettings() -> WorkplaceSettings {
        local.loadSettings()
    }

    func saveSettings(_ settings: WorkplaceSettings) {
        local.saveSettings(settings)
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
            local.saveSessions(result.sessions)
            local.saveSettings(result.settings)
            syncState = cloud.state
            return result
        } catch {
            syncState = .failed(error.localizedDescription)
            throw error
        }
    }
}
