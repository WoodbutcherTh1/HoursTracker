import Foundation

/// Pay classification of a work day under Israeli labor rules.
/// Rest-day and holiday work pays premium rates from the first hour.
enum DayType: String, Codable, CaseIterable, Identifiable {
    case regular
    case restDay
    case holiday
    /// No worked hours — pay is a percentage of a standard day based on
    /// the sick-leave streak (see `OvertimeCalculator.sickStreakDayNumber`),
    /// not on `clockIn`/`clockOut`.
    case sick

    var id: Self { self }

    var isPremium: Bool {
        self != .regular
    }

    var localizedName: String {
        switch self {
        case .regular: return L10n.dayTypeRegular
        case .restDay: return L10n.dayTypeRestDay
        case .holiday: return L10n.dayTypeHoliday
        case .sick: return L10n.dayTypeSick
        }
    }

    static func automatic(for date: Date, settings: WorkplaceSettings, calendar: Calendar = .current) -> DayType {
        let weekday = calendar.component(.weekday, from: date)
        return settings.isRestDayWeekday(weekday) ? .restDay : .regular
    }
}

/// One live break taken during a clocked-in shift ("יצאתי להפסקה" → "חזרתי").
/// `end == nil` while the worker is still on that break.
struct BreakInterval: Codable, Equatable, Hashable {
    var start: Date
    var end: Date?

    var isOpen: Bool { end == nil }

    func seconds(now: Date = Date()) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }
}

struct WorkSession: Codable, Identifiable, Equatable {
    let id: UUID
    var date: Date
    var clockIn: Date
    var clockOut: Date?
    var isManualEntry: Bool
    /// True when imported via the timesheet scanner / OCR flow.
    var isAIImported: Bool
    /// Unpaid break, deducted from paid hours. When the worker used the live break
    /// button, this is kept equal to the recorded `breaks` total (see `endBreak`).
    var breakMinutes: Int
    /// Breaks recorded live with the break button. Empty for manual / imported
    /// entries and for every session saved before the feature existed.
    var breaks: [BreakInterval]
    var dayType: DayType
    /// Night shifts have a shorter standard day before overtime starts.
    var isNightShift: Bool
    var notes: String?
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        date: Date,
        clockIn: Date,
        clockOut: Date? = nil,
        isManualEntry: Bool = false,
        isAIImported: Bool = false,
        breakMinutes: Int = 0,
        breaks: [BreakInterval] = [],
        dayType: DayType = .regular,
        isNightShift: Bool = false,
        notes: String? = nil,
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.clockIn = clockIn
        self.clockOut = clockOut
        self.isManualEntry = isManualEntry
        self.isAIImported = isAIImported
        self.breakMinutes = max(0, breakMinutes)
        self.breaks = breaks
        self.dayType = dayType
        self.isNightShift = isNightShift
        self.notes = notes
        self.modifiedAt = modifiedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, date, clockIn, clockOut, isManualEntry, isAIImported
        case breakMinutes, breaks, dayType, isNightShift
        case notes, modifiedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        clockIn = try c.decode(Date.self, forKey: .clockIn)
        clockOut = try c.decodeIfPresent(Date.self, forKey: .clockOut)
        isManualEntry = try c.decode(Bool.self, forKey: .isManualEntry)
        isAIImported = try c.decodeIfPresent(Bool.self, forKey: .isAIImported) ?? false
        breakMinutes = max(0, try c.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? 0)
        breaks = try c.decodeIfPresent([BreakInterval].self, forKey: .breaks) ?? []
        dayType = try c.decodeIfPresent(DayType.self, forKey: .dayType) ?? .regular
        isNightShift = try c.decodeIfPresent(Bool.self, forKey: .isNightShift) ?? false
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
    }

    mutating func touch() {
        modifiedAt = Date()
    }

    /// Applies the workplace's default unpaid break to a long shift that doesn't already
    /// carry one. Shared by `AppViewModel.clockOut()` and Home's live pay preview so the
    /// running figure doesn't drop the instant the shift is actually closed.
    mutating func applyDefaultBreakIfNeeded(settings: WorkplaceSettings) {
        // A break the worker actually recorded with the break button wins over the
        // workplace default — never deduct both.
        guard breaks.isEmpty else { return }
        guard settings.defaultBreakMinutes > 0, breakMinutes == 0, totalHours >= 6 else { return }
        breakMinutes = settings.defaultBreakMinutes
    }

    // MARK: - Live breaks

    /// The break currently in progress, if any.
    var activeBreak: BreakInterval? {
        guard isOpen else { return nil }
        return breaks.last(where: \.isOpen)
    }

    var isOnBreak: Bool { activeBreak != nil }

    /// Total time spent on recorded breaks, counting a break still in progress up to `now`.
    func recordedBreakSeconds(now: Date = Date()) -> TimeInterval {
        breaks.reduce(0) { $0 + $1.seconds(now: now) }
    }

    /// Starts a break. No-op (returns false) when the shift is closed or a break is
    /// already running, so a double tap from two devices can't open two breaks.
    @discardableResult
    mutating func startBreak(at time: Date = Date()) -> Bool {
        guard isOpen, !isOnBreak, time >= clockIn else { return false }
        breaks.append(BreakInterval(start: time, end: nil))
        return true
    }

    /// Ends the running break and folds the recorded total into `breakMinutes`.
    @discardableResult
    mutating func endBreak(at time: Date = Date()) -> Bool {
        guard let index = breaks.lastIndex(where: \.isOpen) else { return false }
        breaks[index].end = max(time, breaks[index].start)
        syncBreakMinutesFromRecordedBreaks()
        return true
    }

    /// Closes a break left running when the shift itself is closed at `time`.
    mutating func closeOpenBreak(at time: Date) {
        guard let index = breaks.lastIndex(where: \.isOpen) else { return }
        breaks[index].end = max(time, breaks[index].start)
        syncBreakMinutesFromRecordedBreaks()
    }

    private mutating func syncBreakMinutesFromRecordedBreaks() {
        guard !breaks.isEmpty else { return }
        breakMinutes = Int((recordedBreakSeconds() / 60).rounded())
    }

    /// Paid time elapsed so far on an open shift: wall-clock time minus recorded
    /// breaks (a running break stops the paid clock).
    func paidElapsedSeconds(now: Date = Date()) -> TimeInterval {
        max(0, (clockOut ?? now).timeIntervalSince(clockIn) - recordedBreakSeconds(now: clockOut ?? now))
    }

    var isOpen: Bool {
        clockOut == nil
    }

    var totalHours: Double {
        guard let clockOut else { return 0 }
        return max(0, clockOut.timeIntervalSince(clockIn) / 3600)
    }

    /// Paid hours: total minus the unpaid break.
    var effectiveHours: Double {
        max(0, totalHours - Double(breakMinutes) / 60)
    }

    var elapsedSeconds: TimeInterval {
        let end = clockOut ?? Date()
        return max(0, end.timeIntervalSince(clockIn))
    }

    var entryKindIcon: String {
        if isAIImported { return "doc.viewfinder.fill" }
        if isManualEntry { return "pencil.circle.fill" }
        return "bolt.circle.fill"
    }

    var entryKindColorName: String {
        if isAIImported { return "purple" }
        if isManualEntry { return "orange" }
        return "blue"
    }

    /// Orders clock-in / clock-out correctly.
    ///
    /// Fixes the common OCR / RTL mistake where evening and morning are
    /// swapped and then treated as a long overnight (e.g. 17:02 → 07:22+1day
    /// = 14h20, when the real day shift was 07:22 → 17:02 = 9h40).
    static func resolveClockPair(
        clockIn: Date,
        clockOut: Date,
        calendar: Calendar = .current
    ) -> (clockIn: Date, clockOut: Date) {
        if clockOut > clockIn {
            let hours = clockOut.timeIntervalSince(clockIn) / 3600
            guard hours > 12 else { return (clockIn, clockOut) }

            // Long span: maybe times were swapped and then +1 day applied.
            let day = calendar.startOfDay(for: clockIn)
            let inParts = calendar.dateComponents([.hour, .minute], from: clockIn)
            let outParts = calendar.dateComponents([.hour, .minute], from: clockOut)
            guard
                let inHour = inParts.hour, let inMinute = inParts.minute,
                let outHour = outParts.hour, let outMinute = outParts.minute,
                let earlier = calendar.date(bySettingHour: outHour, minute: outMinute, second: 0, of: day),
                let later = calendar.date(bySettingHour: inHour, minute: inMinute, second: 0, of: day),
                later > earlier
            else {
                return (clockIn, clockOut)
            }

            let sameDayHours = later.timeIntervalSince(earlier) / 3600
            if sameDayHours >= 3, sameDayHours <= 12 {
                return (earlier, later)
            }
            return (clockIn, clockOut)
        }

        // Out is not after in yet — either overnight, or the pair is reversed.
        guard let overnightOut = calendar.date(byAdding: .day, value: 1, to: clockOut) else {
            return (clockIn, clockOut)
        }
        let overnightHours = overnightOut.timeIntervalSince(clockIn) / 3600
        let swappedSameDayHours = clockIn.timeIntervalSince(clockOut) / 3600

        if overnightHours > 12, swappedSameDayHours >= 3, swappedSameDayHours <= 12 {
            return (clockOut, clockIn)
        }
        return (clockIn, overnightOut)
    }

    /// A shift counts as a night shift when at least two hours fall
    /// between 22:00 and 06:00 (Hours of Work and Rest Law).
    static func qualifiesAsNightShift(
        clockIn: Date,
        clockOut: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard clockOut > clockIn else { return false }
        var nightSeconds: TimeInterval = 0
        // Night windows run 22:00 → 06:00; check every window that could
        // overlap the shift, starting from the evening before clock-in.
        var day = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: clockIn))!
        while day <= clockOut {
            if let windowStart = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: day) {
                let windowEnd = windowStart.addingTimeInterval(8 * 3600)
                let overlap = min(clockOut, windowEnd).timeIntervalSince(max(clockIn, windowStart))
                if overlap > 0 { nightSeconds += overlap }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return nightSeconds >= 2 * 3600
    }

    static func calendarDay(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    func isSameDay(as other: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(date, inSameDayAs: other)
    }
}
