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

    /// Resolve a String Catalog key in the requested in-app language: the requested
    /// language's `.lproj` bundle, then English, then whatever the app itself resolves.
    ///
    /// The order matters, and it is the reverse of what it used to be. This tried
    /// `String(localized:locale:)` first, on the assumption that `locale:` selects the
    /// language. It does not — that parameter only localizes *interpolated values*, and
    /// the string itself still comes back in whatever language the app is currently
    /// running in. Since that value is essentially never equal to the key, the early
    /// return fired on every single lookup and the correct per-language code below was
    /// unreachable. The in-app language override therefore only appeared to work when it
    /// happened to agree with the device language, and picking Hebrew on an English
    /// phone silently kept showing English.
    ///
    /// Xcode compiles `Localizable.xcstrings` into a `<lang>.lproj/Localizable.strings`
    /// inside the built app, so asking that bundle directly is what actually honors the
    /// override. `String(localized:)` is kept as a last resort for the case where those
    /// resources are somehow absent.
    static func localizedString(_ key: String, language: Language) -> String {
        if let value = stringFromLproj(key, code: language.localeIdentifier) {
            return value
        }

        // A key that hasn't been translated yet shows the development language rather
        // than a raw dotted identifier.
        if language != .english, let value = stringFromLproj(key, code: "en") {
            return value
        }

        let catalogValue = String(localized: String.LocalizationValue(key))
        if catalogValue != key {
            return catalogValue
        }
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    /// Looks `key` up in one specific `<code>.lproj` bundle, or `nil` when that bundle
    /// is absent or doesn't carry the key — `localizedString(forKey:value:table:)`
    /// echoes the key back on a miss when `value` is `nil`.
    private static func stringFromLproj(_ key: String, code: String) -> String? {
        guard let bundle = lprojBundle(for: code) else { return nil }
        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        return value == key ? nil : value
    }

    /// Cached, including misses: `tr(_:)` runs for practically every string in every
    /// view body, and resolving a bundle path hits the filesystem.
    private static func lprojBundle(for code: String) -> Bundle? {
        lprojCacheLock.lock()
        defer { lprojCacheLock.unlock() }

        if let cached = lprojCache[code] {
            return cached
        }

        // Hebrew ships as `he`, but Foundation still answers to the legacy `iw` in
        // places, so try both rather than silently losing an entire language.
        let candidates = code == "he" ? [code, "iw"] : [code]
        var resolved: Bundle?
        for candidate in candidates {
            if let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                resolved = bundle
                break
            }
        }
        lprojCache[code] = resolved
        return resolved
    }

    private static var lprojCache: [String: Bundle?] = [:]
    private static let lprojCacheLock = NSLock()

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
