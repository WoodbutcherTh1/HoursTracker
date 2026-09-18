import SwiftUI

extension Color {
    /// `"RRGGBB"` (no `#`) — tolerant of a leading `#` too. Mirrors the phone's
    /// `Color(hex:)` in `HomeAccentTheme.swift`, reimplemented without `UIColor`
    /// since that file isn't compiled into the Watch target.
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
}
