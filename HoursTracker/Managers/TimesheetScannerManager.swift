import Foundation
import UIKit
import Vision
import PDFKit
import UniformTypeIdentifiers

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

    func toWorkSession(isAIImported: Bool = true) -> WorkSession {
        WorkSession(
            date: Calendar.current.startOfDay(for: date),
            clockIn: clockIn,
            clockOut: clockOut,
            isManualEntry: true,
            isAIImported: isAIImported,
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
            notes: L10n.scannerManualDraftNote,
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
    var processingDetails: ScannerProcessingDetails?

    init(
        drafts: [ScannedSessionDraft],
        ocrText: String,
        usedManualFallback: Bool,
        processingDetails: ScannerProcessingDetails? = nil
    ) {
        self.drafts = drafts
        self.ocrText = ocrText
        self.usedManualFallback = usedManualFallback
        self.processingDetails = processingDetails
    }
}

enum TimesheetScannerError: LocalizedError, Equatable {
    case unsupportedFile
    case pdfRenderFailed
    case fileTooLarge
    case imageDecodeFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            return AppLocale.tr("scanner.error.unsupported")
        case .pdfRenderFailed:
            return AppLocale.tr("scanner.error.pdf")
        case .fileTooLarge:
            return L10n.scannerErrorFileTooLarge
        case .imageDecodeFailed:
            return AppLocale.tr("scanner.error.imageDecode")
        }
    }
}

actor TimesheetScannerManager {
    static let shared = TimesheetScannerManager()

    /// Images and PDFs.
    static let maxBinaryFileBytes: Int64 = 50 * 1024 * 1024
    /// Plain-text / CSV imports.
    static let maxTextFileBytes: Int64 = 5 * 1024 * 1024
    /// Bound OCR / PDF work.
    static let maxPDFPages = 50

    /// Shifts longer than this (or ≈24h overnight from equal tokens) need review.
    static let maxAutoAcceptHours: Double = 16

    private let cloudPreference: SmartScannerCloudPreferencing

    init(cloudPreference: SmartScannerCloudPreferencing = UserDefaultsSmartScannerCloudPreference.shared) {
        self.cloudPreference = cloudPreference
    }

    func scan(image: UIImage) async throws -> TimesheetScanResult {
        let text = try await extractOCRText(from: image)
        return await buildScanResult(from: text)
    }

    /// OCR / PDF text only — does not run the timesheet LLM pipeline.
    /// Used by payslip upload so extraction can go through `PayslipLLMRouter` instead.
    ///
    /// Propagates Vision errors instead of swallowing them to `""`: a genuine OCR
    /// failure (bad image data, Vision request error) must surface to the caller as a
    /// clear failure state, not silently produce an empty-looking, unexplained review
    /// draft that looks like the AI just "didn't fill anything in."
    func extractOCRText(from image: UIImage) async throws -> String {
        try await recognizeText(in: image)
    }

    /// OCR / embedded PDF text for a file URL (image or PDF). No timesheet structuring.
    func extractOCRText(fromFileURL url: URL) async throws -> String {
        let contentType = try url.resourceValues(forKeys: [.contentTypeKey]).contentType
        if let contentType, contentType.conforms(to: .pdf) {
            return try await extractOCRText(fromPDFURL: url)
        }
        if let contentType, contentType.conforms(to: .image) {
            try Self.validateFileSize(at: url, maxBytes: Self.maxBinaryFileBytes)
            let data = try Data(contentsOf: url)
            guard let image = UIImage(data: data) else {
                throw TimesheetScannerError.unsupportedFile
            }
            return try await extractOCRText(from: image)
        }
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            return try await extractOCRText(fromPDFURL: url)
        }
        if ["png", "jpg", "jpeg", "heic", "tif", "tiff"].contains(ext) {
            try Self.validateFileSize(at: url, maxBytes: Self.maxBinaryFileBytes)
            let data = try Data(contentsOf: url)
            guard let image = UIImage(data: data) else {
                throw TimesheetScannerError.unsupportedFile
            }
            return try await extractOCRText(from: image)
        }
        throw TimesheetScannerError.unsupportedFile
    }

    private func extractOCRText(fromPDFURL url: URL) async throws -> String {
        try Self.validateFileSize(at: url, maxBytes: Self.maxBinaryFileBytes)
        guard let document = PDFDocument(url: url) else {
            throw TimesheetScannerError.pdfRenderFailed
        }

        var allText = ""
        let pageLimit = min(document.pageCount, Self.maxPDFPages)
        for index in 0..<pageLimit {
            guard let page = document.page(at: index) else { continue }
            if let pageText = page.string, !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                allText += pageText + "\n"
            } else if let image = render(page: page) {
                allText += ((try? await recognizeText(in: image)) ?? "") + "\n"
            }
        }
        return allText
    }

    func scan(pdfURL: URL) async throws -> TimesheetScanResult {
        let allText = try await extractOCRText(fromPDFURL: pdfURL)
        return await buildScanResult(from: allText)
    }

    func scan(fileURL: URL) async throws -> TimesheetScanResult {
        let contentType = try fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType

        if let contentType, contentType.conforms(to: .pdf) {
            return try await scan(pdfURL: fileURL)
        }
        if let contentType, contentType.conforms(to: .image) {
            try Self.validateFileSize(at: fileURL, maxBytes: Self.maxBinaryFileBytes)
            let data = try Data(contentsOf: fileURL)
            guard let image = UIImage(data: data) else {
                throw TimesheetScannerError.unsupportedFile
            }
            return try await scan(image: image)
        }
        if let contentType, Self.isTextImportType(contentType) {
            try Self.validateFileSize(at: fileURL, maxBytes: Self.maxTextFileBytes)
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            return await buildScanResult(from: text)
        }

        // Fallback for providers that omit contentType: extension as a last resort.
        let ext = fileURL.pathExtension.lowercased()
        if ext == "pdf" { return try await scan(pdfURL: fileURL) }
        if ["png", "jpg", "jpeg", "heic", "tif", "tiff"].contains(ext) {
            try Self.validateFileSize(at: fileURL, maxBytes: Self.maxBinaryFileBytes)
            let data = try Data(contentsOf: fileURL)
            guard let image = UIImage(data: data) else {
                throw TimesheetScannerError.unsupportedFile
            }
            return try await scan(image: image)
        }
        if ["csv", "tsv", "txt", "md"].contains(ext) {
            try Self.validateFileSize(at: fileURL, maxBytes: Self.maxTextFileBytes)
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            return await buildScanResult(from: text)
        }
        throw TimesheetScannerError.unsupportedFile
    }

    nonisolated static func isTextImportType(_ type: UTType) -> Bool {
        type.conforms(to: .plainText)
            || type.conforms(to: .text)
            || type.conforms(to: .commaSeparatedText)
            || type.conforms(to: .tabSeparatedText)
    }

    nonisolated static func validateFileSize(at url: URL, maxBytes: Int64) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let size = Int64(values.fileSize ?? 0)
        if size <= 0 {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let attrSize = attrs[.size] as? NSNumber
            if let attrSize, attrSize.int64Value > maxBytes {
                throw TimesheetScannerError.fileTooLarge
            }
            return
        }
        if size > maxBytes {
            throw TimesheetScannerError.fileTooLarge
        }
    }

    // MARK: - Vision

    private func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = preparedCGImage(from: image) else {
            throw TimesheetScannerError.imageDecodeFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Vision can invoke the request's completion handler with an error
            // AND have `perform` itself throw for the same failure (e.g. an
            // image too small to process) — guard so the continuation only
            // ever resumes once.
            let resumeLock = NSLock()
            var hasResumed = false
            func resumeOnce(_ result: Result<String, Error>) {
                resumeLock.lock()
                defer { resumeLock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    resumeOnce(.failure(error))
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
                resumeOnce(.success(lines.joined(separator: "\n")))
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
                resumeOnce(.failure(error))
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

    // MARK: - Pipeline

    /// Vision OCR text → optional cloud LLM structure → validate → drafts.
    /// When cloud is off (default), uses local heuristic only.
    func buildScanResult(from text: String) async -> TimesheetScanResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cloudEnabled = cloudPreference.isEnabled

        if cloudEnabled {
            let router = ScannerLLMRouter.default(includeCloud: true)
            let structured = await router.structure(ocrText: trimmed)
            var (drafts, details) = ScannerRowValidator.validateAll(structured.rows)
            details.providerName = structured.providerName
            if drafts.isEmpty {
                return TimesheetScanResult(
                    drafts: [ScannedSessionDraft.blankDraft()],
                    ocrText: trimmed,
                    usedManualFallback: true,
                    processingDetails: details
                )
            }
            return TimesheetScanResult(
                drafts: drafts,
                ocrText: trimmed,
                usedManualFallback: false,
                processingDetails: details
            )
        }

        return parseResult(from: trimmed)
    }

    // MARK: - Parsing

    /// Pure parsing — `nonisolated` so local LLM fallback can call without actor re-entry.
    nonisolated func parseResult(from text: String) -> TimesheetScanResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let drafts = parseSessions(from: trimmed)
        let details = ScannerProcessingDetails(
            providerName: "Local",
            acceptedCount: drafts.filter { !$0.needsManualReview }.count,
            rejectedCount: 0,
            reviewCount: drafts.filter(\.needsManualReview).count,
            notes: drafts.map { draft in
                draft.needsManualReview ? "needs review" : "accepted"
            }
        )
        if drafts.isEmpty {
            return TimesheetScanResult(
                drafts: [ScannedSessionDraft.blankDraft()],
                ocrText: trimmed,
                usedManualFallback: true,
                processingDetails: details
            )
        }
        return TimesheetScanResult(
            drafts: drafts,
            ocrText: trimmed,
            usedManualFallback: false,
            processingDetails: details
        )
    }

    nonisolated func parseSessions(from text: String) -> [ScannedSessionDraft] {
        let normalized = normalize(text)
        let calendar = Calendar.current

        // 1) Prefer per-line rows that already contain date + 2 times.
        var drafts = parseLineRows(normalized, calendar: calendar)

        // 2) Global pattern pairing across the whole document.
        if drafts.isEmpty {
            drafts = parseGlobalDateTimePairs(normalized, calendar: calendar)
        }

        // 3) Sliding window over adjacent lines (tables often split cells).
        if drafts.isEmpty {
            drafts = parseAdjacentLineWindows(normalized, calendar: calendar)
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

    nonisolated private func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{200f}", with: "")
            .replacingOccurrences(of: "\u{200e}", with: "")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "٫", with: ".")
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "٫", with: ":")
    }

    nonisolated private func parseLineRows(_ text: String, calendar: Calendar) -> [ScannedSessionDraft] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { line -> ScannedSessionDraft? in
                if isLikelyHeader(line) { return nil }
                guard let date = firstDate(in: line, calendar: calendar) else { return nil }
                let times = allTimes(in: line)
                guard times.count >= 2 else { return nil }
                return makeDraft(date: date, inTime: times[0], outTime: times[1], calendar: calendar, confidence: 0.9)
            }
    }

    /// Globally collect dates and times, then pair each date with the next two unused times.
    nonisolated private func parseGlobalDateTimePairs(_ text: String, calendar: Calendar) -> [ScannedSessionDraft] {
        struct MarkedDate {
            let date: Date
            let location: Int
        }
        struct MarkedTime {
            let time: (Int, Int)
            let location: Int
            var used: Bool
        }

        var dates: [MarkedDate] = []
        var times: [MarkedTime] = []

        let datePattern = #"\b(\d{1,2})[./\-](\d{1,2})(?:[./\-](\d{2,4}))?\b"#
        let timePattern = #"\b([01]?\d|2[0-3])[:.]([0-5]\d)(?:[:.][0-5]\d)?\b"#

        if let regex = try? NSRegularExpression(pattern: datePattern) {
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                guard let full = Range(match.range, in: text),
                      let date = firstDate(in: String(text[full]), calendar: calendar)
                else { continue }
                dates.append(MarkedDate(date: date, location: match.range.location))
            }
        }

        if let regex = try? NSRegularExpression(pattern: timePattern) {
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                guard let full = Range(match.range, in: text),
                      let parsed = parseTime(String(text[full]))
                else { continue }
                // Skip values that were already counted as dates (e.g. 12.07 mistaken) — rare with HH:MM.
                times.append(MarkedTime(time: parsed, location: match.range.location, used: false))
            }
        }

        guard !dates.isEmpty, times.count >= 2 else { return [] }

        var drafts: [ScannedSessionDraft] = []
        for markedDate in dates.sorted(by: { $0.location < $1.location }) {
            // Prefer times that appear after this date in reading order.
            var candidates = times.enumerated().filter { !$0.element.used && $0.element.location >= markedDate.location }
            if candidates.count < 2 {
                candidates = times.enumerated().filter { !$0.element.used }
            }
            guard candidates.count >= 2 else { continue }

            let first = candidates[0]
            let second = candidates[1]
            times[first.offset].used = true
            times[second.offset].used = true

            drafts.append(
                makeDraft(
                    date: markedDate.date,
                    inTime: first.element.time,
                    outTime: second.element.time,
                    calendar: calendar,
                    confidence: 0.7
                )
            )
        }
        return drafts
    }

    nonisolated private func parseAdjacentLineWindows(_ text: String, calendar: Calendar) -> [ScannedSessionDraft] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var drafts: [ScannedSessionDraft] = []
        var index = 0
        while index < lines.count {
            let window = lines[index..<min(index + 3, lines.count)].joined(separator: " ")
            if let date = firstDate(in: window, calendar: calendar) {
                let times = allTimes(in: window)
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

    nonisolated private func makeDraft(
        date: Date,
        inTime: (Int, Int),
        outTime: (Int, Int),
        calendar: Calendar,
        confidence: Double
    ) -> ScannedSessionDraft {
        let rawIn = combine(date: date, time: inTime, calendar: calendar)
        let rawOut = combine(date: date, time: outTime, calendar: calendar)

        // Identical HH:MM tokens often come from a hours-total column, not in/out.
        // Prefer needsManualReview over inventing a ~24h overnight shift.
        if inTime.0 == outTime.0, inTime.1 == outTime.1 {
            return ScannedSessionDraft(
                date: date,
                clockIn: rawIn,
                clockOut: rawOut,
                notes: L10n.scannerImportedNote,
                isSelected: false,
                confidence: min(confidence, 0.3),
                needsManualReview: true
            )
        }

        let resolved = WorkSession.resolveClockPair(clockIn: rawIn, clockOut: rawOut, calendar: calendar)
        let hours = resolved.clockOut.timeIntervalSince(resolved.clockIn) / 3600
        let near24 = ScannerRowValidator.isNear24HourSpan(hours)
        let tooLong = hours > Self.maxAutoAcceptHours
        let needsReview = near24 || tooLong || hours <= 0

        return ScannedSessionDraft(
            date: date,
            clockIn: needsReview && near24 ? rawIn : resolved.clockIn,
            clockOut: needsReview && near24 ? rawOut : resolved.clockOut,
            notes: L10n.scannerImportedNote,
            isSelected: !needsReview,
            confidence: needsReview ? min(confidence, 0.4) : confidence,
            needsManualReview: needsReview
        )
    }

    nonisolated private func isLikelyHeader(_ line: String) -> Bool {
        let lower = line.lowercased()
        let keys = ["תאריך", "כניסה", "יציאה", "שעות", "date", "clock", "hours", "total", "סה\"כ", "סהכ"]
        let hits = keys.filter { lower.contains($0) }.count
        return hits >= 2 && allTimes(in: line).count < 2
    }

    nonisolated private func firstDate(in text: String, calendar: Calendar) -> Date? {
        let patterns = [
            #"(\d{1,2})[./\-](\d{1,2})[./\-](\d{4})"#,
            #"(\d{1,2})[./\-](\d{1,2})[./\-](\d{2})"#,
            #"(\d{1,2})[./\-](\d{1,2})(?!\d)"# // DD/MM without year → assume current year
        ]

        for (index, pattern) in patterns.enumerated() {
            guard let match = firstGroups(in: text, pattern: pattern) else { continue }
            let parts = match.compactMap(Int.init)
            guard parts.count >= 2 else { continue }

            var day = parts[0]
            var month = parts[1]
            var year = parts.count > 2 ? parts[2] : calendar.component(.year, from: Date())
            if year < 100 { year += 2000 }

            // Heuristic: if first number > 12, it's day-first; if second > 12, swap was wrong.
            if index < 2, day > 31 || month > 12 {
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

    nonisolated private func allTimes(in text: String) -> [(Int, Int)] {
        matches(in: text, pattern: #"\b([01]?\d|2[0-3])[:.]([0-5]\d)(?:[:.][0-5]\d)?\b"#)
            .compactMap(parseTime)
    }

    nonisolated private func parseTime(_ text: String) -> (Int, Int)? {
        let cleaned = text.replacingOccurrences(of: ".", with: ":")
        let parts = cleaned.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }

    nonisolated private func combine(date: Date, time: (Int, Int), calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = time.0
        components.minute = time.1
        components.second = 0
        return calendar.date(from: components) ?? date
    }

    nonisolated private func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    nonisolated private func firstGroups(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        var groups: [String] = []
        for i in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: i), in: text) else { continue }
            groups.append(String(text[range]))
        }
        return groups.isEmpty ? nil : groups
    }
}
