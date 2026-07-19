import Foundation

/// Queue of clock events waiting to flush to the phone.
/// When backed by the App Group URL, the iPhone can drain the same file on cold launch.
/// Persists as JSON; safe to replay (phone dedupes by event `id`).
public final class WatchPendingActionQueue: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private var events: [WatchClockEvent]

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? d.decode([WatchClockEvent].self, from: data) {
            self.events = decoded
        } else {
            self.events = []
        }
    }

    public convenience init(directory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) {
        self.init(fileURL: directory.appendingPathComponent("watch_pending_clock_events.json"))
    }

    public var pending: [WatchClockEvent] {
        lock.lock(); defer { lock.unlock() }
        mergeDiskLocked()
        return events
    }

    public func enqueue(_ event: WatchClockEvent) {
        lock.lock()
        mergeDiskLocked()
        if !events.contains(where: { $0.id == event.id }) {
            events.append(event)
            persistLocked()
        }
        lock.unlock()
    }

    /// Returns a snapshot of pending events to transfer, without clearing.
    public func snapshot() -> [WatchClockEvent] {
        pending
    }

    /// Remove events the phone has acknowledged (by event id).
    public func removeAcknowledged(ids: Set<UUID>) {
        lock.lock()
        mergeDiskLocked()
        events.removeAll { ids.contains($0.id) }
        persistLocked()
        lock.unlock()
    }

    public func remove(id: UUID) {
        removeAcknowledged(ids: [id])
    }

    /// Pull in any events written by `WidgetPendingEventStore` (same App Group file).
    private func mergeDiskLocked() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([WatchClockEvent].self, from: data)
        else { return }
        for event in decoded where !events.contains(where: { $0.id == event.id }) {
            events.append(event)
        }
    }

    private func persistLocked() {
        guard let data = try? encoder.encode(events) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
