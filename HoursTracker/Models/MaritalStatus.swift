import Foundation

enum MaritalStatus: String, Codable, CaseIterable, Identifiable {
    case single
    case married

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .single: return String(localized: "tax.marital.single", defaultValue: "Single")
        case .married: return String(localized: "tax.marital.married", defaultValue: "Married")
        }
    }
}
