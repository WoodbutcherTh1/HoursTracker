import SwiftUI

/// Every metric the Home screen's stat cards can show. Only 3 are visible at once
/// (`HomeStatsLayout.order`) — the rest are available to swap in via the "Cards"
/// picker in `HomeThemePickerSheet`.
enum HomeStatMetric: String, CaseIterable, Codable, Identifiable {
    case month
    case week
    case today
    case todayPay
    case weekPay
    case monthPay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: return L10n.homeStatMonth
        case .week: return L10n.homeStatWeek
        case .today: return L10n.homeStatToday
        case .todayPay: return L10n.homeStatTodayPay
        case .weekPay: return L10n.homeStatWeekPay
        case .monthPay: return L10n.homeStatMonthPay
        }
    }
}

/// User-customizable Home screen stat cards: which 3 metrics show, and in what
/// order. Persisted as raw string values so the app doesn't crash on a future case
/// rename — an unrecognized or incomplete saved order just falls back to default.
@MainActor
final class HomeStatsLayout: ObservableObject {
    static let shared = HomeStatsLayout()

    static let defaultOrder: [HomeStatMetric] = [.month, .week, .today]
    private static let storageKey = "homeStatsOrder"
    private static let slotCount = 3

    @Published var order: [HomeStatMetric] {
        didSet {
            UserDefaults.standard.set(order.map(\.rawValue), forKey: Self.storageKey)
        }
    }

    private init(defaults: UserDefaults = .standard) {
        if let saved = defaults.array(forKey: Self.storageKey) as? [String] {
            let metrics = saved.compactMap(HomeStatMetric.init(rawValue:))
            if metrics.count == Self.slotCount && Set(metrics).count == Self.slotCount {
                order = metrics
            } else {
                order = Self.defaultOrder
            }
        } else {
            order = Self.defaultOrder
        }
    }

    /// Swaps `dragged` into `target`'s position — a simple two-item swap reads more
    /// predictably than a full array-move for a 3-card row.
    func move(_ dragged: HomeStatMetric, onto target: HomeStatMetric) {
        guard dragged != target,
              let from = order.firstIndex(of: dragged),
              let to = order.firstIndex(of: target) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            order.swapAt(from, to)
        }
    }

    /// Assigns `metric` to the card at `index`. If `metric` is already showing in
    /// another slot, the two slots swap so no metric is ever shown twice.
    func setMetric(_ metric: HomeStatMetric, at index: Int) {
        guard order.indices.contains(index) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if let existingIndex = order.firstIndex(of: metric), existingIndex != index {
                order.swapAt(existingIndex, index)
            } else {
                order[index] = metric
            }
        }
    }

    func reset() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            order = Self.defaultOrder
        }
    }
}
