import Foundation
import Combine
import UIKit

@MainActor
final class PayslipLibraryViewModel: ObservableObject {
    @Published private(set) var payslips: [PayslipRecord] = []
    @Published var errorMessage: String?
    @Published var showUpload = false

    private let store: PayslipStore
    private let thumbnailCache: PayslipThumbnailCache

    init(
        store: PayslipStore = .shared,
        thumbnailCache: PayslipThumbnailCache = .shared
    ) {
        self.store = store
        self.thumbnailCache = thumbnailCache
    }

    func reload() {
        do {
            let records = try store.listPayslips()
            payslips = Self.sortedByPeriodDescending(records)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            payslips = []
        }
    }

    static func sortedByPeriodDescending(_ records: [PayslipRecord]) -> [PayslipRecord] {
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
