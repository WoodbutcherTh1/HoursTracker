import Foundation
import os

protocol PersistableStore: AnyObject {
    func loadSessions() -> [WorkSession]
    func saveSessions(_ sessions: [WorkSession]) throws
    func loadSettings() -> WorkplaceSettings
    func saveSettings(_ settings: WorkplaceSettings) throws
}

final class PersistenceManager: PersistableStore {
    static let shared = PersistenceManager()

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger = Logger(subsystem: "com.hourstracker.app", category: "persistence")

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

    func saveSessions(_ sessions: [WorkSession]) throws {
        try save(sessions, to: sessionsURL)
    }

    func loadSettings() -> WorkplaceSettings {
        load(from: settingsURL) ?? .default
    }

    func saveSettings(_ settings: WorkplaceSettings) throws {
        try save(settings, to: settingsURL)
    }

    private func load<T: Decodable>(from url: URL) -> T? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.error("Failed to load \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func save<T: Encodable>(_ value: T, to url: URL) throws {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to save \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
