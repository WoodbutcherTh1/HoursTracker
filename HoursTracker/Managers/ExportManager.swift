import Foundation
import UIKit

struct ExportRow {
    let session: WorkSession
    let breakdown: DayPayBreakdown
}

struct ExportReport {
    let settings: WorkplaceSettings
    let rows: [ExportRow]
    let totals: DayPayBreakdown
    let dateRangeDescription: String
}

enum ExportFormat: CaseIterable, Identifiable {
    case pdf
    case txt
    case docx
    case markdown

    var id: Self { self }

    var localizedName: String {
        switch self {
        case .pdf: return L10n.exportFormatPDF
        case .txt: return L10n.exportFormatTXT
        case .docx: return L10n.exportFormatDOCX
        case .markdown: return L10n.exportFormatMD
        }
    }

    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .txt: return "txt"
        case .docx: return "docx"
        case .markdown: return "md"
        }
    }
}

enum ExportDateRange: Equatable {
    case all
    case month(year: Int, month: Int)
    case custom(from: Date, to: Date)
}

final class ExportManager {
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    func buildReport(
        sessions: [WorkSession],
        settings: WorkplaceSettings,
        range: ExportDateRange
    ) -> ExportReport {
        let filtered = filter(sessions: sessions, range: range)
        let completed = filtered.filter { $0.clockOut != nil }
        let rows = completed.map { session in
            ExportRow(session: session, breakdown: OvertimeCalculator.breakdown(for: session, settings: settings))
        }
        let totals = OvertimeCalculator.aggregate(sessions: completed, settings: settings)
        return ExportReport(
            settings: settings,
            rows: rows,
            totals: totals,
            dateRangeDescription: rangeDescription(range)
        )
    }

    func export(report: ExportReport, format: ExportFormat) throws -> URL {
        switch format {
        case .pdf:
            return try exportPDF(report: report)
        case .txt:
            return try exportTXT(report: report)
        case .docx:
            return try exportDOCX(report: report)
        case .markdown:
            return try exportMarkdown(report: report)
        }
    }

    private func filter(sessions: [WorkSession], range: ExportDateRange) -> [WorkSession] {
        switch range {
        case .all:
            return sessions
        case .month(let year, let month):
            let calendar = Calendar.current
            return sessions.filter {
                let components = calendar.dateComponents([.year, .month], from: $0.date)
                return components.year == year && components.month == month
            }
        case .custom(let from, let to):
            let start = Calendar.current.startOfDay(for: from)
            let end = Calendar.current.startOfDay(for: to).addingTimeInterval(86400 - 1)
            return sessions.filter { $0.date >= start && $0.date <= end }
        }
    }

    private func rangeDescription(_ range: ExportDateRange) -> String {
        switch range {
        case .all:
            return L10n.reportAllDays
        case .month(let year, let month):
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1
            let date = Calendar.current.date(from: components) ?? Date()
            return formatter.string(from: date)
        case .custom(let from, let to):
            return "\(dateFormatter.string(from: from)) – \(dateFormatter.string(from: to))"
        }
    }

    // MARK: - PDF

    private func exportPDF(report: ExportReport) throws -> URL {
        let pageWidth: CGFloat = 842
        let pageHeight: CGFloat = 595
        let margin: CGFloat = 40
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let data = renderer.pdfData { context in
            context.beginPage()
            var y = margin

            let titleFont = UIFont.boldSystemFont(ofSize: 18)
            let headerFont = UIFont.boldSystemFont(ofSize: 10)
            let bodyFont = UIFont.systemFont(ofSize: 9)

            func draw(_ text: String, font: UIFont, x: CGFloat, width: CGFloat) {
                let attrs: [NSAttributedString.Key: Any] = [.font: font]
                text.draw(in: CGRect(x: x, y: y, width: width, height: 20), withAttributes: attrs)
            }

            draw(L10n.reportTitle, font: titleFont, x: margin, width: pageWidth - margin * 2)
            y += 28
            draw(headerText(report), font: bodyFont, x: margin, width: pageWidth - margin * 2)
            y += 30

            let columns = tableColumns()
            let colWidth = (pageWidth - margin * 2) / CGFloat(columns.count)

            UIColor.systemGray5.setFill()
            UIRectFill(CGRect(x: margin, y: y, width: pageWidth - margin * 2, height: 22))
            for (i, col) in columns.enumerated() {
                draw(col, font: headerFont, x: margin + CGFloat(i) * colWidth, width: colWidth)
            }
            y += 24

            for row in report.rows {
                if y > pageHeight - 80 {
                    context.beginPage()
                    y = margin
                }
                let values = rowValues(row)
                for (i, val) in values.enumerated() {
                    draw(val, font: bodyFont, x: margin + CGFloat(i) * colWidth, width: colWidth)
                }
                y += 18
            }

            y += 10
            UIColor.systemGray4.setFill()
            UIRectFill(CGRect(x: margin, y: y, width: pageWidth - margin * 2, height: 22))
            let totals = totalsValues(report.totals)
            for (i, val) in totals.enumerated() {
                draw(val, font: headerFont, x: margin + CGFloat(i) * colWidth, width: colWidth)
            }
        }

        return try write(data: data, extension: "pdf")
    }

    // MARK: - TXT

    private func exportTXT(report: ExportReport) throws -> URL {
        var lines: [String] = []
        lines.append(L10n.reportTitle.uppercased())
        lines.append(headerText(report))
        lines.append("")
        let columns = tableColumns()
        let widths = [12, 8, 8, 10, 8, 8, 10, 12, 12]
        lines.append(formatFixedWidth(columns, widths: widths, bold: true))
        lines.append(String(repeating: "-", count: widths.reduce(0, +)))
        for row in report.rows {
            lines.append(formatFixedWidth(rowValues(row), widths: widths))
        }
        lines.append(String(repeating: "-", count: widths.reduce(0, +)))
        lines.append(formatFixedWidth(totalsValues(report.totals), widths: widths))
        let data = lines.joined(separator: "\n").data(using: .utf8)!
        return try write(data: data, extension: "txt")
    }

    // MARK: - Markdown

    private func exportMarkdown(report: ExportReport) throws -> URL {
        var lines: [String] = []
        lines.append("# \(L10n.reportTitle)")
        lines.append("")
        lines.append(headerText(report))
        lines.append("")
        let columns = tableColumns()
        lines.append("| " + columns.joined(separator: " | ") + " |")
        lines.append("| " + columns.map { _ in "---" }.joined(separator: " | ") + " |")
        for row in report.rows {
            lines.append("| " + rowValues(row).joined(separator: " | ") + " |")
        }
        lines.append("| " + totalsValues(report.totals).joined(separator: " | ") + " |")
        let data = lines.joined(separator: "\n").data(using: .utf8)!
        return try write(data: data, extension: "md")
    }

    // MARK: - DOCX

    private func exportDOCX(report: ExportReport) throws -> URL {
        let columns = tableColumns()
        var rowsXML = ""
        rowsXML += docxRow(columns, isHeader: true)
        for row in report.rows {
            rowsXML += docxRow(rowValues(row))
        }
        rowsXML += docxRow(totalsValues(report.totals), isHeader: true)

        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>\(escapeXML(L10n.reportTitle))</w:t></w:r></w:p>
            <w:p><w:r><w:t>\(escapeXML(headerText(report)))</w:t></w:r></w:p>
            <w:tbl>
              \(rowsXML)
            </w:tbl>
          </w:body>
        </w:document>
        """

        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """

        let rels = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HoursReport-\(UUID().uuidString).docx")

        let entries: [ZipWriter.Entry] = [
            .init(path: "[Content_Types].xml", data: Data(contentTypes.utf8)),
            .init(path: "_rels/.rels", data: Data(rels.utf8)),
            .init(path: "word/document.xml", data: Data(documentXML.utf8))
        ]
        try ZipWriter.createArchive(entries: entries, outputURL: outputURL)
        return outputURL
    }

    private func docxRow(_ cells: [String], isHeader: Bool = false) -> String {
        let cellXML = cells.map { cell in
            let text = escapeXML(cell)
            if isHeader {
                return "<w:tc><w:p><w:r><w:rPr><w:b/></w:rPr><w:t>\(text)</w:t></w:r></w:p></w:tc>"
            }
            return "<w:tc><w:p><w:r><w:t>\(text)</w:t></w:r></w:p></w:tc>"
        }.joined()
        return "<w:tr>\(cellXML)</w:tr>"
    }

    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - Helpers

    private func tableColumns() -> [String] {
        [
            L10n.reportColDate, L10n.reportColIn, L10n.reportColOut,
            L10n.reportColRegular, L10n.reportColOT125, L10n.reportColOT150,
            L10n.reportColGas, L10n.reportColTotal, L10n.reportColType
        ]
    }

    private func rowValues(_ row: ExportRow) -> [String] {
        let session = row.session
        let b = row.breakdown
        return [
            dateFormatter.string(from: session.date),
            timeFormatter.string(from: session.clockIn),
            session.clockOut.map { timeFormatter.string(from: $0) } ?? "-",
            formatHours(b.regularHours),
            formatHours(b.ot125Hours),
            formatHours(b.ot150Hours),
            String(format: "₪%.0f", b.gasAllowance),
            String(format: "₪%.2f", b.totalPay),
            session.isManualEntry ? AppLocale.manualEntryLabel() : AppLocale.automaticEntryLabel()
        ]
    }

    private func totalsValues(_ totals: DayPayBreakdown) -> [String] {
        [
            L10n.reportTotal, "", "",
            formatHours(totals.regularHours),
            formatHours(totals.ot125Hours),
            formatHours(totals.ot150Hours),
            String(format: "₪%.0f", totals.gasAllowance),
            String(format: "₪%.2f", totals.totalPay),
            ""
        ]
    }

    private func headerText(_ report: ExportReport) -> String {
        let s = report.settings
        var parts = [
            L10n.reportWorker(s.workerFullName),
            L10n.reportID(s.workerIDNumber),
            L10n.reportEmployee(s.employeeNumber),
            L10n.reportWorkplace(s.workplaceName)
        ]
        if let contractor = s.contractorName, !contractor.isEmpty {
            parts.append(L10n.reportContractor(contractor))
        }
        parts.append(L10n.reportPeriod(report.dateRangeDescription))
        return parts.joined(separator: " | ")
    }

    private func formatHours(_ hours: Double) -> String {
        String(format: "%.2f", hours)
    }

    private func formatFixedWidth(_ values: [String], widths: [Int], bold: Bool = false) -> String {
        zip(values, widths).map { value, width in
            let truncated = String(value.prefix(width))
            return truncated.padding(toLength: width, withPad: " ", startingAt: 0)
        }.joined()
    }

    private func write(data: Data, extension ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HoursReport-\(UUID().uuidString).\(ext)")
        try data.write(to: url)
        return url
    }
}

enum ExportError: LocalizedError {
    case zipFailed

    var errorDescription: String? {
        switch self {
        case .zipFailed: return "Failed to create Word document."
        }
    }
}
