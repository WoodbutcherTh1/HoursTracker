import Foundation

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
        self.confidence = confidence
        self.notes = notes
    }

    /// Notes tolerates the LLM emitting either a JSON string or an array of strings.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        payPeriodStart = try container.decodeIfPresent(String.self, forKey: .payPeriodStart)
        payPeriodEnd = try container.decodeIfPresent(String.self, forKey: .payPeriodEnd)
        paymentMonth = try container.decodeIfPresent(String.self, forKey: .paymentMonth)
        grossPay = try container.decodeIfPresent(Double.self, forKey: .grossPay)
        netPay = try container.decodeIfPresent(Double.self, forKey: .netPay)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        employerName = try container.decodeIfPresent(String.self, forKey: .employerName)
        employeeName = try container.decodeIfPresent(String.self, forKey: .employeeName)
        hoursRegular = try container.decodeIfPresent(Double.self, forKey: .hoursRegular)
        hoursOt = try container.decodeIfPresent(Double.self, forKey: .hoursOt)
        deductionsTotal = try container.decodeIfPresent(Double.self, forKey: .deductionsTotal)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        if let asString = try? container.decode(String.self, forKey: .notes) {
            notes = asString
        } else if let asArray = try? container.decode([String].self, forKey: .notes) {
            notes = asArray.joined(separator: " · ")
        } else {
            notes = nil
        }
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
        if confidence < 0.6 { return true }
        if fields.netPay == nil && fields.grossPay == nil { return true }
        if fields.paymentMonth == nil
            && fields.payPeriodStart == nil
            && fields.payPeriodEnd == nil {
            return true
        }
        return false
    }
}
