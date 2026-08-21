import Foundation

/// A finished assistant reply. Every string on it is either an `L10n` template or a
/// value formatted from the user's own data — there is no field a model can write into.
struct AssistantAnswer: Equatable {
    /// One labeled figure, e.g. ("125%", "6:30").
    struct Row: Equatable {
        let label: String
        let value: String
    }

    /// Something the reply carries alongside the text.
    enum Attachment: Equatable {
        /// A report the assistant generated through `ExportManager`.
        case document(url: URL, fileName: String)
        /// A payslip the user had already uploaded, found by `findPayslip`.
        case payslip(record: PayslipRecord, fileURL: URL)
    }

    /// The sentence at the top of the bubble.
    let headline: String
    /// What was actually counted — always shown, so the scope of a number is never
    /// left implicit.
    var scope: String?
    var rows: [Row] = []
    /// Secondary line: an explanation, a caveat, or an empty-result note.
    var note: String?
    var attachment: Attachment?

    static func plain(_ headline: String, note: String? = nil) -> AssistantAnswer {
        AssistantAnswer(headline: headline, note: note)
    }
}

/// Why the assistant couldn't answer. Each maps to a fixed, translated message; none of
/// them is written by a model.
enum AssistantFailure: Equatable {
    /// No API key saved — the assistant is switched off, not broken.
    case notConfigured
    case rateLimited
    case network
    case unreadableResponse

    init(_ error: ScannerLLMError) {
        switch error {
        case .missingAPIKey:
            self = .notConfigured
        case .rateLimited, .quotaExceeded:
            self = .rateLimited
        case .network:
            self = .network
        case .invalidResponse, .emptyResult:
            self = .unreadableResponse
        }
    }

    var message: String {
        switch self {
        case .notConfigured: return L10n.assistantNotConfigured
        case .rateLimited: return L10n.assistantRateLimited
        case .network: return L10n.assistantNetworkError
        case .unreadableResponse: return L10n.assistantUnreadable
        }
    }
}
