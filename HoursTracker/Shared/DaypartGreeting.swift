import Foundation

/// Time-of-day greeting that flips automatically (morning → afternoon → evening → night).
///
/// Shared between the phone (Home) and the Watch app (`WatchHomeView`) so the two
/// surfaces never drift again — the Watch previously re-implemented the hour bands
/// inline with a different evening cutoff (17–22 vs the phone's 17–21), which is
/// exactly the kind of silent divergence this extraction prevents. Both targets
/// compile this file (see project.yml), so it must stay free of UIKit/SwiftUI.
///
/// Localization goes through `L10n` → `AppLocale.tr`, which resolves the in-app
/// language from `AppLanguageController`/`AppleLanguages` — on the Watch that is
/// whatever the phone pushed via the `setLanguage` request, so greetings follow
/// the user's chosen app language on both devices.
enum DaypartGreeting: Equatable {
    case morning
    case afternoon
    case evening
    case night

    static func current(at date: Date = Date(), calendar: Calendar = .current) -> DaypartGreeting {
        let hour = calendar.component(.hour, from: date)
        // Morning 05:00–11:59 · afternoon 12:00–17:59 · evening 18:00–22:59 ·
        // night 23:00–04:59. Pinned at every edge by DaypartGreetingTests.
        switch hour {
        case 5..<12: return .morning
        case 12..<18: return .afternoon
        case 18..<23: return .evening
        default: return .night
        }
    }

    var title: String {
        switch self {
        case .morning: return L10n.homeGreetingMorning
        case .afternoon: return L10n.homeGreetingAfternoon
        // "Good night" reads as a goodbye to someone starting or ending a night
        // shift, so the night band greets like the evening.
        case .evening, .night: return L10n.homeGreetingEvening
        }
    }

    /// Personalized greeting using the first token of `fullName`.
    /// Empty / whitespace-only names keep the plain `title` unchanged.
    func title(withName fullName: String?) -> String {
        guard let first = Self.firstName(from: fullName) else { return title }
        // Isolate the name so a Latin first name doesn't scramble RTL Hebrew/Arabic.
        let isolated = "\u{2068}\(first)\u{2069}"
        switch self {
        case .morning: return L10n.homeGreetingMorningName(isolated)
        case .afternoon: return L10n.homeGreetingAfternoonName(isolated)
        case .evening, .night: return L10n.homeGreetingEveningName(isolated)
        }
    }

    /// First whitespace-separated token, or `nil` when the name is blank.
    static func firstName(from fullName: String?) -> String? {
        let trimmed = (fullName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let token = trimmed.split(whereSeparator: \.isWhitespace).first else { return nil }
        let name = String(token)
        return name.isEmpty ? nil : name
    }
}
