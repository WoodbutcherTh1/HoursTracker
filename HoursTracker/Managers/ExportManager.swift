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
    private var copy = ExportCopy(language: .phone)

    private lazy var dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private lazy var timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private lazy var weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    func buildReport(
        sessions: [WorkSession],
        settings: WorkplaceSettings,
        range: ExportDateRange,
        language: ExportLanguage = .phone
    ) -> ExportReport {
        apply(language: language)
        let filtered = filter(sessions: sessions, range: range)
        let completed = filtered.filter { $0.clockOut != nil }
        let rows = OvertimeCalculator.dayAwareBreakdowns(sessions: completed, settings: settings)
            .map { ExportRow(session: $0.session, breakdown: $0.breakdown) }
        let totals = OvertimeCalculator.aggregate(sessions: completed, settings: settings)
        return ExportReport(
            settings: settings,
            rows: rows,
            totals: totals,
            dateRangeDescription: rangeDescription(range)
        )
    }

    func export(
        report: ExportReport,
        format: ExportFormat,
        language: ExportLanguage = .phone
    ) throws -> URL {
        apply(language: language)
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

    private func apply(language: ExportLanguage) {
        copy = ExportCopy(language: language)
        dateFormatter.locale = copy.locale
        timeFormatter.locale = copy.locale
        weekdayFormatter.locale = copy.locale
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
            return copy.allDays
        case .month(let year, let month):
            let formatter = DateFormatter()
            formatter.locale = copy.locale
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

    // MARK: - PDF (payroll layout)

    private func exportPDF(report: ExportReport) throws -> URL {
        let pageWidth: CGFloat = 842
        let pageHeight: CGFloat = 595
        let margin: CGFloat = 36
        let contentWidth = pageWidth - margin * 2
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        let totals = report.totals

        let data = renderer.pdfData { context in
            context.beginPage()
            var y = margin

            let titleFont = UIFont.boldSystemFont(ofSize: 20)
            let sectionFont = UIFont.boldSystemFont(ofSize: 12)
            let headerFont = UIFont.boldSystemFont(ofSize: 9)
            let bodyFont = UIFont.systemFont(ofSize: 9)
            let smallFont = UIFont.systemFont(ofSize: 8)

            func attrs(_ font: UIFont, color: UIColor = .black) -> [NSAttributedString.Key: Any] {
                [.font: font, .foregroundColor: color]
            }

            func drawText(
                _ text: String,
                font: UIFont,
                x: CGFloat,
                width: CGFloat,
                height: CGFloat = 18,
                color: UIColor = .black
            ) {
                text.draw(
                    in: CGRect(x: x, y: y, width: width, height: height),
                    withAttributes: attrs(font, color: color)
                )
            }

            func wrappedHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
                let rect = (text as NSString).boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs(font),
                    context: nil
                )
                return ceil(rect.height)
            }

            // Title band
            UIColor(red: 0.12, green: 0.22, blue: 0.33, alpha: 1).setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: pageWidth, height: 52))
            y = 16
            drawText(copy.title, font: titleFont, x: margin, width: contentWidth, color: .white)
            y = 60

            // Employee / workplace header
            let headerLines = headerLines(report)
            for line in headerLines {
                drawText(line, font: bodyFont, x: margin, width: contentWidth, height: 14)
                y += 14
            }
            y += 8

            // Payroll summary cards
            drawText(copy.payrollSummary, font: sectionFont, x: margin, width: contentWidth)
            y += 20

            let deductions = totals.incomeTax + totals.nationalInsurance + totals.healthTax
            let cards: [(String, String)] = [
                (copy.colTotalHours, formatHours(totals.totalHours)),
                (copy.colGrossPay, totals.formattedGrossPay),
                (copy.colDeductions, totals.formatted(deductions)),
                (copy.colNetPay, totals.formattedNetPay)
            ]
            let cardGap: CGFloat = 10
            let cardWidth = (contentWidth - cardGap * 3) / 4
            let cardHeight: CGFloat = 48
            for (index, card) in cards.enumerated() {
                let x = margin + CGFloat(index) * (cardWidth + cardGap)
                UIColor(red: 0.94, green: 0.96, blue: 0.98, alpha: 1).setFill()
                UIRectFill(CGRect(x: x, y: y, width: cardWidth, height: cardHeight))
                UIColor(red: 0.75, green: 0.82, blue: 0.88, alpha: 1).setStroke()
                let path = UIBezierPath(rect: CGRect(x: x, y: y, width: cardWidth, height: cardHeight))
                path.lineWidth = 1
                path.stroke()
                card.0.draw(
                    in: CGRect(x: x + 8, y: y + 6, width: cardWidth - 16, height: 14),
                    withAttributes: attrs(smallFont, color: UIColor.darkGray)
                )
                card.1.draw(
                    in: CGRect(x: x + 8, y: y + 22, width: cardWidth - 16, height: 18),
                    withAttributes: attrs(headerFont)
                )
            }
            y += cardHeight + 14

            // Hours + pay charts side by side
            let chartWidth = (contentWidth - 16) / 2
            let chartTop = y
            y = drawBarChart(
                title: copy.hoursChart,
                segments: [
                    (copy.colRegular, totals.regularHours, UIColor(red: 0.20, green: 0.55, blue: 0.40, alpha: 1)),
                    (copy.colOT125, totals.ot125Hours, UIColor(red: 0.90, green: 0.55, blue: 0.15, alpha: 1)),
                    (copy.colOT150, totals.ot150Hours, UIColor(red: 0.80, green: 0.25, blue: 0.25, alpha: 1))
                ],
                x: margin,
                y: chartTop,
                width: chartWidth,
                titleFont: sectionFont,
                labelFont: smallFont,
                valueFormatter: formatHours
            )
            let payY = drawBarChart(
                title: copy.payChart,
                segments: [
                    (copy.colRegular, totals.basePay, UIColor(red: 0.20, green: 0.45, blue: 0.70, alpha: 1)),
                    (copy.colOT125, totals.ot125Pay, UIColor(red: 0.90, green: 0.55, blue: 0.15, alpha: 1)),
                    (copy.colOT150, totals.ot150Pay, UIColor(red: 0.80, green: 0.25, blue: 0.25, alpha: 1)),
                    (copy.colGas, totals.gasAllowance, UIColor(red: 0.45, green: 0.45, blue: 0.55, alpha: 1))
                ],
                x: margin + chartWidth + 16,
                y: chartTop,
                width: chartWidth,
                titleFont: sectionFont,
                labelFont: smallFont,
                valueFormatter: { totals.formatted($0) }
            )
            y = max(y, payY) + 12

            // Column guide (compact)
            drawText(copy.legendTitle, font: sectionFont, x: margin, width: contentWidth)
            y += 16
            for line in copy.legendLines {
                let h = wrappedHeight(line, font: smallFont, width: contentWidth)
                if y + h > pageHeight - 90 {
                    context.beginPage()
                    y = margin
                }
                line.draw(
                    in: CGRect(x: margin, y: y, width: contentWidth, height: h),
                    withAttributes: attrs(smallFont, color: UIColor.darkGray)
                )
                y += h + 2
            }
            y += 10

            // Daily payroll table
            if y > pageHeight - 120 {
                context.beginPage()
                y = margin
            }
            drawText(copy.dailyTable, font: sectionFont, x: margin, width: contentWidth)
            y += 18

            let columns = tableColumns()
            let colWidth = contentWidth / CGFloat(columns.count)
            UIColor(red: 0.12, green: 0.22, blue: 0.33, alpha: 1).setFill()
            UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: 20))
            for (i, col) in columns.enumerated() {
                col.draw(
                    in: CGRect(x: margin + CGFloat(i) * colWidth + 2, y: y + 3, width: colWidth - 4, height: 14),
                    withAttributes: attrs(headerFont, color: .white)
                )
            }
            y += 22

            for (rowIndex, row) in report.rows.enumerated() {
                if y > pageHeight - 60 {
                    context.beginPage()
                    y = margin
                    UIColor(red: 0.12, green: 0.22, blue: 0.33, alpha: 1).setFill()
                    UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: 20))
                    for (i, col) in columns.enumerated() {
                        col.draw(
                            in: CGRect(x: margin + CGFloat(i) * colWidth + 2, y: y + 3, width: colWidth - 4, height: 14),
                            withAttributes: attrs(headerFont, color: .white)
                        )
                    }
                    y += 22
                }
                if rowIndex % 2 == 1 {
                    UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1).setFill()
                    UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: 16))
                }
                for (i, val) in rowValues(row).enumerated() {
                    val.draw(
                        in: CGRect(x: margin + CGFloat(i) * colWidth + 2, y: y + 1, width: colWidth - 4, height: 14),
                        withAttributes: attrs(bodyFont)
                    )
                }
                y += 16
            }

            y += 6
            if y > pageHeight - 40 {
                context.beginPage()
                y = margin
            }
            UIColor(red: 0.18, green: 0.28, blue: 0.38, alpha: 1).setFill()
            UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: 20))
            for (i, val) in totalsValues(totals).enumerated() {
                val.draw(
                    in: CGRect(x: margin + CGFloat(i) * colWidth + 2, y: y + 3, width: colWidth - 4, height: 14),
                    withAttributes: attrs(headerFont, color: .white)
                )
            }
        }

        return try write(data: data, extension: "pdf")
    }

    /// Draws a titled horizontal bar chart; returns the Y position below the chart.
    private func drawBarChart(
        title: String,
        segments: [(String, Double, UIColor)],
        x: CGFloat,
        y startY: CGFloat,
        width: CGFloat,
        titleFont: UIFont,
        labelFont: UIFont,
        valueFormatter: (Double) -> String
    ) -> CGFloat {
        var y = startY
        let attrsTitle: [NSAttributedString.Key: Any] = [.font: titleFont]
        let attrsLabel: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: UIColor.darkGray]
        title.draw(in: CGRect(x: x, y: y, width: width, height: 16), withAttributes: attrsTitle)
        y += 20

        let total = segments.map(\.1).reduce(0, +)
        let barHeight: CGFloat = 14
        let labelWidth: CGFloat = min(90, width * 0.35)
        let valueWidth: CGFloat = 54
        let barWidth = max(40, width - labelWidth - valueWidth - 8)

        for (label, value, color) in segments {
            label.draw(in: CGRect(x: x, y: y, width: labelWidth, height: 14), withAttributes: attrsLabel)
            let trackX = x + labelWidth + 4
            UIColor(white: 0.92, alpha: 1).setFill()
            UIRectFill(CGRect(x: trackX, y: y + 1, width: barWidth, height: barHeight))
            let fraction = total > 0 ? CGFloat(value / total) : 0
            color.setFill()
            UIRectFill(CGRect(x: trackX, y: y + 1, width: max(0, barWidth * fraction), height: barHeight))
            valueFormatter(value).draw(
                in: CGRect(x: trackX + barWidth + 4, y: y, width: valueWidth, height: 14),
                withAttributes: attrsLabel
            )
            y += 18
        }
        return y
    }

    // MARK: - TXT

    private func exportTXT(report: ExportReport) throws -> URL {
        var lines: [String] = []
        lines.append(copy.title.uppercased())
        lines.append(contentsOf: headerLines(report))
        lines.append("")
        lines.append(copy.payrollSummary)
        lines.append(contentsOf: summaryLines(report.totals))
        lines.append("")
        lines.append(copy.hoursChart)
        lines.append(contentsOf: asciiBars(hoursSegments(report.totals), formatValue: formatHours))
        lines.append("")
        lines.append(copy.payChart)
        lines.append(contentsOf: asciiBars(paySegments(report.totals), formatValue: { report.totals.formatted($0) }))
        lines.append("")
        lines.append(contentsOf: columnLegendBlock())
        lines.append("")
        lines.append(copy.dailyTable)
        let columns = tableColumns()
        let widths = [10, 11, 7, 7, 7, 7, 7, 8, 10, 10, 10]
        lines.append(formatFixedWidth(columns, widths: widths))
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
        lines.append("# \(copy.title)")
        lines.append("")
        for line in headerLines(report) {
            lines.append("- \(line)")
        }
        lines.append("")
        lines.append("## \(copy.payrollSummary)")
        lines.append("")
        for line in summaryLines(report.totals) {
            lines.append("- \(line)")
        }
        lines.append("")
        lines.append("## \(copy.hoursChart)")
        lines.append("")
        lines.append(contentsOf: asciiBars(hoursSegments(report.totals), formatValue: formatHours).map { "- `\($0)`" })
        lines.append("")
        lines.append("## \(copy.payChart)")
        lines.append("")
        lines.append(contentsOf: asciiBars(paySegments(report.totals), formatValue: { report.totals.formatted($0) }).map { "- `\($0)`" })
        lines.append("")
        lines.append("## \(copy.legendTitle)")
        lines.append("")
        for line in copy.legendLines {
            lines.append("- \(line)")
        }
        lines.append("")
        lines.append("## \(copy.dailyTable)")
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

        func paragraphs(_ lines: [String]) -> String {
            lines.map { "<w:p><w:r><w:t>\(escapeXML($0))</w:t></w:r></w:p>" }
                .joined(separator: "\n            ")
        }

        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:rPr><w:b/></w:rPr><w:t>\(escapeXML(copy.title))</w:t></w:r></w:p>
            \(paragraphs(headerLines(report)))
            <w:p><w:r><w:rPr><w:b/></w:rPr><w:t>\(escapeXML(copy.payrollSummary))</w:t></w:r></w:p>
            \(paragraphs(summaryLines(report.totals)))
            <w:p><w:r><w:rPr><w:b/></w:rPr><w:t>\(escapeXML(copy.hoursChart))</w:t></w:r></w:p>
            \(paragraphs(asciiBars(hoursSegments(report.totals), formatValue: formatHours)))
            <w:p><w:r><w:rPr><w:b/></w:rPr><w:t>\(escapeXML(copy.payChart))</w:t></w:r></w:p>
            \(paragraphs(asciiBars(paySegments(report.totals), formatValue: { report.totals.formatted($0) })))
            \(paragraphs(columnLegendBlock()))
            <w:p><w:r><w:rPr><w:b/></w:rPr><w:t>\(escapeXML(copy.dailyTable))</w:t></w:r></w:p>
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

    private func headerLines(_ report: ExportReport) -> [String] {
        let s = report.settings
        var lines = [
            copy.worker(s.workerFullName),
            copy.idNumber(s.workerIDNumber),
            copy.employee(s.employeeNumber),
            copy.workplace(s.workplaceName)
        ]
        if let contractor = s.contractorName, !contractor.isEmpty {
            lines.append(copy.contractor(contractor))
        }
        lines.append(copy.period(report.dateRangeDescription))
        lines.append(copy.creditPoints(String(format: "%.2f", s.creditPoints)))
        return lines
    }

    private func summaryLines(_ totals: DayPayBreakdown) -> [String] {
        let deductions = totals.incomeTax + totals.nationalInsurance + totals.healthTax
        return [
            "\(copy.colTotalHours): \(formatHours(totals.totalHours))",
            "\(copy.colGrossPay): \(totals.formattedGrossPay)",
            "\(copy.colDeductions): \(totals.formatted(deductions))",
            "\(copy.colNetPay): \(totals.formattedNetPay)"
        ]
    }

    private func hoursSegments(_ totals: DayPayBreakdown) -> [(String, Double)] {
        [
            (copy.colRegular, totals.regularHours),
            (copy.colOT125, totals.ot125Hours),
            (copy.colOT150, totals.ot150Hours)
        ]
    }

    private func paySegments(_ totals: DayPayBreakdown) -> [(String, Double)] {
        [
            (copy.colRegular, totals.basePay),
            (copy.colOT125, totals.ot125Pay),
            (copy.colOT150, totals.ot150Pay),
            (copy.colGas, totals.gasAllowance)
        ]
    }

    private func asciiBars(
        _ segments: [(String, Double)],
        formatValue: (Double) -> String
    ) -> [String] {
        let total = segments.map(\.1).reduce(0, +)
        let maxBars = 20
        return segments.map { label, value in
            let count = total > 0 ? Int((value / total) * Double(maxBars)) : 0
            let bar = String(repeating: "█", count: max(0, count))
                + String(repeating: "░", count: max(0, maxBars - count))
            return "\(label): \(bar) \(formatValue(value))"
        }
    }

    private func columnLegendBlock() -> [String] {
        [copy.legendTitle] + copy.legendLines
    }

    private func tableColumns() -> [String] {
        [
            copy.colDay, copy.colDate, copy.colIn, copy.colOut,
            copy.colRegular, copy.colOT125, copy.colOT150,
            copy.colGas, copy.colGross, copy.colNet, copy.colType
        ]
    }

    private func rowValues(_ row: ExportRow) -> [String] {
        let session = row.session
        let b = row.breakdown
        let typeLabel: String
        if session.isAIImported {
            typeLabel = copy.entryScanned
        } else if session.isManualEntry {
            typeLabel = copy.entryManual
        } else {
            typeLabel = copy.entryAutomatic
        }
        return [
            weekdayFormatter.string(from: session.date),
            dateFormatter.string(from: session.date),
            timeFormatter.string(from: session.clockIn),
            session.clockOut.map { timeFormatter.string(from: $0) } ?? "-",
            formatHours(b.regularHours),
            formatHours(b.ot125Hours),
            formatHours(b.ot150Hours),
            b.formatted(b.gasAllowance),
            b.formattedGrossPay,
            b.formattedNetPay,
            typeLabel
        ]
    }

    private func totalsValues(_ totals: DayPayBreakdown) -> [String] {
        [
            copy.total, "", "", "",
            formatHours(totals.regularHours),
            formatHours(totals.ot125Hours),
            formatHours(totals.ot150Hours),
            totals.formatted(totals.gasAllowance),
            totals.formattedGrossPay,
            totals.formattedNetPay,
            ""
        ]
    }

    private func formatHours(_ hours: Double) -> String {
        String(format: "%.2f", hours)
    }

    private func formatFixedWidth(_ values: [String], widths: [Int]) -> String {
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
