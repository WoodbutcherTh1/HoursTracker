import Foundation

enum AppLocale {
    enum Language: Equatable {
        case arabic
        case hebrew
        case english
        case russian

        /// Display name in the current app UI language (for “phone language is X”).
        var localizedDisplayName: String {
            switch self {
            case .arabic: return L10n.languageNameArabic
            case .hebrew: return L10n.languageNameHebrew
            case .english: return L10n.languageNameEnglish
            case .russian: return L10n.languageNameRussian
            }
        }

        var localeIdentifier: String {
            switch self {
            case .arabic: return "ar"
            case .hebrew: return "he"
            case .english: return "en"
            case .russian: return "ru"
            }
        }
    }

    /// Locale used for formatters / SwiftUI environment under the in-app override.
    static var resolvedLocale: Locale {
        Locale(identifier: current.localeIdentifier)
    }

    /// Date/time formatter locked to the in-app language (never device locale).
    static func makeDateFormatter(
        dateStyle: DateFormatter.Style = .none,
        timeStyle: DateFormatter.Style = .none,
        template: String? = nil
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = resolvedLocale
        formatter.calendar = Calendar(identifier: .gregorian)
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

    /// Resolve a String Catalog / lproj key for the requested in-app language.
    ///
    /// The per-language `.lproj` lookup runs FIRST: `String(localized:locale:)`
    /// only honors the locale for languages the process was actually launched
    /// with, so under an in-app override (or in a test host running en-only)
    /// it silently resolves every language to the development language and
    /// returns English. The compiled `en/he/ar/ru.lproj` bundles are always
    /// present in the app and always honor the requested language.
    static func localizedString(_ key: String, language: Language) -> String {
        let code = language.localeIdentifier

        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            let value = bundle.localizedString(forKey: key, value: nil, table: nil)
            if value != key { return value }
        }

        // String Catalog path — prefer explicit locale so in-app overrides work.
        let catalogValue = String(localized: String.LocalizationValue(key), locale: Locale(identifier: code))
        if catalogValue != key {
            return catalogValue
        }

        // Fall back through English catalog + lproj, then the development bundle.
        if language != .english {
            if let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
               let bundle = Bundle(path: path) {
                let value = bundle.localizedString(forKey: key, value: nil, table: nil)
                if value != key { return value }
            }

            let enCatalog = String(localized: String.LocalizationValue(key), locale: Locale(identifier: "en"))
            if enCatalog != key { return enCatalog }
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
        case .russian: return .russian
        case .system:
            return language(fromPreferredLanguages: preferredLanguages)
        }
    }

    static func language(fromPreferredLanguages preferredLanguages: [String]) -> Language {
        let preferred = preferredLanguages.first?.lowercased() ?? "en"
        if preferred.hasPrefix("ar") { return .arabic }
        if preferred.hasPrefix("he") || preferred.hasPrefix("iw") { return .hebrew }
        if preferred.hasPrefix("ru") { return .russian }
        return .english
    }

    static func clockInPrompt() -> String {
        switch current {
        case .arabic: return "عملت دخول؟"
        case .hebrew: return "עשית כניסה?"
        case .english: return "Did you clock in?"
        case .russian: return "Начали смену?"
        }
    }

    static func clockOutReminder() -> String {
        switch current {
        case .arabic: return "عملت بصمة خروج؟"
        case .hebrew: return "החתמת יציאה?"
        case .english: return "Did you clock out?"
        case .russian: return "Закончили смену?"
        }
    }

    static func forgotClockOut() -> String {
        switch current {
        case .arabic: return "لسا داخل؟ ما نسيت تعمل خروج؟"
        case .hebrew: return "עדיין בעבודה? לא שכחת להחתים יציאה?"
        case .english: return "Still at work? Did you forget to clock out?"
        case .russian: return "Всё ещё на работе? Не забыли закончить смену?"
        }
    }

    static func shiftStartsSoon(minutes: Int) -> String {
        switch current {
        case .arabic: return "ورديتك بتبلش بعد \(minutes) دقائق — لا تنسى تعمل دخول"
        case .hebrew: return "המשמרת מתחילה בעוד \(minutes) דקות — לא לשכוח להחתים כניסה"
        case .english: return "Your shift starts in \(minutes) minutes — don't forget to clock in"
        case .russian: return "Смена начнётся через \(minutes) мин. — не забудьте начать смену"
        }
    }

    static func shiftEndsSoon(minutes: Int) -> String {
        switch current {
        case .arabic: return "ورديتك بتخلص بعد \(minutes) دقائق — لا تنسى تعمل خروج"
        case .hebrew: return "המשמרת מסתיימת בעוד \(minutes) דקות — לא לשכוח להחתים יציאה"
        case .english: return "Your shift ends in \(minutes) minutes — don't forget to clock out"
        case .russian: return "Смена закончится через \(minutes) мин. — не забудьте закончить смену"
        }
    }

    static func breakEndingSoon(minutes: Int) -> String {
        switch current {
        case .arabic: return "الاستراحة بتخلص بعد \(minutes) دقائق"
        case .hebrew: return "ההפסקה מסתיימת בעוד \(minutes) דקות"
        case .english: return "Your break ends in \(minutes) minutes"
        case .russian: return "Перерыв закончится через \(minutes) мин."
        }
    }

    static func breakOver() -> String {
        switch current {
        case .arabic: return "خلصت الاستراحة — يلا نرجع للشغل"
        case .hebrew: return "ההפסקה נגמרה — חוזרים לעבודה"
        case .english: return "Your break is over — back to work"
        case .russian: return "Перерыв окончен — пора за работу"
        }
    }

    static func geofenceExitPrompt() -> String {
        switch current {
        case .arabic: return " طلعت من الشغل؟ لا تنسى تعمل خروج!"
        case .hebrew: return "יצאת מהעבודה? אל תשכח להחתים יציאה!"
        case .english: return "Leaving the workplace? Remember to clock out!"
        case .russian: return "Уходите с работы? Не забудьте закончить смену!"
        }
    }

    static func manualEntryLabel() -> String {
        switch current {
        case .arabic: return "يدوي"
        case .hebrew: return "ידני"
        case .english: return "Manual"
        case .russian: return "Вручную"
        }
    }

    static func automaticEntryLabel() -> String {
        switch current {
        case .arabic: return "أوتوماتيكي"
        case .hebrew: return "אוטומטי"
        case .english: return "Automatic"
        case .russian: return "Автоматически"
        }
    }
}
