import Foundation

/// Field-level lenient decoding shared by `PayslipLLMFields` and its nested line-item
/// structs. Generic over `CodingKey` so every one of these types — each with its own
/// `CodingKeys` enum — can use the same never-throws helpers.
///
/// A longer, more detailed extraction prompt gives the model more surface area to slip on
/// any single field's exact type (e.g. emitting "7,820.00" as a quoted string instead of a
/// number). `Decodable`'s default behavior is all-or-nothing: one mismatched field throws
/// and takes the entire object down with it, silently turning a mostly-correct extraction
/// into a completely empty one. These helpers instead let "this one field came back null"
/// stand in for "the whole record failed to parse".
enum PayslipLLMLenientDecoding {
    // `(try? …) ?? nil`, not `if let x = try? …, let x`: whether `try?` on an
    // already-`Optional`-returning call flattens to one level of Optional or leaves two
    // has flip-flopped across Swift versions/overload-resolution paths (the compiler
    // treated ostensibly identical `decodeIfPresent` calls for different `Decodable`
    // types differently here). `?? nil` collapses either shape to a single `T?` — "threw"
    // and "decoded to nil" both just mean "not there" for our purposes anyway.

    /// Accepts a JSON number, or a numeric-looking string (with thousands separators the
    /// model might echo back despite the prompt's normalisation rule) — never throws.
    static func double<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ key: K) -> Double? {
        if let value = (try? container.decodeIfPresent(Double.self, forKey: key)) ?? nil {
            return value
        }
        if let raw = (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil {
            let cleaned = raw.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
            return Double(cleaned)
        }
        return nil
    }

    /// Accepts a JSON string, or falls back to a number's textual form for a field the
    /// model mistakenly typed as numeric — never throws. Empty/whitespace collapses to nil.
    static func string<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ key: K) -> String? {
        if let raw = (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = (try? container.decodeIfPresent(Double.self, forKey: key)) ?? nil {
            return String(value)
        }
        return nil
    }

    /// Accepts a JSON integer, or a string containing one (e.g. "125%") by stripping
    /// non-digit characters — never throws.
    static func int<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ key: K) -> Int? {
        if let value = (try? container.decodeIfPresent(Int.self, forKey: key)) ?? nil {
            return value
        }
        if let raw = (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil {
            return Int(raw.filter(\.isNumber))
        }
        return nil
    }
}

/// JSON schema for a single payslip produced by a cloud LLM (or the local heuristic).
///
/// The `CodingKeys` match the exact snake_case field names documented in the prompt
/// so the same struct can decode raw provider responses without an intermediate wrapper.
struct PayslipLLMFields: Codable, Equatable, Sendable {
    var payPeriodStart: String?
    var payPeriodEnd: String?
    var paymentMonth: String?
    var grossPay: Double?
    var netPay: Double?
    var currency: String?
    var employerName: String?
    var employeeName: String?
    var hoursRegular: Double?
    var hoursOt: Double?
    var deductionsTotal: Double?
    /// Itemized overtime tiers (e.g. 125%, 150%) — the aggregate `hoursOt` above is their
    /// sum. Empty when the payslip doesn't break overtime out by rate.
    var overtimeLines: [PayslipLLMOvertimeLine]
    /// Itemized deduction rows (ביטוח לאומי, מס בריאות, ...) — `deductionsTotal` above is
    /// their sum. Empty when the payslip only shows a single total.
    var deductionLines: [PayslipLLMDeductionLine]
    var confidence: Double?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case payPeriodStart = "pay_period_start"
        case payPeriodEnd = "pay_period_end"
        case paymentMonth = "payment_month"
        case grossPay = "gross_pay"
        case netPay = "net_pay"
        case currency
        case employerName = "employer_name"
        case employeeName = "employee_name"
        case hoursRegular = "hours_regular"
        case hoursOt = "hours_ot"
        case deductionsTotal = "deductions_total"
        case overtimeLines = "overtime_lines"
        case deductionLines = "deduction_lines"
        case confidence
        case notes
    }

    init(
        payPeriodStart: String? = nil,
        payPeriodEnd: String? = nil,
        paymentMonth: String? = nil,
        grossPay: Double? = nil,
        netPay: Double? = nil,
        currency: String? = nil,
        employerName: String? = nil,
        employeeName: String? = nil,
        hoursRegular: Double? = nil,
        hoursOt: Double? = nil,
        deductionsTotal: Double? = nil,
        overtimeLines: [PayslipLLMOvertimeLine] = [],
        deductionLines: [PayslipLLMDeductionLine] = [],
        confidence: Double? = nil,
        notes: String? = nil
    ) {
        self.payPeriodStart = payPeriodStart
        self.payPeriodEnd = payPeriodEnd
        self.paymentMonth = paymentMonth
        self.grossPay = grossPay
        self.netPay = netPay
        self.currency = currency
        self.employerName = employerName
        self.employeeName = employeeName
        self.hoursRegular = hoursRegular
        self.hoursOt = hoursOt
        self.deductionsTotal = deductionsTotal
        self.overtimeLines = overtimeLines
        self.deductionLines = deductionLines
        self.confidence = confidence
        self.notes = notes
    }

    /// Every field is decoded leniently via `PayslipLLMLenientDecoding` — see its doc
    /// comment for why: one field's type slip must not take the whole record down.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        payPeriodStart = PayslipLLMLenientDecoding.string(container, .payPeriodStart)
        payPeriodEnd = PayslipLLMLenientDecoding.string(container, .payPeriodEnd)
        paymentMonth = PayslipLLMLenientDecoding.string(container, .paymentMonth)
        grossPay = PayslipLLMLenientDecoding.double(container, .grossPay)
        netPay = PayslipLLMLenientDecoding.double(container, .netPay)
        currency = PayslipLLMLenientDecoding.string(container, .currency)
        employerName = PayslipLLMLenientDecoding.string(container, .employerName)
        employeeName = PayslipLLMLenientDecoding.string(container, .employeeName)
        hoursRegular = PayslipLLMLenientDecoding.double(container, .hoursRegular)
        hoursOt = PayslipLLMLenientDecoding.double(container, .hoursOt)
        deductionsTotal = PayslipLLMLenientDecoding.double(container, .deductionsTotal)
        overtimeLines = (try? container.decodeIfPresent([PayslipLLMOvertimeLine].self, forKey: .overtimeLines)) ?? nil ?? []
        deductionLines = (try? container.decodeIfPresent([PayslipLLMDeductionLine].self, forKey: .deductionLines)) ?? nil ?? []
        confidence = PayslipLLMLenientDecoding.double(container, .confidence)
        if let asString = try? container.decode(String.self, forKey: .notes) {
            notes = asString
        } else if let asArray = try? container.decode([String].self, forKey: .notes) {
            notes = asArray.joined(separator: " · ")
        } else {
            notes = nil
        }
    }
}

/// One itemized overtime tier row, e.g. 125% × 7.42h.
struct PayslipLLMOvertimeLine: Codable, Equatable, Sendable {
    var ratePercent: Int?
    var hours: Double?
    var amount: Double?

    enum CodingKeys: String, CodingKey {
        case ratePercent = "rate_percent"
        case hours
        case amount
    }

    init(ratePercent: Int? = nil, hours: Double? = nil, amount: Double? = nil) {
        self.ratePercent = ratePercent
        self.hours = hours
        self.amount = amount
    }

    /// Same leniency as `PayslipLLMFields`: a type slip on one row (e.g. "125%" as a
    /// string) drops just that row's field to nil rather than the plain synthesized
    /// decoder's default of throwing and losing the entire overtime breakdown.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ratePercent = PayslipLLMLenientDecoding.int(container, .ratePercent)
        hours = PayslipLLMLenientDecoding.double(container, .hours)
        amount = PayslipLLMLenientDecoding.double(container, .amount)
    }
}

/// One itemized deduction row, e.g. "ביטוח לאומי" — 36.00.
struct PayslipLLMDeductionLine: Codable, Equatable, Sendable {
    var label: String?
    var amount: Double?

    enum CodingKeys: String, CodingKey {
        case label
        case amount
    }

    init(label: String? = nil, amount: Double? = nil) {
        self.label = label
        self.amount = amount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = PayslipLLMLenientDecoding.string(container, .label)
        amount = PayslipLLMLenientDecoding.double(container, .amount)
    }
}

/// The cloud LLM returns a single JSON object matching `PayslipLLMFields` exactly (no wrapper).
/// The alias exists so call sites read symmetrically with `ScannerLLMPayload`.
typealias PayslipLLMPayload = PayslipLLMFields

/// Wrapper returned by every `PayslipLLMProviding`. `needsManualReview` is set by the provider /
/// router according to confidence and completeness rules — the local heuristic always sets it
/// to `true`.
struct PayslipLLMStructureResult: Equatable, Sendable {
    var fields: PayslipLLMFields
    var providerName: String
    var rawJSON: String?
    var needsManualReview: Bool

    init(
        fields: PayslipLLMFields,
        providerName: String,
        rawJSON: String? = nil,
        needsManualReview: Bool
    ) {
        self.fields = fields
        self.providerName = providerName
        self.rawJSON = rawJSON
        self.needsManualReview = needsManualReview
    }

    /// True if the LLM produced at least one identifying money or period field.
    /// Used by the router to decide whether to try the next provider.
    var hasAnyPrimaryValue: Bool {
        fields.grossPay != nil
            || fields.netPay != nil
            || fields.paymentMonth != nil
            || fields.payPeriodStart != nil
            || fields.payPeriodEnd != nil
    }
}

/// Shared review evaluation used by the cloud providers. Local always returns `true`
/// regardless of this evaluation.
enum PayslipReviewEvaluator {
    static func needsManualReview(for fields: PayslipLLMFields) -> Bool {
        let confidence = fields.confidence ?? 0
        // <= not < : the prompt tells the model to use "< 0.6" for an unclear read, so a
        // model reporting exactly 0.6 is already saying "borderline" — treating that as
        // fully trusted let a wrong-but-not-quite-unconfident extraction through unflagged.
        if confidence <= 0.6 { return true }
        if fields.netPay == nil && fields.grossPay == nil { return true }
        if fields.paymentMonth == nil
            && fields.payPeriodStart == nil
            && fields.payPeriodEnd == nil {
            return true
        }
        // Belt-and-suspenders: the prompt already tells the model to null out an
        // impossible start-after-end pair itself, but never trust a probabilistic model
        // to follow that unconditionally — a swapped/misread period is easy to catch here
        // in code and is a strong signal the whole extraction needs a human look.
        if let start = parseDDMMYYYY(fields.payPeriodStart),
           let end = parseDDMMYYYY(fields.payPeriodEnd),
           start > end {
            return true
        }
        return false
    }

    /// Parses the `DD/MM/YYYY` format the prompt requires for period dates. Returns nil
    /// for anything else rather than guessing — this check only fires when it's sure.
    private static func parseDDMMYYYY(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.date(from: raw)
    }
}
