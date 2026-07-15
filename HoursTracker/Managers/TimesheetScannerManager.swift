import Foundation
import UIKit
import Vision
import PDFKit

struct ScannedSessionDraft: Identifiable, Equatable {
    let id: UUID
    var date: Date
    var clockIn: Date
    var clockOut: Date
    var notes: String?
    var isSelected: Bool
    var confidence: Double
    var needsManualReview: Bool

    init(
        id: UUID = UUID(),
        date: Date,
        clockIn: Date,
        clockOut: Date,
        notes: String? = nil,
        isSelected: Bool = true,
        confidence: Double = 1,
        needsManualReview: Bool = false
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.clockIn = clockIn
        self.clockOut = clockOut
        self.notes = notes
        self.isSelected = isSelected
        self.confidence = confidence
        self.needsManualReview = needsManualReview
    }

    var totalHours: Double {
        max(0, clockOut.timeIntervalSince(clockIn) / 3600)
    }

    func toWorkSession() -> WorkSession {
        WorkSession(
            date: Calendar.current.startOfDay(for: date),
            clockIn: clockIn,
            clockOut: clockOut,
            isManualEntry: true,
            isAIImported: true,
            notes: notes
        )
    }

    static func blankDraft(on day: Date = Date(), calendar: Calendar = .current) -> ScannedSessionDraft {
        let start = calendar.startOfDay(for: day)
        let clockIn = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: start) ?? start
        let clockOut = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: start)
            ?? start.addingTimeInterval(9 * 3600)
        return ScannedSessionDraft(
            date: start,
            clockIn: clockIn,
            clockOut: clockOut,
            notes: String(localized: "scanner.manualDraftNote", defaultValue: "Fill in manually"),
            isSelected: true,
            confidence: 0,
            needsManualReview: true
        )
    }
}

struct TimesheetScanResult {
    let drafts: [ScannedSessionDraft]
    let ocrText: String
    let usedManualFallback: Bool
}

enum TimesheetScannerError: LocalizedError {
    case unsupportedFile
    case pdfRenderFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            return String(localized: "scanner.error.unsupported", defaultValue: "Unsupported file type.")
        case .pdfRenderFailed:
            return String(localized: "scanner.error.pdf", defaultValue: "Could not read this PDF.")
        }
    }
}

actor TimesheetScannerManager {
    static let shared = TimesheetScannerManager()

    func scan(image: UIImage) async throws -> TimesheetScanResult {
        let text = (try? await recognizeText(in: image)) ?? ""
        return parseResult(from: text)
    }

    func scan(pdfURL: URL) async throws -> TimesheetScanResult {
        guard let document = PDFDocument(url: pdfURL) else {
            throw TimesheetScannerError.pdfRenderFailed
        }

        var allText = ""
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            if let pageText = page.string, !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                allText += pageText + "\n"
            } else if let image = render(page: page) {
                allText += ((try? await recognizeText(in: image)) ?? "") + "\n"
            }
        }
        return parseResult(from: allText)
    }

    func scan(fileURL: URL) async throws -> TimesheetScanResult {
        let ext = fileURL.pathExtension.lowercased()
        if ext == "pdf" { return try await scan(pdfURL: fileURL) }
        if ["png", "jpg", "jpeg", "heic", "tif", "tiff"].contains(ext),
           let data = try? Data(contentsOf: fileURL),
           let image = UIImage(data: data) {
            return try await scan(image: image)
        }
        if ["csv", "tsv", "txt", "md"].contains(ext),
           let text = try? String(contentsOf: fileURL, encoding: .utf8) {
            return parseResult(from: text)
        }
        throw TimesheetScannerError.unsupportedFile
    }

    // MARK: - Vision

    private func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = preparedCGImage(from: image) else { return "" }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let sorted = observations.sorted { lhs, rhs in
                    let ly = lhs.boundingBox.midY
                    let ry = rhs.boundingBox.midY
                    if abs(ly - ry) > 0.015 { return ly > ry }
                    return lhs.boundingBox.minX < rhs.boundingBox.minX
                }
                let lines = sorted.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["he-IL", "en-US"]
            request.customWords = [
                "כניסה", "יציאה", "תאריך", "שעות", "נוכחות", "משמרת", "סה\"כ",
                "Date", "In", "Out", "Hours", "Clock", "Total"
            ]

            do {
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func preparedCGImage(from image: UIImage) -> CGImage? {
        if let cgImage = image.cgImage { return cgImage }
        guard let ciImage = image.ciImage else { return nil }
        return CIContext().createCGImage(ciImage, from: ciImage.extent)
    }

    private func render(page: PDFPage) -> UIImage? {
        let rect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.5
        let size = CGSize(width: rect.width * scale, height: rect.height * scale)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }

    // MARK: - Parsing

    func parseResult(from text: String) -> TimesheetScanResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let drafts = parseSessions(from: trimmed)
        if drafts.isEmpty {
            return TimesheetScanResult(
                drafts: [ScannedSessionDraft.blankDraft()],
                ocrText: trimmed,
                usedManualFallback: true
            )
        }
        return TimesheetScanResult(drafts: drafts, ocrText: trimmed, usedManualFallback: false)
    }

    func parseSessions(from text: String) -> [ScannedSessionDraft] {
        let normalized = normalize(text)
        let calendar = Calendar.current
        let dateOrder = detectDateOrder(in: normalized, calendar: calendar)
        let preferColonTimes = textContainsColonTimes(normalized)

        // 1) Prefer per-line rows that already contain date + 2 times.
        var drafts = parseLineRows(
            normalized,
            calendar: calendar,
            dateOrder: dateOrder,
            preferColonTimes: preferColonTimes
        )

        // 2) Global pattern pairing across the whole document.
        if drafts.isEmpty {
            drafts = parseGlobalDateTimePairs(
                normalized,
                calendar: calendar,
                dateOrder: dateOrder,
                preferColonTimes: preferColonTimes
            )
        }

        // 3) Sliding window over adjacent lines (tables often split cells).
        if drafts.isEmpty {
            drafts = parseAdjacentLineWindows(
                normalized,
                calendar: calendar,
                dateOrder: dateOrder,
                preferColonTimes: preferColonTimes
            )
        }

        var seen = Set<TimeInterval>()
        var unique: [ScannedSessionDraft] = []
        for draft in drafts.sorted(by: { $0.date < $1.date }) {
            let key = calendar.startOfDay(for: draft.date).timeIntervalSince1970
            if seen.insert(key).inserted {
                unique.append(draft)
            }
        }
        return unique
    }

    private enum DateOrder {
        /// Israeli / European: 01/07 = 1 July
        case dayMonth
        /// US-style exports: 07-01 = 1 July
        case monthDay
    }

    private func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{200f}", with: "")
            .replacingOccurrences(of: "\u{200e}", with: "")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "：", with: ":")
            // Arabic decimal separator → ASCII dot (timesheets often use 7.17 for 7:17).
            .replacingOccurrences(of: "٫", with: ".")
    }

    private func textContainsColonTimes(_ text: String) -> Bool {
        matches(in: text, pattern: #"\b([01]?\d|2[0-3]):([0-5]\d)(?:[:.][0-5]\d)?\b"#).count >= 2
    }

    /// Prefer MM-DD when weekday labels match that reading; otherwise DD-MM (default for IL).
    private func detectDateOrder(in text: String, calendar: Calendar) -> DateOrder {
        let lower = text.lowercased()
        let hasHebrew = text.range(of: #"\p{Hebrew}"#, options: .regularExpression) != nil
        let looksUSExport = lower.contains("entry") && lower.contains("exit")
            || lower.contains("total_hours")
            || lower.contains("total hours")

        let weekdayNames: [(String, Int)] = [
            ("sunday", 1), ("sun", 1), ("'א", 1), ("א'", 1),
            ("monday", 2), ("mon", 2), ("'ב", 2), ("ב'", 2),
            ("tuesday", 3), ("tue", 3), ("'ג", 3), ("ג'", 3),
            ("wednesday", 4), ("wed", 4), ("'ד", 4), ("ד'", 4),
            ("thursday", 5), ("thu", 5), ("'ה", 5), ("ה'", 5),
            ("friday", 6), ("fri", 6), ("'ו", 6), ("ו'", 6),
            ("saturday", 7), ("sat", 7), ("'ש", 7), ("ש'", 7)
        ]

        struct Mark {
            let first: Int
            let second: Int
            let location: Int
            let weekday: Int?
        }

        let datePattern = #"\b(\d{1,2})([/\-])(\d{1,2})(?![./\-\d])"#
        var marks: [Mark] = []
        if let regex = try? NSRegularExpression(pattern: datePattern) {
            let nsText = text as NSString
            let range = NSRange(location: 0, length: nsText.length)
            for match in regex.matches(in: text, range: range) {
                guard match.numberOfRanges >= 4 else { continue }
                let first = Int(nsText.substring(with: match.range(at: 1))) ?? 0
                let second = Int(nsText.substring(with: match.range(at: 3))) ?? 0
                guard first > 0, second > 0 else { continue }

                let windowStart = max(0, match.range.location - 16)
                let windowEnd = min(nsText.length, match.range.location + match.range.length + 16)
                let window = nsText.substring(with: NSRange(location: windowStart, length: windowEnd - windowStart))
                    .lowercased()

                var weekday: Int?
                for (name, value) in weekdayNames where window.contains(name) {
                    weekday = value
                    break
                }
                marks.append(Mark(first: first, second: second, location: match.range.location, weekday: weekday))
            }
        }

        func score(_ order: DateOrder) -> Int {
            var total = 0
            for mark in marks {
                let day = order == .dayMonth ? mark.first : mark.second
                let month = order == .dayMonth ? mark.second : mark.first
                guard (1...12).contains(month), (1...31).contains(day) else { continue }
                var comps = DateComponents()
                comps.year = calendar.component(.year, from: Date())
                comps.month = month
                comps.day = day
                guard let date = calendar.date(from: comps),
                      let expected = mark.weekday
                else { continue }
                if calendar.component(.weekday, from: date) == expected {
                    total += 1
                } else {
                    total -= 1
                }
            }
            return total
        }

        let dayMonthScore = score(.dayMonth)
        let monthDayScore = score(.monthDay)
        if monthDayScore > dayMonthScore { return .monthDay }
        if dayMonthScore > monthDayScore { return .dayMonth }
        if looksUSExport && !hasHebrew { return .monthDay }
        return .dayMonth
    }

    private func parseLineRows(
        _ text: String,
        calendar: Calendar,
        dateOrder: DateOrder,
        preferColonTimes: Bool
    ) -> [ScannedSessionDraft] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { line -> ScannedSessionDraft? in
                if isLikelyHeader(line) { return nil }
                guard let date = firstDate(in: line, calendar: calendar, dateOrder: dateOrder) else { return nil }
                let times = allTimes(in: line, preferColon: preferColonTimes)
                guard times.count >= 2 else { return nil }
                return makeDraft(date: date, inTime: times[0], outTime: times[1], calendar: calendar, confidence: 0.9)
            }
    }

    /// Globally collect dates and times, then pair each date with the nearest unused times.
    private func parseGlobalDateTimePairs(
        _ text: String,
        calendar: Calendar,
        dateOrder: DateOrder,
        preferColonTimes: Bool
    ) -> [ScannedSessionDraft] {
        struct MarkedDate {
            let date: Date
            let location: Int
            let hasYear: Bool
            let usesSlash: Bool
        }
        struct MarkedTime {
            let time: (Int, Int)
            let location: Int
            var used: Bool
        }

        var dates: [MarkedDate] = []
        var times: [MarkedTime] = []

        let datePattern = #"\b(\d{1,2})([./\-])(\d{1,2})(?:\2(\d{2,4}))?\b"#
        let timePattern = preferColonTimes
            ? #"\b([01]?\d|2[0-3]):([0-5]\d)(?:[:.][0-5]\d)?\b"#
            : #"\b([01]?\d|2[0-3])[:.]([0-5]\d)(?:[:.][0-5]\d)?\b"#

        if let regex = try? NSRegularExpression(pattern: datePattern) {
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                guard let full = Range(match.range, in: text) else { continue }
                let token = String(text[full])
                guard let parsed = parseDateToken(token, calendar: calendar, dateOrder: dateOrder) else { continue }
                dates.append(
                    MarkedDate(
                        date: parsed.date,
                        location: match.range.location,
                        hasYear: parsed.hasYear,
                        usesSlash: token.contains("/")
                    )
                )
            }
        }

        if let regex = try? NSRegularExpression(pattern: timePattern) {
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                guard let full = Range(match.range, in: text),
                      let parsed = parseTime(String(text[full]))
                else { continue }
                times.append(MarkedTime(time: parsed, location: match.range.location, used: false))
            }
        }

        // Printed Hebrew sheets use `/` for table dates and `.` for times; a dotted
        // header date like 15.7.2024 must not steal the first row's clock times.
        // Keep yearless slash dates (13/07) alongside year-bearing ones.
        if dates.contains(where: { $0.usesSlash && $0.hasYear }) {
            dates = dates.filter(\.usesSlash)
        }

        guard !dates.isEmpty, times.count >= 2 else { return [] }

        var drafts: [ScannedSessionDraft] = []
        for markedDate in dates.sorted(by: { $0.location < $1.location }) {
            // Pair each date with the two nearest unused times. Hebrew RTL tables often
            // OCR clock-out/in to the left of the date, so "times after date" is wrong.
            let unused = times.enumerated().filter { !$0.element.used }
            let nearest = unused
                .map { (offset: $0.offset, time: $0.element, distance: abs($0.element.location - markedDate.location)) }
                .filter { $0.distance <= 120 }
                .sorted { $0.distance < $1.distance }
            guard nearest.count >= 2 else { continue }

            let pair = Array(nearest.prefix(2)).sorted { $0.time.location < $1.time.location }
            times[pair[0].offset].used = true
            times[pair[1].offset].used = true

            drafts.append(
                makeDraft(
                    date: markedDate.date,
                    inTime: pair[0].time.time,
                    outTime: pair[1].time.time,
                    calendar: calendar,
                    confidence: markedDate.hasYear ? 0.85 : 0.7
                )
            )
        }
        return drafts
    }

    private func parseAdjacentLineWindows(
        _ text: String,
        calendar: Calendar,
        dateOrder: DateOrder,
        preferColonTimes: Bool
    ) -> [ScannedSessionDraft] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var drafts: [ScannedSessionDraft] = []
        var index = 0
        while index < lines.count {
            let window = lines[index..<min(index + 4, lines.count)].joined(separator: " ")
            if let date = firstDate(in: window, calendar: calendar, dateOrder: dateOrder) {
                let times = allTimes(in: window, preferColon: preferColonTimes)
                if times.count >= 2 {
                    drafts.append(
                        makeDraft(date: date, inTime: times[0], outTime: times[1], calendar: calendar, confidence: 0.6)
                    )
                    index += 2
                    continue
                }
            }
            index += 1
        }
        return drafts
    }

    private func makeDraft(
        date: Date,
        inTime: (Int, Int),
        outTime: (Int, Int),
        calendar: Calendar,
        confidence: Double
    ) -> ScannedSessionDraft {
        let rawIn = combine(date: date, time: inTime, calendar: calendar)
        let rawOut = combine(date: date, time: outTime, calendar: calendar)
        let resolved = WorkSession.resolveClockPair(clockIn: rawIn, clockOut: rawOut, calendar: calendar)
        return ScannedSessionDraft(
            date: date,
            clockIn: resolved.clockIn,
            clockOut: resolved.clockOut,
            notes: String(localized: "scanner.importedNote", defaultValue: "Imported from scan"),
            confidence: confidence
        )
    }

    private func isLikelyHeader(_ line: String) -> Bool {
        let lower = line.lowercased()
        let keys = [
            "תאריך", "כניסה", "יציאה", "שעות",
            "date", "day", "entry", "exit", "clock", "hours", "total", "total_hours",
            "סה\"כ", "סהכ"
        ]
        let hits = keys.filter { lower.contains($0) }.count
        return hits >= 2 && allTimes(in: line, preferColon: false).count < 2
    }

    private func firstDate(in text: String, calendar: Calendar, dateOrder: DateOrder) -> Date? {
        let pattern = #"\b(\d{1,2})([./\-])(\d{1,2})(?:\2(\d{2,4}))?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            guard let tokenRange = Range(match.range, in: text) else { continue }
            if let parsed = parseDateToken(String(text[tokenRange]), calendar: calendar, dateOrder: dateOrder) {
                return parsed.date
            }
        }
        return nil
    }

    /// Parses a date token. Yearless dotted/colon values that look like HH.MM are rejected
    /// so printed timesheets using dots for clock-in/out (7.17, 17.08) do not become May/August days.
    private func parseDateToken(
        _ token: String,
        calendar: Calendar,
        dateOrder: DateOrder
    ) -> (date: Date, hasYear: Bool)? {
        let pattern = #"^(\d{1,2})([./\-])(\d{1,2})(?:\2(\d{2,4}))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)),
              match.numberOfRanges >= 4
        else { return nil }

        func group(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: token) else { return nil }
            return String(token[range])
        }

        guard let firstText = group(1),
              let separator = group(2),
              let secondText = group(3),
              let first = Int(firstText),
              let second = Int(secondText)
        else { return nil }
        let yearPart = group(4).flatMap(Int.init)

        if yearPart == nil {
            // Israeli printed sheets usually use `/` for dates and `.` for clock times
            // (7.17, 17.08). Yearless dotted/colon tokens are therefore times, not dates.
            if separator == "." || separator == ":" {
                return nil
            }
        }

        var day: Int
        var month: Int
        if dateOrder == .monthDay {
            month = first
            day = second
        } else {
            day = first
            month = second
        }
        var year = yearPart ?? calendar.component(.year, from: Date())
        if year < 100 { year += 2000 }

        // If the preferred order is impossible, fall back to the other order.
        if !(1...12).contains(month) || !(1...31).contains(day) {
            swap(&day, &month)
        }
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }

        let currentYear = calendar.component(.year, from: Date())
        if yearPart != nil, year < 1990 || year > currentYear + 1 {
            return nil
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return nil }
        return (calendar.startOfDay(for: date), yearPart != nil)
    }

    private func allTimes(in text: String, preferColon: Bool) -> [(Int, Int)] {
        let pattern = preferColon
            ? #"\b([01]?\d|2[0-3]):([0-5]\d)(?:[:.][0-5]\d)?\b"#
            : #"\b([01]?\d|2[0-3])[:.]([0-5]\d)(?:[:.][0-5]\d)?\b"#
        return matches(in: text, pattern: pattern).compactMap(parseTime)
    }

    private func parseTime(_ text: String) -> (Int, Int)? {
        let cleaned = text.replacingOccurrences(of: ".", with: ":")
        let parts = cleaned.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }

    private func combine(date: Date, time: (Int, Int), calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = time.0
        components.minute = time.1
        components.second = 0
        return calendar.date(from: components) ?? date
    }

    private func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }
}
