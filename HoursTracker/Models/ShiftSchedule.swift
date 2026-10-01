import Foundation

/// The worker's usual shift per weekday, learned from their own recent shifts — what
/// the "don't forget to clock in / out" reminders are timed against.
///
/// For each weekday it takes the **median** clock-in time and the **median** shift
/// length over the lookback window, so one late start or one long day doesn't move
/// the reminder. A weekday needs a minimum number of shifts before it counts as a
/// work day at all, so a one-off Friday shift doesn't start a weekly Friday nag.
struct ShiftSchedule: Equatable {
    struct Window: Equatable {
        /// Minutes after midnight the shift usually starts.
        var startMinutes: Int
        /// Usual wall-clock length, breaks included (so the end time is real).
        var durationMinutes: Int
        var sampleCount: Int
    }

    /// Keyed by `Calendar` weekday (1 = Sunday … 7 = Saturday).
    var windows: [Int: Window]

    static let empty = ShiftSchedule(windows: [:])

    static func learn(
        from sessions: [WorkSession],
        now: Date = Date(),
        calendar: Calendar = .current,
        lookbackDays: Int = 56,
        minimumSamples: Int = 2
    ) -> ShiftSchedule {
        guard let cutoff = calendar.date(byAdding: .day, value: -lookbackDays, to: now) else { return .empty }
        var starts: [Int: [Int]] = [:]
        var durations: [Int: [Int]] = [:]
        for session in sessions {
            guard let clockOut = session.clockOut,
                  session.dayType != .sick,
                  session.clockIn >= cutoff,
                  session.clockIn <= now else { continue }
            let minutes = Int(clockOut.timeIntervalSince(session.clockIn) / 60)
            // Ignore obvious mistakes (forgot to clock out, double tap).
            guard (30...(16 * 60)).contains(minutes) else { continue }
            let weekday = calendar.component(.weekday, from: session.clockIn)
            let parts = calendar.dateComponents([.hour, .minute], from: session.clockIn)
            starts[weekday, default: []].append((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            durations[weekday, default: []].append(minutes)
        }
        var windows: [Int: Window] = [:]
        for (weekday, dayStarts) in starts where dayStarts.count >= minimumSamples {
            windows[weekday] = Window(
                startMinutes: median(dayStarts),
                durationMinutes: median(durations[weekday] ?? []),
                sampleCount: dayStarts.count
            )
        }
        return ShiftSchedule(windows: windows)
    }

    func window(for date: Date, calendar: Calendar = .current) -> Window? {
        windows[calendar.component(.weekday, from: date)]
    }

    /// Usual start on `date`'s calendar day, or nil if that weekday isn't a usual work day.
    func start(on date: Date, calendar: Calendar = .current) -> Date? {
        guard let window = window(for: date, calendar: calendar) else { return nil }
        return calendar.startOfDay(for: date).addingTimeInterval(TimeInterval(window.startMinutes * 60))
    }

    /// Usual end of the shift that starts on `date`'s calendar day (may be after midnight).
    func end(on date: Date, calendar: Calendar = .current) -> Date? {
        guard let window = window(for: date, calendar: calendar),
              let start = start(on: date, calendar: calendar) else { return nil }
        return start.addingTimeInterval(TimeInterval(window.durationMinutes * 60))
    }

    private static func median(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
