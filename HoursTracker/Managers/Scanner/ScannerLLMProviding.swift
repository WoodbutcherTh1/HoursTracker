import Foundation

/// Provider that turns raw OCR / timesheet text into structured rows.
protocol ScannerLLMProviding: Sendable {
    var name: String { get }
    func structure(ocrText: String) async throws -> ScannerLLMStructureResult
}
