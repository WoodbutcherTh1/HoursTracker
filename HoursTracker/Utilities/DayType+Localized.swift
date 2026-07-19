import Foundation
import HoursTrackerKit

extension DayType {
    var localizedName: String {
        switch self {
        case .regular: return L10n.dayTypeRegular
        case .restDay: return L10n.dayTypeRestDay
        case .holiday: return L10n.dayTypeHoliday
        }
    }
}
