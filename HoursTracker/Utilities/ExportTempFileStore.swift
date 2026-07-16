import Foundation
import os

/// Protected temp files for export/share flows. Always written under `tmp/Exports/`
/// with Data Protection, and wiped after sharing, on launch, background, and delete-all.
enum ExportTempFileStore {
    private static let logger = Logger(subsystem: "com.hourstracker.app", category: "exportTemp")
    private static let folderName = "Exports"

    static var exportsDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(folderName, isDirectory: true)
    }

    static func prepareDirectory(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(
            at: exportsDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Creates a protected file in the exports directory and returns its URL.
    static func write(
        data: Data,
        fileName: String,
        writer: FileWriting = ProtectedFileWriter.shared,
        fileManager: FileManager = .default
    ) throws -> URL {
        try prepareDirectory(fileManager: fileManager)
        let url = exportsDirectory.appendingPathComponent(fileName)
        try writer.write(data, to: url)
        return url
    }

    /// Removes a single export file (best-effort).
    static func remove(_ url: URL, fileManager: FileManager = .default) {
        guard url.path.contains("/\(folderName)/") else { return }
        try? fileManager.removeItem(at: url)
    }

    /// Deletes every file in the exports directory.
    static func wipeAll(fileManager: FileManager = .default) {
        let dir = exportsDirectory
        guard fileManager.fileExists(atPath: dir.path) else { return }
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            )
            for url in contents {
                try fileManager.removeItem(at: url)
            }
        } catch {
            logger.error("Failed to wipe export temp files: \(error.localizedDescription, privacy: .private)")
        }
    }
}
