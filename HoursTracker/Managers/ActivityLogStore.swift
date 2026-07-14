import Foundation

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
@MainActor
final class ActivityLogStore: ObservableObject {
    static let shared = ActivityLogStore()

    @Published private(set) var entries: [ActivityLogEntry] = []

    private let maxEntries = 500
    private let fileManager = FileManager.default
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

    private var logURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("activity_log.json")
    }

    private init() {
        load()
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
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("SaatMark-Log-\(stamp).\(format.fileExtension)")
        try data.write(to: url, options: .atomic)
        log(
            L10n.logEventLogExported,
            level: .success,
            category: "log",
            details: format.fileExtension.uppercased()
        )
        return url
    }

    // MARK: - Persistence

    private func load() {
        guard fileManager.fileExists(atPath: logURL.path),
              let data = try? Data(contentsOf: logURL),
              let decoded = try? decoder.decode([ActivityLogEntry].self, from: data)
        else {
            entries = []
            return
        }
        entries = decoded
    }

    private func persist() {
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: logURL, options: .atomic)
    }

    // MARK: - Renderers

    private var stampFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }

    private func renderTXT() -> String {
        var lines = ["SaatMark — Activity Log", ""]
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
                csv(stamp),
                csv(entry.level.rawValue),
                csv(entry.category),
                csv(entry.message),
                csv(entry.details ?? "")
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    private func renderMarkdown() -> String {
        var lines = [
            "# SaatMark — Activity Log",
            "",
            "| Time | Level | Category | Message | Details |",
            "| --- | --- | --- | --- | --- |"
        ]
        for entry in entries {
            let stamp = stampFormatter.string(from: entry.timestamp)
            let details = (entry.details ?? "").replacingOccurrences(of: "|", with: "\\|")
            let message = entry.message.replacingOccurrences(of: "|", with: "\\|")
            lines.append("| \(stamp) | \(entry.level.rawValue) | \(entry.category) | \(message) | \(details) |")
        }
        return lines.joined(separator: "\n")
    }

    private func csv(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            return "\"\(escaped)\""
        }
        return escaped
    }
}
