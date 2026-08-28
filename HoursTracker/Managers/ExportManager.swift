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
    case csv
    case txt
    case docx
    case markdown

    var id: Self { self }

    var localizedName: String {
        switch self {
        case .pdf: return L10n.exportFormatPDF
        case .csv: return L10n.exportFormatCSV
        case .txt: return L10n.exportFormatTXT
        case .docx: return L10n.exportFormatDOCX
        case .markdown: return L10n.exportFormatMD
        }
    }

    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .csv: return "csv"
        case .txt: return "txt"
        case .docx: return "docx"
        case .markdown: return "md"
        }
    }

    var mimeType: String {
        switch self {
        case .pdf: return "application/pdf"
        case .csv: return "text/csv"
        case .txt: return "text/plain"
        case .docx: return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case .markdown: return "text/markdown"
        }
    }
}

enum ExportDateRange: Equatable {
    case all
    case month(year: Int, month: Int)
    /// Full calendar year (Jan 1 … Dec 31 inclusive).
    case year(Int)
    case custom(from: Date, to: Date)
}

final class ExportManager {
    private var copy = ExportCopy(language: .phone)

    /// Layout direction for the active export language (independent of device/UI).
    private var isRTL: Bool { ExportLayout.isRTL(language: copy.language) }

    private lazy var dateFormatter: DateFormatter = {
        let f = DateFormatter()
        // Numeric date avoids English month names leaking into Hebrew/Arabic exports.
        f.dateFormat = "dd.MM.yy"
        // Always Western digits / Gregorian calendar — language only affects weekday names.
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    private lazy var timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    private lazy var weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    func buildReport(
        sessions: [WorkSession],
        settings: WorkplaceSettings,
        range: ExportDateRange,
        language: ExportLanguage = .phone,
        dayTypes: Set<DayType>? = nil
    ) -> ExportReport {
        apply(language: language)
        let filtered = filter(sessions: sessions, range: range)
        var completed = filtered.filter { $0.clockOut != nil }
        if let dayTypes {
            completed = completed.filter { dayTypes.contains($0.dayType) }
        }
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
        case .csv:
            return try exportCSV(report: report)
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
        case .year(let year):
            let calendar = Calendar.current
            return sessions.filter {
                calendar.component(.year, from: $0.date) == year
            }
        case .custom(let from, let to):
            // `to` is inclusive (start of last day), matching PayrollPeriod.end.
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
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = "MMMM yyyy"
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1
            let date = Calendar(identifier: .gregorian).date(from: components) ?? Date()
            return formatter.string(from: date)
        case .year(let year):
            return copy.yearLabel(year)
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
        let rtl = isRTL

        let data = renderer.pdfData { context in
            context.beginPage()
            var y = margin

            let titleFont = UIFont.boldSystemFont(ofSize: 20)
            let sectionFont = UIFont.boldSystemFont(ofSize: 12)
            let headerFont = UIFont.boldSystemFont(ofSize: 9)
            let bodyFont = UIFont.systemFont(ofSize: 9)
            let smallFont = UIFont.systemFont(ofSize: 8)

            func attrs(
                _ font: UIFont,
                color: UIColor = .black,
                align: NSTextAlignment? = nil,
                lineBreakMode: NSLineBreakMode = .byWordWrapping
            ) -> [NSAttributedString.Key: Any] {
                let style = NSMutableParagraphStyle()
                style.alignment = align ?? (rtl ? .right : .left)
                style.baseWritingDirection = rtl ? .rightToLeft : .leftToRight
                style.lineBreakMode = lineBreakMode
                return [.font: font, .foregroundColor: color, .paragraphStyle: style]
            }

            func drawText(
                _ text: String,
                font: UIFont,
                x: CGFloat,
                width: CGFloat,
                height: CGFloat = 18,
                color: UIColor = .black
            ) {
                (text as NSString).draw(
                    with: CGRect(x: x, y: y, width: width, height: height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs(font, color: color),
                    context: nil
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

            /// Logical column weights (Day … Daily wage); mirrored with the headers in RTL.
            let columnWeights: [CGFloat] = [1.55, 1.15, 0.85, 0.85, 0.75, 0.9, 0.8, 0.8, 0.8, 1.15, 1.25]
            func columnFrames(count: Int) -> [CGRect] {
                let weights = ExportLayout.visualOrder(Array(columnWeights.prefix(count)), isRTL: rtl)
                let totalWeight = weights.reduce(0, +)
                var frames: [CGRect] = []
                var x = margin
                for weight in weights {
                    let width = contentWidth * (weight / totalWeight)
                    frames.append(CGRect(x: x, y: y, width: width, height: 16))
                    x += width
                }
                return frames
            }

            func drawCell(
                _ text: String,
                in frame: CGRect,
                font: UIFont,
                color: UIColor,
                yOffset: CGFloat
            ) {
                let inset: CGFloat = 3
                let rect = CGRect(
                    x: frame.minX + inset,
                    y: frame.minY + yOffset,
                    width: max(0, frame.width - inset * 2),
                    height: 14
                )
                (text as NSString).draw(
                    with: rect,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs(font, color: color, lineBreakMode: .byTruncatingTail),
                    context: nil
                )
            }

            func drawTableHeaderRow(columns: [String]) {
                UIColor(red: 0.12, green: 0.22, blue: 0.33, alpha: 1).setFill()
                UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: 20))
                let frames = columnFrames(count: columns.count)
                for (i, col) in columns.enumerated() {
                    var frame = frames[i]
                    frame.size.height = 20
                    drawCell(col, in: frame, font: headerFont, color: .white, yOffset: 3)
                }
                y += 22
            }

            // Title band — tall enough for 20pt bold (a short rect squashes glyphs in PDF).
            UIColor(red: 0.12, green: 0.22, blue: 0.33, alpha: 1).setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: pageWidth, height: 56))
            y = 14
            drawText(copy.title, font: titleFont, x: margin, width: contentWidth, height: 28, color: .white)
            y = 64

            // Employee / workplace header
            for line in headerLines(report) {
                drawText(line, font: bodyFont, x: margin, width: contentWidth, height: 14)
                y += 14
            }
            y += 8

            // Payroll summary cards (mirrored order in RTL).
            // Aggregate banner: hours, gross, both OT tiers, deductions, net —
            // everything a payroll clerk checks first, before the daily table.
            drawText(copy.payrollSummary, font: sectionFont, x: margin, width: contentWidth)
            y += 20

            let deductions = totals.incomeTax + totals.nationalInsurance + totals.healthTax
            let netPay = totals.grossPay - deductions
            let cards = ExportLayout.visualOrder([
                (copy.colSummaryTotalHours, formatHours(totals.totalHours)),
                (copy.colGrossPay, formatMoney(totals.grossPay, currencyCode: totals.currencyCode)),
                ("125%", formatMoney(totals.ot125Pay, currencyCode: totals.currencyCode)),
                ("150%", formatMoney(totals.ot150Pay, currencyCode: totals.currencyCode)),
                (copy.colDeductions, formatMoney(deductions, currencyCode: totals.currencyCode)),
                (copy.colNetPay, formatMoney(netPay, currencyCode: totals.currencyCode))
            ], isRTL: rtl)
            let cardGap: CGFloat = 8
            let cardsPerRow = 3
            let rowCount = Int(ceil(Double(cards.count) / Double(cardsPerRow)))
            let cardWidth = (contentWidth - cardGap * CGFloat(cardsPerRow - 1)) / CGFloat(cardsPerRow)
            let labelHeight: CGFloat = 12
            let valueHeight: CGFloat = 18
            let cardHeight = labelHeight + valueHeight + 12
            for index in cards.indices {
                let row = index / cardsPerRow
                let column = index % cardsPerRow
                let x = margin + CGFloat(column) * (cardWidth + cardGap)
                let cardY = y + CGFloat(row) * (cardHeight + cardGap)
                UIColor(red: 0.94, green: 0.96, blue: 0.98, alpha: 1).setFill()
                UIRectFill(CGRect(x: x, y: cardY, width: cardWidth, height: cardHeight))
                UIColor(red: 0.75, green: 0.82, blue: 0.88, alpha: 1).setStroke()
                let path = UIBezierPath(rect: CGRect(x: x, y: cardY, width: cardWidth, height: cardHeight))
                path.lineWidth = 1
                path.stroke()
                cards[index].0.draw(
                    in: CGRect(x: x + 6, y: cardY + 5, width: cardWidth - 12, height: labelHeight),
                    withAttributes: attrs(smallFont, color: UIColor.darkGray)
                )
                cards[index].1.draw(
                    in: CGRect(x: x + 6, y: cardY + 5 + labelHeight, width: cardWidth - 12, height: valueHeight),
                    withAttributes: attrs(headerFont)
                )
            }
            y += CGFloat(rowCount) * (cardHeight + cardGap) + 6

            // Hours + pay charts side by side (hours on the right in RTL)
            let chartWidth = (contentWidth - 16) / 2
            let chartTop = y
            let hoursX = rtl ? margin + chartWidth + 16 : margin
            let payX = rtl ? margin : margin + chartWidth + 16
            let hoursBottom = drawBarChart(
                title: copy.hoursChart,
                segments: [
                    (copy.colRegular, totals.regularHours, UIColor(red: 0.20, green: 0.55, blue: 0.40, alpha: 1)),
                    (copy.colOT125, totals.ot125Hours, UIColor(red: 0.90, green: 0.55, blue: 0.15, alpha: 1)),
                    (copy.colOT150, totals.ot150Hours, UIColor(red: 0.80, green: 0.25, blue: 0.25, alpha: 1))
                ],
                x: hoursX,
                y: chartTop,
                width: chartWidth,
                isRTL: rtl,
                titleFont: sectionFont,
                labelFont: smallFont,
                valueFormatter: formatHours
            )
            let payBottom = drawBarChart(
                title: copy.payChart,
                segments: [
                    (copy.colRegular, totals.basePay, UIColor(red: 0.20, green: 0.45, blue: 0.70, alpha: 1)),
                    (copy.colOT125, totals.ot125Pay, UIColor(red: 0.90, green: 0.55, blue: 0.15, alpha: 1)),
                    (copy.colOT150, totals.ot150Pay, UIColor(red: 0.80, green: 0.25, blue: 0.25, alpha: 1)),
                    (copy.colGas, totals.gasAllowance, UIColor(red: 0.45, green: 0.45, blue: 0.55, alpha: 1))
                ],
                x: payX,
                y: chartTop,
                width: chartWidth,
                isRTL: rtl,
                titleFont: sectionFont,
                labelFont: smallFont,
                valueFormatter: { formatMoney($0, currencyCode: totals.currencyCode) }
            )
            y = max(hoursBottom, payBottom) + 12

            // Estimated deductions chart (replaces the old column guide)
            if y > pageHeight - 110 {
                context.beginPage()
                y = margin
            }
            y = drawBarChart(
                title: copy.deductionsChart,
                segments: [
                    (copy.colIncomeTax, totals.incomeTax, UIColor(red: 0.75, green: 0.28, blue: 0.32, alpha: 1)),
                    (copy.colNationalInsurance, totals.nationalInsurance, UIColor(red: 0.55, green: 0.40, blue: 0.70, alpha: 1)),
                    (copy.colHealthTax, totals.healthTax, UIColor(red: 0.20, green: 0.55, blue: 0.65, alpha: 1))
                ],
                x: margin,
                y: y,
                width: contentWidth,
                isRTL: rtl,
                titleFont: sectionFont,
                labelFont: smallFont,
                valueFormatter: { formatMoney($0, currencyCode: totals.currencyCode) }
            ) + 12

            // Daily table starts on its own page (below the summary/charts page),
            // so it isn't split with only a few rows under the graphs.
            context.beginPage()
            y = margin
            drawText(copy.dailyTable, font: sectionFont, x: margin, width: contentWidth)
            y += 18

            let columns = ExportLayout.visualOrder(tableColumns(), isRTL: rtl)
            drawTableHeaderRow(columns: columns)

            for (rowIndex, row) in report.rows.enumerated() {
                if y > pageHeight - 60 {
                    context.beginPage()
                    y = margin
                    drawTableHeaderRow(columns: columns)
                }
                if rowIndex % 2 == 1 {
                    UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1).setFill()
                    UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: 16))
                }
                let values = ExportLayout.visualOrder(rowValues(row), isRTL: rtl)
                let frames = columnFrames(count: values.count)
                for (i, val) in values.enumerated() {
                    drawCell(val, in: frames[i], font: bodyFont, color: .black, yOffset: 1)
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
            let totalVals = ExportLayout.visualOrder(totalsValues(totals), isRTL: rtl)
            let totalFrames = columnFrames(count: totalVals.count)
            for (i, val) in totalVals.enumerated() {
                var frame = totalFrames[i]
                frame.size.height = 20
                drawCell(val, in: frame, font: headerFont, color: .white, yOffset: 3)
            }
        }

        return try write(data: data, extension: "pdf")
    }

    /// Draws a titled horizontal bar chart; returns the Y position below the chart.
    /// RTL: labels on the right, bars fill right→left, values on the left.
    private func drawBarChart(
        title: String,
        segments: [(String, Double, UIColor)],
        x: CGFloat,
        y startY: CGFloat,
        width: CGFloat,
        isRTL: Bool,
        titleFont: UIFont,
        labelFont: UIFont,
        valueFormatter: (Double) -> String
    ) -> CGFloat {
        var y = startY
        let titleStyle = NSMutableParagraphStyle()
        titleStyle.alignment = isRTL ? .right : .left
        titleStyle.baseWritingDirection = isRTL ? .rightToLeft : .leftToRight
        let attrsTitle: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .paragraphStyle: titleStyle
        ]
        let labelStyle = NSMutableParagraphStyle()
        labelStyle.alignment = isRTL ? .right : .left
        labelStyle.baseWritingDirection = isRTL ? .rightToLeft : .leftToRight
        let attrsLabel: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: UIColor.darkGray,
            .paragraphStyle: labelStyle
        ]
        let valueStyle = NSMutableParagraphStyle()
        valueStyle.alignment = isRTL ? .left : .right
        let attrsValue: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: UIColor.darkGray,
            .paragraphStyle: valueStyle
        ]

        title.draw(in: CGRect(x: x, y: y, width: width, height: 16), withAttributes: attrsTitle)
        y += 20

        let total = segments.map(\.1).reduce(0, +)
        let barHeight: CGFloat = 14
        let labelWidth: CGFloat = min(90, width * 0.35)
        let valueWidth: CGFloat = 54
        let barWidth = max(40, width - labelWidth - valueWidth - 8)

        for (label, value, color) in segments {
            let fraction = total > 0 ? CGFloat(value / total) : 0
            let filled = max(0, barWidth * fraction)
            let valueText = valueFormatter(value)

            if isRTL {
                let valueX = x
                let trackX = x + valueWidth + 4
                let labelX = trackX + barWidth + 4
                valueText.draw(
                    in: CGRect(x: valueX, y: y, width: valueWidth, height: 14),
                    withAttributes: attrsValue
                )
                UIColor(white: 0.92, alpha: 1).setFill()
                UIRectFill(CGRect(x: trackX, y: y + 1, width: barWidth, height: barHeight))
                color.setFill()
                UIRectFill(CGRect(x: trackX + barWidth - filled, y: y + 1, width: filled, height: barHeight))
                label.draw(
                    in: CGRect(x: labelX, y: y, width: labelWidth, height: 14),
                    withAttributes: attrsLabel
                )
            } else {
                label.draw(
                    in: CGRect(x: x, y: y, width: labelWidth, height: 14),
                    withAttributes: attrsLabel
                )
                let trackX = x + labelWidth + 4
                UIColor(white: 0.92, alpha: 1).setFill()
                UIRectFill(CGRect(x: trackX, y: y + 1, width: barWidth, height: barHeight))
                color.setFill()
                UIRectFill(CGRect(x: trackX, y: y + 1, width: filled, height: barHeight))
                valueText.draw(
                    in: CGRect(x: trackX + barWidth + 4, y: y, width: valueWidth, height: 14),
                    withAttributes: attrsValue
                )
            }
            y += 18
        }
        return y
    }

    // MARK: - CSV

    private func exportCSV(report: ExportReport) throws -> URL {
        // Logical column order (not RTL-mirrored) — spreadsheets are LTR data tables.
        var lines = [tableColumns().map(ExportSanitizer.csvCell).joined(separator: ",")]
        for row in report.rows {
            lines.append(rowValues(row).map(ExportSanitizer.csvCell).joined(separator: ","))
        }
        lines.append(totalsValues(report.totals).map(ExportSanitizer.csvCell).joined(separator: ","))

        // UTF-8 BOM so Excel/Numbers detect Hebrew/Arabic headers correctly.
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(lines.joined(separator: "\n").utf8))
        data.append(Data("\n".utf8))
        return try write(data: data, extension: "csv")
    }

    // MARK: - TXT

    private func exportTXT(report: ExportReport) throws -> URL {
        let rtl = isRTL
        var lines: [String] = []
        lines.append(ExportLayout.directedLine(copy.title.uppercased(), isRTL: rtl))
        lines.append(contentsOf: headerLines(report).map { ExportLayout.directedLine($0, isRTL: rtl) })
        lines.append("")
        lines.append(ExportLayout.directedLine(copy.payrollSummary, isRTL: rtl))
        lines.append(contentsOf: summaryLines(report.totals).map { ExportLayout.directedLine($0, isRTL: rtl) })
        lines.append("")
        lines.append(ExportLayout.directedLine(copy.hoursChart, isRTL: rtl))
        lines.append(contentsOf: asciiBars(hoursSegments(report.totals), formatValue: formatHours).map {
            ExportLayout.directedLine($0, isRTL: rtl)
        })
        lines.append("")
        lines.append(ExportLayout.directedLine(copy.payChart, isRTL: rtl))
        lines.append(contentsOf: asciiBars(paySegments(report.totals), formatValue: {
            formatMoney($0, currencyCode: report.totals.currencyCode)
        }).map { ExportLayout.directedLine($0, isRTL: rtl) })
        lines.append("")
        lines.append(ExportLayout.directedLine(copy.deductionsChart, isRTL: rtl))
        lines.append(contentsOf: asciiBars(deductionSegments(report.totals), formatValue: {
            formatMoney($0, currencyCode: report.totals.currencyCode)
        }).map { ExportLayout.directedLine($0, isRTL: rtl) })
        lines.append("")
        lines.append(ExportLayout.directedLine(copy.dailyTable, isRTL: rtl))
        let columns = ExportLayout.visualOrder(tableColumns(), isRTL: rtl)
        let widths = ExportLayout.visualOrder(
            [10, 11, 7, 7, 7, 7, 7, 8, 10, 10, 10],
            isRTL: rtl
        )
        lines.append(formatFixedWidth(columns, widths: widths))
        lines.append(String(repeating: "-", count: widths.reduce(0, +)))
        for row in report.rows {
            lines.append(formatFixedWidth(
                ExportLayout.visualOrder(rowValues(row), isRTL: rtl),
                widths: widths
            ))
        }
        lines.append(String(repeating: "-", count: widths.reduce(0, +)))
        lines.append(formatFixedWidth(
            ExportLayout.visualOrder(totalsValues(report.totals), isRTL: rtl),
            widths: widths
        ))
        let data = lines.joined(separator: "\n").data(using: .utf8)!
        return try write(data: data, extension: "txt")
    }

    // MARK: - Markdown

    private func exportMarkdown(report: ExportReport) throws -> URL {
        let rtl = isRTL
        var lines: [String] = []
        lines.append("# \(ExportLayout.directedLine(copy.title, isRTL: rtl))")
        lines.append("")
        for line in headerLines(report) {
            lines.append("- \(ExportSanitizer.markdownInline(ExportLayout.directedLine(line, isRTL: rtl)))")
        }
        lines.append("")
        lines.append("## \(ExportLayout.directedLine(copy.payrollSummary, isRTL: rtl))")
        lines.append("")
        for line in summaryLines(report.totals) {
            lines.append("- \(ExportLayout.directedLine(line, isRTL: rtl))")
        }
        lines.append("")
        lines.append("## \(ExportLayout.directedLine(copy.hoursChart, isRTL: rtl))")
        lines.append("")
        lines.append(contentsOf: asciiBars(hoursSegments(report.totals), formatValue: formatHours).map {
            "- `\(ExportLayout.directedLine($0, isRTL: rtl))`"
        })
        lines.append("")
        lines.append("## \(ExportLayout.directedLine(copy.payChart, isRTL: rtl))")
        lines.append("")
        lines.append(contentsOf: asciiBars(paySegments(report.totals), formatValue: {
            formatMoney($0, currencyCode: report.totals.currencyCode)
        }).map { "- `\(ExportLayout.directedLine($0, isRTL: rtl))`" })
        lines.append("")
        lines.append("## \(ExportLayout.directedLine(copy.deductionsChart, isRTL: rtl))")
        lines.append("")
        lines.append(contentsOf: asciiBars(deductionSegments(report.totals), formatValue: {
            formatMoney($0, currencyCode: report.totals.currencyCode)
        }).map { "- `\(ExportLayout.directedLine($0, isRTL: rtl))`" })
        lines.append("")
        lines.append("## \(ExportLayout.directedLine(copy.dailyTable, isRTL: rtl))")
        lines.append("")
        let columns = ExportLayout.visualOrder(tableColumns(), isRTL: rtl)
        lines.append("| " + columns.joined(separator: " | ") + " |")
        lines.append("| " + columns.map { _ in "---" }.joined(separator: " | ") + " |")
        for row in report.rows {
            let cells = ExportLayout.visualOrder(rowValues(row), isRTL: rtl)
                .map(ExportSanitizer.markdownCell)
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        let totalCells = ExportLayout.visualOrder(totalsValues(report.totals), isRTL: rtl)
            .map(ExportSanitizer.markdownCell)
        lines.append("| " + totalCells.joined(separator: " | ") + " |")
        let data = lines.joined(separator: "\n").data(using: .utf8)!
        return try write(data: data, extension: "md")
    }

    // MARK: - DOCX

    private func exportDOCX(report: ExportReport) throws -> URL {
        let rtl = isRTL
        // Keep logical cell order; `bidiVisual` mirrors the table when Word/Pages open it.
        let columns = tableColumns()
        var rowsXML = ""
        rowsXML += docxRow(columns, isHeader: true, isRTL: rtl)
        for row in report.rows {
            rowsXML += docxRow(rowValues(row), isRTL: rtl)
        }
        rowsXML += docxRow(totalsValues(report.totals), isHeader: true, isRTL: rtl)

        let tblPr = rtl ? "<w:tblPr><w:bidiVisual/></w:tblPr>" : ""

        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            \(docxParagraph(copy.title, bold: true, isRTL: rtl))
            \(headerLines(report).map { docxParagraph($0, isRTL: rtl) }.joined(separator: "\n            "))
            \(docxParagraph(copy.payrollSummary, bold: true, isRTL: rtl))
            \(summaryLines(report.totals).map { docxParagraph($0, isRTL: rtl) }.joined(separator: "\n            "))
            \(docxParagraph(copy.hoursChart, bold: true, isRTL: rtl))
            \(asciiBars(hoursSegments(report.totals), formatValue: formatHours).map { docxParagraph($0, isRTL: rtl) }.joined(separator: "\n            "))
            \(docxParagraph(copy.payChart, bold: true, isRTL: rtl))
            \(asciiBars(paySegments(report.totals), formatValue: { formatMoney($0, currencyCode: report.totals.currencyCode) }).map { docxParagraph($0, isRTL: rtl) }.joined(separator: "\n            "))
            \(docxParagraph(copy.deductionsChart, bold: true, isRTL: rtl))
            \(asciiBars(deductionSegments(report.totals), formatValue: { formatMoney($0, currencyCode: report.totals.currencyCode) }).map { docxParagraph($0, isRTL: rtl) }.joined(separator: "\n            "))
            \(docxParagraph(copy.dailyTable, bold: true, isRTL: rtl))
            <w:tbl>
              \(tblPr)
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

        try ExportTempFileStore.prepareDirectory()
        let outputURL = ExportTempFileStore.exportsDirectory
            .appendingPathComponent("HoursReport-\(UUID().uuidString).docx")

        let entries: [ZipWriter.Entry] = [
            .init(path: "[Content_Types].xml", data: Data(contentTypes.utf8)),
            .init(path: "_rels/.rels", data: Data(rels.utf8)),
            .init(path: "word/document.xml", data: Data(documentXML.utf8))
        ]
        try ZipWriter.createArchive(entries: entries, outputURL: outputURL)
        return outputURL
    }

    private func docxParagraph(_ text: String, bold: Bool = false, isRTL: Bool) -> String {
        var pPrParts: [String] = []
        if isRTL {
            pPrParts.append("<w:bidi/>")
            pPrParts.append("<w:jc w:val=\"right\"/>")
        }
        let pPr = pPrParts.isEmpty ? "" : "<w:pPr>\(pPrParts.joined())</w:pPr>"
        let rPr = bold ? "<w:rPr><w:b/></w:rPr>" : ""
        return "<w:p>\(pPr)<w:r>\(rPr)<w:t>\(escapeXML(text))</w:t></w:r></w:p>"
    }

    private func docxRow(_ cells: [String], isHeader: Bool = false, isRTL: Bool = false) -> String {
        let pPr: String
        if isRTL {
            pPr = "<w:pPr><w:bidi/><w:jc w:val=\"right\"/></w:pPr>"
        } else {
            pPr = ""
        }
        let cellXML = cells.map { cell in
            let text = escapeXML(cell)
            let rPr = isHeader ? "<w:rPr><w:b/></w:rPr>" : ""
            return "<w:tc><w:p>\(pPr)<w:r>\(rPr)<w:t>\(text)</w:t></w:r></w:p></w:tc>"
        }.joined()
        return "<w:tr>\(cellXML)</w:tr>"
    }

    private func escapeXML(_ string: String) -> String {
        ExportSanitizer.escapeXML(string)
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
            "\(copy.colSummaryTotalHours): \(formatHours(totals.totalHours))",
            "\(copy.colGrossPay): \(formatMoney(totals.grossPay, currencyCode: totals.currencyCode))",
            "\(copy.colDeductions): \(formatMoney(deductions, currencyCode: totals.currencyCode))",
            "\(copy.colNetPay): \(formatMoney(totals.netPay, currencyCode: totals.currencyCode))"
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

    private func deductionSegments(_ totals: DayPayBreakdown) -> [(String, Double)] {
        [
            (copy.colIncomeTax, totals.incomeTax),
            (copy.colNationalInsurance, totals.nationalInsurance),
            (copy.colHealthTax, totals.healthTax)
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

    private func tableColumns() -> [String] {
        [
            copy.colDay, copy.colDate, copy.colIn, copy.colOut,
            copy.colBreak, copy.colTotalHours,
            copy.colRate100, copy.colRate125, copy.colRate150,
            copy.colTravel, copy.colDailyWage
        ]
    }

    private func rowValues(_ row: ExportRow) -> [String] {
        let session = row.session
        let b = row.breakdown
        let breakHours = Double(session.breakMinutes) / 60
        return [
            weekdayFormatter.string(from: session.date),
            dateFormatter.string(from: session.date),
            timeFormatter.string(from: session.clockIn),
            session.clockOut.map { timeFormatter.string(from: $0) } ?? "—",
            formatHours(breakHours),
            formatHours(b.totalHours),
            formatHours(b.regularHours),
            formatHours(b.ot125Hours),
            formatHours(b.ot150Hours),
            formatMoney(b.gasAllowance, currencyCode: b.currencyCode),
            formatMoney(b.grossPay, currencyCode: b.currencyCode)
        ]
    }

    private func totalsValues(_ totals: DayPayBreakdown) -> [String] {
        [
            copy.total, "", "", "",
            "",
            formatHours(totals.totalHours),
            formatHours(totals.regularHours),
            formatHours(totals.ot125Hours),
            formatHours(totals.ot150Hours),
            formatMoney(totals.gasAllowance, currencyCode: totals.currencyCode),
            formatMoney(totals.grossPay, currencyCode: totals.currencyCode)
        ]
    }

    private func formatHours(_ hours: Double) -> String {
        String(format: "%.1f", hours)
    }

    private func formatMoney(_ amount: Double, currencyCode: String) -> String {
        PayFormatter.string(amount, currencyCode: currencyCode, locale: copy.locale)
    }

    private func formatFixedWidth(_ values: [String], widths: [Int]) -> String {
        zip(values, widths).map { value, width in
            let truncated = String(value.prefix(width))
            return truncated.padding(toLength: width, withPad: " ", startingAt: 0)
        }.joined()
    }

    private func write(data: Data, extension ext: String) throws -> URL {
        let stamp: String = {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()
        return try ExportTempFileStore.write(
            data: data,
            fileName: "HoursTracker-Report-\(stamp).\(ext)"
        )
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
