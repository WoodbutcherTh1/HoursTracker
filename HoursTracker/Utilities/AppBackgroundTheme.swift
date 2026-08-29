import SwiftUI

/// The one dark background color the whole app paints on, and the only place it is
/// defined. Home, History, Export, Settings, the payslip library and detail screens,
/// the guide, the theme picker, the lock screen and the launch splash all read this
/// token, so changing it in the picker changes every screen at once rather than only
/// the chrome behind the tab bar.
///
/// Same shape as `HomeAccentTheme`: a `@Published` color mirrored into `UserDefaults`
/// as hex, a curated preset list, and a `reset()` back to the shipped default. The
/// default is the exact color `HomeNeon.bg` has always been, so nothing changes in
/// appearance until someone picks another one.
///
/// Every preset is deliberately darker than `HomeNeon.card` in all three channels, so
/// cards, sheets, and rows keep reading as lifted *above* the background whichever one
/// is chosen — including pure-black Onyx.
@MainActor
final class AppBackgroundTheme: ObservableObject {
    static let shared = AppBackgroundTheme()

    private static let storageKey = "appBackgroundColorHex"
    /// `HomeNeon.bg` — Color(red: 0.04, green: 0.05, blue: 0.06).
    static let defaultHex = "0A0D0F"

    @Published var background: Color {
        didSet {
            UserDefaults.standard.set(background.hexString, forKey: Self.storageKey)
        }
    }

    private init(defaults: UserDefaults = .standard) {
        let hex = defaults.string(forKey: Self.storageKey) ?? Self.defaultHex
        background = Color(hex: hex)
    }

    func reset() {
        background = Color(hex: Self.defaultHex)
    }

    /// Plain-language names rather than evocative ones: this list is read while choosing,
    /// and "Midnight" tells you what you are about to get in a way "Raven" does not.
    static let presets: [(name: String, hex: String)] = [
        ("Midnight", "0A0D0F"),
        ("Charcoal", "121618"),
        ("Graphite", "131313"),
        ("Slate", "0D141C"),
        ("Onyx", "000000")
    ]

    /// Localized preset name — falls back to the English name for anything unrecognized
    /// (e.g. a hex the user picked by hand).
    static func localizedPresetName(_ name: String) -> String {
        switch name {
        case "Midnight": return L10n.homeBackgroundMidnight
        case "Charcoal": return L10n.homeBackgroundCharcoal
        case "Graphite": return L10n.homeBackgroundGraphite
        case "Slate": return L10n.homeBackgroundSlate
        case "Onyx": return L10n.homeBackgroundOnyx
        default: return name
        }
    }
}
