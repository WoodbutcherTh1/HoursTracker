import Foundation

/// Language used for the exported report body (independent of the app UI language).
enum ExportLanguage: CaseIterable, Identifiable, Equatable {
    /// Resolve to the phone's preferred language (Arabic / Hebrew / English / Russian).
    case phone
    case english
    case hebrew
    case arabic
    case russian

    var id: Self { self }

    /// Locale used when looking up String Catalog keys for the report.
    var resolvedLocale: Locale {
        switch self {
        case .phone:
            switch AppLocale.current {
            case .arabic: return Locale(identifier: "ar")
            case .hebrew: return Locale(identifier: "he")
            case .english: return Locale(identifier: "en")
            case .russian: return Locale(identifier: "ru")
            }
        case .english:
            return Locale(identifier: "en")
        case .hebrew:
            return Locale(identifier: "he")
        case .arabic:
            return Locale(identifier: "ar")
        case .russian:
            return Locale(identifier: "ru")
        }
    }

    /// Resolved language bucket after expanding `.phone`.
    var resolvedLanguage: AppLocale.Language {
        switch self {
        case .phone: return AppLocale.current
        case .english: return .english
        case .hebrew: return .hebrew
        case .arabic: return .arabic
        case .russian: return .russian
        }
    }
}
