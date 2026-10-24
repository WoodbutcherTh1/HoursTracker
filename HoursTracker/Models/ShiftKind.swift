import Foundation

/// The name of a shift: morning, evening or night.
///
/// Night follows the Hours of Work and Rest Law: at least two hours of the shift fall
/// between 22:00 and 06:00 (`WorkSession.qualifiesAsNightShift`). Everything else is
/// named by when it started: morning 06:00–14:00, evening 14:00–22:00. A shift that is
/// still running and started in the night window (22:00–04:00) is called night from the
/// start, since a normal shift from there reaches the two hours. Display only — pay uses
/// `WorkSession.isNightShift`, which is set from the real clock-in/out times.
enum ShiftKind: Equatable {
    case morning, evening, night

    static func of(
        clockIn: Date,
        clockOut: Date?,
        storedNight: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ShiftKind {
        if let clockOut {
            if storedNight { return .night }
            return byStart(clockIn, calendar: calendar, closed: true)
        }
        // Running: night once the legal two hours are reached…
        if WorkSession.qualifiesAsNightShift(clockIn: clockIn, clockOut: now, calendar: calendar) { return .night }
        return byStart(clockIn, calendar: calendar, closed: false)
    }

    private static func byStart(_ clockIn: Date, calendar: Calendar, closed: Bool) -> ShiftKind {
        let hour = calendar.component(.hour, from: clockIn)
        switch hour {
        case 6..<14: return .morning
        case 14..<22: return .evening
        case 22..<24: return closed ? .evening : .night
        default: return hour < 4 ? (closed ? .morning : .night) : .morning   // 04:00–05:59: an early morning start
        }
    }
}

extension WorkSession {
    func shiftKind(now: Date = Date(), calendar: Calendar = .current) -> ShiftKind {
        ShiftKind.of(clockIn: clockIn, clockOut: clockOut, storedNight: isNightShift, now: now, calendar: calendar)
    }
}
