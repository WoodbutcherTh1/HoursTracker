import Foundation

/// One pay tier of a shift as the user should see it: hours, their gross pay, and
/// the rate they were actually paid at.
///
/// DISPLAY ONLY — reads a `DayPayBreakdown`, never prices anything. The engine keeps
/// rest-day / holiday hours in its "regular" bucket but pays them at 1.5×
/// (`OvertimeCalculator.tiers(for:)`: 150% / 175% / 200%), so the percent comes from
/// the day type, not the bucket name — a Shabbat shift must never read "100%".
struct PayTier: Equatable, Identifiable {
    let hours: Double
    let grossPay: Double
    /// 100, 125, 150 on a regular day; 150, 175, 200 on a rest day or holiday.
    let percent: Int
    /// The day's base tier (as opposed to overtime on top of it).
    let isBase: Bool

    var id: Int { percent }

    /// Tiers with hours in them, lowest rate first.
    static func tiers(for breakdown: DayPayBreakdown, dayType: DayType) -> [PayTier] {
        let rates = OvertimeCalculator.tiers(for: dayType)
        let all = [
            PayTier(hours: breakdown.regularHours, grossPay: breakdown.basePay, percent: percent(rates.base), isBase: true),
            PayTier(hours: breakdown.ot125Hours, grossPay: breakdown.ot125Pay, percent: percent(rates.tier1), isBase: false),
            PayTier(hours: breakdown.ot150Hours, grossPay: breakdown.ot150Pay, percent: percent(rates.tier2), isBase: false)
        ]
        return all.filter { $0.hours > 0.001 }
    }

    /// Colour family of a rate: the accent at 100%, gold at 125%, orange from 150%
    /// (so a rest-day or holiday shift reads as one orange bar).
    enum Tone: Equatable {
        case accent, gold, orange
    }

    static func tone(percent: Int) -> Tone {
        switch percent {
        case ..<125: return .accent
        case 125..<150: return .gold
        default: return .orange
        }
    }

    /// The highest rate worked — what the hero glow follows.
    static func dominantPercent(_ tiers: [PayTier]) -> Int? {
        tiers.map(\.percent).max()
    }

    /// Display-only share of the day's net pay for this tier: its gross scaled by the
    /// day's net / gross ratio. Not a tax calculation — just so net mode can show a
    /// per-tier figure that adds up to the net hero.
    func approximateNet(dayGross: Double, dayNet: Double) -> Double {
        guard dayGross > 0 else { return 0 }
        return grossPay * dayNet / dayGross
    }

    /// The same proportional net share for any other gross line (e.g. the travel
    /// allowance), so every row in net mode adds up to the day's net.
    static func netShare(of gross: Double, in breakdown: DayPayBreakdown) -> Double {
        guard breakdown.grossPay > 0 else { return 0 }
        return gross * breakdown.netPay / breakdown.grossPay
    }

    private static func percent(_ multiplier: Double) -> Int {
        Int((multiplier * 100).rounded())
    }
}
