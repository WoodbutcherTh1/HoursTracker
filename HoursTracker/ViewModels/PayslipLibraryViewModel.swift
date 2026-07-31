import Foundation
import Combine
import UIKit

/// User-choosable ordering for the payslip grid — persisted so the choice sticks
/// between visits, same pattern as the Home screen's card layout.
enum PayslipSortOption: String, CaseIterable, Identifiable {
    case dateDescending
    case amountDescending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateDescending: return L10n.payslipSortByDate
        case .amountDescending: return L10n.payslipSortByAmount
        }
    }
}

@MainActor
final class PayslipLibraryViewModel: ObservableObject {
    @Published private(set) var payslips: [PayslipRecord] = []
    @Published var errorMessage: String?
    @Published var showUpload = false
    @Published var sortOption: PayslipSortOption {
        didSet {
            UserDefaults.standard.set(sortOption.rawValue, forKey: Self.sortStorageKey)
            payslips = Self.sorted(payslips, by: sortOption)
        }
    }

    private static let sortStorageKey = "payslipLibrarySortOption"

    private let store: PayslipStore
    private let thumbnailCache: PayslipThumbnailCache

    init(
        store: PayslipStore = .shared,
        thumbnailCache: PayslipThumbnailCache = .shared
    ) {
        self.store = store
        self.thumbnailCache = thumbnailCache
        if let raw = UserDefaults.standard.string(forKey: Self.sortStorageKey),
           let saved = PayslipSortOption(rawValue: raw) {
            sortOption = saved
        } else {
            sortOption = .dateDescending
        }
    }

    func reload() {
        do {
            let records = try store.listPayslips()
            payslips = Self.sorted(records, by: sortOption)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            payslips = []
        }
    }

    static func sorted(_ records: [PayslipRecord], by option: PayslipSortOption) -> [PayslipRecord] {
        switch option {
        case .dateDescending:
            return sortedByPeriodDescending(records)
        case .amountDescending:
            return records.sorted { lhs, rhs in
                let left = (lhs.effectiveNetPay ?? 0) as Decimal
                let right = (rhs.effectiveNetPay ?? 0) as Decimal
                if left != right {
                    return left > right
                }
                return lhs.effectivePeriodMonth > rhs.effectivePeriodMonth
            }
        }
    }

    nonisolated static func sortedByPeriodDescending(_ records: [PayslipRecord]) -> [PayslipRecord] {
        records.sorted { lhs, rhs in
            let left = lhs.effectivePeriodMonth
            let right = rhs.effectivePeriodMonth
            if left != right {
                return left > right
            }
            return lhs.uploadedAt > rhs.uploadedAt
        }
    }

    func delete(_ record: PayslipRecord) throws {
        try store.deletePayslip(id: record.id)
        // Store already clears the thumbnail cache; reload grid.
        reload()
    }

    func sourceURL(for record: PayslipRecord) -> URL {
        store.url(for: record)
    }

    func requestThumbnail(for record: PayslipRecord, completion: @escaping (UIImage?) -> Void) {
        if let cached = thumbnailCache.cachedImage(for: record.id) {
            completion(cached)
            return
        }
        thumbnailCache.thumbnail(
            for: record,
            sourceURL: store.url(for: record),
            completion: completion
        )
    }
}
