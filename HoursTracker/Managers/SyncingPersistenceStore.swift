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

    init(cloud: CloudSyncing? = nil) {
        // Prefer CloudKit when capability is enabled; otherwise stay local-only (safe for Simulator).
        if let cloud {
            self.cloud = cloud
        } else if UserDefaults.standard.bool(forKey: "HTCloudKitCapabilityEnabled") {
            self.cloud = CloudKitSyncManager.shared
        } else {
            self.cloud = NoOpCloudSyncManager.shared
        }
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
