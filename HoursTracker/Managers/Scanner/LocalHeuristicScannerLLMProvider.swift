import Foundation

/// Wraps the existing regex / heuristic timesheet parser as a "local" LLM provider.
struct LocalHeuristicScannerLLMProvider: ScannerLLMProviding {
    let name = "Local"

    func structure(ocrText: String) async throws -> ScannerLLMStructureResult {
        // `parseSessions` is nonisolated — safe to call synchronously (no actor hop).
        let drafts = TimesheetScannerManager.shared.parseSessions(from: ocrText)
        let rows = drafts.map { draft -> ScannerLLMRow in
            let calendar = Calendar.current
            let day = calendar.component(.day, from: draft.date)
            let month = calendar.component(.month, from: draft.date)
            let year = calendar.component(.year, from: draft.date)
            let inH = calendar.component(.hour, from: draft.clockIn)
            let inM = calendar.component(.minute, from: draft.clockIn)
            let outH = calendar.component(.hour, from: draft.clockOut)
            let outM = calendar.component(.minute, from: draft.clockOut)
            return ScannerLLMRow(
                date: String(format: "%02d/%02d/%04d", day, month, year),
                clockIn: String(format: "%02d:%02d", inH, inM),
                clockOut: String(format: "%02d:%02d", outH, outM),
                totalHours: draft.totalHours,
                confidence: draft.confidence
            )
        }
        return ScannerLLMStructureResult(
            rows: rows,
            providerName: name,
            rawJSON: nil
        )
    }
}
