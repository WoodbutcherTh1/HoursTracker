import Foundation

struct WorkSession: Codable, Identifiable, Equatable {
    let id: UUID
    var date: Date
    var clockIn: Date
    var clockOut: Date?
    var isManualEntry: Bool
    /// True when imported via the timesheet scanner / OCR flow.
    var isAIImported: Bool
    var notes: String?
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        date: Date,
        clockIn: Date,
        clockOut: Date? = nil,
        isManualEntry: Bool = false,
        isAIImported: Bool = false,
        notes: String? = nil,
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.clockIn = clockIn
        self.clockOut = clockOut
        self.isManualEntry = isManualEntry
        self.isAIImported = isAIImported
        self.notes = notes
        self.modifiedAt = modifiedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, date, clockIn, clockOut, isManualEntry, isAIImported, notes, modifiedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        clockIn = try c.decode(Date.self, forKey: .clockIn)
        clockOut = try c.decodeIfPresent(Date.self, forKey: .clockOut)
        isManualEntry = try c.decode(Bool.self, forKey: .isManualEntry)
        isAIImported = try c.decodeIfPresent(Bool.self, forKey: .isAIImported) ?? false
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
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

    static func calendarDay(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    func isSameDay(as other: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(date, inSameDayAs: other)
    }
}
