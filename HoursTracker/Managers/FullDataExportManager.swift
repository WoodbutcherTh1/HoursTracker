import Foundation
import UIKit

enum FullDataExportFormat: String, CaseIterable, Identifiable {
    case pdf
    case csvZip
    case json

    var id: Self { self }

    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .csvZip: return "zip"
        case .json: return "json"
        }
    }

    var localizedName: String {
        switch self {
        case .pdf: return L10n.fullExportFormatPDF
        case .csvZip: return L10n.fullExportFormatCSV
        case .json: return L10n.fullExportFormatJSON
        }
    }

    var detail: String {
        switch self {
        case .pdf: return L10n.fullExportFormatPDFDetail
        case .csvZip: return L10n.fullExportFormatCSVDetail
        case .json: return L10n.fullExportFormatJSONDetail
        }
    }
}

enum FullDataImportError: LocalizedError {
    case invalidFormat
    case unsupportedFileType
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return L10n.fullImportErrorInvalidFormat
        case .unsupportedFileType:
            return L10n.fullImportErrorUnsupportedType
        case .emptyFile:
            return L10n.fullImportErrorEmpty
        }
    }
}

enum FullDataImportMode: String, CaseIterable, Identifiable {
    case replace
    case merge
    var id: Self { self }
}

/// Builds a complete personal-data export (settings, all sessions, pay breakdowns, activity log).
final class FullDataExportManager {
    private var copy = ExportCopy(language: .phone)

    private lazy var isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private lazy var dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    private lazy var timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    private lazy var stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var isRTL: Bool { ExportLayout.isRTL(language: copy.language) }

    // MARK: - Public

    func export(
        settings: WorkplaceSettings,
        sessions: [WorkSession],
        activityLog: [ActivityLogEntry],
        format: FullDataExportFormat,
        language: ExportLanguage = .phone,
        appVersion: String = FullDataExportManager.appVersionString(),
        exportedAt: Date = Date()
    ) throws -> URL {
        apply(language: language)
        let fileName = "HoursTracker-Full-Export-\(stampFormatter.string(from: exportedAt)).\(format.fileExtension)"

        switch format {
        case .json:
            let data = try buildJSON(
                settings: settings,
                sessions: sessions,
                activityLog: activityLog,
                appVersion: appVersion,
                exportedAt: exportedAt
            )
            return try ExportTempFileStore.write(data: data, fileName: fileName)
        case .csvZip:
            return try buildCSVZip(
                settings: settings,
                sessions: sessions,
                activityLog: activityLog,
                fileName: fileName
            )
        case .pdf:
            let data = buildPDF(
                settings: settings,
                sessions: sessions,
                activityLog: activityLog,
                appVersion: appVersion,
                exportedAt: exportedAt
            )
            return try ExportTempFileStore.write(data: data, fileName: fileName)
        }
    }

    /// Decodes a JSON file previously produced by `buildJSON` / full export (.json).
    func decodeJSONDocument(from data: Data) throws -> FullDataExportDocument {
        guard !data.isEmpty else { throw FullDataImportError.emptyFile }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(FullDataExportDocument.self, from: data)
        } catch {
            throw FullDataImportError.invalidFormat
        }
    }

    func loadJSONDocument(from url: URL) throws -> FullDataExportDocument {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        let data = try Data(contentsOf: url)
        return try decodeJSONDocument(from: data)
    }

    /// Testable JSON document builder (UTF-8).
    func buildJSON(
        settings: WorkplaceSettings,
        sessions: [WorkSession],
        activityLog: [ActivityLogEntry],
        appVersion: String = FullDataExportManager.appVersionString(),
        exportedAt: Date = Date()
    ) throws -> Data {
        let completed = sessions.filter { !$0.isOpen }
        let pairs = OvertimeCalculator.dayAwareBreakdowns(sessions: completed, settings: settings)
        let document = FullDataExportDocument(
            exportedAt: isoFormatter.string(from: exportedAt),
            appVersion: appVersion,
            settings: settings,
            sessions: sessions.sorted { $0.clockIn < $1.clockIn },
            computedBreakdowns: pairs.map { pair in
                FullDataExportBreakdownDTO(sessionId: pair.session.id, breakdown: pair.breakdown)
            },
            activityLog: activityLog
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    /// Testable CSV builders.
    func buildProfileCSV(settings: WorkplaceSettings) -> String {
        let lat = settings.locationLatitude.map { String($0) } ?? ""
        let lon = settings.locationLongitude.map { String($0) } ?? ""
        let rows: [(String, String)] = [
            ("workplaceName", settings.workplaceName),
            ("contractorName", settings.contractorName ?? ""),
            ("workerFullName", settings.workerFullName),
            ("workerIDNumber", settings.workerIDNumber),
            ("employeeNumber", settings.employeeNumber),
            ("hourlyRate", String(settings.hourlyRate)),
            ("dailyGasAllowance", String(settings.dailyGasAllowance)),
            ("standardDayHours", String(settings.standardDayHours)),
            ("ot125HoursCap", String(settings.ot125HoursCap)),
            ("locationLatitude", lat),
            ("locationLongitude", lon),
            ("locationRadiusMeters", String(settings.locationRadiusMeters)),
            ("maritalStatus", settings.maritalStatus.rawValue),
            ("hasChildren", String(settings.hasChildren)),
            ("numberOfChildren", String(settings.numberOfChildren)),
            ("spouseEmployed", String(settings.spouseEmployed)),
            ("payrollStartDay", String(settings.payrollStartDay)),
            ("restDayWeekday", String(settings.restDayWeekday)),
            ("secondRestDayWeekday", settings.secondRestDayWeekday.map(String.init) ?? ""),
            ("defaultBreakMinutes", String(settings.defaultBreakMinutes)),
            ("nightStandardDayHours", String(settings.nightStandardDayHours)),
            ("currencyCode", settings.currencyCode),
            ("arrivalRemindersEnabled", String(settings.arrivalRemindersEnabled)),
            ("modifiedAt", isoFormatter.string(from: settings.modifiedAt))
        ]
        var lines = [
            [
                ExportSanitizer.csvCell(copy.fullExportCSVField),
                ExportSanitizer.csvCell(copy.fullExportCSVValue)
            ].joined(separator: ",")
        ]
        for (key, value) in rows {
            lines.append([
                ExportSanitizer.csvCell(key),
                ExportSanitizer.csvCell(value)
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    func buildSessionsCSV(settings: WorkplaceSettings, sessions: [WorkSession]) -> String {
        let completed = sessions.filter { !$0.isOpen }
        let pairs = OvertimeCalculator.dayAwareBreakdowns(sessions: completed, settings: settings)
        let byID = Dictionary(uniqueKeysWithValues: pairs.map { ($0.session.id, $0.breakdown) })
        let ordered = sessions.sorted { $0.clockIn < $1.clockIn }

        let header = [
            copy.fullExportCSVId, copy.colDate, copy.colIn, copy.colOut,
            copy.fullExportCSVIsOpen, copy.fullExportCSVManual, copy.fullExportCSVAIImported,
            copy.colBreak, copy.fullExportCSVDayType, copy.fullExportCSVNight,
            copy.fullExportNotes, copy.fullExportCSVModifiedAt,
            copy.colTotalHours, copy.fullExportCSVEffectiveHours,
            copy.colRate100, copy.colRate125, copy.colRate150,
            copy.fullExportCSVBasePay, copy.fullExportCSVOT125Pay, copy.fullExportCSVOT150Pay,
            copy.colTravel, copy.colGrossPay, copy.colNetPay,
            copy.fullExportCSVIncomeTax, copy.fullExportCSVNationalInsurance, copy.fullExportCSVHealthTax,
            copy.fullExportCurrency
        ]
        var lines = [header.map(ExportSanitizer.csvCell).joined(separator: ",")]

        for session in ordered {
            let b = byID[session.id]
            let cells: [String] = [
                session.id.uuidString,
                isoFormatter.string(from: session.date),
                isoFormatter.string(from: session.clockIn),
                session.clockOut.map { isoFormatter.string(from: $0) } ?? "",
                String(session.isOpen),
                String(session.isManualEntry),
                String(session.isAIImported),
                String(session.breakMinutes),
                session.dayType.rawValue,
                String(session.isNightShift),
                session.notes ?? "",
                isoFormatter.string(from: session.modifiedAt),
                formatNumber(session.totalHours),
                formatNumber(session.effectiveHours),
                formatNumber(b?.regularHours ?? 0),
                formatNumber(b?.ot125Hours ?? 0),
                formatNumber(b?.ot150Hours ?? 0),
                formatNumber(b?.basePay ?? 0),
                formatNumber(b?.ot125Pay ?? 0),
                formatNumber(b?.ot150Pay ?? 0),
                formatNumber(b?.gasAllowance ?? 0),
                formatNumber(b?.grossPay ?? 0),
                formatNumber(b?.netPay ?? 0),
                formatNumber(b?.incomeTax ?? 0),
                formatNumber(b?.nationalInsurance ?? 0),
                formatNumber(b?.healthTax ?? 0),
                b?.currencyCode ?? settings.currencyCode
            ]
            lines.append(cells.map(ExportSanitizer.csvCell).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    func buildActivityLogCSV(_ entries: [ActivityLogEntry]) -> String {
        let header = [
            copy.fullExportCSVTimestamp,
            copy.fullExportCSVLevel,
            copy.fullExportCSVCategory,
            copy.fullExportCSVMessage,
            copy.fullExportCSVDetails
        ].map(ExportSanitizer.csvCell).joined(separator: ",")
        var rows = [header]
        for entry in entries {
            rows.append([
                ExportSanitizer.csvCell(isoFormatter.string(from: entry.timestamp)),
                ExportSanitizer.csvCell(entry.level.rawValue),
                ExportSanitizer.csvCell(entry.category),
                ExportSanitizer.csvCell(entry.message),
                ExportSanitizer.csvCell(entry.details ?? "")
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    static func appVersionString() -> String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    // MARK: - Private builders

    private func apply(language: ExportLanguage) {
        copy = ExportCopy(language: language)
        dateFormatter.locale = copy.locale
        timeFormatter.locale = copy.locale
    }

    private func buildCSVZip(
        settings: WorkplaceSettings,
        sessions: [WorkSession],
        activityLog: [ActivityLogEntry],
        fileName: String
    ) throws -> URL {
        try ExportTempFileStore.prepareDirectory()
        let outputURL = ExportTempFileStore.exportsDirectory.appendingPathComponent(fileName)
        let entries: [ZipWriter.Entry] = [
            .init(path: "profile_settings.csv", data: Data(buildProfileCSV(settings: settings).utf8)),
            .init(path: "work_sessions.csv", data: Data(buildSessionsCSV(settings: settings, sessions: sessions).utf8)),
            .init(path: "activity_log.csv", data: Data(buildActivityLogCSV(activityLog).utf8))
        ]
        try ZipWriter.createArchive(entries: entries, outputURL: outputURL)
        return outputURL
    }

    private func formatNumber(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    private func formatHours(_ hours: Double) -> String {
        String(format: "%.1f", hours)
    }

    private func formatMoney(_ amount: Double, currencyCode: String) -> String {
        PayFormatter.string(amount, currencyCode: currencyCode, locale: copy.locale)
    }
}

// MARK: - JSON DTOs

struct FullDataExportDocument: Codable, Equatable {
    let exportedAt: String
    let appVersion: String
    let settings: WorkplaceSettings
    let sessions: [WorkSession]
    let computedBreakdowns: [FullDataExportBreakdownDTO]
    let activityLog: [ActivityLogEntry]
}

struct FullDataExportBreakdownDTO: Codable, Equatable {
    let sessionId: UUID
    let regularHours: Double
    let ot125Hours: Double
    let ot150Hours: Double
    let totalHours: Double
    let gasAllowance: Double
    let basePay: Double
    let ot125Pay: Double
    let ot150Pay: Double
    let grossPay: Double
    let netPay: Double
    let incomeTax: Double
    let nationalInsurance: Double
    let healthTax: Double
    let creditPoints: Double
    let currencyCode: String

    init(sessionId: UUID, breakdown: DayPayBreakdown) {
        self.sessionId = sessionId
        regularHours = breakdown.regularHours
        ot125Hours = breakdown.ot125Hours
        ot150Hours = breakdown.ot150Hours
        totalHours = breakdown.totalHours
        gasAllowance = breakdown.gasAllowance
        basePay = breakdown.basePay
        ot125Pay = breakdown.ot125Pay
        ot150Pay = breakdown.ot150Pay
        grossPay = breakdown.grossPay
        netPay = breakdown.netPay
        incomeTax = breakdown.incomeTax
        nationalInsurance = breakdown.nationalInsurance
        healthTax = breakdown.healthTax
        creditPoints = breakdown.creditPoints
        currencyCode = breakdown.currencyCode
    }
}

// MARK: - PDF

extension FullDataExportManager {
    fileprivate func buildPDF(
        settings: WorkplaceSettings,
        sessions: [WorkSession],
        activityLog: [ActivityLogEntry],
        appVersion: String,
        exportedAt: Date
    ) -> Data {
        let pageWidth: CGFloat = 842
        let pageHeight: CGFloat = 595
        let margin: CGFloat = 36
        let contentWidth = pageWidth - margin * 2
        let rtl = isRTL
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let completed = sessions.filter { !$0.isOpen }
        let pairs = OvertimeCalculator.dayAwareBreakdowns(sessions: completed, settings: settings)
        let byID = Dictionary(uniqueKeysWithValues: pairs.map { ($0.session.id, $0.breakdown) })
        let totals = OvertimeCalculator.aggregate(sessions: completed, settings: settings)
        let orderedSessions = sessions.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.clockIn < $1.clockIn
        }

        return renderer.pdfData { context in
            var y: CGFloat = 0

            let titleFont = UIFont.boldSystemFont(ofSize: 20)
            let sectionFont = UIFont.boldSystemFont(ofSize: 12)
            let headerFont = UIFont.boldSystemFont(ofSize: 9)
            let bodyFont = UIFont.systemFont(ofSize: 9)
            let smallFont = UIFont.systemFont(ofSize: 8)

            func attrs(_ font: UIFont, color: UIColor = .black) -> [NSAttributedString.Key: Any] {
                let style = NSMutableParagraphStyle()
                style.alignment = rtl ? .right : .left
                style.baseWritingDirection = rtl ? .rightToLeft : .leftToRight
                return [.font: font, .foregroundColor: color, .paragraphStyle: style]
            }

            func beginPage() {
                context.beginPage()
                y = margin
            }

            func ensureSpace(_ needed: CGFloat) {
                if y + needed > pageHeight - margin {
                    beginPage()
                }
            }

            func drawText(_ text: String, font: UIFont, height: CGFloat = 16, color: UIColor = .black) {
                text.draw(
                    in: CGRect(x: margin, y: y, width: contentWidth, height: height),
                    withAttributes: attrs(font, color: color)
                )
                y += height
            }

            beginPage()

            // Cover band
            UIColor(red: 0.12, green: 0.22, blue: 0.33, alpha: 1).setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: pageWidth, height: 58))
            y = 14
            drawText(copy.fullExportTitle, font: titleFont, height: 22, color: .white)
            drawText(
                "\(copy.fullExportExportedAt): \(dateFormatter.string(from: exportedAt))  ·  v\(appVersion)",
                font: smallFont,
                height: 14,
                color: UIColor.white.withAlphaComponent(0.9)
            )
            y = 70

            drawText(copy.fullExportProfile, font: sectionFont)
            y += 4
            let profileLines = [
                copy.worker(settings.workerFullName),
                copy.idNumber(settings.workerIDNumber),
                copy.employee(settings.employeeNumber),
                copy.workplace(settings.workplaceName),
                "\(copy.colRate100): \(formatMoney(settings.hourlyRate, currencyCode: settings.currencyCode))",
                "\(copy.creditPoints(String(format: "%.2f", TaxCreditPointsCalculator.creditPoints(for: settings))))",
                "\(copy.fullExportPayrollStart): \(settings.payrollStartDay)",
                "\(copy.fullExportCurrency): \(settings.currencyCode)"
            ]
            for line in profileLines where !line.hasSuffix(": ") && !line.hasSuffix(": 0") {
                ensureSpace(14)
                drawText(line, font: bodyFont, height: 14)
            }
            y += 10

            // Lifetime stats cards
            ensureSpace(80)
            drawText(copy.fullExportStatistics, font: sectionFont)
            y += 6
            let cards: [(String, String)] = [
                (copy.fullExportTotalShifts, "\(sessions.count)"),
                (copy.colSummaryTotalHours, formatHours(totals.totalHours)),
                (copy.colGrossPay, formatMoney(totals.grossPay, currencyCode: totals.currencyCode)),
                (copy.colNetPay, formatMoney(totals.netPay, currencyCode: totals.currencyCode))
            ]
            let visualCards = ExportLayout.visualOrder(cards, isRTL: rtl)
            let cardGap: CGFloat = 10
            let cardWidth = (contentWidth - cardGap * 3) / 4
            let cardHeight: CGFloat = 48
            for (index, card) in visualCards.enumerated() {
                let x = margin + CGFloat(index) * (cardWidth + cardGap)
                UIColor(red: 0.94, green: 0.96, blue: 0.98, alpha: 1).setFill()
                UIRectFill(CGRect(x: x, y: y, width: cardWidth, height: cardHeight))
                card.0.draw(
                    in: CGRect(x: x + 6, y: y + 6, width: cardWidth - 12, height: 14),
                    withAttributes: attrs(smallFont, color: .darkGray)
                )
                card.1.draw(
                    in: CGRect(x: x + 6, y: y + 22, width: cardWidth - 12, height: 18),
                    withAttributes: attrs(headerFont)
                )
            }
            y += cardHeight + 8
            drawText(
                "\(copy.colOT125): \(formatHours(totals.ot125Hours))  ·  \(copy.colOT150): \(formatHours(totals.ot150Hours))  ·  \(copy.fullExportOpenShifts): \(sessions.filter(\.isOpen).count)",
                font: smallFont,
                height: 14,
                color: .darkGray
            )
            y += 12

            // Sessions table
            ensureSpace(40)
            drawText(copy.fullExportSessions, font: sectionFont)
            y += 6

            let columns = ExportLayout.visualOrder([
                copy.colDate, copy.colIn, copy.colOut, copy.colTotalHours,
                copy.colRate100, copy.colRate125, copy.colRate150,
                copy.colTravel, copy.colDailyWage, copy.fullExportNotes
            ], isRTL: rtl)
            let colWidth = contentWidth / CGFloat(columns.count)

            func drawHeader() {
                UIColor(red: 0.12, green: 0.22, blue: 0.33, alpha: 1).setFill()
                UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: 18))
                for (i, col) in columns.enumerated() {
                    col.draw(
                        in: CGRect(x: margin + CGFloat(i) * colWidth + 2, y: y + 2, width: colWidth - 4, height: 14),
                        withAttributes: attrs(headerFont, color: .white)
                    )
                }
                y += 20
            }

            drawHeader()

            for (rowIndex, session) in orderedSessions.enumerated() {
                ensureSpace(18)
                if y < margin + 24 {
                    drawHeader()
                }
                if rowIndex % 2 == 1 {
                    UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1).setFill()
                    UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: 16))
                }
                let b = byID[session.id]
                let values = ExportLayout.visualOrder([
                    dateFormatter.string(from: session.date),
                    timeFormatter.string(from: session.clockIn),
                    session.clockOut.map { timeFormatter.string(from: $0) } ?? copy.fullExportOpen,
                    formatHours(session.totalHours),
                    formatHours(b?.regularHours ?? 0),
                    formatHours(b?.ot125Hours ?? 0),
                    formatHours(b?.ot150Hours ?? 0),
                    formatMoney(b?.gasAllowance ?? 0, currencyCode: settings.currencyCode),
                    formatMoney(b?.grossPay ?? 0, currencyCode: settings.currencyCode),
                    String((session.notes ?? "").prefix(18))
                ], isRTL: rtl)
                for (i, val) in values.enumerated() {
                    val.draw(
                        in: CGRect(x: margin + CGFloat(i) * colWidth + 2, y: y + 1, width: colWidth - 4, height: 14),
                        withAttributes: attrs(bodyFont)
                    )
                }
                y += 16
            }

            // Activity log appendix
            y += 14
            ensureSpace(40)
            drawText(copy.fullExportActivityLog, font: sectionFont)
            y += 6
            if activityLog.isEmpty {
                drawText("—", font: bodyFont, height: 14, color: .darkGray)
            } else {
                for entry in activityLog.prefix(200) {
                    ensureSpace(28)
                    let stamp = dateFormatter.string(from: entry.timestamp)
                        + " "
                        + timeFormatter.string(from: entry.timestamp)
                    let line = "[\(entry.level.rawValue)] \(entry.category) — \(entry.message)"
                    drawText(stamp, font: smallFont, height: 12, color: .darkGray)
                    drawText(line, font: bodyFont, height: 14)
                    if let details = entry.details, !details.isEmpty {
                        drawText(details, font: smallFont, height: 12, color: .darkGray)
                    }
                    y += 2
                }
            }
        }
    }
}
