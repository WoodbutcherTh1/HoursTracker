import Foundation

/// Tracks watch clock-event IDs already applied on the phone (idempotency).
public final class WatchEventDedupeStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let maxCount: Int
    private let lock = NSLock()

    public init(
        defaults: UserDefaults = .standard,
        key: String = "ht.watchAppliedEventIDs",
        maxCount: Int = 200
    ) {
        self.defaults = defaults
        self.key = key
        self.maxCount = maxCount
    }

    public func contains(_ id: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return Set(defaults.stringArray(forKey: key) ?? []).contains(id.uuidString)
    }

    public func insert(_ id: UUID) {
        lock.lock()
        var arr = defaults.stringArray(forKey: key) ?? []
        let s = id.uuidString
        if !arr.contains(s) {
            arr.append(s)
            if arr.count > maxCount {
                arr = Array(arr.suffix(maxCount))
            }
            defaults.set(arr, forKey: key)
        }
        lock.unlock()
    }
}
