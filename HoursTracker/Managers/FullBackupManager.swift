import Foundation
import HoursTrackerKit

/// Lossless full-app backup (sessions + settings + activity log).
/// File type: `.htbackup.json` with `formatID == hourstracker.backup`.
enum FullBackupError: LocalizedError {
    case invalidFormat
    case unsupportedVersion(Int)
    case encodeFailed
    case writeFailed
    case emptyBackup

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return L10n.backupErrorInvalidFormat
        case .unsupportedVersion(let v):
            return L10n.backupErrorUnsupportedVersion(v)
        case .encodeFailed, .writeFailed:
            return L10n.backupErrorWriteFailed
        case .emptyBackup:
            return L10n.backupErrorEmpty
        }
    }
}

enum FullBackupRestoreMode: String, CaseIterable, Identifiable {
    case replace
    case merge
    var id: Self { self }
}

struct FullBackupDocument: Codable, Equatable {
    static let formatID = "hourstracker.backup"
    static let currentVersion = 1

    var formatID: String
    var formatVersion: Int
    var exportedAt: Date
    var appVersion: String
    var settings: WorkplaceSettings
    var sessions: [WorkSession]
    var activityLog: [ActivityLogEntry]

    /// Summary for confirmation UI (computed, also encoded for older clients).
    var sessionCount: Int { sessions.count }
    var completedSessionCount: Int { sessions.filter { $0.clockOut != nil }.count }
    var lastSessionClockIn: Date? {
        sessions.map(\.clockIn).max()
    }

    var monthCount: Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let keys = Set(sessions.map { session -> String in
            let c = cal.dateComponents([.year, .month], from: session.date)
            return "\(c.year ?? 0)-\(c.month ?? 0)"
        })
        return keys.count
    }

    init(
        formatID: String = FullBackupDocument.formatID,
        formatVersion: Int = FullBackupDocument.currentVersion,
        exportedAt: Date = Date(),
        appVersion: String,
        settings: WorkplaceSettings,
        sessions: [WorkSession],
        activityLog: [ActivityLogEntry]
    ) {
        self.formatID = formatID
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.settings = settings
        self.sessions = sessions
        self.activityLog = activityLog
    }
}

struct FullBackupSummary: Equatable {
    let exportedAt: Date
    let sessionCount: Int
    let completedSessionCount: Int
    let monthCount: Int
    let lastSessionClockIn: Date?
    let appVersion: String
    let workerName: String
}

/// Builds, stores, and validates lossless backups. Auto copies live in the App Group.
final class FullBackupManager {
    static let shared = FullBackupManager()

    static let fileExtension = "htbackup.json"
    static let latestFileName = "latest.htbackup.json"
    static let maxAutomaticBackups = 14
    /// Skip another automatic backup if one ran within this interval (unless forced).
    static let automaticMinInterval: TimeInterval = 20 * 60 * 60

    private let fileManager: FileManager
    private let fileWriter: FileWriting
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let lastAutoBackupKey = "ht.backup.lastAutomaticAt"
    private let lastUserBackupKey = "ht.backup.lastUserExportAt"

    init(
        fileManager: FileManager = .default,
        fileWriter: FileWriting = ProtectedFileWriter.shared
    ) {
        self.fileManager = fileManager
        self.fileWriter = fileWriter
    }

    // MARK: - Locations

    var backupsDirectoryURL: URL? {
        let group = WatchSharedStore.containerURL?
            .appendingPathComponent("backups", isDirectory: true)
        if let group {
            try? fileManager.createDirectory(at: group, withIntermediateDirectories: true)
            return group
        }
        // Fallback if App Group unavailable (simulator / misconfigured entitlements).
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("backups", isDirectory: true)
        try? fileManager.createDirectory(at: docs, withIntermediateDirectories: true)
        return docs
    }

    var latestBackupURL: URL? {
        backupsDirectoryURL?.appendingPathComponent(Self.latestFileName)
    }

    // MARK: - Build / parse

    func makeDocument(
        settings: WorkplaceSettings,
        sessions: [WorkSession],
        activityLog: [ActivityLogEntry],
        exportedAt: Date = Date(),
        appVersion: String = Self.appVersionString()
    ) -> FullBackupDocument {
        FullBackupDocument(
            exportedAt: exportedAt,
            appVersion: appVersion,
            settings: settings,
            sessions: sessions.sorted { $0.clockIn < $1.clockIn },
            activityLog: activityLog
        )
    }

    func encode(_ document: FullBackupDocument) throws -> Data {
        do {
            return try encoder.encode(document)
        } catch {
            throw FullBackupError.encodeFailed
        }
    }

    func decode(from data: Data) throws -> FullBackupDocument {
        // Primary: dedicated backup format.
        if let doc = try? decoder.decode(FullBackupDocument.self, from: data),
           doc.formatID == FullBackupDocument.formatID {
            guard doc.formatVersion <= FullBackupDocument.currentVersion else {
                throw FullBackupError.unsupportedVersion(doc.formatVersion)
            }
            return doc
        }

        // Compatibility: Full Data Export JSON (same payload fields, no formatID).
        if let legacy = try? decoder.decode(FullDataExportDocument.self, from: data) {
            let exportedAt = ISO8601DateFormatter().date(from: legacy.exportedAt) ?? Date()
            return FullBackupDocument(
                exportedAt: exportedAt,
                appVersion: legacy.appVersion,
                settings: legacy.settings,
                sessions: legacy.sessions,
                activityLog: legacy.activityLog
            )
        }

        throw FullBackupError.invalidFormat
    }

    func summary(of document: FullBackupDocument) -> FullBackupSummary {
        FullBackupSummary(
            exportedAt: document.exportedAt,
            sessionCount: document.sessionCount,
            completedSessionCount: document.completedSessionCount,
            monthCount: document.monthCount,
            lastSessionClockIn: document.lastSessionClockIn,
            appVersion: document.appVersion,
            workerName: document.settings.workerFullName
        )
    }

    // MARK: - User export (temp file for Share / Files)

    func writeExportFile(
        settings: WorkplaceSettings,
        sessions: [WorkSession],
        activityLog: [ActivityLogEntry],
        exportedAt: Date = Date()
    ) throws -> URL {
        let document = makeDocument(
            settings: settings,
            sessions: sessions,
            activityLog: activityLog,
            exportedAt: exportedAt
        )
        let data = try encode(document)
        let stamp = Self.fileStampFormatter.string(from: exportedAt)
        let name = "HoursTracker-Backup-\(stamp).\(Self.fileExtension)"
        let url = try ExportTempFileStore.write(data: data, fileName: name, writer: fileWriter)
        markUserBackup(at: exportedAt)
        return url
    }

    // MARK: - Sync Now + automatic

    @discardableResult
    func syncNow(
        settings: WorkplaceSettings,
        sessions: [WorkSession],
        activityLog: [ActivityLogEntry],
        at date: Date = Date()
    ) throws -> URL {
        let url = try writeRollingBackup(
            settings: settings,
            sessions: sessions,
            activityLog: activityLog,
            at: date,
            prefix: "backup"
        )
        markUserBackup(at: date)
        markAutomaticBackup(at: date)
        return url
    }

    /// Silent daily / post–clock-out backup. No-ops if last auto backup is recent.
    @discardableResult
    func performAutomaticBackupIfNeeded(
        settings: WorkplaceSettings,
        sessions: [WorkSession],
        activityLog: [ActivityLogEntry],
        force: Bool = false,
        now: Date = Date()
    ) throws -> URL? {
        if !force, let last = lastAutomaticBackupDate(),
           now.timeIntervalSince(last) < Self.automaticMinInterval {
            return nil
        }
        let url = try writeRollingBackup(
            settings: settings,
            sessions: sessions,
            activityLog: activityLog,
            at: now,
            prefix: "auto"
        )
        markAutomaticBackup(at: now)
        return url
    }

    @discardableResult
    func writePreRestoreSnapshot(
        settings: WorkplaceSettings,
        sessions: [WorkSession],
        activityLog: [ActivityLogEntry],
        at date: Date = Date()
    ) throws -> URL {
        try writeRollingBackup(
            settings: settings,
            sessions: sessions,
            activityLog: activityLog,
            at: date,
            prefix: "pre-restore"
        )
    }

    private func writeRollingBackup(
        settings: WorkplaceSettings,
        sessions: [WorkSession],
        activityLog: [ActivityLogEntry],
        at date: Date,
        prefix: String
    ) throws -> URL {
        guard let dir = backupsDirectoryURL, let latest = latestBackupURL else {
            throw FullBackupError.writeFailed
        }
        let document = makeDocument(
            settings: settings,
            sessions: sessions,
            activityLog: activityLog,
            exportedAt: date
        )
        let data = try encode(document)
        let stamp = Self.fileStampFormatter.string(from: date)
        let dated = dir.appendingPathComponent("\(prefix)_\(stamp).\(Self.fileExtension)")
        try fileWriter.write(data, to: dated)
        try fileWriter.write(data, to: latest)
        pruneOldBackups(in: dir)
        return dated
    }

    func pruneOldBackups(in directory: URL? = nil) {
        guard let directory = directory ?? backupsDirectoryURL else { return }
        let items = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let dated = items.filter {
            $0.lastPathComponent != Self.latestFileName
                && $0.lastPathComponent.hasSuffix(Self.fileExtension)
        }
        .sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db
        }
        for stale in dated.dropFirst(Self.maxAutomaticBackups) {
            try? fileManager.removeItem(at: stale)
        }
    }

    func listBackupFiles() -> [URL] {
        guard let directory = backupsDirectoryURL else { return [] }
        let items = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return items
            .filter { $0.lastPathComponent.hasSuffix(Self.fileExtension) }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
    }

    // MARK: - Timestamps

    func lastBackupDate() -> Date? {
        let user = UserDefaults.standard.object(forKey: lastUserBackupKey) as? Date
        let auto = lastAutomaticBackupDate()
        let latestFile: Date? = {
            guard let url = latestBackupURL,
                  fileManager.fileExists(atPath: url.path),
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            else { return nil }
            return values.contentModificationDate
        }()
        return [user, auto, latestFile].compactMap { $0 }.max()
    }

    func lastAutomaticBackupDate() -> Date? {
        UserDefaults.standard.object(forKey: lastAutoBackupKey) as? Date
    }

    private func markUserBackup(at date: Date) {
        UserDefaults.standard.set(date, forKey: lastUserBackupKey)
    }

    private func markAutomaticBackup(at date: Date) {
        UserDefaults.standard.set(date, forKey: lastAutoBackupKey)
    }

    static func appVersionString() -> String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    private static let fileStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f
    }()
}
