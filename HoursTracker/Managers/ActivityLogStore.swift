import Foundation
import os

enum ActivityLogLevel: String, Codable, CaseIterable {
    case info
    case success
    case warning
    case error
}

struct ActivityLogEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let level: ActivityLogLevel
    let category: String
    let message: String
    let details: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: ActivityLogLevel,
        category: String,
        message: String,
        details: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.details = details
    }
}

enum ActivityLogExportFormat: String, CaseIterable, Identifiable {
    case txt
    case json
    case csv
    case markdown

    var id: Self { self }

    var fileExtension: String { rawValue }

    var localizedName: String {
        switch self {
        case .txt: return L10n.logFormatTXT
        case .json: return L10n.logFormatJSON
        case .csv: return L10n.logFormatCSV
        case .markdown: return L10n.logFormatMarkdown
        }
    }
}

/// Persistent on-device activity log the user can browse and export.
/// Details must never contain PII, GPS coordinates, or free-text notes.
@MainActor
final class ActivityLogStore: ObservableObject {
    static let shared = ActivityLogStore()

    @Published private(set) var entries: [ActivityLogEntry] = []

    private let maxEntries = 500
    private let fileManager: FileManager
    private let fileWriter: FileWriting
    private let logger = Logger(subsystem: "com.hourstracker.app", category: "activityLog")
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

    var logURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("activity_log.json")
    }

    /// Matches legacy "lat, lon" details written before coordinate scrubbing.
    static let coordinateDetailsPattern = /^[+-]?\d+(\.\d+)?\s*,\s*[+-]?\d+(\.\d+)?$/

    init(
        fileManager: FileManager = .default,
        fileWriter: FileWriting = ProtectedFileWriter.shared
    ) {
        self.fileManager = fileManager
        self.fileWriter = fileWriter
        load()
        scrubCoordinateDetailsIfNeeded()
        migrateProtectionIfNeeded()
    }

    func log(
        _ message: String,
        level: ActivityLogLevel = .info,
        category: String,
        details: String? = nil
    ) {
        let entry = ActivityLogEntry(
            level: level,
            category: category,
            message: message,
            details: details
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        persist()
    }

    func clear() {
        entries = []
        persist()
        log(L10n.logClearedMessage, level: .info, category: "system")
    }

    /// Wipes the log without appending a follow-up entry (used by Delete All My Data).
    func wipeForPrivacy() {
        entries = []
        persist()
        CorruptFileQuarantine.removeSidecars(for: logURL, fileManager: fileManager)
    }

    func export(format: ActivityLogExportFormat) throws -> URL {
        let data: Data
        switch format {
        case .txt:
            data = Data(renderTXT().utf8)
        case .json:
            data = try encoder.encode(entries)
        case .csv:
            data = Data(renderCSV().utf8)
        case .markdown:
            data = Data(renderMarkdown().utf8)
        }

        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = try ExportTempFileStore.write(
            data: data,
            fileName: "HoursTracker-Log-\(stamp).\(format.fileExtension)",
            writer: fileWriter,
            fileManager: fileManager
        )
        log(
            L10n.logEventLogExported,
            level: .success,
            category: "log",
            details: format.fileExtension.uppercased()
        )
        return url
    }

    /// Test seam: replace in-memory entries without persisting first.
    func replaceEntriesForTesting(_ newEntries: [ActivityLogEntry]) {
        entries = newEntries
    }

    /// Replace the log with an imported set (used by full-data restore).
    func replaceEntries(_ newEntries: [ActivityLogEntry]) {
        entries = Array(newEntries.prefix(maxEntries))
        persist()
    }

    /// Merge imported entries by id, newest-first, capped at `maxEntries`.
    func mergeEntries(_ incoming: [ActivityLogEntry]) {
        var byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        for entry in incoming {
            byID[entry.id] = entry
        }
        entries = Array(
            byID.values.sorted { $0.timestamp > $1.timestamp }.prefix(maxEntries)
        )
        persist()
    }

    /// Removes coordinate-like details from historical "location" entries.
    func scrubCoordinateDetailsIfNeeded() {
        var changed = false
        let scrubbed = entries.map { entry -> ActivityLogEntry in
            guard entry.category == "location",
                  let details = entry.details,
                  details.wholeMatch(of: Self.coordinateDetailsPattern) != nil
            else {
                return entry
            }
            changed = true
            return ActivityLogEntry(
                id: entry.id,
                timestamp: entry.timestamp,
                level: entry.level,
                category: entry.category,
                message: entry.message,
                details: nil
            )
        }
        guard changed else { return }
        entries = scrubbed
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard fileManager.fileExists(atPath: logURL.path) else {
            entries = []
            return
        }
        do {
            let data = try Data(contentsOf: logURL)
            entries = try decoder.decode([ActivityLogEntry].self, from: data)
        } catch {
            logger.error("Failed to load activity log: \(error.localizedDescription, privacy: .private)")
            if let quarantined = CorruptFileQuarantine.quarantine(at: logURL, fileManager: fileManager) {
                logger.error("Quarantined corrupt activity log as \(quarantined.lastPathComponent, privacy: .private)")
            }
            entries = []
        }
    }

    private func persist() {
        do {
            let data = try encoder.encode(entries)
            try fileWriter.write(data, to: logURL)
        } catch {
            logger.error("Failed to persist activity log: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func migrateProtectionIfNeeded() {
        do {
            try ProtectedFileMigration.ensureProtection(
                at: logURL,
                fileManager: fileManager,
                writer: fileWriter
            )
        } catch {
            logger.error("Failed to migrate activity log protection: \(error.localizedDescription, privacy: .private)")
        }
    }

    // MARK: - Renderers

    private var stampFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }

    private func renderTXT() -> String {
        var lines = ["HoursTracker — Activity Log", ""]
        for entry in entries {
            let stamp = stampFormatter.string(from: entry.timestamp)
            var line = "[\(stamp)] [\(entry.level.rawValue.uppercased())] [\(entry.category)] \(entry.message)"
            if let details = entry.details, !details.isEmpty {
                line += " | \(details)"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    private func renderCSV() -> String {
        var rows = ["timestamp,level,category,message,details"]
        for entry in entries {
            let stamp = stampFormatter.string(from: entry.timestamp)
            rows.append([
                ExportSanitizer.csvCell(stamp),
                ExportSanitizer.csvCell(entry.level.rawValue),
                ExportSanitizer.csvCell(entry.category),
                ExportSanitizer.csvCell(entry.message),
                ExportSanitizer.csvCell(entry.details ?? "")
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    private func renderMarkdown() -> String {
        var lines = [
            "# HoursTracker — Activity Log",
            "",
            "| Time | Level | Category | Message | Details |",
            "| --- | --- | --- | --- | --- |"
        ]
        for entry in entries {
            let stamp = stampFormatter.string(from: entry.timestamp)
            let details = ExportSanitizer.markdownCell(entry.details ?? "")
            let message = ExportSanitizer.markdownCell(entry.message)
            lines.append("| \(stamp) | \(entry.level.rawValue) | \(entry.category) | \(message) | \(details) |")
        }
        return lines.joined(separator: "\n")
    }

    /// Test seam for CSV injection coverage.
    func renderCSVForTesting() -> String { renderCSV() }
}
