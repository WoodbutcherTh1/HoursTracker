import Foundation

/// Lossless full-app backup (sessions + settings + activity log + payslips).
/// File type: `.htbackup.zip` with `formatID == hourstracker.backup`.
enum FullBackupError: LocalizedError {
    case invalidFormat
    case unsupportedVersion(Int)
    case encodeFailed
    case writeFailed
    case emptyBackup
    case payslipFileMissing(UUID)
    case backupTooLarge(bytes: Int)
    case payslipEntryTooLarge(UUID, bytes: Int)

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
        case .payslipFileMissing(let id):
            return L10n.backupErrorPayslipMissing(id.uuidString)
        case .backupTooLarge(let bytes):
            return L10n.backupErrorTooLarge(Self.byteCountString(bytes))
        case .payslipEntryTooLarge(let id, let bytes):
            return L10n.backupErrorPayslipEntryTooLarge("\(id.uuidString), \(Self.byteCountString(bytes))")
        }
    }

    private static func byteCountString(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

enum FullBackupRestoreMode: String, CaseIterable, Identifiable {
    case replace
    case merge
    var id: Self { self }
}

struct FullBackupDocument: Codable, Equatable {
    static let formatID = "hourstracker.backup"
    static let currentVersion = 2
    static let appGroupID = "group.com.hourstracker.app"

    var formatID: String
    var formatVersion: Int
    var exportedAt: Date
    var appVersion: String
    var settings: WorkplaceSettings
    var sessions: [WorkSession]
    var activityLog: [ActivityLogEntry]
    var payslipRecords: [PayslipRecord]

    var sessionCount: Int { sessions.count }
    var completedSessionCount: Int { sessions.filter { $0.clockOut != nil }.count }
    var lastSessionClockIn: Date? { sessions.map(\.clockIn).max() }

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
        activityLog: [ActivityLogEntry],
        payslipRecords: [PayslipRecord] = []
    ) {
        self.formatID = formatID
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.settings = settings
        self.sessions = sessions
        self.activityLog = activityLog
        self.payslipRecords = payslipRecords
    }

    private enum CodingKeys: String, CodingKey {
        case formatID
        case formatVersion
        case exportedAt
        case appVersion
        case settings
        case sessions
        case activityLog
        case payslipRecords
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatID = try container.decode(String.self, forKey: .formatID)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        appVersion = try container.decode(String.self, forKey: .appVersion)
        settings = try container.decode(WorkplaceSettings.self, forKey: .settings)
        sessions = try container.decode([WorkSession].self, forKey: .sessions)
        activityLog = try container.decode([ActivityLogEntry].self, forKey: .activityLog)
        payslipRecords = try container.decodeIfPresent([PayslipRecord].self, forKey: .payslipRecords) ?? []
    }
}

struct FullBackupPackage: Equatable {
    var document: FullBackupDocument
    var payslipFiles: [UUID: Data]
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

/// Builds, stores, and validates lossless backups. Auto copies prefer the App Group.
final class FullBackupManager {
    static let shared = FullBackupManager()

    static let fileExtension = "htbackup.zip"
    static let legacyJSONExtension = "htbackup.json"
    static let latestFileName = "latest.htbackup.zip"
    static let maxAutomaticBackups = 14
    static let automaticMinInterval: TimeInterval = 20 * 60 * 60
    static let softMaxBackupBytes = 200 * 1024 * 1024

    private let fileManager: FileManager
    private let fileWriter: FileWriting
    private let backupsDirectoryOverride: URL?
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
    private let contentDirtyKey = "ht.backup.contentDirty"

    init(
        fileManager: FileManager = .default,
        fileWriter: FileWriting = ProtectedFileWriter.shared,
        backupsDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.fileWriter = fileWriter
        self.backupsDirectoryOverride = backupsDirectory
    }

    var backupsDirectoryURL: URL? {
        if let backupsDirectoryOverride {
            try? fileManager.createDirectory(at: backupsDirectoryOverride, withIntermediateDirectories: true)
            return backupsDirectoryOverride
        }
        let groupRoot = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: FullBackupDocument.appGroupID
        )
        let base = groupRoot
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("backups", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var latestBackupURL: URL? {
        backupsDirectoryURL?.appendingPathComponent(Self.latestFileName)
    }

    func makeDocument(
        settings: WorkplaceSettings,
        sessions: [WorkSession],
        activityLog: [ActivityLogEntry],
        payslipRecords: [PayslipRecord] = [],
        exportedAt: Date = Date(),
        appVersion: String = Self.appVersionString()
    ) -> FullBackupDocument {
        FullBackupDocument(
            exportedAt: exportedAt,
            appVersion: appVersion,
            settings: settings,
            sessions: sessions.sorted { $0.clockIn < $1.clockIn },
            activityLog: activityLog,
            payslipRecords: payslipRecords.sorted { $0.uploadedAt < $1.uploadedAt }
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
        if let doc = try? decoder.decode(FullBackupDocument.self, from: data),
           doc.formatID == FullBackupDocument.formatID {
            guard doc.formatVersion <= FullBackupDocument.currentVersion else {
                throw FullBackupError.unsupportedVersion(doc.formatVersion)
            }
            return doc
        }

        if let legacy = try? decoder.decode(FullDataExportDocument.self, from: data) {
            let exportedAt = ISO8601DateFormatter().date(from: legacy.exportedAt) ?? Date()
            return FullBackupDocument(
                exportedAt: exportedAt,
                appVersion: legacy.appVersion,
                settings: legacy.settings,
                sessions: legacy.sessions,
                activityLog: legacy.activityLog,
                payslipRecords: []
            )
        }

        throw FullBackupError.invalidFormat
    }

    func loadBackupPackage(from url: URL) throws -> FullBackupPackage {
        let data = try Data(contentsOf: url)
        if Self.isZipBackup(url: url, data: data) {
            do {
                let manifest = try ZipWriter.data(forEntry: "manifest.json", in: data)
                let document = try decode(from: manifest)
                let entryPaths = try ZipWriter.entryPaths(in: data)
                let payslipFiles = try loadPayslipEntries(from: data, entryPaths: entryPaths)
                try validatePayslipPayloads(document: document, payslipFiles: payslipFiles)
                return FullBackupPackage(document: document, payslipFiles: payslipFiles)
            } catch let error as FullBackupError {
                throw error
            } catch {
                throw FullBackupError.invalidFormat
            }
        }
        let document = try decode(from: data)
        return FullBackupPackage(document: document, payslipFiles: [:])
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

    func writeExportFile(
        settings: WorkplaceSettings,
        sessions: [WorkSession],
        activityLog: [ActivityLogEntry],
        exportedAt: Date = Date(),
        payslipStore: PayslipStore = .shared
    ) throws -> URL {
        let document = try makeDocumentWithPayslips(
            settings: settings,
            sessions: sessions,
            activityLog: activityLog,
            exportedAt: exportedAt,
            payslipStore: payslipStore
        )
        let stamp = Self.fileStampFormatter.string(from: exportedAt)
        let name = "HoursTracker-Backup-\(stamp).\(Self.fileExtension)"
        try ExportTempFileStore.prepareDirectory(fileManager: fileManager)
        let url = ExportTempFileStore.exportsDirectory.appendingPathComponent(name)
        try writePackage(document: document, payslipStore: payslipStore, to: url)
        markUserBackup(at: exportedAt)
        return url
    }

    @discardableResult
    func syncNow(
        settings: WorkplaceSettings,
        sessions: [WorkSession],
        activityLog: [ActivityLogEntry],
        at date: Date = Date(),
        payslipStore: PayslipStore = .shared
    ) throws -> URL {
        let url = try writeRollingBackup(
            settings: settings,
            sessions: sessions,
            activityLog: activityLog,
            at: date,
            prefix: "backup",
            payslipStore: payslipStore
        )
        markUserBackup(at: date)
        markAutomaticBackup(at: date)
        clearContentDirty()
        return url
    }

    @discardableResult
    func performAutomaticBackupIfNeeded(
        settings: WorkplaceSettings,
        sessions: [WorkSession],
        activityLog: [ActivityLogEntry],
        force: Bool = false,
        now: Date = Date(),
        payslipStore: PayslipStore = .shared
    ) throws -> URL? {
        let dirty = isContentDirty()
        if !force, !dirty, let last = lastAutomaticBackupDate(),
           now.timeIntervalSince(last) < Self.automaticMinInterval {
            return nil
        }
        let url = try writeRollingBackup(
            settings: settings,
            sessions: sessions,
            activityLog: activityLog,
            at: now,
            prefix: "auto",
            payslipStore: payslipStore
        )
        markAutomaticBackup(at: now)
        clearContentDirty()
        return url
    }

    @discardableResult
    func writePreRestoreSnapshot(
        settings: WorkplaceSettings,
        sessions: [WorkSession],
        activityLog: [ActivityLogEntry],
        at date: Date = Date(),
        payslipStore: PayslipStore = .shared
    ) throws -> URL {
        try writeRollingBackup(
            settings: settings,
            sessions: sessions,
            activityLog: activityLog,
            at: date,
            prefix: "pre-restore",
            payslipStore: payslipStore
        )
    }

    func markContentDirty() {
        UserDefaults.standard.set(true, forKey: contentDirtyKey)
    }

    func isContentDirty() -> Bool {
        UserDefaults.standard.bool(forKey: contentDirtyKey)
    }

    func clearContentDirty() {
        UserDefaults.standard.removeObject(forKey: contentDirtyKey)
    }

    func validatePayslipPayloads(document: FullBackupDocument, payslipFiles: [UUID: Data]) throws {
        for record in document.payslipRecords {
            guard let data = payslipFiles[record.id] else {
                throw FullBackupError.payslipFileMissing(record.id)
            }
            if Int64(data.count) > PayslipStore.maxFileBytes {
                throw FullBackupError.payslipEntryTooLarge(record.id, bytes: data.count)
            }
        }
    }

    private func makeDocumentWithPayslips(
        settings: WorkplaceSettings,
        sessions: [WorkSession],
        activityLog: [ActivityLogEntry],
        exportedAt: Date,
        payslipStore: PayslipStore
    ) throws -> FullBackupDocument {
        try makeDocument(
            settings: settings,
            sessions: sessions,
            activityLog: activityLog,
            payslipRecords: payslipStore.listPayslips(),
            exportedAt: exportedAt
        )
    }

    private func writeRollingBackup(
        settings: WorkplaceSettings,
        sessions: [WorkSession],
        activityLog: [ActivityLogEntry],
        at date: Date,
        prefix: String,
        payslipStore: PayslipStore
    ) throws -> URL {
        guard let dir = backupsDirectoryURL else {
            throw FullBackupError.writeFailed
        }
        let document = try makeDocumentWithPayslips(
            settings: settings,
            sessions: sessions,
            activityLog: activityLog,
            exportedAt: date,
            payslipStore: payslipStore
        )
        let stamp = Self.fileStampFormatter.string(from: date)
        let dated = dir.appendingPathComponent("\(prefix)_\(stamp).\(Self.fileExtension)")
        let latest = dir.appendingPathComponent(Self.latestFileName)
        try writePackage(document: document, payslipStore: payslipStore, to: dated)
        try writePackage(document: document, payslipStore: payslipStore, to: latest)
        pruneOldBackups(in: dir)
        return dated
    }

    private func writePackage(
        document: FullBackupDocument,
        payslipStore: PayslipStore,
        to url: URL
    ) throws {
        let entries = try packageEntries(for: document, payslipStore: payslipStore)
        let uncompressedBytes = entries.reduce(0) { $0 + $1.data.count }
        guard uncompressedBytes <= Self.softMaxBackupBytes else {
            throw FullBackupError.backupTooLarge(bytes: uncompressedBytes)
        }
        try ZipWriter.createArchive(entries: entries, outputURL: url, fileWriter: fileWriter)
    }

    private func packageEntries(
        for document: FullBackupDocument,
        payslipStore: PayslipStore
    ) throws -> [ZipWriter.Entry] {
        var entries = [
            ZipWriter.Entry(path: "manifest.json", data: try encode(document))
        ]
        for record in document.payslipRecords {
            let fileURL = payslipStore.url(for: record)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                throw FullBackupError.payslipFileMissing(record.id)
            }
            let data = try Data(contentsOf: fileURL)
            guard Int64(data.count) <= PayslipStore.maxFileBytes else {
                throw FullBackupError.payslipEntryTooLarge(record.id, bytes: data.count)
            }
            entries.append(
                ZipWriter.Entry(
                    path: "payslips/\(record.id.uuidString).\(backupExtension(for: record))",
                    data: data
                )
            )
        }
        return entries
    }

    private func loadPayslipEntries(from archive: Data, entryPaths: [String]) throws -> [UUID: Data] {
        var files: [UUID: Data] = [:]
        for path in entryPaths where path.hasPrefix("payslips/") {
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            let idString = (fileName as NSString).deletingPathExtension
            guard let id = UUID(uuidString: idString) else {
                continue
            }
            let data = try ZipWriter.data(forEntry: path, in: archive)
            if Int64(data.count) > PayslipStore.maxFileBytes {
                throw FullBackupError.payslipEntryTooLarge(id, bytes: data.count)
            }
            files[id] = data
        }
        return files
    }

    private func backupExtension(for record: PayslipRecord) -> String {
        let ext = (record.relativeFilePath as NSString).pathExtension.lowercased()
        if !ext.isEmpty { return ext }
        switch record.sourceKind {
        case .image:
            return "img"
        case .pdf:
            return "pdf"
        }
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
                && ($0.lastPathComponent.hasSuffix(Self.fileExtension)
                    || $0.lastPathComponent.hasSuffix(Self.legacyJSONExtension))
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

    private static func isZipBackup(url: URL, data: Data) -> Bool {
        if url.lastPathComponent.hasSuffix(fileExtension) { return true }
        guard data.count >= 4 else { return false }
        return data[0] == 0x50 && data[1] == 0x4b && data[2] == 0x03 && data[3] == 0x04
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
