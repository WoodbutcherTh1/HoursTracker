import Foundation

/// A holiday the worker added (or moved / renamed from the bundled calendar).
struct CustomHoliday: Codable, Equatable, Identifiable {
    var id = UUID()
    /// Start of the calendar day.
    var date: Date
    var name: String
    /// Pays the holiday rate. Off = shown on the calendar only (like Yom HaAtzmaut).
    var affectsPay = true

    init(id: UUID = UUID(), date: Date, name: String, affectsPay: Bool = true) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.name = name
        self.affectsPay = affectsPay
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = Calendar.current.startOfDay(for: try c.decode(Date.self, forKey: .date))
        name = try c.decode(String.self, forKey: .name)
        affectsPay = try c.decodeIfPresent(Bool.self, forKey: .affectsPay) ?? true
    }
}

/// Per-workplace edits on top of the bundled Israeli holiday calendar: bundled
/// days the worker removed, and days they added. Renaming or moving a bundled
/// holiday is "hide the original, add a custom one". Stored in `WorkplaceSettings`.
struct HolidayCustomization: Codable, Equatable {
    var custom: [CustomHoliday] = []
    /// Start-of-day dates of bundled holidays the worker removed.
    var hiddenDates: [Date] = []

    var isEmpty: Bool { custom.isEmpty && hiddenDates.isEmpty }

    init(custom: [CustomHoliday] = [], hiddenDates: [Date] = []) {
        self.custom = custom
        self.hiddenDates = hiddenDates
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A malformed entry must never make the whole settings unreadable.
        custom = (try? c.decodeIfPresent([CustomHoliday].self, forKey: .custom)) ?? []
        hiddenDates = (try? c.decodeIfPresent([Date].self, forKey: .hiddenDates)) ?? []
    }

    func isHidden(_ day: Date, calendar: Calendar = .current) -> Bool {
        hiddenDates.contains { calendar.isDate($0, inSameDayAs: day) }
    }

    func customHoliday(on day: Date, calendar: Calendar = .current) -> CustomHoliday? {
        custom.first { calendar.isDate($0.date, inSameDayAs: day) }
    }
}

/// A holiday on a given day after the worker's edits are applied — either from
/// the bundled calendar or one they added.
struct ResolvedHoliday: Equatable {
    let englishName: String
    let hebrewName: String
    let hebrewShortName: String
    let affectsPay: Bool
    let isCustom: Bool

    init(_ bundled: IsraeliHoliday) {
        englishName = bundled.englishName
        hebrewName = bundled.hebrewName
        hebrewShortName = bundled.hebrewShortName
        affectsPay = bundled.affectsPay
        isCustom = false
    }

    init(_ custom: CustomHoliday) {
        englishName = custom.name
        hebrewName = custom.name
        hebrewShortName = custom.name
        affectsPay = custom.affectsPay
        isCustom = true
    }
}

extension IsraeliHolidayCalendar {
    /// The holiday observed on `date` for a workplace: its own additions win, then
    /// the bundled calendar minus anything the worker removed.
    static func resolved(
        on date: Date,
        calendar: Calendar = .current,
        customization: HolidayCustomization
    ) -> ResolvedHoliday? {
        if let custom = customization.customHoliday(on: date, calendar: calendar) {
            return ResolvedHoliday(custom)
        }
        if customization.isHidden(date, calendar: calendar) { return nil }
        return holiday(on: date, calendar: calendar).map(ResolvedHoliday.init)
    }

    static func isHoliday(_ date: Date, calendar: Calendar = .current, customization: HolidayCustomization) -> Bool {
        resolved(on: date, calendar: calendar, customization: customization)?.affectsPay == true
    }

    /// Bundled holidays in a Gregorian year, in date order — the list the editor shows.
    static func bundledHolidays(inYear year: Int, calendar: Calendar = .current) -> [(date: Date, holiday: IsraeliHoliday)] {
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) else { return [] }
        var result: [(Date, IsraeliHoliday)] = []
        var cursor = start
        while cursor <= end {
            if let holiday = holiday(on: cursor, calendar: calendar) { result.append((cursor, holiday)) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }
}
