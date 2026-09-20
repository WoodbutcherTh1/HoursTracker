import Foundation

/// One named job with its own pay rate — the first piece of multi-workplace support.
/// Not yet wired into `WorkSession`, clock-in, or Settings; this is storage-only so it
/// can land without touching any currently-working flow.
struct Workplace: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var hourlyRate: Double
    var currencyCode: String
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        hourlyRate: Double = 0,
        currencyCode: String = "ILS",
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.hourlyRate = hourlyRate
        self.currencyCode = currencyCode
        self.modifiedAt = modifiedAt
    }
}
