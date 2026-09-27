import Foundation

// MARK: - Recently deleted shifts

/// A deleted shift, kept for `DeletedSessionsStore.retention` so a mistaken delete
/// can be undone.
struct DeletedSession: Codable, Equatable, Identifiable {
    var session: WorkSession
    var deletedAt: Date

    var id: UUID { session.id }
}

/// "Recently deleted" bin for shifts. Deleting a shift moves it here instead of
/// dropping it; it can be restored for 30 days, after which it's purged.
///
/// Lives in Application Support (not Documents — nothing here is meant for the
/// Files app), written atomically with Data Protection like every other store.
final class DeletedSessionsStore {
    static let shared = DeletedSessionsStore()
    static let retention: TimeInterval = 30 * 24 * 3600

    private let url: URL
    private let writer: FileWriting

    init(
        directory: URL = DataSafetyPaths.root,
        writer: FileWriting = ProtectedFileWriter.shared
    ) {
        url = directory.appendingPathComponent("deleted_sessions.json")
        self.writer = writer
    }

    /// Newest first, with anything past the retention window left out.
    func load(now: Date = Date()) -> [DeletedSession] {
        guard let data = try? Data(contentsOf: url),
              let items = try? Self.decoder.decode([DeletedSession].self, from: data) else { return [] }
        return items
            .filter { now.timeIntervalSince($0.deletedAt) < Self.retention }
            .sorted { $0.deletedAt > $1.deletedAt }
    }

    func add(_ session: WorkSession, at date: Date = Date()) throws {
        var items = load(now: date).filter { $0.id != session.id }
        items.insert(DeletedSession(session: session, deletedAt: date), at: 0)
        try save(items)
    }

    /// Removes and returns the entry (for restore or delete-forever).
    @discardableResult
    func remove(id: UUID) throws -> DeletedSession? {
        var items = load()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = items.remove(at: index)
        try save(items)
        return removed
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: url)
    }

    private func save(_ items: [DeletedSession]) throws {
        try writer.write(try Self.encoder.encode(items), to: url)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

// MARK: - Automatic on-device backups

/// One automatic backup on disk.
struct LocalBackup: Identifiable, Equatable {
    let url: URL
    let createdAt: Date
    let sessionCount: Int
    /// True for the snapshot taken automatically right before a restore.
    let isPreRestore: Bool

    var id: URL { url }
}

/// Daily automatic backups of all shifts + settings, kept on the device for
/// `keepDays` days, restorable from Settings.
///
/// Each backup is a regular full-data export JSON (`FullDataExportDocument`), so
/// restoring goes through the same tested import path as a manual export file.
/// The day's backup is taken the first time the app saves or opens that day — the
/// state *before* anything that happens later that day — and is never overwritten,
/// so a mistake made during the day can always be rolled back to that morning.
final class LocalBackupStore {
    static let shared = LocalBackupStore()
    static let keepDays = 14

    private let directory: URL
    private let writer: FileWriting

    init(
        directory: URL = DataSafetyPaths.root.appendingPathComponent("Backups", isDirectory: true),
        writer: FileWriting = ProtectedFileWriter.shared
    ) {
        self.directory = directory
        self.writer = writer
    }

    /// Takes today's backup if there isn't one yet. Never backs up an empty
    /// shift list — an empty snapshot would only push real ones out of the window.
    @discardableResult
    func backupIfNeeded(
        settings: WorkplaceSettings,
        sessions: [WorkSession],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard !sessions.isEmpty else { return false }
        let url = directory.appendingPathComponent("backup-\(Self.dayKey(now, calendar: calendar)).json")
        guard !FileManager.default.fileExists(atPath: url.path) else { return false }
        do {
            try write(settings: settings, sessions: sessions, to: url, at: now)
            prune()
            return true
        } catch {
            return false
        }
    }

    /// Snapshot of the current state taken right before a restore, so restoring
    /// the wrong day can itself be undone.
    func backupBeforeRestore(settings: WorkplaceSettings, sessions: [WorkSession], now: Date = Date()) {
        guard !sessions.isEmpty else { return }
        let stamp = Int(now.timeIntervalSince1970)
        let url = directory.appendingPathComponent("pre-restore-\(stamp).json")
        try? write(settings: settings, sessions: sessions, to: url, at: now)
        prune()
    }

    /// Newest first.
    func list() -> [LocalBackup] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey]
        )) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> LocalBackup? in
                guard let document = try? load(url) else { return nil }
                // The time recorded inside the backup; the file date only as a fallback.
                let created = ISO8601DateFormatter().date(from: document.exportedAt)
                    ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
                    ?? .distantPast
                return LocalBackup(
                    url: url,
                    createdAt: created,
                    sessionCount: document.sessions.count,
                    isPreRestore: url.lastPathComponent.hasPrefix("pre-restore-")
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func load(_ url: URL) throws -> FullDataExportDocument {
        try FullDataExportManager().decodeJSONDocument(from: Data(contentsOf: url))
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(settings: WorkplaceSettings, sessions: [WorkSession], to url: URL, at date: Date) throws {
        let data = try FullDataExportManager().buildJSON(
            settings: settings,
            sessions: sessions,
            activityLog: [],
            exportedAt: date
        )
        try writer.write(data, to: url)
    }

    /// Keeps the newest `keepDays` daily backups and the 3 newest pre-restore ones.
    private func prune() {
        let all = list()
        let daily = all.filter { !$0.isPreRestore }
        let preRestore = all.filter(\.isPreRestore)
        for backup in Array(daily.dropFirst(Self.keepDays)) + Array(preRestore.dropFirst(3)) {
            try? FileManager.default.removeItem(at: backup.url)
        }
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

enum DataSafetyPaths {
    /// Application Support/HoursTracker — not exposed to the Files app, included in
    /// the device's own iCloud/Finder backups.
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("HoursTracker", isDirectory: true)
    }
}
