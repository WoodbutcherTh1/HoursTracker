import Foundation
import SwiftUI

/// In-app language choice. `system` follows the device; other cases force that language.
enum AppLanguageOption: String, CaseIterable, Identifiable, Equatable {
    case system
    case english
    case hebrew
    case arabic

    var id: String { rawValue }

    static let storageKey = "appLanguagePreference"
    static let appleLanguagesKey = "AppleLanguages"

    /// Label shown in the picker — fixed-language options stay in their own script
    /// so users can always find their way back. "System" is localized.
    var pickerLabel: String {
        switch self {
        case .system: return L10n.settingsLanguageSystem
        case .english: return "English"
        case .hebrew: return "עברית"
        case .arabic: return "العربية"
        }
    }

    /// BCP-47 code written to `AppleLanguages`, or `nil` for system default.
    var languageCode: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .hebrew: return "he"
        case .arabic: return "ar"
        }
    }

    var locale: Locale {
        switch self {
        case .system:
            return Locale(identifier: AppLocale.language(
                fromPreferredLanguages: Locale.preferredLanguages
            ).localeIdentifier)
        case .english:
            return Locale(identifier: "en")
        case .hebrew:
            return Locale(identifier: "he")
        case .arabic:
            return Locale(identifier: "ar")
        }
    }

    var layoutDirection: LayoutDirection {
        switch AppLocale.resolve(preference: self, preferredLanguages: Locale.preferredLanguages) {
        case .hebrew, .arabic: return .rightToLeft
        case .english: return .leftToRight
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> AppLanguageOption {
        guard let raw = defaults.string(forKey: storageKey),
              let value = AppLanguageOption(rawValue: raw)
        else {
            return .system
        }
        return value
    }
}

/// Persists the in-app language override (UserDefaults / CA92.1) and applies
/// `AppleLanguages` so Bundle / notification resolution stays consistent.
@MainActor
final class AppLanguageController: ObservableObject {
    static let shared = AppLanguageController()

    @Published var preference: AppLanguageOption {
        didSet {
            guard oldValue != preference else { return }
            persistAndApply()
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loaded = AppLanguageOption.load(from: defaults)
        preference = loaded
        applyAppleLanguages(for: loaded)
    }

    var locale: Locale { preference.locale }
    var layoutDirection: LayoutDirection { preference.layoutDirection }

    private func persistAndApply() {
        defaults.set(preference.rawValue, forKey: AppLanguageOption.storageKey)
        applyAppleLanguages(for: preference)
    }

    private func applyAppleLanguages(for option: AppLanguageOption) {
        if let code = option.languageCode {
            defaults.set([code], forKey: AppLanguageOption.appleLanguagesKey)
        } else {
            defaults.removeObject(forKey: AppLanguageOption.appleLanguagesKey)
        }
    }
}
