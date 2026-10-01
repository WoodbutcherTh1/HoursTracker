import SwiftUI

/// A second (third, …) job with its own complete pay settings — rate, overtime,
/// rest days, tax, payroll start day — kept inside the main workplace's settings
/// so it is saved, backed up and synced exactly like them. Shifts point at it with
/// `WorkSession.workplaceID`; the main workplace is `nil`.
struct AdditionalWorkplace: Codable, Equatable, Identifiable {
    var id: UUID
    /// Index into `WorkplacePalette.colors` (the main workplace is always 0).
    var colorIndex: Int
    /// This workplace's own settings. Its `additionalWorkplaces` is always empty.
    var settings: WorkplaceSettings

    init(id: UUID = UUID(), colorIndex: Int, settings: WorkplaceSettings) {
        self.id = id
        self.colorIndex = colorIndex
        var own = settings
        own.additionalWorkplaces = []
        self.settings = own
    }
}

/// Colors that tell workplaces apart (merged History view, pickers).
enum WorkplacePalette {
    static let colors: [Color] = [
        Color(red: 0.15, green: 0.85, blue: 0.45), // main — green
        Color(red: 0.25, green: 0.60, blue: 1.00), // blue
        Color(red: 1.00, green: 0.60, blue: 0.15), // orange
        Color(red: 0.75, green: 0.45, blue: 1.00), // purple
        Color(red: 1.00, green: 0.40, blue: 0.60), // pink
        Color(red: 0.20, green: 0.80, blue: 0.85)  // teal
    ]

    static func color(_ index: Int) -> Color {
        colors[((index % colors.count) + colors.count) % colors.count]
    }

    /// First color not used by an existing workplace (wraps when all are taken).
    static func nextIndex(used: [Int]) -> Int {
        (1..<colors.count).first { !used.contains($0) } ?? (used.count % (colors.count - 1)) + 1
    }
}

extension DayPayBreakdown {
    /// Adds up totals computed separately per workplace (merged History view).
    /// Display only: each part was priced by its own workplace's rules.
    static func combined(_ parts: [DayPayBreakdown]) -> DayPayBreakdown? {
        guard let first = parts.first else { return nil }
        func sum(_ value: (DayPayBreakdown) -> Double) -> Double {
            parts.reduce(0) { $0 + value($1) }
        }
        return DayPayBreakdown(
            regularHours: sum { $0.regularHours },
            ot125Hours: sum { $0.ot125Hours },
            ot150Hours: sum { $0.ot150Hours },
            totalHours: sum { $0.totalHours },
            gasAllowance: sum { $0.gasAllowance },
            basePay: sum { $0.basePay },
            ot125Pay: sum { $0.ot125Pay },
            ot150Pay: sum { $0.ot150Pay },
            totalPay: sum { $0.totalPay },
            netPay: sum { $0.netPay },
            incomeTax: sum { $0.incomeTax },
            nationalInsurance: sum { $0.nationalInsurance },
            healthTax: sum { $0.healthTax },
            creditPointsApplied: sum { $0.creditPointsApplied },
            creditPoints: first.creditPoints,
            currencyCode: first.currencyCode
        )
    }
}
