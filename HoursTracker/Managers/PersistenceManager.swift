import Foundation

protocol PersistableStore: AnyObject {
    func loadSessions() -> [WorkSession]
    func saveSessions(_ sessions: [WorkSession])
    func loadSettings() -> WorkplaceSettings
    func saveSettings(_ settings: WorkplaceSettings)
}

final class PersistenceManager: PersistableStore {
    static let shared = PersistenceManager()

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var sessionsURL: URL {
        documentsDirectory.appendingPathComponent("work_sessions.json")
    }

    private var settingsURL: URL {
        documentsDirectory.appendingPathComponent("workplace_settings.json")
    }

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadSessions() -> [WorkSession] {
        load(from: sessionsURL) ?? []
    }

    func saveSessions(_ sessions: [WorkSession]) {
        save(sessions, to: sessionsURL)
    }

    func loadSettings() -> WorkplaceSettings {
        load(from: settingsURL) ?? .default
    }

    func saveSettings(_ settings: WorkplaceSettings) {
        save(settings, to: settingsURL)
    }

    private func load<T: Decodable>(from url: URL) -> T? {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
