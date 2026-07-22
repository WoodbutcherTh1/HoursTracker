import Foundation

enum FullDataImportError: LocalizedError {
    case invalidFormat
    case unsupportedFileType
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return L10n.fullImportErrorInvalidFormat
        case .unsupportedFileType:
            return L10n.fullImportErrorUnsupportedType
        case .emptyFile:
            return L10n.fullImportErrorEmpty
        }
    }
}

enum FullDataImportMode: String, CaseIterable, Identifiable {
    case replace
    case merge
    var id: Self { self }
}

extension FullDataExportManager {
    /// Decodes a JSON file previously produced by `buildJSON` / full export (.json).
    func decodeJSONDocument(from data: Data) throws -> FullDataExportDocument {
        guard !data.isEmpty else { throw FullDataImportError.emptyFile }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(FullDataExportDocument.self, from: data)
        } catch {
            throw FullDataImportError.invalidFormat
        }
    }

    func loadJSONDocument(from url: URL) throws -> FullDataExportDocument {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        let data = try Data(contentsOf: url)
        return try decodeJSONDocument(from: data)
    }
}
