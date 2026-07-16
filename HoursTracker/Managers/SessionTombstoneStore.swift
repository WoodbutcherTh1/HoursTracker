import Foundation
import os

struct SessionTombstone: Codable, Equatable, Identifiable {
    let id: UUID
    let deletedAt: Date
}

/// Persists deleted session IDs so CloudKit merge cannot resurrect them.
protocol SessionTombstoneStoring: AnyObject {
    var tombstoneIDs: Set<UUID> { get }
    func record(ids: Set<UUID>, at date: Date)
    func prune(olderThan interval: TimeInterval)
    func remove(ids: Set<UUID>)
    func removeAll()
}

extension SessionTombstoneStoring {
    func record(ids: Set<UUID>) {
        record(ids: ids, at: Date())
    }

    func prune() {
        prune(olderThan: SessionTombstoneStore.defaultRetention)
    }
}

final class SessionTombstoneStore: SessionTombstoneStoring {
    static let shared = SessionTombstoneStore()
    static let defaultRetention: TimeInterval = 90 * 24 * 60 * 60

    private let fileManager: FileManager
    private let fileWriter: FileWriting
    private let documentsDirectoryOverride: URL?
    private let logger = Logger(subsystem: "com.hourstracker.app", category: "tombstones")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var tombstones: [UUID: SessionTombstone] = [:]

    private var fileURL: URL {
        let dir = documentsDirectoryOverride
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("session_tombstones.json")
    }

    var tombstoneIDs: Set<UUID> { Set(tombstones.keys) }

    init(
        fileManager: FileManager = .default,
        fileWriter: FileWriting = ProtectedFileWriter.shared,
        documentsDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.fileWriter = fileWriter
        self.documentsDirectoryOverride = documentsDirectory
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func record(ids: Set<UUID>, at date: Date = Date()) {
        guard !ids.isEmpty else { return }
        for id in ids {
            tombstones[id] = SessionTombstone(id: id, deletedAt: date)
        }
        persist()
    }

    func prune(olderThan interval: TimeInterval = SessionTombstoneStore.defaultRetention) {
        let cutoff = Date().addingTimeInterval(-interval)
        let before = tombstones.count
        tombstones = tombstones.filter { $0.value.deletedAt >= cutoff }
        if tombstones.count != before {
            persist()
        }
    }

    func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for id in ids { tombstones.removeValue(forKey: id) }
        persist()
    }

    func removeAll() {
        tombstones = [:]
        persist()
    }

    private func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            tombstones = [:]
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try decoder.decode([SessionTombstone].self, from: data)
            tombstones = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
        } catch {
            logger.error("Failed to load tombstones: \(error.localizedDescription, privacy: .private)")
            if let quarantined = CorruptFileQuarantine.quarantine(at: fileURL, fileManager: fileManager) {
                logger.error("Quarantined corrupt tombstones as \(quarantined.lastPathComponent, privacy: .private)")
            }
            tombstones = [:]
        }
    }

    /// Removes `.corrupt` sidecars (Delete All My Data).
    func wipeQuarantinedSidecars() {
        CorruptFileQuarantine.removeSidecars(for: fileURL, fileManager: fileManager)
    }

    private func persist() {
        do {
            let list = Array(tombstones.values).sorted { $0.deletedAt > $1.deletedAt }
            let data = try encoder.encode(list)
            try fileWriter.write(data, to: fileURL)
        } catch {
            logger.error("Failed to persist tombstones: \(error.localizedDescription, privacy: .private)")
        }
    }
}
