import Foundation

/// Local, on-device payslip parser. Regex-only — no network, no ML.
///
/// The heuristic always sets `needsManualReview = true` regardless of how confident
/// the parse looks, because the local pipeline is best-effort and should never present
/// as authoritative data.
struct LocalHeuristicPayslipLLMProvider: PayslipLLMProviding {
    let name = "Local"

    func extractPayslip(ocrText: String) async throws -> PayslipLLMStructureResult {
        let trimmed = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return PayslipLLMStructureResult(
                fields: PayslipLLMFields(confidence: 0.0),
                providerName: name,
                rawJSON: nil,
                needsManualReview: true
            )
        }

        var fields = PayslipLLMFields()
        let lines = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            let nextLine = index + 1 < lines.count ? lines[index + 1] : nil

            if fields.netPay == nil, Self.isNetLine(line, lower: lower) {
                fields.netPay = Self.moneyOnLineOrNext(line, next: nextLine)
            }
            if fields.grossPay == nil, Self.isGrossLine(line, lower: lower) {
                fields.grossPay = Self.moneyOnLineOrNext(line, next: nextLine)
            }
            if fields.deductionsTotal == nil, Self.isDeductionsLine(line, lower: lower) {
                fields.deductionsTotal = Self.moneyOnLineOrNext(line, next: nextLine)
            }
            if fields.employerName == nil, let employer = Self.labeledName(in: line, labels: Self.employerLabels) {
                fields.employerName = employer
            }
            if fields.employeeName == nil, let employee = Self.labeledName(in: line, labels: Self.employeeLabels) {
                fields.employeeName = employee
            }
        }

        // Fallback: if labels never matched, take the largest currency-looking amounts
        // near common Hebrew payslip keywords anywhere in the text.
        if fields.netPay == nil {
            fields.netPay = Self.scanKeywordMoney(in: trimmed, keywords: Self.netKeywords)
        }
        if fields.grossPay == nil {
            fields.grossPay = Self.scanKeywordMoney(in: trimmed, keywords: Self.grossKeywords)
        }

        if let (start, end) = Self.detectPeriod(in: trimmed) {
            fields.payPeriodStart = start
            fields.payPeriodEnd = end
            fields.paymentMonth = Self.paymentMonth(fromDate: end) ?? Self.paymentMonth(fromDate: start)
        }
        if fields.paymentMonth == nil,
           let month = Self.detectPaymentMonth(in: trimmed) {
            fields.paymentMonth = month
        }

        if fields.currency == nil {
            if trimmed.contains("₪") || trimmed.localizedCaseInsensitiveContains("ILS")
                || trimmed.contains("ש\"ח") || trimmed.contains("שח") {
                fields.currency = "ILS"
            } else if trimmed.contains("$") || trimmed.localizedCaseInsensitiveContains("USD") {
                fields.currency = "USD"
            } else if trimmed.contains("€") || trimmed.localizedCaseInsensitiveContains("EUR") {
                fields.currency = "EUR"
            } else {
                fields.currency = "ILS"
            }
        }

        let signals = [fields.netPay, fields.grossPay].compactMap { $0 }.count
            + (fields.paymentMonth != nil ? 1 : 0)
        switch signals {
        case 0: fields.confidence = 0.15
        case 1: fields.confidence = 0.35
        case 2: fields.confidence = 0.55
        default: fields.confidence = 0.65
        }

        return PayslipLLMStructureResult(
            fields: fields,
            providerName: name,
            rawJSON: nil,
            needsManualReview: true
        )
    }

    // MARK: - Line classifiers

    private static let netKeywords = [
        "נטו לתשלום", "סך נטו", "סה\"כ נטו", "סהכ נטו", "לתשלום", "נטו",
        "סכום לתשלום", "שולם", "לתשלום נטו",
        "صافي", "المبلغ الصافي", "net pay", "take home", "net salary"
    ]
    private static let grossKeywords = [
        "שכר ברוטו", "סה\"כ ברוטו", "סהכ ברוטו", "ברוטו", "משכורת",
        "שכר כולל", "שכר בסיס", "שכר בסיסי", "שכר רגיל", "bruto", "gross",
        "إجمالي", "الراتب الأساسي", "gross pay", "gross salary"
    ]
    private static let employerLabels = [
        "מעסיק", "שם המעסיק", "מקום עבודה", "מעביד", "שם חברה",
        "employer", "company name", "شركة", "جهة العمل"
    ]
    private static let employeeLabels = [
        "עובד", "שם העובד", "שם פרטי", "שם מלא", "עובד/ת",
        "employee", "عامل", "اسم الموظف"
    ]

    private static func isNetLine(_ line: String, lower: String) -> Bool {
        if line.contains("נטו") { return true }
        if line.contains("صافي") { return true }
        if lower.contains("net pay") || lower.contains("take home") { return true }
        if lower.contains("net") && !lower.contains("network") { return true }
        if line.contains("לתשלום") && !line.contains("ברוטו") { return true }
        return false
    }

    private static func isGrossLine(_ line: String, lower: String) -> Bool {
        // "משכורת" alone also appears in the generic payslip title line
        // ("תלוש משכורת לחודש ..."), which carries no gross amount — only
        // treat it as a gross line when it's not that header.
        if line.contains("לחודש") { return false }
        return line.contains("ברוטו")
            || line.contains("משכורת")
            || lower.contains("gross")
            || line.contains("إجمالي")
    }

    private static func isDeductionsLine(_ line: String, lower: String) -> Bool {
        line.contains("ניכוי")
            || line.contains("ניכויים")
            || lower.contains("deduction")
            || line.contains("خصم")
    }

    private static func moneyOnLineOrNext(_ line: String, next: String?) -> Double? {
        if let value = firstMoneyValue(in: line) { return value }
        if let next, let value = firstMoneyValue(in: next) { return value }
        return nil
    }

    private static func labeledName(in line: String, labels: [String]) -> String? {
        for label in labels {
            guard let range = line.range(of: label, options: [.caseInsensitive]) else { continue }
            var rest = String(line[range.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: ":：-–— ").union(.whitespaces))
            // Strip trailing money amounts that sometimes share the line.
            if let moneyRange = rest.range(of: #"\d"# , options: .regularExpression) {
                rest = String(rest[..<moneyRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if rest.count >= 2 { return rest }
        }
        return nil
    }

    private static func scanKeywordMoney(in text: String, keywords: [String]) -> Double? {
        let lower = text.lowercased()
        for keyword in keywords {
            let needle = keyword.lowercased()
            guard let range = lower.range(of: needle) else { continue }
            let from = text.index(range.lowerBound, offsetBy: 0)
            let windowEnd = text.index(from, offsetBy: min(80, text.distance(from: from, to: text.endIndex)))
            let window = String(text[from..<windowEnd])
            if let value = firstMoneyValue(in: window) {
                return value
            }
        }
        return nil
    }

    // MARK: - Number parsing

    /// Extracts the first plausible monetary amount from a line, handling:
    ///   1,234.56  (English/US)
    ///   1.234,56  (European / Hebrew locale)
    ///   1234.56   (plain)
    ///   1234      (integer)
    static func firstMoneyValue(in line: String) -> Double? {
        let pattern = #"-?\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{1,2})?|-?\d+(?:[.,]\d{1,2})?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        let matches = regex.matches(in: line, range: range)
        var best: Double?
        for match in matches {
            guard let r = Range(match.range, in: line) else { continue }
            let raw = String(line[r])
            guard let value = parseNumber(raw) else { continue }
            // Prefer the largest amount on the line — payslip lines often contain
            // small ordinal / code numbers before the actual value.
            if best == nil || value > (best ?? 0) {
                best = value
            }
        }
        return best
    }

    static func parseNumber(_ raw: String) -> Double? {
        var s = raw
        let hasDot = s.contains(".")
        let hasComma = s.contains(",")

        if hasDot && hasComma {
            let lastDot = s.lastIndex(of: ".")!
            let lastComma = s.lastIndex(of: ",")!
            if lastDot > lastComma {
                s.removeAll { $0 == "," }
            } else {
                s.removeAll { $0 == "." }
                s = s.replacingOccurrences(of: ",", with: ".")
            }
        } else if hasComma {
            let parts = s.split(separator: ",", omittingEmptySubsequences: false)
            if parts.count == 2 && parts[1].count <= 2 {
                s = s.replacingOccurrences(of: ",", with: ".")
            } else {
                s.removeAll { $0 == "," }
            }
        } else if hasDot {
            let parts = s.split(separator: ".", omittingEmptySubsequences: false)
            if parts.count > 2 || (parts.count == 2 && parts[1].count == 3) {
                s.removeAll { $0 == "." }
            }
        }
        return Double(s)
    }

    // MARK: - Dates

    static func detectPeriod(in text: String) -> (String, String)? {
        let pattern = #"(\d{1,2}[./-]\d{1,2}[./-]\d{2,4})\s*[-–—to]{1,3}\s*(\d{1,2}[./-]\d{1,2}[./-]\d{2,4})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let r1 = Range(match.range(at: 1), in: text),
              let r2 = Range(match.range(at: 2), in: text) else {
            return nil
        }
        return (String(text[r1]), String(text[r2]))
    }

    static func paymentMonth(fromDate dateString: String) -> String? {
        let parts = dateString.split(whereSeparator: { "/.-".contains($0) })
        guard parts.count == 3 else { return nil }
        // Prefer day/month/year (IL) when first part is a plausible day.
        let a = Int(parts[0]) ?? 0
        let b = Int(parts[1]) ?? 0
        let yearRaw = Int(parts[2]) ?? 0
        let year = yearRaw < 100 ? 2000 + yearRaw : yearRaw
        if a > 12 && b >= 1 && b <= 12 {
            return String(format: "%04d-%02d", year, b)
        }
        if b > 12 && a >= 1 && a <= 12 {
            return String(format: "%04d-%02d", year, a)
        }
        if a >= 1 && a <= 12 {
            return String(format: "%04d-%02d", year, a)
        }
        return nil
    }

    /// Looks for "לחודש 5/2026", "MM/YYYY", or "YYYY-MM".
    static func detectPaymentMonth(in text: String) -> String? {
        let hebrewMonth = #"לחודש\s*(0?[1-9]|1[0-2])[./-](20\d{2})"#
        if let regex = try? NSRegularExpression(pattern: hebrewMonth) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range),
               let mRange = Range(match.range(at: 1), in: text),
               let yRange = Range(match.range(at: 2), in: text),
               let month = Int(text[mRange]),
               let year = Int(text[yRange]) {
                return String(format: "%04d-%02d", year, month)
            }
        }

        let mmYYYY = #"\b(0?[1-9]|1[0-2])[./-](20\d{2})\b"#
        if let regex = try? NSRegularExpression(pattern: mmYYYY) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range),
               let mRange = Range(match.range(at: 1), in: text),
               let yRange = Range(match.range(at: 2), in: text),
               let month = Int(text[mRange]),
               let year = Int(text[yRange]) {
                return String(format: "%04d-%02d", year, month)
            }
        }
        let yyyyMM = #"\b(20\d{2})[-/](0?[1-9]|1[0-2])\b"#
        if let regex = try? NSRegularExpression(pattern: yyyyMM) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range),
               let yRange = Range(match.range(at: 1), in: text),
               let mRange = Range(match.range(at: 2), in: text),
               let year = Int(text[yRange]),
               let month = Int(text[mRange]) {
                return String(format: "%04d-%02d", year, month)
            }
        }
        return nil
    }
}
