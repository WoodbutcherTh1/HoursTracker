import Foundation

/// App Group manifest + CSV file produced by `QuickExportIntent` for notification share (path A)
/// or hand-off when the app opens Export ready (path B).
public struct WidgetQuickExportManifest: Codable, Equatable, Sendable {
    public var fileName: String
    public var createdAt: Date
    public var openExportReady: Bool

    public init(fileName: String, createdAt: Date = Date(), openExportReady: Bool = false) {
        self.fileName = fileName
        self.createdAt = createdAt
        self.openExportReady = openExportReady
    }
}

public enum WidgetQuickExportStore {
    public static let directoryName = "widget_exports"
    public static let manifestFileName = "quick_export_manifest.json"
    public static let openExportFlagName = "open_export_ready.flag"

    public static let notificationCategoryID = "HT_QUICK_EXPORT"
    public static let shareActionID = "HT_SHARE_EXPORT"
    public static let notificationID = "ht.quick-export.ready"

    /// Deep link used when notification permission is denied (fallback B).
    public static let exportReadyURL = URL(string: "hourstracker://export?ready=1")!

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static var exportsDirectoryURL: URL? {
        guard let root = WatchSharedStore.containerURL else { return nil }
        let dir = root.appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var manifestURL: URL? {
        WatchSharedStore.containerURL?.appendingPathComponent(manifestFileName)
    }

    public static var openExportFlagURL: URL? {
        WatchSharedStore.containerURL?.appendingPathComponent(openExportFlagName)
    }

    public static func fileURL(named fileName: String) -> URL? {
        exportsDirectoryURL?.appendingPathComponent(fileName)
    }

    public static func saveManifest(_ manifest: WidgetQuickExportManifest) {
        guard let url = manifestURL,
              let data = try? encoder.encode(manifest)
        else { return }
        try? data.write(to: url, options: [.atomic])
    }

    public static func loadManifest() -> WidgetQuickExportManifest? {
        guard let url = manifestURL,
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? decoder.decode(WidgetQuickExportManifest.self, from: data)
    }

    public static func clearManifest() {
        if let url = manifestURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    public static func markOpenExportReady() {
        guard let url = openExportFlagURL else { return }
        try? Data().write(to: url, options: [.atomic])
    }

    /// Non-consuming check — used by `OpenExportReadyIntent.openAppWhenRun`.
    public static func peekOpenExportReady() -> Bool {
        guard let url = openExportFlagURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    public static func consumeOpenExportReady() -> Bool {
        guard let url = openExportFlagURL,
              FileManager.default.fileExists(atPath: url.path)
        else { return false }
        try? FileManager.default.removeItem(at: url)
        return true
    }

    /// Lightweight CSV from the shared snapshot (this payroll-ish month of completed sessions).
    public static func writeQuickCSV(from snapshot: WatchSnapshot, now: Date = Date()) -> URL? {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: now)
        guard let monthStart = cal.date(from: DateComponents(year: comps.year, month: comps.month, day: 1)),
              let monthEnd = cal.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)
        else { return nil }

        let monthEndOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: monthEnd) ?? monthEnd
        let sessions = snapshot.sessions
            .filter { !$0.isOpen }
            .filter {
                let d = $0.date
                return d >= monthStart && d <= monthEndOfDay
            }
            .sorted { $0.clockIn < $1.clockIn }

        let iso = ISO8601DateFormatter()
        var lines = ["date,clock_in,clock_out,hours,currency"]
        for session in sessions {
            let out = session.clockOut.map { iso.string(from: $0) } ?? ""
            let hours = String(format: "%.2f", session.totalHours)
            lines.append([
                iso.string(from: session.date),
                iso.string(from: session.clockIn),
                out,
                hours,
                snapshot.paySettings.currencyCode
            ].joined(separator: ","))
        }

        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(lines.joined(separator: "\n").utf8))
        data.append(Data("\n".utf8))

        let stamp = Int(now.timeIntervalSince1970)
        let fileName = "HoursTracker-quick-\(stamp).csv"
        guard let url = fileURL(named: fileName) else { return nil }
        do {
            try data.write(to: url, options: [.atomic])
            saveManifest(WidgetQuickExportManifest(fileName: fileName, createdAt: now, openExportReady: false))
            return url
        } catch {
            return nil
        }
    }
}
