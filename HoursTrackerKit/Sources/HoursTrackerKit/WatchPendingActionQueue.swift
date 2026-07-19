import Foundation

/// Local queue of watch clock events waiting to flush to the phone.
/// Persists as JSON; safe to replay (phone dedupes by event `id`).
public final class WatchPendingActionQueue: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private var events: [WatchClockEvent]

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? decoder.decode([WatchClockEvent].self, from: data) {
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
        return events
    }

    public func enqueue(_ event: WatchClockEvent) {
        lock.lock()
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
        events.removeAll { ids.contains($0.id) }
        persistLocked()
        lock.unlock()
    }

    public func remove(id: UUID) {
        removeAcknowledged(ids: [id])
    }

    private func persistLocked() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(events) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
