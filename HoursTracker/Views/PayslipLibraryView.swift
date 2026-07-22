import SwiftUI
import UIKit

/// Grid library of saved payslips — entry point from Export (ייצוא).
/// Relies on the parent `NavigationStack` (ExportView) for push navigation.
struct PayslipLibraryView: View {
    @StateObject private var viewModel: PayslipLibraryViewModel
    @ObservedObject var appViewModel: AppViewModel
    @State private var deleteError: String?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
        // Construct on the main actor inside init — default-arg evaluation is nonisolated.
        _viewModel = StateObject(wrappedValue: PayslipLibraryViewModel())
    }

    /// Test/injection seam — call only from `@MainActor` contexts.
    init(appViewModel: AppViewModel, viewModel: PayslipLibraryViewModel) {
        self.appViewModel = appViewModel
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            if viewModel.payslips.isEmpty {
                emptyState
            } else {
                gridContent
            }
        }
        .navigationTitle(L10n.payslipLibraryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.showUpload = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(L10n.payslipUploadAction)
            }
        }
        .navigationDestination(for: PayslipRecord.self) { record in
            PayslipDetailView(
                record: record,
                sourceURL: viewModel.sourceURL(for: record),
                onDelete: {
                    do {
                        try viewModel.delete(record)
                        appViewModel.showSuccessToast(L10n.payslipDeletedToast)
                    } catch {
                        deleteError = error.localizedDescription
                    }
                }
            )
        }
        .sheet(isPresented: $viewModel.showUpload, onDismiss: {
            viewModel.reload()
        }) {
            PayslipUploadReviewView(settings: appViewModel.settings) { _ in
                appViewModel.showSuccessToast(L10n.payslipSavedToast)
            }
        }
        .onAppear { viewModel.reload() }
        .alert(L10n.payslipDeleteFailed, isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button(L10n.editCancel, role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(viewModel.payslips) { record in
                    NavigationLink(value: record) {
                        PayslipGridCard(
                            record: record,
                            loadThumbnail: { completion in
                                viewModel.requestThumbnail(for: record, completion: completion)
                            }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            Text(L10n.payslipLibraryEmptyTitle)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(L10n.payslipLibraryEmptySubtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                viewModel.showUpload = true
            } label: {
                Label(L10n.payslipUploadAction, systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding(.top, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Grid card

private struct PayslipGridCard: View {
    let record: PayslipRecord
    let loadThumbnail: (@escaping (UIImage?) -> Void) -> Void

    @State private var thumbnail: UIImage?
    @State private var didRequest = false

    private let cornerRadius: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                thumbnailView
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }

                if needsReviewBadge {
                    Text(L10n.payslipNeedsReview)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.92), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(8)
                }
            }

            Text(periodLabel)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Text(netLabel)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear { requestThumbnailIfNeeded() }
    }

    private var needsReviewBadge: Bool {
        record.reviewState != .confirmed || record.extraction.needsManualReview
    }

    private var periodLabel: String {
        if let label = record.periodLabel, !label.isEmpty {
            return label
        }
        return PayslipDisplayFormatting.periodMonthLabel(record.effectivePeriodMonth)
    }

    private var netLabel: String {
        if let net = record.effectiveNetPay {
            return PayslipDisplayFormatting.money(net, currencyCode: record.userOverrides?.currencyCode ?? record.extraction.currencyCode)
        }
        return L10n.payslipNetUnavailable
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
                .accessibilityLabel(L10n.payslipPreview)
        } else {
            ZStack {
                Color(.tertiarySystemFill)
                ProgressView()
            }
            .accessibilityLabel(L10n.payslipPreview)
        }
    }

    private func requestThumbnailIfNeeded() {
        guard !didRequest else { return }
        didRequest = true
        if let cached = PayslipThumbnailCache.shared.cachedImage(for: record.id) {
            thumbnail = cached
            return
        }
        loadThumbnail { image in
            thumbnail = image
        }
    }
}

// MARK: - Shared formatting

enum PayslipDisplayFormatting {
    static func periodMonthLabel(_ date: Date) -> String {
        let formatter = AppLocale.makeDateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    static func money(_ amount: Decimal, currencyCode: String?) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode ?? "ILS"
        formatter.locale = AppLocale.resolvedLocale
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }

    static func optionalMoney(_ amount: Decimal?, currencyCode: String?) -> String {
        guard let amount else { return "—" }
        return money(amount, currencyCode: currencyCode)
    }

    static func optionalDouble(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f", value)
    }

    static func optionalDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return AppLocale.makeDateFormatter(dateStyle: .medium).string(from: date)
    }
}
