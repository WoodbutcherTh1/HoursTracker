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

        for rawLine in trimmed.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()

            let isNetLine = line.contains("נטו")
                || line.contains("صافي")
                || lower.contains("net pay")
                || lower.contains("take home")
                || (lower.contains("net") && !lower.contains("network"))

            let isGrossLine = line.contains("ברוטו")
                || lower.contains("gross")
                || lower.contains("إجمالي")

            if isNetLine, fields.netPay == nil, let value = Self.firstMoneyValue(in: line) {
                fields.netPay = value
            }
            if isGrossLine, fields.grossPay == nil, let value = Self.firstMoneyValue(in: line) {
                fields.grossPay = value
            }
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
                || trimmed.contains("ש\"ח") {
                fields.currency = "ILS"
            } else if trimmed.contains("$") || trimmed.localizedCaseInsensitiveContains("USD") {
                fields.currency = "USD"
            } else if trimmed.contains("€") || trimmed.localizedCaseInsensitiveContains("EUR") {
                fields.currency = "EUR"
            }
        }

        // Cap confidence low — local extraction is only a hint.
        let signals = [fields.netPay, fields.grossPay].compactMap { $0 }.count
            + (fields.paymentMonth != nil ? 1 : 0)
        switch signals {
        case 0: fields.confidence = 0.1
        case 1: fields.confidence = 0.3
        default: fields.confidence = 0.5
        }

        return PayslipLLMStructureResult(
            fields: fields,
            providerName: name,
            rawJSON: nil,
            needsManualReview: true
        )
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
        guard parts.count == 3,
              let month = Int(parts[1]),
              let yearRaw = Int(parts[2]) else {
            return nil
        }
        let year = yearRaw < 100 ? 2000 + yearRaw : yearRaw
        return String(format: "%04d-%02d", year, month)
    }

    /// Looks for standalone "MM/YYYY" or "YYYY-MM" markers when no explicit range appears.
    static func detectPaymentMonth(in text: String) -> String? {
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
