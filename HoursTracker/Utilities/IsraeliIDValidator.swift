import Foundation

/// Israeli teudat zehut checksum (Luhn-like). Used for soft warnings only — never blocks save.
enum IsraeliIDValidator {
    /// Empty / non-digit-only input is treated as “no warning”.
    static func shouldWarn(for raw: String) -> Bool {
        let digits = raw.filter(\.isNumber)
        guard !digits.isEmpty else { return false }
        return !isChecksumValid(digits)
    }

    static func isChecksumValid(_ digits: String) -> Bool {
        let padded = String(repeating: "0", count: max(0, 9 - digits.count)) + digits
        guard padded.count == 9, padded.allSatisfy(\.isNumber) else { return false }

        var sum = 0
        for (index, char) in padded.enumerated() {
            guard let digit = char.wholeNumberValue else { return false }
            var value = digit * (index % 2 == 0 ? 1 : 2)
            if value > 9 { value -= 9 }
            sum += value
        }
        return sum % 10 == 0
    }
}
