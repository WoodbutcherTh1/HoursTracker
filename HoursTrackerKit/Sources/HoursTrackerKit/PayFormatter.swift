import Foundation

/// Currency-aware money formatting. Replaces hardcoded shekel formatting so the
/// display currency can be chosen in Settings.
public enum PayFormatter {
    public static let supportedCurrencyCodes = ["ILS", "USD", "EUR", "GBP"]

    private static var formatters: [String: NumberFormatter] = [:]
    private static let lock = NSLock()

    public static func string(_ amount: Double, currencyCode: String, locale: Locale? = nil) -> String {
        formatter(for: currencyCode, locale: locale).string(from: NSNumber(value: amount))
            ?? String(format: "%.2f", amount)
    }

    public static func symbol(for currencyCode: String) -> String {
        formatter(for: currencyCode, locale: nil).currencySymbol ?? currencyCode
    }

    private static func formatter(for code: String, locale: Locale?) -> NumberFormatter {
        let cacheKey = "\(code)|\(locale?.identifier ?? "current")"
        lock.lock()
        defer { lock.unlock() }
        if let cached = formatters[cacheKey] {
            return cached
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        if let locale {
            formatter.locale = locale
        }
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatters[cacheKey] = formatter
        return formatter
    }
}
