import Foundation

struct DayPayBreakdown: Equatable {
    let regularHours: Double
    let ot125Hours: Double
    let ot150Hours: Double
    let totalHours: Double
    let gasAllowance: Double
    let totalPay: Double

    var formattedTotalPay: String {
        String(format: "₪%.2f", totalPay)
    }
}

enum OvertimeCalculator {
    static func breakdown(
        totalHours: Double,
        settings: WorkplaceSettings,
        includeGasAllowance: Bool = true
    ) -> DayPayBreakdown {
        let regular = min(totalHours, settings.standardDayHours)
        let overtimeTotal = max(0, totalHours - settings.standardDayHours)
        let ot125 = min(overtimeTotal, settings.ot125HoursCap)
        let ot150 = max(0, overtimeTotal - ot125)

        let rate = settings.hourlyRate
        let gas = includeGasAllowance ? settings.dailyGasAllowance : 0
        let pay = regular * rate + ot125 * rate * 1.25 + ot150 * rate * 1.5 + gas

        return DayPayBreakdown(
            regularHours: regular,
            ot125Hours: ot125,
            ot150Hours: ot150,
            totalHours: totalHours,
            gasAllowance: gas,
            totalPay: pay
        )
    }

    static func breakdown(for session: WorkSession, settings: WorkplaceSettings) -> DayPayBreakdown {
        breakdown(totalHours: session.totalHours, settings: settings)
    }

    static func aggregate(
        sessions: [WorkSession],
        settings: WorkplaceSettings
    ) -> DayPayBreakdown {
        let totals = sessions.map { breakdown(for: $0, settings: settings) }
        let regular = totals.reduce(0) { $0 + $1.regularHours }
        let ot125 = totals.reduce(0) { $0 + $1.ot125Hours }
        let ot150 = totals.reduce(0) { $0 + $1.ot150Hours }
        let hours = totals.reduce(0) { $0 + $1.totalHours }
        let gas = totals.reduce(0) { $0 + $1.gasAllowance }
        let pay = totals.reduce(0) { $0 + $1.totalPay }

        return DayPayBreakdown(
            regularHours: regular,
            ot125Hours: ot125,
            ot150Hours: ot150,
            totalHours: hours,
            gasAllowance: gas,
            totalPay: pay
        )
    }
}
