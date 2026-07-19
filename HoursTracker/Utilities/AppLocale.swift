import Foundation

enum AppLocale {
    enum Language: Equatable {
        case arabic
        case hebrew
        case english

        /// Display name in the current app UI language (for “phone language is X”).
        var localizedDisplayName: String {
            switch self {
            case .arabic: return L10n.languageNameArabic
            case .hebrew: return L10n.languageNameHebrew
            case .english: return L10n.languageNameEnglish
            }
        }

        var localeIdentifier: String {
            switch self {
            case .arabic: return "ar"
            case .hebrew: return "he"
            case .english: return "en"
            }
        }
    }

    /// Locale used for formatters / SwiftUI environment under the in-app override.
    static var resolvedLocale: Locale {
        Locale(identifier: current.localeIdentifier)
    }

    /// Gregorian calendar for payroll / week math. Never follows an Islamic
    /// calendar (`ar_SA`) and keeps Sunday-first weeks (Israeli work week)
    /// even when the UI language is Arabic.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = resolvedLocale
        calendar.firstWeekday = 1 // Sunday
        return calendar
    }

    /// Date/time formatter locked to the in-app language (never device locale).
    static func makeDateFormatter(
        dateStyle: DateFormatter.Style = .none,
        timeStyle: DateFormatter.Style = .none,
        template: String? = nil
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = resolvedLocale
        formatter.calendar = calendar
        if let template {
            formatter.setLocalizedDateFormatFromTemplate(template)
        } else {
            formatter.dateStyle = dateStyle
            formatter.timeStyle = timeStyle
        }
        return formatter
    }

    /// Catalog lookup in the active in-app language (works outside SwiftUI too).
    static func tr(_ key: String) -> String {
        localizedString(key, language: current)
    }

    /// Resolve a key from the matching `*.lproj` (not `String(localized:locale:)`,
    /// which often keeps the launch language and only flips layout direction).
    static func localizedString(_ key: String, language: Language) -> String {
        let code = language.localeIdentifier
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            let value = bundle.localizedString(forKey: key, value: nil, table: nil)
            if value != key { return value }
        }
        // Fall back through English, then the development bundle.
        if language != .english,
           let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
           let bundle = Bundle(path: path) {
            let value = bundle.localizedString(forKey: key, value: nil, table: nil)
            if value != key { return value }
        }
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    /// Prefer the in-app language override; fall back to the device preferred languages.
    static var current: Language {
        resolve(
            preference: AppLanguageOption.load(),
            preferredLanguages: Locale.preferredLanguages
        )
    }

    /// Testable resolution: override wins; `.system` uses `preferredLanguages`.
    static func resolve(
        preference: AppLanguageOption,
        preferredLanguages: [String]
    ) -> Language {
        switch preference {
        case .english: return .english
        case .hebrew: return .hebrew
        case .arabic: return .arabic
        case .system:
            return language(fromPreferredLanguages: preferredLanguages)
        }
    }

    static func language(fromPreferredLanguages preferredLanguages: [String]) -> Language {
        let preferred = preferredLanguages.first?.lowercased() ?? "en"
        if preferred.hasPrefix("ar") { return .arabic }
        if preferred.hasPrefix("he") || preferred.hasPrefix("iw") { return .hebrew }
        return .english
    }

    static func clockInPrompt() -> String {
        switch current {
        case .arabic: return "عملت دخول؟"
        case .hebrew: return "עשית כניסה?"
        case .english: return "Did you clock in?"
        }
    }

    static func clockOutReminder() -> String {
        switch current {
        case .arabic: return "عملت بصمة خروج؟"
        case .hebrew: return "החתמת יציאה?"
        case .english: return "Did you clock out?"
        }
    }

    static func forgotClockOut() -> String {
        switch current {
        case .arabic: return "لسا داخل؟ ما نسيت تعمل خروج؟"
        case .hebrew: return "עדיין בעבודה? לא שכחת להחתים יציאה?"
        case .english: return "Still at work? Did you forget to clock out?"
        }
    }

    static func manualEntryLabel() -> String {
        switch current {
        case .arabic: return "يدوي"
        case .hebrew: return "ידני"
        case .english: return "Manual"
        }
    }

    static func automaticEntryLabel() -> String {
        switch current {
        case .arabic: return "أوتوماتيكي"
        case .hebrew: return "אוטומטי"
        case .english: return "Automatic"
        }
    }
}
