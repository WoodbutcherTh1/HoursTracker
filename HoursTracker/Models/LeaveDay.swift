import Foundation

/// A day off the worker marks in History (no shift that day): vacation (חופש)
/// or recuperation (הבראה). Display only — counted in the pay summary, never fed
/// into the pay engine.
enum LeaveKind: String, Codable, CaseIterable, Identifiable {
    case vacation
    case recuperation

    var id: Self { self }

    var localizedName: String {
        switch self {
        case .vacation: return L10n.leaveVacation
        case .recuperation: return L10n.leaveRecuperation
        }
    }

    var systemImage: String {
        switch self {
        case .vacation: return "beach.umbrella"
        case .recuperation: return "leaf"
        }
    }
}

struct LeaveDay: Codable, Equatable, Identifiable {
    var id: UUID
    /// Start of the marked day.
    var date: Date
    var kind: LeaveKind

    init(id: UUID = UUID(), date: Date, kind: LeaveKind, calendar: Calendar = .current) {
        self.id = id
        self.date = calendar.startOfDay(for: date)
        self.kind = kind
    }
}

/// How many holiday, vacation, recuperation and sick days fall in a range —
/// the "Days" card of the pay summary. Counts distinct calendar days.
struct PeriodDayCounts: Equatable {
    /// Statutory or marked holidays the worker actually worked (paid at the holiday rate).
    var holiday = 0
    var vacation = 0
    var recuperation = 0
    var sick = 0
    /// Statutory holidays with no worked hours: a paid day off, not a worked holiday.
    var holidayNotWorked = 0

    /// - Parameters:
    ///   - start: first day of the range (any time that day).
    ///   - end: last day of the range, inclusive.
    static func count(
        sessions: [WorkSession],
        leaveDays: [LeaveDay],
        from start: Date,
        through end: Date,
        calendar: Calendar = .current
    ) -> PeriodDayCounts {
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        guard first <= last else { return PeriodDayCounts() }
        func inRange(_ date: Date) -> Bool {
            let day = calendar.startOfDay(for: date)
            return day >= first && day <= last
        }

        // Candidate holiday days: statutory holidays in the range plus days manually
        // marked as holiday. Each one is then split by whether any hours were worked.
        var holidayCandidates = Set<Date>()
        var sickDays = Set<Date>()
        var workedHoursByDay: [Date: Double] = [:]
        for session in sessions where inRange(session.date) {
            let day = calendar.startOfDay(for: session.date)
            if session.dayType == .sick {
                sickDays.insert(day)
                continue
            }
            if session.dayType == .holiday {
                holidayCandidates.insert(day)
            }
            workedHoursByDay[day, default: 0] += session.effectiveHours
        }
        var cursor = first
        while cursor <= last {
            if IsraeliHolidayCalendar.holiday(on: cursor, calendar: calendar) != nil {
                holidayCandidates.insert(cursor)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        var holidayDays = Set<Date>()
        var holidayNotWorkedDays = Set<Date>()
        for day in holidayCandidates {
            if (workedHoursByDay[day] ?? 0) > 0 {
                holidayDays.insert(day)
            } else {
                holidayNotWorkedDays.insert(day)
            }
        }

        var vacationDays = Set<Date>()
        var recuperationDays = Set<Date>()
        for leave in leaveDays where inRange(leave.date) {
            let day = calendar.startOfDay(for: leave.date)
            switch leave.kind {
            case .vacation: vacationDays.insert(day)
            case .recuperation: recuperationDays.insert(day)
            }
        }

        return PeriodDayCounts(
            holiday: holidayDays.count,
            vacation: vacationDays.count,
            recuperation: recuperationDays.count,
            sick: sickDays.count,
            holidayNotWorked: holidayNotWorkedDays.count
        )
    }
}
