import Foundation

/// Moves unreadable store files aside so a fresh empty/default store can be written
/// without destroying corrupt bytes (recoverable via a `.corrupt` sibling).
enum CorruptFileQuarantine {
    /// Quarantines `url` to `url.corrupt` (or a timestamped sibling if that exists).
    @discardableResult
    static func quarantine(
        at url: URL,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) -> URL? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        var destination = url.appendingPathExtension("corrupt")
        if fileManager.fileExists(atPath: destination.path) {
            let stamp = Int(now.timeIntervalSince1970)
            destination = url.appendingPathExtension("corrupt.\(stamp)")
        }

        do {
            try fileManager.moveItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    /// Removes quarantine sidecars for a primary store file (used by Delete All My Data).
    static func removeSidecars(
        for url: URL,
        fileManager: FileManager = .default
    ) {
        let directory = url.deletingLastPathComponent()
        let baseName = url.lastPathComponent
        guard let items = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        for item in items {
            let name = item.lastPathComponent
            if name == "\(baseName).corrupt" || name.hasPrefix("\(baseName).corrupt.") {
                try? fileManager.removeItem(at: item)
            }
        }
    }
}
