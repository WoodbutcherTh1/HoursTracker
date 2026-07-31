import Foundation

struct PayslipRecord: Identifiable, Codable, Equatable, Hashable {
    enum SourceKind: String, Codable, Equatable, Hashable {
        case image
        case pdf
    }

    enum ReviewState: String, Codable, Equatable, Hashable {
        case pendingReview
        case confirmed
        case rejected
    }

    var id: UUID
    var periodMonth: Date
    var periodStartDay: Int?
    var periodLabel: String?
    var uploadedAt: Date
    var sourceKind: SourceKind
    var originalFileName: String
    /// Relative to the storage root, e.g. `payslips/files/<uuid>.<ext>`.
    var relativeFilePath: String
    var fileByteSize: Int
    var contentTypeUTI: String
    var extraction: PayslipExtraction
    var userOverrides: PayslipOverrides?
    var reviewState: ReviewState
    var notes: String?

    var effectiveNetPay: Decimal? {
        userOverrides?.netPay ?? extraction.netPay
    }

    var effectiveGrossPay: Decimal? {
        userOverrides?.grossPay ?? extraction.grossPay
    }

    var effectivePeriodMonth: Date {
        let sourceDate = userOverrides?.payPeriodStart
            ?? extraction.payPeriodStart
            ?? periodMonth
        return Calendar.current.ht_startOfMonth(for: sourceDate)
    }
}

struct PayslipExtraction: Codable, Equatable, Hashable {
    var providerName: String
    var extractedAt: Date
    var confidence: Double
    var needsManualReview: Bool
    var rawJSON: String?
    var grossPay: Decimal?
    var netPay: Decimal?
    var currencyCode: String?
    var employerName: String?
    var employeeName: String?
    var employeeID: String?
    var payPeriodStart: Date?
    var payPeriodEnd: Date?
    var paymentDate: Date?
    var hoursRegular: Double?
    var hoursOT: Double?
    var deductionsTotal: Decimal?
    /// Itemized overtime tiers (125%, 150%, ...) whose hours sum to `hoursOT`. `nil`/empty
    /// when the source payslip only shows a single overtime total. Not user-editable — the
    /// review flow only lets people correct the aggregate `hoursOT`. Optional (rather than
    /// defaulted to `[]`) so records persisted before this field existed still decode —
    /// Codable synthesis only skips a missing key for `Optional` properties.
    var overtimeLines: [PayslipOvertimeLine]? = nil
    /// Itemized deduction rows (ביטוח לאומי, מס בריאות, ...) whose amounts sum to
    /// `deductionsTotal`. `nil`/empty when the source payslip only shows a single total.
    /// Optional for the same pre-existing-record decoding reason as `overtimeLines`.
    var deductionLines: [PayslipDeductionLine]? = nil
    var extras: [String: String]

    /// Non-optional convenience for display code — collapses the "field never existed"
    /// and "payslip had none" cases, which UI doesn't need to distinguish.
    var overtimeLinesOrEmpty: [PayslipOvertimeLine] { overtimeLines ?? [] }
    var deductionLinesOrEmpty: [PayslipDeductionLine] { deductionLines ?? [] }
}

/// One itemized overtime tier row, e.g. 125% × 7.42h — see `PayslipExtraction.overtimeLines`.
struct PayslipOvertimeLine: Codable, Equatable, Hashable {
    var ratePercent: Int
    var hours: Double
    var amount: Decimal?
}

/// One itemized deduction row, e.g. "ביטוח לאומי" — 36.00 — see `PayslipExtraction.deductionLines`.
struct PayslipDeductionLine: Codable, Equatable, Hashable {
    var label: String
    var amount: Decimal
}

struct PayslipOverrides: Codable, Equatable, Hashable {
    var editedAt: Date
    var grossPay: Decimal?
    var netPay: Decimal?
    var currencyCode: String?
    var employerName: String?
    var employeeName: String?
    var employeeID: String?
    var payPeriodStart: Date?
    var payPeriodEnd: Date?
    var paymentDate: Date?
    var hoursRegular: Double?
    var hoursOT: Double?
    var deductionsTotal: Decimal?
    var extras: [String: String]?
}

private extension Calendar {
    func ht_startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components).map(startOfDay(for:)) ?? startOfDay(for: date)
    }
}
