import Foundation

/// JSON schema for structured timesheet rows produced by an LLM (or local heuristic).
struct ScannerLLMRow: Codable, Equatable, Sendable {
    var date: String
    var clockIn: String
    var clockOut: String
    var totalHours: Double?
    var confidence: Double?

    enum CodingKeys: String, CodingKey {
        case date
        case clockIn = "clock_in"
        case clockOut = "clock_out"
        case totalHours = "total_hours"
        case confidence
    }
}

struct ScannerLLMPayload: Codable, Equatable, Sendable {
    var rows: [ScannerLLMRow]
}

struct ScannerLLMStructureResult: Equatable, Sendable {
    var rows: [ScannerLLMRow]
    var providerName: String
    var rawJSON: String?
}

struct ScannerProcessingDetails: Equatable, Sendable {
    var providerName: String
    var acceptedCount: Int
    var rejectedCount: Int
    var reviewCount: Int
    var notes: [String]

    var summaryLine: String {
        "\(providerName): \(acceptedCount) ok, \(reviewCount) review, \(rejectedCount) rejected"
    }
}

enum ScannerLLMError: Error, Equatable {
    case missingAPIKey
    case rateLimited
    case quotaExceeded
    case network(String)
    case invalidResponse(String)
    case emptyResult
}
