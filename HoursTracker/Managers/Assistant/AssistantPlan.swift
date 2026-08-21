import Foundation

/// What the assistant should do with the sessions a plan selects. Exactly one per
/// question. Anything the model returns that isn't one of these — including a topic the
/// app has no answer for — decodes as `outOfScope`, which is answered from a fixed
/// string in `AssistantEngine`, never by the model.
enum AssistantAction: String, Codable, Equatable, CaseIterable {
    /// Hours worked, split by regular / 125% / 150%.
    case summarizeHours = "summarize_hours"
    /// Gross or net pay for the selected sessions.
    case aggregatePay = "aggregate_pay"
    /// The individual shifts themselves, dated.
    case listSessions = "list_sessions"
    /// Days in a month with no completed shift.
    case listDaysWithoutSessions = "list_days_without_sessions"
    /// A PDF / Word / Markdown / plain-text report of the selected sessions.
    case generateDocument = "generate_document"
    /// Look up a payslip the user already uploaded. Retrieval, never generation.
    case findPayslip = "find_payslip"
    /// Nothing here can answer it.
    case outOfScope = "out_of_scope"
}

/// Which overtime tier a question is about.
enum AssistantOvertimeTier: String, Codable, Equatable, CaseIterable {
    case regular
    case ot125
    case ot150
}

/// Output file type the assistant can produce, mapped onto the app's existing
/// `ExportFormat` so documents come out of `ExportManager` like every other export.
enum AssistantDocumentFormat: String, Codable, Equatable, CaseIterable {
    case pdf
    case word
    case markdown
    case txt

    var exportFormat: ExportFormat {
        switch self {
        case .pdf: return .pdf
        case .word: return .docx
        case .markdown: return .markdown
        case .txt: return .txt
        }
    }
}

/// The composable filters. Each one corresponds to a single Swift function in
/// `AssistantToolbox`; a plan is just which of them to apply and with what arguments.
/// Every field is optional — omitting them all selects every recorded session.
struct AssistantFilters: Codable, Equatable {
    /// `"YYYY-MM"`. Shorthand for the whole calendar month.
    var month: String?
    /// `"YYYY-MM-DD"`, inclusive.
    var startDate: String?
    /// `"YYYY-MM-DD"`, inclusive.
    var endDate: String?
    /// `"HH:MM"` — only shifts that started at or after this time of day.
    var clockInAfter: String?
    /// `"HH:MM"` — only shifts that started before this time of day.
    var clockInBefore: String?
    var overtimeTier: AssistantOvertimeTier?
    /// `WorkSession.dayType` raw value: regular / restDay / holiday / sick.
    var dayType: String?

    enum CodingKeys: String, CodingKey {
        case month
        case startDate = "start_date"
        case endDate = "end_date"
        case clockInAfter = "clock_in_after"
        case clockInBefore = "clock_in_before"
        case overtimeTier = "overtime_tier"
        case dayType = "day_type"
    }

    var isEmpty: Bool {
        month == nil && startDate == nil && endDate == nil && clockInAfter == nil
            && clockInBefore == nil && overtimeTier == nil && dayType == nil
    }

    /// Lenient decoding: a model that emits `"overtime_tier": "125"` or an empty string
    /// shouldn't fail the whole plan, it should just drop that one filter.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        month = assistantDecodedString(container, .month)
        startDate = assistantDecodedString(container, .startDate)
        endDate = assistantDecodedString(container, .endDate)
        clockInAfter = assistantDecodedString(container, .clockInAfter)
        clockInBefore = assistantDecodedString(container, .clockInBefore)
        overtimeTier = assistantDecodedString(container, .overtimeTier)
            .flatMap(AssistantOvertimeTier.init(rawValue:))
        dayType = assistantDecodedString(container, .dayType)
    }

    init(
        month: String? = nil,
        startDate: String? = nil,
        endDate: String? = nil,
        clockInAfter: String? = nil,
        clockInBefore: String? = nil,
        overtimeTier: AssistantOvertimeTier? = nil,
        dayType: String? = nil
    ) {
        self.month = month
        self.startDate = startDate
        self.endDate = endDate
        self.clockInAfter = clockInAfter
        self.clockInBefore = clockInBefore
        self.overtimeTier = overtimeTier
        self.dayType = dayType
    }
}

/// Non-empty trimmed string for `key`, or `nil` when it is missing, null, empty, or not
/// a string at all. Models are inconsistent about which of those they emit for "no
/// value", and none of them should fail a whole plan.
private func assistantDecodedString<K: CodingKey>(
    _ container: KeyedDecodingContainer<K>,
    _ key: K
) -> String? {
    guard let value = try? container.decode(String.self, forKey: key) else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

/// The complete instruction the model produces. This is the *only* thing that crosses
/// back from the network into the app — there is no free text field on it, so no model
/// output can reach the user as prose, and no number in an answer can come from anywhere
/// but the user's own recorded data.
struct AssistantPlan: Codable, Equatable {
    var action: AssistantAction
    var filters: AssistantFilters
    var payMode: PayDisplayMode?
    var documentFormat: AssistantDocumentFormat?
    /// `"YYYY-MM"` for `findPayslip`.
    var period: String?

    enum CodingKeys: String, CodingKey {
        case action
        case filters
        case payMode = "pay_mode"
        case documentFormat = "document_format"
        case period
    }

    init(
        action: AssistantAction,
        filters: AssistantFilters = AssistantFilters(),
        payMode: PayDisplayMode? = nil,
        documentFormat: AssistantDocumentFormat? = nil,
        period: String? = nil
    ) {
        self.action = action
        self.filters = filters
        self.payMode = payMode
        self.documentFormat = documentFormat
        self.period = period
    }

    /// An unrecognized action is treated as out of scope rather than as a decoding
    /// failure: a model inventing `"action": "book_flight"` should get the fixed refusal,
    /// not an error message about JSON.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = assistantDecodedString(container, .action)
            .flatMap(AssistantAction.init(rawValue:)) ?? .outOfScope
        filters = (try? container.decode(AssistantFilters.self, forKey: .filters)) ?? AssistantFilters()
        payMode = assistantDecodedString(container, .payMode)
            .flatMap(PayDisplayMode.init(rawValue:))
        documentFormat = assistantDecodedString(container, .documentFormat)
            .flatMap(AssistantDocumentFormat.init(rawValue:))
        period = assistantDecodedString(container, .period)
    }

    /// Parses a model response, tolerating the markdown fences some models still wrap
    /// JSON in. Anything unparseable is a decoding failure the caller surfaces as an
    /// error — it is deliberately not silently downgraded to a plausible-looking plan.
    static func decode(from text: String) throws -> AssistantPlan {
        let json = GeminiScannerLLMProvider.extractJSONObject(from: text)
        guard let data = json.data(using: .utf8) else {
            throw ScannerLLMError.invalidResponse("empty plan")
        }
        return try JSONDecoder().decode(AssistantPlan.self, from: data)
    }
}
