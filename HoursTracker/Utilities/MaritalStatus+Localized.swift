import Foundation
import HoursTrackerKit

extension MaritalStatus {
    var displayName: String {
        switch self {
        case .single: return AppLocale.tr("tax.marital.single")
        case .married: return AppLocale.tr("tax.marital.married")
        }
    }
}
