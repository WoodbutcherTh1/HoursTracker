import Foundation
import UIKit
import Vision
import PDFKit
import CoreImage

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

/// One OCR word/line with its page position (Vision normalized coords).
private struct OCRToken {
    let text: String
    let box: CGRect
    let confidence: Float
}

actor TimesheetScannerManager {
    static let shared = TimesheetScannerManager()

    private let ciContext = CIContext(options: nil)

    func scan(image: UIImage) async throws -> TimesheetScanResult {
        let tokens = (try? await recognizeTokens(in: image)) ?? []
        let flatText = tokens.map(\.text).joined(separator: "\n")
        let rowText = tableRows(from: tokens).joined(separator: "\n")

        // Prefer spatially reconstructed table rows; fall back to flat OCR text.
        var drafts = parseSessions(from: rowText)
        if drafts.isEmpty {
            drafts = parseSessions(from: flatText)
        }
        drafts = finalizeDrafts(drafts)

        if drafts.isEmpty {
            return TimesheetScanResult(
                drafts: [ScannedSessionDraft.blankDraft()],
                ocrText: flatText,
                usedManualFallback: true
            )
        }
        return TimesheetScanResult(drafts: drafts, ocrText: flatText, usedManualFallback: false)
    }

    func scan(pdfURL: URL) async throws -> TimesheetScanResult {
        guard let document = PDFDocument(url: pdfURL) else {
            throw TimesheetScannerError.pdfRenderFailed
        }

        var allText = ""
        var allDrafts: [ScannedSessionDraft] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            if let pageText = page.string, !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                allText += pageText + "\n"
                allDrafts.append(contentsOf: parseSessions(from: pageText))
            } else if let image = render(page: page) {
                let result = try await scan(image: image)
                allText += result.ocrText + "\n"
                allDrafts.append(contentsOf: result.drafts.filter { !$0.needsManualReview || $0.confidence > 0 })
            }
        }

        let drafts = finalizeDrafts(allDrafts)
        if drafts.isEmpty {
            return TimesheetScanResult(
                drafts: [ScannedSessionDraft.blankDraft()],
                ocrText: allText,
                usedManualFallback: true
            )
        }
        return TimesheetScanResult(drafts: drafts, ocrText: allText, usedManualFallback: false)
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

    private func recognizeTokens(in image: UIImage) async throws -> [OCRToken] {
        guard let cgImage = preparedCGImage(from: image) else { return [] }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                var tokens: [OCRToken] = []
                for observation in observations {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    // Drop very low-confidence noise that invents fake digits.
                    if candidate.confidence < 0.35 { continue }
                    tokens.append(
                        OCRToken(
                            text: candidate.string,
                            box: observation.boundingBox,
                            confidence: candidate.confidence
                        )
                    )
                }
                continuation.resume(returning: tokens)
            }
            request.recognitionLevel = .accurate
            // Language correction "fixes" timesheet numbers (7.17 → words). Keep it off.
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["he-IL", "en-US"]
            request.customWords = [
                "כניסה", "יציאה", "תאריך", "שעות", "נוכחות", "משמרת", "סה\"כ",
                "Date", "Day", "Entry", "Exit", "In", "Out", "Hours", "Clock", "Total", "total_hours"
            ]

            do {
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Cluster OCR boxes into table rows (top → bottom), then left → right within a row.
    private func tableRows(from tokens: [OCRToken]) -> [String] {
        guard !tokens.isEmpty else { return [] }

        let sorted = tokens.sorted { lhs, rhs in
            if abs(lhs.box.midY - rhs.box.midY) > 0.012 {
                return lhs.box.midY > rhs.box.midY
            }
            return lhs.box.minX < rhs.box.minX
        }

        var rows: [[OCRToken]] = []
        for token in sorted {
            if var last = rows.last, abs(last[0].box.midY - token.box.midY) <= 0.018 {
                last.append(token)
                rows[rows.count - 1] = last
            } else {
                rows.append([token])
            }
        }

        return rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }
                .map(\.text)
                .joined(separator: " ")
        }
    }

    private func preparedCGImage(from image: UIImage) -> CGImage? {
        let source: CIImage?
        if let cgImage = image.cgImage {
            source = CIImage(cgImage: cgImage)
        } else {
            source = image.ciImage
        }
        guard var ciImage = source else { return nil }

        // Boost contrast so faint printed tables OCR more reliably.
        if let filter = CIFilter(name: "CIColorControls") {
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            filter.setValue(1.15, forKey: kCIInputContrastKey)
            filter.setValue(0.02, forKey: kCIInputBrightnessKey)
            if let output = filter.outputImage {
                ciImage = output
            }
        }

        return ciContext.createCGImage(ciImage, from: ciImage.extent)
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
        let drafts = finalizeDrafts(parseSessions(from: trimmed))
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
        let currentYear = calendar.component(.year, from: Date())
        let dateOrder = detectDateOrder(in: normalized, calendar: calendar)
        let preferColonTimes = textContainsColonTimes(normalized)
        let preferredYear = dominantPrintedYear(in: normalized, currentYear: currentYear) ?? currentYear

        // 1) Prefer per-line rows that already contain date + 2 times.
        var drafts = parseLineRows(
            normalized,
            calendar: calendar,
            dateOrder: dateOrder,
            preferColonTimes: preferColonTimes,
            preferredYear: preferredYear
        )

        // 2) Global pattern pairing across the whole document.
        if drafts.isEmpty {
            drafts = parseGlobalDateTimePairs(
                normalized,
                calendar: calendar,
                dateOrder: dateOrder,
                preferColonTimes: preferColonTimes,
                preferredYear: preferredYear
            )
        }

        // 3) Sliding window over adjacent lines (tables often split cells).
        if drafts.isEmpty {
            drafts = parseAdjacentLineWindows(
                normalized,
                calendar: calendar,
                dateOrder: dateOrder,
                preferColonTimes: preferColonTimes,
                preferredYear: preferredYear
            )
        }

        return drafts
    }

    /// Drop impossible shifts and de-dupe identical rows (keep multiple real shifts/day).
    private func finalizeDrafts(_ drafts: [ScannedSessionDraft]) -> [ScannedSessionDraft] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let currentYear = calendar.component(.year, from: today)
        var seen = Set<String>()
        var unique: [ScannedSessionDraft] = []

        for draft in drafts.sorted(by: { $0.date < $1.date }) {
            let hours = draft.totalHours
            // Reject OCR garbage: empty, tiny, or absurdly long same-day spans.
            guard hours >= 0.5, hours <= 16 else { continue }

            // Never keep years the user is not living in (e.g. OCR 2001 while in 2026).
            let year = calendar.component(.year, from: draft.date)
            guard isPlausibleTimesheetYear(year, currentYear: currentYear) else { continue }

            // Timesheets are records of work already done — not future dates.
            let dayStart = calendar.startOfDay(for: draft.date)
            guard dayStart <= today else { continue }

            let inC = calendar.dateComponents([.hour, .minute], from: draft.clockIn)
            let outC = calendar.dateComponents([.hour, .minute], from: draft.clockOut)
            let key = "\(dayStart.timeIntervalSince1970)-\(inC.hour ?? 0)-\(inC.minute ?? 0)-\(outC.hour ?? 0)-\(outC.minute ?? 0)"
            guard seen.insert(key).inserted else { continue }

            var cleaned = draft
            // Typical work day is 3–12h; outside that, keep but force review.
            if hours < 3 || hours > 12 {
                cleaned.needsManualReview = true
                cleaned.confidence = min(cleaned.confidence, 0.45)
            }
            unique.append(cleaned)
        }
        return unique
    }

    /// Accepted import window: recent years only (payroll lag / last-year sheets).
    private func isPlausibleTimesheetYear(_ year: Int, currentYear: Int) -> Bool {
        year >= currentYear - 5 && year <= currentYear + 1
    }

    /// OCR often flips a digit (2024→2004, 2021→2001). Repair when the fixed year is plausible.
    private func sanitizeYear(_ rawYear: Int, currentYear: Int) -> Int? {
        var year = rawYear
        if year < 100 { year += 2000 }
        if isPlausibleTimesheetYear(year, currentYear: currentYear) {
            return year
        }

        // 2001 / 2004 / 2014 style misreads → try current decade with same units digit.
        if (1990...2019).contains(year) {
            let units = year % 10
            let decadeBase = (currentYear / 10) * 10
            let repaired = decadeBase + units
            if isPlausibleTimesheetYear(repaired, currentYear: currentYear) {
                return repaired
            }
            let alt = decadeBase - 10 + units
            if isPlausibleTimesheetYear(alt, currentYear: currentYear) {
                return alt
            }
        }
        return nil
    }

    /// When the sheet prints years, reuse the dominant one for yearless rows (scan 2024 sheet in 2026).
    private func dominantPrintedYear(in text: String, currentYear: Int) -> Int? {
        let pattern = #"\b(\d{1,2})[./\-](\d{1,2})[./\-](\d{2,4})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        var counts: [Int: Int] = [:]
        for match in regex.matches(in: text, range: range) {
            guard let yearRange = Range(match.range(at: 3), in: text),
                  let raw = Int(text[yearRange]),
                  let year = sanitizeYear(raw, currentYear: currentYear)
            else { continue }
            counts[year, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
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
                marks.append(Mark(first: first, second: second, weekday: weekday))
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
        preferColonTimes: Bool,
        preferredYear: Int
    ) -> [ScannedSessionDraft] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { line -> ScannedSessionDraft? in
                if isLikelyHeader(line) { return nil }
                guard let date = firstDate(
                    in: line,
                    calendar: calendar,
                    dateOrder: dateOrder,
                    preferredYear: preferredYear
                ) else { return nil }
                let times = allTimes(in: line, preferColon: preferColonTimes)
                guard let pair = pickClockPair(times) else { return nil }
                return makeDraft(date: date, inTime: pair.0, outTime: pair.1, calendar: calendar, confidence: 0.9)
            }
    }

    /// Globally collect dates and times, then pair each date with the nearest unused times.
    private func parseGlobalDateTimePairs(
        _ text: String,
        calendar: Calendar,
        dateOrder: DateOrder,
        preferColonTimes: Bool,
        preferredYear: Int
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
                guard let parsed = parseDateToken(
                    token,
                    calendar: calendar,
                    dateOrder: dateOrder,
                    preferredYear: preferredYear
                ) else { continue }
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
            let unusedIndexes = times.indices.filter { !times[$0].used }
            let nearest = unusedIndexes
                .map { (offset: $0, distance: abs(times[$0].location - markedDate.location)) }
                .filter { $0.distance <= 80 }
                .sorted { $0.distance < $1.distance }
            // Only the two closest times — taking more steals the next row's clocks.
            guard nearest.count >= 2 else { continue }

            let first = times[nearest[0].offset].time
            let second = times[nearest[1].offset].time
            times[nearest[0].offset].used = true
            times[nearest[1].offset].used = true

            drafts.append(
                makeDraft(
                    date: markedDate.date,
                    inTime: first,
                    outTime: second,
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
        preferColonTimes: Bool,
        preferredYear: Int
    ) -> [ScannedSessionDraft] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var drafts: [ScannedSessionDraft] = []
        var index = 0
        while index < lines.count {
            let window = lines[index..<min(index + 4, lines.count)].joined(separator: " ")
            if let date = firstDate(
                in: window,
                calendar: calendar,
                dateOrder: dateOrder,
                preferredYear: preferredYear
            ) {
                let times = allTimes(in: window, preferColon: preferColonTimes)
                if let pair = pickClockPair(times) {
                    drafts.append(
                        makeDraft(date: date, inTime: pair.0, outTime: pair.1, calendar: calendar, confidence: 0.6)
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

    /// Choose morning + evening when extra decimals (total hours) pollute the time list.
    private func pickClockPair(_ times: [(Int, Int)]) -> ((Int, Int), (Int, Int))? {
        guard times.count >= 2 else { return nil }
        if times.count == 2 { return (times[0], times[1]) }

        let morning = times.filter { (5...11).contains($0.0) }
            .min { lhs, rhs in
                if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
                return lhs.1 < rhs.1
            }
        let evening = times.filter { (12...23).contains($0.0) }
            .max { lhs, rhs in
                if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
                return lhs.1 < rhs.1
            }
        if let morning, let evening { return (morning, evening) }
        return (times[0], times[1])
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

    private func firstDate(
        in text: String,
        calendar: Calendar,
        dateOrder: DateOrder,
        preferredYear: Int
    ) -> Date? {
        let pattern = #"\b(\d{1,2})([./\-])(\d{1,2})(?:\2(\d{2,4}))?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            guard let tokenRange = Range(match.range, in: text) else { continue }
            if let parsed = parseDateToken(
                String(text[tokenRange]),
                calendar: calendar,
                dateOrder: dateOrder,
                preferredYear: preferredYear
            ) {
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
        dateOrder: DateOrder,
        preferredYear: Int
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
        let currentYear = calendar.component(.year, from: Date())

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

        // If the preferred order is impossible, fall back to the other order.
        if !(1...12).contains(month) || !(1...31).contains(day) {
            swap(&day, &month)
        }
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }

        let year: Int
        if let yearPart {
            guard let sanitized = sanitizeYear(yearPart, currentYear: currentYear) else {
                return nil
            }
            year = sanitized
        } else {
            // Yearless row: use the sheet's dominant printed year, else "now".
            year = preferredYear
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return nil }

        // Still refuse future calendar days after building the date.
        let today = calendar.startOfDay(for: Date())
        let dayStart = calendar.startOfDay(for: date)
        if dayStart > today { return nil }

        return (dayStart, yearPart != nil)
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
