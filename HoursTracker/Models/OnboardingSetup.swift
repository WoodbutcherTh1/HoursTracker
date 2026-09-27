import Foundation

/// How the user's work week looks, asked during onboarding.
///
/// DISPLAY ONLY — never used in pay math. It drives the onboarding estimate and
/// default weekly hours only.
///
/// Legally sensitive: do NOT bind this to `restDayWeekday` / `secondRestDayWeekday`.
/// Those are the legal weekly rest days (Shabbat / Friday / Sunday) and work on them
/// earns a premium — "a day I don't usually work" is not a rest day. Someone who
/// works Friday and Saturday picks them here as workdays; their legal rest day is
/// still whatever Settings says. See AI_AGENT_BRIEF.md → Legally Sensitive Fields.
enum WeekPattern: String, CaseIterable, Identifiable {
    case fiveDays
    case sixDays
    case varies
    case custom

    var id: String { rawValue }

    /// Calendar weekdays (1 = Sunday … 7 = Saturday) worked in a typical week.
    func workdays(custom: Set<Int>) -> Set<Int> {
        switch self {
        case .fiveDays: return [1, 2, 3, 4, 5]
        case .sixDays: return [1, 2, 3, 4, 5, 6]
        case .varies: return [1, 2, 3, 4, 5]
        case .custom: return custom.isEmpty ? [1, 2, 3, 4, 5] : custom
        }
    }

    /// Starting value for the weekly-hours slider.
    func defaultWeeklyHours(custom: Set<Int>) -> Int {
        switch self {
        case .fiveDays, .sixDays: return 42
        case .varies: return 30
        case .custom:
            return OnboardingEstimate.clampWeeklyHours(workdays(custom: custom).count * 8)
        }
    }
}

/// Onboarding answers that are not workplace settings.
///
/// DISPLAY ONLY — never used in pay math. `weeklyGoalHoursDisplayOnly` is the
/// user's *expected* hours, not the legal weekly standard (`weeklyStandardHours`,
/// which drives overtime). Nothing in `OvertimeCalculator`, `IsraeliTaxEstimator`
/// or the live pay curve reads these keys — pinned by `OnboardingSetupTests`.
final class DisplayPreferences {
    static let shared = DisplayPreferences()

    private enum Key {
        static let weeklyGoal = "display.weeklyGoalHoursDisplayOnly"
        static let weekPattern = "display.weekPattern"
        static let customWorkdays = "display.customWorkdays"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // DISPLAY ONLY — never used in pay math.
    var weeklyGoalHoursDisplayOnly: Int? {
        get { defaults.object(forKey: Key.weeklyGoal) as? Int }
        set { defaults.set(newValue, forKey: Key.weeklyGoal) }
    }

    // DISPLAY ONLY — never used in pay math.
    var weekPattern: WeekPattern? {
        get { defaults.string(forKey: Key.weekPattern).flatMap(WeekPattern.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: Key.weekPattern) }
    }

    // DISPLAY ONLY — never used in pay math.
    var customWorkdays: Set<Int> {
        get { Set((defaults.array(forKey: Key.customWorkdays) as? [Int]) ?? []) }
        set { defaults.set(newValue.sorted(), forKey: Key.customWorkdays) }
    }
}

/// The onboarding's preview numbers, priced by the real pay engine
/// (`OvertimeCalculator.breakdown(totalHours:settings:)` — the quick-estimate
/// entry point) with the user's rate. No pay math of its own.
enum OnboardingEstimate {
    static let rateRange: ClosedRange<Double> = 1...500
    static let weeklyHoursRange: ClosedRange<Int> = 10...60
    static let previewDayHours: Double = 8

    static func clampWeeklyHours(_ hours: Int) -> Int {
        min(max(hours, weeklyHoursRange.lowerBound), weeklyHoursRange.upperBound)
    }

    /// Parses what was typed into the rate field: Western or Arabic-Indic digits,
    /// "." or "," or "٫" as the decimal separator. Nil when not a valid rate.
    static func parseRate(_ text: String) -> Double? {
        let arabicIndic: [Character: Character] = [
            "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
            "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9"
        ]
        let normalized = String(text.trimmingCharacters(in: .whitespaces).map { char -> Character in
            if let western = arabicIndic[char] { return western }
            if char == "," || char == "٫" { return "." }
            return char
        })
        guard let value = Double(normalized), rateRange.contains(value) else { return nil }
        return value
    }

    /// "If you work 8 hours today".
    static func day(settings: WorkplaceSettings, hours: Double = previewDayHours) -> DayPayBreakdown {
        OvertimeCalculator.breakdown(totalHours: hours, settings: settings)
    }

    /// A typical week: the weekly hours spread evenly over the workdays, each day
    /// priced by the engine. An estimate — it ignores weekly caps and holidays.
    static func weeklyGross(settings: WorkplaceSettings, weeklyHours: Int, workdayCount: Int) -> Double {
        let days = max(1, workdayCount)
        let perDay = Double(weeklyHours) / Double(days)
        return OvertimeCalculator.breakdown(totalHours: perDay, settings: settings).grossPay * Double(days)
    }
}
