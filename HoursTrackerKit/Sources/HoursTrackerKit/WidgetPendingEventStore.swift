import Foundation

/// App Group queue for clock events originating from iOS / watch widgets.
/// Phone drains and applies via `AppViewModel.applyWatchClockEvent`; watch flushes via WCSession.
public enum WidgetPendingEventStore {
    public static let fileName = "widget_pending_clock_events.json"

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
        WatchSharedStore.containerURL?.appendingPathComponent(fileName)
    }

    public static func load() -> [WatchClockEvent] {
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
}
