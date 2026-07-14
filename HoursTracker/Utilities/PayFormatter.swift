import Foundation

/// Currency-aware money formatting. Replaces hardcoded shekel formatting so the
/// display currency can be chosen in Settings.
enum PayFormatter {
    static let supportedCurrencyCodes = ["ILS", "USD", "EUR", "GBP"]

    private static var formatters: [String: NumberFormatter] = [:]
    private static let lock = NSLock()

    static func string(_ amount: Double, currencyCode: String) -> String {
        formatter(for: currencyCode).string(from: NSNumber(value: amount))
            ?? String(format: "%.2f %@", amount, currencyCode)
    }

    static func symbol(for currencyCode: String) -> String {
        formatter(for: currencyCode).currencySymbol ?? currencyCode
    }

    private static func formatter(for code: String) -> NumberFormatter {
        lock.lock()
        defer { lock.unlock() }
        if let cached = formatters[code] {
            return cached
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatters[code] = formatter
        return formatter
    }
}
