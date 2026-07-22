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
    var extras: [String: String]
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
