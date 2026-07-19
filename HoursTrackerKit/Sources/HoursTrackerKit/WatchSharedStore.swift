import Foundation

/// App Group bridge so the watch app and its WidgetKit extension share one snapshot file.
public enum WatchSharedStore {
    public static let appGroupID = "group.com.hourstracker.app"
    public static let snapshotFileName = "watch_snapshot.json"

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

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    public static var snapshotURL: URL? {
        containerURL?.appendingPathComponent(snapshotFileName)
    }

    public static func loadSnapshot() -> WatchSnapshot? {
        guard let url = snapshotURL,
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? decoder.decode(WatchSnapshot.self, from: data)
    }

    @discardableResult
    public static func saveSnapshot(_ snapshot: WatchSnapshot) -> Bool {
        guard let url = snapshotURL,
              let data = try? encoder.encode(snapshot)
        else { return false }
        do {
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }
}
