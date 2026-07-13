import Foundation

struct WorkSession: Codable, Identifiable, Equatable {
    let id: UUID
    var date: Date
    var clockIn: Date
    var clockOut: Date?
    var isManualEntry: Bool
    var notes: String?
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        date: Date,
        clockIn: Date,
        clockOut: Date? = nil,
        isManualEntry: Bool = false,
        notes: String? = nil,
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.clockIn = clockIn
        self.clockOut = clockOut
        self.isManualEntry = isManualEntry
        self.notes = notes
        self.modifiedAt = modifiedAt
    }

    mutating func touch() {
        modifiedAt = Date()
    }

    var isOpen: Bool {
        clockOut == nil
    }

    var totalHours: Double {
        guard let clockOut else { return 0 }
        return max(0, clockOut.timeIntervalSince(clockIn) / 3600)
    }

    var elapsedSeconds: TimeInterval {
        let end = clockOut ?? Date()
        return max(0, end.timeIntervalSince(clockIn))
    }

    static func calendarDay(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    func isSameDay(as other: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(date, inSameDayAs: other)
    }
}
