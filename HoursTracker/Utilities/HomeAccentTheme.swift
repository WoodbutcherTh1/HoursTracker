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
        }
    }

    private init(defaults: UserDefaults = .standard) {
        let hex = defaults.string(forKey: Self.storageKey) ?? Self.defaultHex
        accent = Color(hex: hex)
    }

    func reset() {
        accent = Color(hex: Self.defaultHex)
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
