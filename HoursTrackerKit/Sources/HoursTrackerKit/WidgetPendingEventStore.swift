import Foundation

/// App Group queue for clock events from the watch app, complications, and iOS widgets.
/// Phone drains and applies via `AppViewModel.applyWatchClockEvent`.
/// Watch also mirrors into its WCSession flush path.
public enum WidgetPendingEventStore {
    /// Legacy filename — migrated into `WatchSharedStore.pendingEventsFileName` on first load.
    public static let legacyFileName = "widget_pending_clock_events.json"
    public static let fileName = WatchSharedStore.pendingEventsFileName

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

    public static var fileURL: URL? {
        WatchSharedStore.pendingEventsURL
    }

    private static var legacyFileURL: URL? {
        WatchSharedStore.containerURL?.appendingPathComponent(legacyFileName)
    }

    public static func load() -> [WatchClockEvent] {
        migrateLegacyIfNeeded()
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let events = try? decoder.decode([WatchClockEvent].self, from: data)
        else { return [] }
        return events
    }

    public static func save(_ events: [WatchClockEvent]) {
        guard let url = fileURL,
              let data = try? encoder.encode(events)
        else { return }
        try? data.write(to: url, options: [.atomic])
    }

    public static func enqueue(_ event: WatchClockEvent) {
        var events = load()
        if !events.contains(where: { $0.id == event.id }) {
            events.append(event)
            save(events)
            WatchSyncLog.event("AppGroup enqueue \(event.kind.rawValue) id=\(event.id.uuidString.prefix(8))")
        }
    }

    public static func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        var events = load()
        let before = events.count
        events.removeAll { ids.contains($0.id) }
        if events.count != before {
            save(events)
        }
    }

    public static func remove(id: UUID) {
        remove(ids: [id])
    }

    private static func migrateLegacyIfNeeded() {
        guard let legacy = legacyFileURL,
              let shared = fileURL,
              FileManager.default.fileExists(atPath: legacy.path)
        else { return }
        let legacyEvents: [WatchClockEvent]
        if let data = try? Data(contentsOf: legacy),
           let decoded = try? decoder.decode([WatchClockEvent].self, from: data) {
            legacyEvents = decoded
        } else {
            legacyEvents = []
        }
        var merged = (try? Data(contentsOf: shared)).flatMap {
            try? decoder.decode([WatchClockEvent].self, from: $0)
        } ?? []
        for event in legacyEvents where !merged.contains(where: { $0.id == event.id }) {
            merged.append(event)
        }
        if let data = try? encoder.encode(merged) {
            try? data.write(to: shared, options: [.atomic])
        }
        try? FileManager.default.removeItem(at: legacy)
    }
}
