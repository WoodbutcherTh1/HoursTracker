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
    private let dataReader: DataReading
    private let documentsDirectoryOverride: URL?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger = Logger(subsystem: "com.hourstracker.app", category: "persistence")
    private var didMigrateProtection = false

    /// Number of times `load` will re-attempt a read that failed with a transient error
    /// (e.g. Data Protection lock right after unlock, POSIX EBUSY/EACCES).
    /// The value is intentionally small so we never turn a persistent I/O outage into a hang.
    private let loadRetryAttempts: Int

    /// Base delay between transient read retries. Each subsequent retry doubles this.
    private let loadRetryBaseDelay: TimeInterval

    /// Sleep hook so tests can run retries without wall-clock delays.
    private let sleeper: (TimeInterval) -> Void

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
        dataReader: DataReading = DefaultDataReader.shared,
        documentsDirectory: URL? = nil,
        loadRetryAttempts: Int = 3,
        loadRetryBaseDelay: TimeInterval = 0.05,
        sleeper: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.fileManager = fileManager
        self.fileWriter = fileWriter
        self.dataReader = dataReader
        self.documentsDirectoryOverride = documentsDirectory
        self.loadRetryAttempts = max(1, loadRetryAttempts)
        self.loadRetryBaseDelay = max(0, loadRetryBaseDelay)
        self.sleeper = sleeper
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

    /// Loads and decodes a store file.
    ///
    /// Failure handling is intentionally split into two categories to avoid the
    /// "protected-file-read → quarantine → empty-load" wipe pattern:
    ///
    /// 1. **Transient read failures** (e.g. the file is momentarily unreadable
    ///    because `.completeFileProtectionUnlessOpen` has not yet released the
    ///    class key after unlock, or a POSIX EBUSY/EACCES race). We retry a
    ///    small, bounded number of times with a short backoff and, if the file
    ///    still can't be read, we return `nil` **without** quarantining. The
    ///    intact bytes stay on disk so the next launch (post-unlock) can
    ///    recover them.
    ///
    /// 2. **Decode failures** (bytes were read successfully but did not parse
    ///    as `T`). This is a genuine corruption signal, so we quarantine the
    ///    file to a `.corrupt` sibling as before.
    ///
    /// Non-transient read failures (e.g. permission denied that is not a
    /// Data-Protection race) also return `nil` without quarantining — we would
    /// rather surface a temporary empty read than destroy user data.
    private func load<T: Decodable>(from url: URL) -> T? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        var attempt = 0
        while true {
            attempt += 1
            let data: Data
            do {
                data = try dataReader.read(from: url)
            } catch {
                let transient = Self.isTransientReadError(error)
                if transient && attempt < loadRetryAttempts {
                    logger.error("Transient read failure for \(url.lastPathComponent, privacy: .private) (attempt \(attempt)/\(self.loadRetryAttempts)); retrying: \(error.localizedDescription, privacy: .private)")
                    let backoff = loadRetryBaseDelay * pow(2.0, Double(attempt - 1))
                    sleeper(backoff)
                    continue
                }
                logger.error("Read failed for \(url.lastPathComponent, privacy: .private) after \(attempt) attempt(s) (transient=\(transient)); leaving file intact: \(error.localizedDescription, privacy: .private)")
                return nil
            }

            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                logger.error("Failed to decode \(url.lastPathComponent, privacy: .private): \(error.localizedDescription, privacy: .private)")
                if let quarantined = CorruptFileQuarantine.quarantine(at: url, fileManager: fileManager) {
                    logger.error("Quarantined corrupt store as \(quarantined.lastPathComponent, privacy: .private)")
                }
                return nil
            }
        }
    }

    /// Classifies read errors that are worth retrying because the underlying
    /// resource is likely to become available again on its own — typically a
    /// Data-Protection race just after device unlock or a short-lived POSIX
    /// contention.
    ///
    /// We deliberately do NOT classify decode errors here; those are handled
    /// separately and always fall through to quarantine.
    static func isTransientReadError(_ error: Error) -> Bool {
        let nsError = error as NSError

        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileReadNoPermissionError,
                 NSFileReadUnknownError,
                 NSFileLockingError:
                return true
            default:
                break
            }
        }

        if nsError.domain == NSPOSIXErrorDomain {
            switch Int32(nsError.code) {
            case EPERM, EACCES, EBUSY, EAGAIN, EINTR, EIO:
                return true
            default:
                break
            }
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isTransientReadError(underlying)
        }

        return false
    }

    /// Removes `.corrupt` sidecars next to sessions/settings (Delete All My Data).
    func wipeQuarantinedSidecars() {
        CorruptFileQuarantine.removeSidecars(for: sessionsURL, fileManager: fileManager)
        CorruptFileQuarantine.removeSidecars(for: settingsURL, fileManager: fileManager)
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
