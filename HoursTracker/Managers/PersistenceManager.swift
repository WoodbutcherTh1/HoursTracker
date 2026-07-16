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

    private let fileManager: FileManager
    private let fileWriter: FileWriting
    private let documentsDirectoryOverride: URL?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger = Logger(subsystem: "com.hourstracker.app", category: "persistence")
    private var didMigrateProtection = false

    private var documentsDirectory: URL {
        documentsDirectoryOverride
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var sessionsURL: URL {
        documentsDirectory.appendingPathComponent("work_sessions.json")
    }

    var settingsURL: URL {
        documentsDirectory.appendingPathComponent("workplace_settings.json")
    }

    init(
        fileManager: FileManager = .default,
        fileWriter: FileWriting = ProtectedFileWriter.shared,
        documentsDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.fileWriter = fileWriter
        self.documentsDirectoryOverride = documentsDirectory
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadSessions() -> [WorkSession] {
        migrateProtectionIfNeeded()
        return load(from: sessionsURL) ?? []
    }

    func saveSessions(_ sessions: [WorkSession]) throws {
        migrateProtectionIfNeeded()
        try save(sessions, to: sessionsURL)
    }

    func loadSettings() -> WorkplaceSettings {
        migrateProtectionIfNeeded()
        var settings: WorkplaceSettings = load(from: settingsURL) ?? WorkplaceSettings.default

        // Migration: move plaintext national ID from JSON into Keychain, then rewrite.
        if !settings.workerIDNumber.isEmpty {
            let migrated = settings.workerIDNumber
            do {
                try KeychainStore.setString(migrated, for: .workerIDNumber)
                settings.workerIDNumber = ""
                try save(settings, to: settingsURL)
                settings.workerIDNumber = migrated
            } catch {
                logger.error("Failed to migrate worker ID to Keychain: \(error.localizedDescription, privacy: .private)")
                settings.workerIDNumber = migrated
            }
            return settings
        }

        settings.workerIDNumber = KeychainStore.string(for: .workerIDNumber) ?? ""
        return settings
    }

    func saveSettings(_ settings: WorkplaceSettings) throws {
        migrateProtectionIfNeeded()
        do {
            try KeychainStore.setString(settings.workerIDNumber, for: .workerIDNumber)
        } catch {
            logger.error("Failed to persist worker ID to Keychain: \(error.localizedDescription, privacy: .private)")
            throw error
        }
        var diskCopy = settings
        diskCopy.workerIDNumber = ""
        try save(diskCopy, to: settingsURL)
    }

    // MARK: - Private

    private func migrateProtectionIfNeeded() {
        guard !didMigrateProtection else { return }
        didMigrateProtection = true
        for url in [sessionsURL, settingsURL] {
            do {
                try ProtectedFileMigration.ensureProtection(
                    at: url,
                    fileManager: fileManager,
                    writer: fileWriter
                )
            } catch {
                logger.error("Failed to migrate file protection for \(url.lastPathComponent, privacy: .private): \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    private func load<T: Decodable>(from url: URL) -> T? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.error("Failed to load \(url.lastPathComponent, privacy: .private): \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    private func save<T: Encodable>(_ value: T, to url: URL) throws {
        do {
            let data = try encoder.encode(value)
            try fileWriter.write(data, to: url)
        } catch {
            logger.error("Failed to save \(url.lastPathComponent, privacy: .private): \(error.localizedDescription, privacy: .private)")
            throw error
        }
    }
}
