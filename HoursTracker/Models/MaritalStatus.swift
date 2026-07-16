import Foundation

enum MaritalStatus: String, Codable, CaseIterable, Identifiable {
    case single
    case married

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .single: return AppLocale.tr("tax.marital.single")
        case .married: return AppLocale.tr("tax.marital.married")
        }
    }
}
