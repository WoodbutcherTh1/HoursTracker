import Foundation
import os

/// Outcome of a store load that distinguishes "no data yet" from
/// "data exists on disk but we couldn't read it right now".
///
/// The `.temporarilyUnavailable` case is what protects against the silent-wipe
/// path: an intact `sessions.json` that was momentarily unreadable (Data
/// Protection race, POSIX EBUSY, etc.) must NOT collapse to `.loaded([])` in
/// the public API, because the caller would then treat that as an empty store
/// and happily persist `[]` back over the real file on the next save.
enum PersistenceLoadResult<T> {
    /// The file existed and decoded successfully.
    case loaded(T)
    /// No file on disk. Safe to treat as an empty/default store.
    case missing
    /// The file exists on disk but every read attempt (including bounded
    /// retries) failed with a transient error. Callers MUST NOT overwrite the
    /// file with defaults; the intact bytes are still there.
    case temporarilyUnavailable
    /// Bytes were read but did not decode. The primary file has already been
    /// moved aside to a `.corrupt` sibling; safe to treat as empty/default.
    case corruptQuarantined
}

protocol PersistableStore: AnyObject {
    func loadSessions() -> [WorkSession]
    /// Preferred loader: exposes whether the underlying file was intact-but-unreadable.
    /// Callers with meaningful in-memory state (e.g. `AppViewModel`) MUST use this
    /// variant so a transient read failure does not turn into an empty-wipe on the
    /// next save.
    func loadSessionsResult() -> PersistenceLoadResult<[WorkSession]>
    func saveSessions(_ sessions: [WorkSession]) throws
    func loadSettings() -> WorkplaceSettings
    /// Preferred loader (see `loadSessionsResult`).
    func loadSettingsResult() -> PersistenceLoadResult<WorkplaceSettings>
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
        switch loadSessionsResult() {
        case .loaded(let sessions):
            return sessions
        case .missing, .corruptQuarantined, .temporarilyUnavailable:
            // Compatibility path only: callers that still use this method opt into the
            // legacy "return empty on failure" behavior. New code should use
            // `loadSessionsResult()` so it can distinguish the wipe-risk case.
            return []
        }
    }

    func loadSessionsResult() -> PersistenceLoadResult<[WorkSession]> {
        migrateProtectionIfNeeded()
        return load(from: sessionsURL)
    }

    func saveSessions(_ sessions: [WorkSession]) throws {
        migrateProtectionIfNeeded()
        try save(sessions, to: sessionsURL)
    }

    func loadSettings() -> WorkplaceSettings {
        switch loadSettingsResult() {
        case .loaded(let settings):
            return settings
        case .missing, .corruptQuarantined, .temporarilyUnavailable:
            var settings = WorkplaceSettings.default
            settings.workerIDNumber = KeychainStore.string(for: .workerIDNumber) ?? ""
            return settings
        }
    }

    func loadSettingsResult() -> PersistenceLoadResult<WorkplaceSettings> {
        migrateProtectionIfNeeded()
        let raw: PersistenceLoadResult<WorkplaceSettings> = load(from: settingsURL)
        switch raw {
        case .loaded(var settings):
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
                return .loaded(settings)
            }
            settings.workerIDNumber = KeychainStore.string(for: .workerIDNumber) ?? ""
            return .loaded(settings)
        case .missing, .corruptQuarantined, .temporarilyUnavailable:
            return raw
        }
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
    /// The four `PersistenceLoadResult` cases exist specifically to protect
    /// callers from the "protected-file-read → empty-load → next-save-wipe"
    /// pattern. Read/decode outcomes map as follows:
    ///
    /// - **File missing on disk** → `.missing`. Safe to treat as an empty
    ///   store (fresh install, delete-all).
    /// - **Transient read failure** (e.g. `.completeFileProtectionUnlessOpen`
    ///   still holds the class key just after unlock, or a POSIX
    ///   `EBUSY`/`EACCES` race). We retry a small, bounded number of times
    ///   with a short backoff. If retries exhaust while the file is still on
    ///   disk, we return `.temporarilyUnavailable` **without** quarantining.
    ///   The intact bytes stay on disk so the next launch (post-unlock) can
    ///   recover them, and callers know NOT to overwrite with defaults.
    /// - **Non-transient read failure with the file still on disk** →
    ///   `.temporarilyUnavailable` (same reasoning: we would rather surface a
    ///   temporary unreadable state than let a caller destroy real data).
    /// - **Decode failure** (bytes were read successfully but did not parse
    ///   as `T`). This is a genuine corruption signal, so we quarantine the
    ///   file to a `.corrupt` sibling and return `.corruptQuarantined`.
    private func load<T: Decodable>(from url: URL) -> PersistenceLoadResult<T> {
        guard fileManager.fileExists(atPath: url.path) else { return .missing }

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
                // The file is still on disk — the failure is at the read layer
                // (Data Protection, POSIX contention, non-transient I/O). We MUST
                // signal `temporarilyUnavailable` so callers do not overwrite the
                // intact bytes with an empty/default store on the next save.
                if fileManager.fileExists(atPath: url.path) {
                    return .temporarilyUnavailable
                }
                return .missing
            }

            do {
                return .loaded(try decoder.decode(T.self, from: data))
            } catch {
                logger.error("Failed to decode \(url.lastPathComponent, privacy: .private): \(error.localizedDescription, privacy: .private)")
                if let quarantined = CorruptFileQuarantine.quarantine(at: url, fileManager: fileManager) {
                    logger.error("Quarantined corrupt store as \(quarantined.lastPathComponent, privacy: .private)")
                }
                return .corruptQuarantined
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
