import Foundation

/// Seam for verifying that persisted data is written with Data Protection options.
protocol FileWriting {
    func write(_ data: Data, to url: URL) throws
}

/// Seam for reading store bytes so tests can inject transient I/O failures.
///
/// Kept intentionally minimal: production code just forwards to `Data(contentsOf:)`.
protocol DataReading {
    func read(from url: URL) throws -> Data
}

struct DefaultDataReader: DataReading {
    static let shared = DefaultDataReader()

    func read(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }
}

/// Atomic writes with complete file protection while the file is closed.
/// Files remain readable by this process while open (`.completeFileProtectionUnlessOpen`).
struct ProtectedFileWriter: FileWriting {
    static let shared = ProtectedFileWriter()

    /// Options applied to every protected write in the app.
    static let writingOptions: Data.WritingOptions = [
        .atomic,
        .completeFileProtectionUnlessOpen
    ]

    func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: Self.writingOptions)
    }
}

enum ProtectedFileMigration {
    /// Re-writes an existing file so it carries `.completeUnlessOpen` protection.
    static func ensureProtection(
        at url: URL,
        fileManager: FileManager = .default,
        writer: FileWriting = ProtectedFileWriter.shared
    ) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let attrs = try fileManager.attributesOfItem(atPath: url.path)
        let protection = attrs[.protectionKey] as? FileProtectionType
        if protection == .completeUnlessOpen { return }
        let data = try Data(contentsOf: url)
        try writer.write(data, to: url)
    }

    static func protection(
        at url: URL,
        fileManager: FileManager = .default
    ) throws -> FileProtectionType? {
        let attrs = try fileManager.attributesOfItem(atPath: url.path)
        return attrs[.protectionKey] as? FileProtectionType
    }
}
