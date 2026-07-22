import Foundation
import os
import PDFKit
import UniformTypeIdentifiers

enum PayslipStoreError: Error, Equatable {
    case fileTooLarge(maxBytes: Int64, actualBytes: Int64)
    case unsupportedFileType
    case passwordProtectedPDF
    case unreadablePDF
    case recordNotFound(UUID)
    case temporarilyUnavailable
    case invalidStoredPath(UUID)
}

extension PayslipStoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .fileTooLarge(maxBytes, actualBytes):
            return "Payslip file is too large (\(actualBytes) bytes). Maximum allowed size is \(maxBytes) bytes."
        case .unsupportedFileType:
            return "Payslips must be imported as an image or PDF file."
        case .passwordProtectedPDF:
            return "Password-protected PDF payslips cannot be imported."
        case .unreadablePDF:
            return "The PDF payslip could not be opened."
        case let .recordNotFound(id):
            return "Payslip record not found: \(id.uuidString)."
        case .temporarilyUnavailable:
            return "Payslip storage is temporarily unavailable. Please try again when the device is unlocked."
        case let .invalidStoredPath(id):
            return "Payslip record has an invalid storage path: \(id.uuidString)."
        }
    }
}

enum PayslipPDFInspectionResult: Equatable {
    case unlocked
    case locked
    case unreadable
}

protocol PayslipPDFInspecting {
    func inspectPDF(at url: URL) -> PayslipPDFInspectionResult
    func inspectPDF(data: Data) -> PayslipPDFInspectionResult
}

struct PDFKitPayslipPDFInspector: PayslipPDFInspecting {
    static let shared = PDFKitPayslipPDFInspector()

    func inspectPDF(at url: URL) -> PayslipPDFInspectionResult {
        guard let document = PDFDocument(url: url) else {
            return .unreadable
        }
        return inspect(document: document)
    }

    func inspectPDF(data: Data) -> PayslipPDFInspectionResult {
        guard let document = PDFDocument(data: data) else {
            return .unreadable
        }
        return inspect(document: document)
    }

    private func inspect(document: PDFDocument) -> PayslipPDFInspectionResult {
        if document.isLocked || document.isEncrypted {
            return .locked
        }
        return .unlocked
    }
}

final class PayslipStore {
    static let shared = PayslipStore()

    static let appGroupIdentifier = "group.com.hourstracker.app"
    static let maxFileBytes: Int64 = 25 * 1024 * 1024

    private let fileManager: FileManager
    private let fileWriter: FileWriting
    private let dataReader: DataReading
    private let pdfInspector: PayslipPDFInspecting
    private let rootDirectoryOverride: URL?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger = Logger(subsystem: "com.hourstracker.app", category: "payslips")

    private var rootDirectory: URL {
        if let rootDirectoryOverride {
            return rootDirectoryOverride
        }
        return fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        ) ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var payslipsDirectory: URL {
        rootDirectory.appendingPathComponent("payslips", isDirectory: true)
    }

    var indexURL: URL {
        payslipsDirectory.appendingPathComponent("index.json")
    }

    var filesDirectory: URL {
        payslipsDirectory.appendingPathComponent("files", isDirectory: true)
    }

    init(
        fileManager: FileManager = .default,
        fileWriter: FileWriting = ProtectedFileWriter.shared,
        dataReader: DataReading = DefaultDataReader.shared,
        pdfInspector: PayslipPDFInspecting = PDFKitPayslipPDFInspector.shared,
        rootDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.fileWriter = fileWriter
        self.dataReader = dataReader
        self.pdfInspector = pdfInspector
        self.rootDirectoryOverride = rootDirectory
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    static func wipeAll() {
        shared.removeAllStoredData()
    }

    func loadRecordsResult() -> PersistenceLoadResult<[PayslipRecord]> {
        loadIndex()
    }

    func listPayslips() throws -> [PayslipRecord] {
        switch loadIndex() {
        case let .loaded(records):
            return records
        case .missing, .corruptQuarantined:
            return []
        case .temporarilyUnavailable:
            throw PayslipStoreError.temporarilyUnavailable
        }
    }

    @discardableResult
    func importFile(
        from fileURL: URL,
        periodMonth: Date,
        periodStartDay: Int? = nil,
        periodLabel: String? = nil,
        extraction: PayslipExtraction,
        userOverrides: PayslipOverrides? = nil,
        reviewState: PayslipRecord.ReviewState = .pendingReview,
        notes: String? = nil,
        id: UUID = UUID(),
        uploadedAt: Date = Date()
    ) throws -> PayslipRecord {
        let contentType = try resolvedContentType(for: fileURL)
        let sourceKind = try sourceKind(for: contentType, fileExtension: fileURL.pathExtension)
        let byteSize = try validateFileSize(at: fileURL)
        if sourceKind == .pdf {
            try validatePDFIsImportable(at: fileURL)
        }

        let records = try mutableRecordsForWrite()
        let data = try Data(contentsOf: fileURL)
        return try storePayslip(
            data: data,
            byteSize: byteSize,
            originalFileName: fileURL.lastPathComponent,
            originalExtension: fileURL.pathExtension,
            contentType: contentType,
            sourceKind: sourceKind,
            periodMonth: periodMonth,
            periodStartDay: periodStartDay,
            periodLabel: periodLabel,
            extraction: extraction,
            userOverrides: userOverrides,
            reviewState: reviewState,
            notes: notes,
            id: id,
            uploadedAt: uploadedAt,
            existingRecords: records
        )
    }

    @discardableResult
    func addPayslip(
        fileData: Data,
        originalFileName: String,
        contentType: UTType,
        periodMonth: Date,
        periodStartDay: Int? = nil,
        periodLabel: String? = nil,
        extraction: PayslipExtraction,
        userOverrides: PayslipOverrides? = nil,
        reviewState: PayslipRecord.ReviewState = .pendingReview,
        notes: String? = nil,
        id: UUID = UUID(),
        uploadedAt: Date = Date()
    ) throws -> PayslipRecord {
        let byteSize = Int64(fileData.count)
        try validateFileSize(byteSize)
        let sourceKind = try sourceKind(for: contentType, fileExtension: (originalFileName as NSString).pathExtension)
        if sourceKind == .pdf {
            try validatePDFIsImportable(data: fileData)
        }

        let records = try mutableRecordsForWrite()
        return try storePayslip(
            data: fileData,
            byteSize: byteSize,
            originalFileName: originalFileName,
            originalExtension: (originalFileName as NSString).pathExtension,
            contentType: contentType,
            sourceKind: sourceKind,
            periodMonth: periodMonth,
            periodStartDay: periodStartDay,
            periodLabel: periodLabel,
            extraction: extraction,
            userOverrides: userOverrides,
            reviewState: reviewState,
            notes: notes,
            id: id,
            uploadedAt: uploadedAt,
            existingRecords: records
        )
    }

    func deletePayslip(id: UUID) throws {
        var records = try mutableRecordsForWrite()
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw PayslipStoreError.recordNotFound(id)
        }
        let record = records.remove(at: index)
        try saveIndex(records)
        let storedFileURL = url(for: record)
        if fileManager.fileExists(atPath: storedFileURL.path) {
            try fileManager.removeItem(at: storedFileURL)
        }
        FullBackupManager.shared.markContentDirty()
    }

    func url(for record: PayslipRecord) -> URL {
        rootDirectory.appendingPathComponent(record.relativeFilePath)
    }

    func removeAllStoredData(markContentDirty: Bool = true) {
        guard fileManager.fileExists(atPath: payslipsDirectory.path) else { return }
        do {
            try fileManager.removeItem(at: payslipsDirectory)
            if markContentDirty {
                FullBackupManager.shared.markContentDirty()
            }
        } catch {
            logger.error("Failed to wipe payslips directory: \(error.localizedDescription, privacy: .private)")
        }
    }

    func replaceAll(records: [PayslipRecord], fileDataByID: [UUID: Data]) throws {
        try validateRestorePayloads(records: records, fileDataByID: fileDataByID)
        removeAllStoredData(markContentDirty: false)
        try writeRestoredFiles(records: records, fileDataByID: fileDataByID)
        try saveIndex(records.sorted { $0.uploadedAt < $1.uploadedAt })
        FullBackupManager.shared.markContentDirty()
    }

    func merge(records incomingRecords: [PayslipRecord], fileDataByID: [UUID: Data]) throws {
        guard !incomingRecords.isEmpty else { return }
        try validateRestorePayloads(records: incomingRecords, fileDataByID: fileDataByID)
        var byID = Dictionary(uniqueKeysWithValues: try mutableRecordsForWrite().map { ($0.id, $0) })
        for record in incomingRecords {
            byID[record.id] = record
        }
        try writeRestoredFiles(records: incomingRecords, fileDataByID: fileDataByID)
        try saveIndex(byID.values.sorted { $0.uploadedAt < $1.uploadedAt })
        FullBackupManager.shared.markContentDirty()
    }

    static func isTransientReadError(_ error: Error) -> Bool {
        PersistenceManager.isTransientReadError(error)
    }

    private func loadIndex() -> PersistenceLoadResult<[PayslipRecord]> {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return .missing
        }

        let data: Data
        do {
            data = try dataReader.read(from: indexURL)
        } catch {
            if isMissingFileError(error) {
                return .missing
            }
            let transient = Self.isTransientReadError(error)
            logger.error("Failed to read payslip index (transient=\(transient)): \(error.localizedDescription, privacy: .private)")
            return .temporarilyUnavailable
        }

        do {
            return .loaded(try decoder.decode([PayslipRecord].self, from: data))
        } catch {
            logger.error("Failed to decode payslip index: \(error.localizedDescription, privacy: .private)")
            if let quarantined = CorruptFileQuarantine.quarantine(at: indexURL, fileManager: fileManager) {
                logger.error("Quarantined corrupt payslip index as \(quarantined.lastPathComponent, privacy: .private)")
            }
            return .corruptQuarantined
        }
    }

    private func mutableRecordsForWrite() throws -> [PayslipRecord] {
        switch loadIndex() {
        case let .loaded(records):
            return records
        case .missing, .corruptQuarantined:
            return []
        case .temporarilyUnavailable:
            throw PayslipStoreError.temporarilyUnavailable
        }
    }

    private func storePayslip(
        data: Data,
        byteSize: Int64,
        originalFileName: String,
        originalExtension: String,
        contentType: UTType,
        sourceKind: PayslipRecord.SourceKind,
        periodMonth: Date,
        periodStartDay: Int?,
        periodLabel: String?,
        extraction: PayslipExtraction,
        userOverrides: PayslipOverrides?,
        reviewState: PayslipRecord.ReviewState,
        notes: String?,
        id: UUID,
        uploadedAt: Date,
        existingRecords: [PayslipRecord]
    ) throws -> PayslipRecord {
        let storedExtension = storageExtension(
            for: contentType,
            sourceKind: sourceKind,
            originalExtension: originalExtension
        )
        let relativeFilePath = "payslips/files/\(id.uuidString).\(storedExtension)"
        let fileURL = rootDirectory.appendingPathComponent(relativeFilePath)
        let record = PayslipRecord(
            id: id,
            periodMonth: Calendar.current.ht_payslipStartOfMonth(for: periodMonth),
            periodStartDay: periodStartDay,
            periodLabel: periodLabel,
            uploadedAt: uploadedAt,
            sourceKind: sourceKind,
            originalFileName: originalFileName,
            relativeFilePath: relativeFilePath,
            fileByteSize: Int(byteSize),
            contentTypeUTI: contentType.identifier,
            extraction: extraction,
            userOverrides: userOverrides,
            reviewState: reviewState,
            notes: notes
        )

        var records = existingRecords.filter { $0.id != id }
        records.append(record)
        try fileWriter.write(data, to: fileURL)
        do {
            try saveIndex(records)
        } catch {
            try? fileManager.removeItem(at: fileURL)
            throw error
        }
        FullBackupManager.shared.markContentDirty()
        return record
    }

    private func validateRestorePayloads(records: [PayslipRecord], fileDataByID: [UUID: Data]) throws {
        for record in records {
            guard let data = fileDataByID[record.id] else {
                throw FullBackupError.payslipFileMissing(record.id)
            }
            try validateFileSize(Int64(data.count))
            _ = try validatedRestoredFileURL(for: record)
        }
    }

    private func writeRestoredFiles(records: [PayslipRecord], fileDataByID: [UUID: Data]) throws {
        for record in records {
            guard let data = fileDataByID[record.id] else {
                throw FullBackupError.payslipFileMissing(record.id)
            }
            try fileWriter.write(data, to: validatedRestoredFileURL(for: record))
        }
    }

    private func validatedRestoredFileURL(for record: PayslipRecord) throws -> URL {
        let components = record.relativeFilePath.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0] == "payslips",
              components[1] == "files" else {
            throw PayslipStoreError.invalidStoredPath(record.id)
        }
        let fileName = String(components[2])
        guard !fileName.isEmpty,
              !fileName.contains("/"),
              !fileName.contains(".."),
              (fileName as NSString).deletingPathExtension == record.id.uuidString else {
            throw PayslipStoreError.invalidStoredPath(record.id)
        }
        return filesDirectory.appendingPathComponent(fileName)
    }

    private func saveIndex(_ records: [PayslipRecord]) throws {
        do {
            let data = try encoder.encode(records)
            try fileWriter.write(data, to: indexURL)
        } catch {
            logger.error("Failed to save payslip index: \(error.localizedDescription, privacy: .private)")
            throw error
        }
    }

    private func resolvedContentType(for fileURL: URL) throws -> UTType {
        if let contentType = try fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType
        }
        if let type = UTType(filenameExtension: fileURL.pathExtension) {
            return type
        }
        throw PayslipStoreError.unsupportedFileType
    }

    private func sourceKind(for contentType: UTType, fileExtension: String) throws -> PayslipRecord.SourceKind {
        if contentType.conforms(to: .pdf) {
            return .pdf
        }
        if contentType.conforms(to: .image) {
            return .image
        }
        switch fileExtension.lowercased() {
        case "pdf":
            return .pdf
        case "png", "jpg", "jpeg", "heic", "tif", "tiff":
            return .image
        default:
            throw PayslipStoreError.unsupportedFileType
        }
    }

    private func storageExtension(
        for contentType: UTType,
        sourceKind: PayslipRecord.SourceKind,
        originalExtension: String
    ) -> String {
        let sanitizedOriginal = originalExtension.lowercased()
        if sourceKind == .pdf {
            return "pdf"
        }
        if ["png", "jpg", "jpeg", "heic", "tif", "tiff"].contains(sanitizedOriginal) {
            return sanitizedOriginal
        }
        return contentType.preferredFilenameExtension ?? "img"
    }

    @discardableResult
    private func validateFileSize(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let size = Int64(values.fileSize ?? 0)
        if size > 0 {
            try validateFileSize(size)
            return size
        }

        let attrs = try fileManager.attributesOfItem(atPath: url.path)
        let attrSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        try validateFileSize(attrSize)
        return attrSize
    }

    private func validateFileSize(_ byteSize: Int64) throws {
        if byteSize > Self.maxFileBytes {
            throw PayslipStoreError.fileTooLarge(maxBytes: Self.maxFileBytes, actualBytes: byteSize)
        }
    }

    private func validatePDFIsImportable(at url: URL) throws {
        switch pdfInspector.inspectPDF(at: url) {
        case .unlocked:
            return
        case .locked:
            throw PayslipStoreError.passwordProtectedPDF
        case .unreadable:
            throw PayslipStoreError.unreadablePDF
        }
    }

    private func validatePDFIsImportable(data: Data) throws {
        switch pdfInspector.inspectPDF(data: data) {
        case .unlocked:
            return
        case .locked:
            throw PayslipStoreError.passwordProtectedPDF
        case .unreadable:
            throw PayslipStoreError.unreadablePDF
        }
    }

    private func isMissingFileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == NSFileReadNoSuchFileError {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain,
           nsError.code == Int(ENOENT) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isMissingFileError(underlying)
        }
        return false
    }
}

private extension Calendar {
    func ht_payslipStartOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components).map(startOfDay(for:)) ?? startOfDay(for: date)
    }
}
