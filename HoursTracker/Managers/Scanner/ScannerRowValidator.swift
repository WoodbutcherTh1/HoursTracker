import Foundation

/// Validates structured scanner rows before they become import drafts.
/// Hours must be in (0, 16]; equal in/out must not become a 24h overnight.
enum ScannerRowValidator {
    static let maxAcceptableHours: Double = 16
    static let near24HoursLower: Double = 23.5
    static let near24HoursUpper: Double = 24.5

    enum Outcome: Equatable {
        case accepted(ScannedSessionDraft)
        case needsReview(ScannedSessionDraft)
        case rejected(reason: String)
    }

    static func validate(
        _ row: ScannerLLMRow,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Outcome {
        guard let day = parseDate(row.date, calendar: calendar, now: now) else {
            return .rejected(reason: "unparseable date: \(row.date)")
        }
        guard let inTime = parseTime(row.clockIn) else {
            return .rejected(reason: "unparseable clock-in: \(row.clockIn)")
        }
        guard let outTime = parseTime(row.clockOut) else {
            return .rejected(reason: "unparseable clock-out: \(row.clockOut)")
        }

        let confidence = row.confidence ?? 0.75
        let rawIn = combine(date: day, time: inTime, calendar: calendar)
        let rawOut = combine(date: day, time: outTime, calendar: calendar)

        // Equal HH:MM tokens (often a hours-total column misread as in/out).
        if inTime.hour == outTime.hour, inTime.minute == outTime.minute {
            return .needsReview(
                ScannedSessionDraft(
                    date: day,
                    clockIn: rawIn,
                    clockOut: rawOut,
                    notes: L10n.scannerImportedNote,
                    isSelected: false,
                    confidence: min(confidence, 0.3),
                    needsManualReview: true
                )
            )
        }

        let resolved = WorkSession.resolveClockPair(
            clockIn: rawIn,
            clockOut: rawOut,
            calendar: calendar
        )
        let hours = resolved.clockOut.timeIntervalSince(resolved.clockIn) / 3600

        if hours <= 0 {
            return .rejected(reason: "non-positive duration")
        }

        if isNear24HourSpan(hours) {
            return .needsReview(
                ScannedSessionDraft(
                    date: day,
                    clockIn: rawIn,
                    clockOut: rawOut,
                    notes: L10n.scannerImportedNote,
                    isSelected: false,
                    confidence: min(confidence, 0.2),
                    needsManualReview: true
                )
            )
        }

        if hours > maxAcceptableHours {
            return .needsReview(
                ScannedSessionDraft(
                    date: day,
                    clockIn: resolved.clockIn,
                    clockOut: resolved.clockOut,
                    notes: L10n.scannerImportedNote,
                    isSelected: false,
                    confidence: min(confidence, 0.4),
                    needsManualReview: true
                )
            )
        }

        if resolved.clockOut <= resolved.clockIn {
            return .needsReview(
                ScannedSessionDraft(
                    date: day,
                    clockIn: resolved.clockIn,
                    clockOut: resolved.clockOut,
                    notes: L10n.scannerImportedNote,
                    isSelected: false,
                    confidence: min(confidence, 0.4),
                    needsManualReview: true
                )
            )
        }

        return .accepted(
            ScannedSessionDraft(
                date: day,
                clockIn: resolved.clockIn,
                clockOut: resolved.clockOut,
                notes: L10n.scannerImportedNote,
                isSelected: true,
                confidence: confidence,
                needsManualReview: false
            )
        )
    }

    static func validateAll(
        _ rows: [ScannerLLMRow],
        calendar: Calendar = .current
    ) -> (drafts: [ScannedSessionDraft], details: ScannerProcessingDetails) {
        var drafts: [ScannedSessionDraft] = []
        var accepted = 0
        var rejected = 0
        var review = 0
        var notes: [String] = []

        for (index, row) in rows.enumerated() {
            switch validate(row, calendar: calendar) {
            case .accepted(let draft):
                accepted += 1
                drafts.append(draft)
                notes.append("row \(index + 1): accepted")
            case .needsReview(let draft):
                review += 1
                drafts.append(draft)
                notes.append("row \(index + 1): needs review")
            case .rejected(let reason):
                rejected += 1
                notes.append("row \(index + 1): rejected — \(reason)")
            }
        }

        let details = ScannerProcessingDetails(
            providerName: "",
            acceptedCount: accepted,
            rejectedCount: rejected,
            reviewCount: review,
            notes: notes
        )
        return (drafts, details)
    }

    static func isNear24HourSpan(_ hours: Double) -> Bool {
        hours >= near24HoursLower && hours <= near24HoursUpper
    }

    // MARK: - Parsing helpers

    struct TimeParts: Equatable {
        var hour: Int
        var minute: Int
    }

    static func parseTime(_ text: String) -> TimeParts? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: ":")
        let parts = cleaned.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else {
            return nil
        }
        return TimeParts(hour: parts[0], minute: parts[1])
    }

    static func parseDate(_ text: String, calendar: Calendar, now: Date) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        if let date = iso.date(from: String(trimmed.prefix(10))) {
            return calendar.startOfDay(for: date)
        }

        let patterns = [
            #"(\d{1,2})[./\-](\d{1,2})[./\-](\d{4})"#,
            #"(\d{1,2})[./\-](\d{1,2})[./\-](\d{2})"#,
            #"(\d{4})[./\-](\d{1,2})[./\-](\d{1,2})"#,
            #"(\d{1,2})[./\-](\d{1,2})"#
        ]

        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
            else { continue }

            var nums: [Int] = []
            for i in 1..<match.numberOfRanges {
                guard let range = Range(match.range(at: i), in: trimmed),
                      let value = Int(trimmed[range]) else { continue }
                nums.append(value)
            }
            guard nums.count >= 2 else { continue }

            var day: Int
            var month: Int
            var year: Int

            if index == 2 {
                year = nums[0]
                month = nums[1]
                day = nums[2]
            } else {
                day = nums[0]
                month = nums[1]
                year = nums.count > 2 ? nums[2] : calendar.component(.year, from: now)
                if year < 100 { year += 2000 }
            }

            if day > 31 || month > 12 {
                swap(&day, &month)
            }
            guard (1...12).contains(month), (1...31).contains(day) else { continue }

            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            if let date = calendar.date(from: components) {
                return calendar.startOfDay(for: date)
            }
        }
        return nil
    }

    private static func combine(date: Date, time: TimeParts, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        return calendar.date(from: components) ?? date
    }
}
