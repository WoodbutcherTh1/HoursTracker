import Foundation
import HoursTrackerKit
import WidgetKit

/// Small local JSON cache of the last `WatchSnapshot` on the watch.
final class WatchPersistenceManager {
    static let shared = WatchPersistenceManager()

    private let fileURL: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("watch_snapshot.json")
    }

    func load() -> WatchSnapshot? {
        if let shared = WatchSharedStore.loadSnapshot() {
            return shared
        }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(WatchSnapshot.self, from: data)
    }

    func save(_ snapshot: WatchSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: [.atomic])
        // Mirror into the App Group for WidgetKit complications.
        if WatchSharedStore.saveSnapshot(snapshot) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
