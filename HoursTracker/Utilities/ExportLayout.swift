import Foundation

/// Report-language layout helpers. Direction follows `ExportLanguage` / `ExportCopy.language`
/// only — never the device or in-app UI locale.
enum ExportLayout {
    static func isRTL(language: AppLocale.Language) -> Bool {
        switch language {
        case .hebrew, .arabic: return true
        case .english: return false
        }
    }

    /// Visual left→right order for columns/cards/chart panes.
    /// RTL reports place the logical first item at the trailing (right) edge.
    static func visualOrder<T>(_ items: [T], isRTL: Bool) -> [T] {
        isRTL ? Array(items.reversed()) : items
    }

    /// Right-to-left mark for plain-text lines that mix labels and Western digits.
    static let rightToLeftMark = "\u{200F}"

    static func directedLine(_ string: String, isRTL: Bool) -> String {
        isRTL ? rightToLeftMark + string : string
    }
}
