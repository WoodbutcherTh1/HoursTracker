import Foundation

/// Provider that turns raw OCR text from a payslip into structured fields.
///
/// Parallel to `ScannerLLMProviding` (timesheet rows), kept as a separate protocol so
/// cloud providers can specialise the prompt and JSON schema without overloading the
/// timesheet payload type. Both protocols reuse the shared `ScannerLLMError` cases.
protocol PayslipLLMProviding: Sendable {
    var name: String { get }
    func extractPayslip(ocrText: String) async throws -> PayslipLLMStructureResult
}
