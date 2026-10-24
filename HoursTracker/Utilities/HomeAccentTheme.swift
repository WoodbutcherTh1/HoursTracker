import SwiftUI

extension Color {
    /// `"RRGGBB"` (no `#`) — tolerant of a leading `#` too.
    init(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") { sanitized.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// `"RRGGBB"`, no `#`. Round-trips with `init(hex:)` for persistence.
    var hexString: String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    /// Approximate darker variant for gradient depth. `HomeNeon`'s fixed colors each
    /// ship a hand-picked "Deep" shade; a user-chosen color derives one instead of
    /// requiring a second picker control.
    func darkened(by factor: Double = 0.55) -> Color {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return Color(red: r * factor, green: g * factor, blue: b * factor)
    }
}

extension Color {
    /// The user's chosen app accent. Use this instead of `Color.accentColor`, which is
    /// system blue whenever a view doesn't inherit the root `.tint` (sheets, recycled
    /// list rows, popovers) — that made buttons flip from green to blue.
    @MainActor static var appAccent: Color { HomeAccentTheme.shared.accent }
}

/// User-customizable accent color for the app: drives the tab bar tint, the
/// HoursTracker wordmark, and every neon-styled element across Home, Payslip
/// Library/Detail, and the Forgot Clock In / launch splash screens. Defaults to
/// the app's original green — nothing changes in appearance until the user opens
/// the picker and picks something else. The coral "active session" / warning
/// color stays fixed everywhere since it carries semantic meaning (currently
/// clocked in, destructive action), not just decoration.
@MainActor
final class HomeAccentTheme: ObservableObject {
    static let shared = HomeAccentTheme()

    private static let storageKey = "homeAccentColorHex"
    static let defaultHex = "26F273"

    @Published var accent: Color {
        didSet {
            UserDefaults.standard.set(accent.hexString, forKey: Self.storageKey)
            applyUIKitTint()
        }
    }

    /// UIKit-drawn parts of SwiftUI lists and sheets (row icons, chevrons, pickers) take
    /// their colour from the window's `tintColor`, which is system blue unless set —
    /// the "icon flips to blue" bug. Keep it on the chosen accent, on every window.
    func applyUIKitTint() {
        let color = UIColor(accent)
        UIView.appearance().tintColor = color
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows { window.tintColor = color }
        }
    }

    private init(defaults: UserDefaults = .standard) {
        let hex = defaults.string(forKey: Self.storageKey) ?? Self.defaultHex
        accent = Color(hex: hex)
        // `didSet` doesn't run inside init; the windows may not exist yet, so the app
        // re-applies this when it becomes active.
        UIView.appearance().tintColor = UIColor(accent)
    }

    func reset() {
        accent = Color(hex: Self.defaultHex)
    }

    /// True once a colour was ever saved — i.e. the picker has been used, even
    /// before `home.themeTipSeen` existed.
    static var hasSavedChoice: Bool {
        UserDefaults.standard.object(forKey: storageKey) != nil
    }

    /// Curated presets so most people never need the full picker.
    static let presets: [(name: String, hex: String)] = [
        ("Green", "26F273"),
        ("Mint", "35E0A8"),
        ("Cyan", "2ED6E6"),
        ("Blue", "3B9CFF"),
        ("Violet", "9C6BFF"),
        ("Pink", "FF5FA8"),
        ("Amber", "FFB238"),
        ("Red", "FF5A5F")
    ]
}
