import Foundation

/// Snapshot of clock/pay state sent from the phone to the paired Watch app over
/// WatchConnectivity. Kept small and fully precomputed (no raw session list) so the
/// Watch app has zero pay-calculation logic of its own — it only renders numbers the
/// phone already produced with the real `OvertimeCalculator` (weekly OT caps, tax
/// estimate, etc.), not a simplified re-implementation living on the watch.
///
/// This file is compiled into both the app target and the watch app target (see
/// project.yml) — it must stay free of iOS-only or watchOS-only imports.
struct WatchSnapshot: Codable, Equatable {
    var isClockedIn: Bool
    var clockInTime: Date?
    var todayHours: Double
    var todayNetPay: Double
    var todayGrossPay: Double
    var weekHours: Double
    var weekNetPay: Double
    var weekGrossPay: Double
    var currencyCode: String
    var workplaceName: String
    var generatedAt: Date

    static let empty = WatchSnapshot(
        isClockedIn: false,
        clockInTime: nil,
        todayHours: 0,
        todayNetPay: 0,
        todayGrossPay: 0,
        weekHours: 0,
        weekNetPay: 0,
        weekGrossPay: 0,
        currencyCode: "ILS",
        workplaceName: "",
        generatedAt: .distantPast
    )
}

/// Actions the Watch app can request the phone perform.
enum WatchAction: String, Codable {
    case clockIn
    case clockOut
}

/// Shared (de)serialization for WatchConnectivity messages, which only accept
/// property-list-compatible dictionary values — `Data` qualifies, raw `Codable`
/// structs don't.
enum WatchMessageKey {
    static let snapshot = "watchSnapshot"
    static let action = "watchAction"
}

extension WatchSnapshot {
    func asMessage() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        return [WatchMessageKey.snapshot: data]
    }

    static func from(message: [String: Any]) -> WatchSnapshot? {
        guard let data = message[WatchMessageKey.snapshot] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    }
}
