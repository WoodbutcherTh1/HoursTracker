import SwiftUI
import UIKit

/// Grid library of saved payslips — entry point from Export (ייצוא).
///
/// Relies on the parent `NavigationStack` (ExportView) for push navigation. Deliberately
/// does **not** declare its own `.navigationDestination(for: PayslipRecord.self)` here:
/// this view is itself pushed onto ExportView's stack (via `NavigationLink`), so a
/// destination declared on it — rather than on the stack's root — could end up
/// registered twice as you navigate in and out, which SwiftUI resolves by honoring only
/// the copy closest to the root. In practice that showed up as the first tap on a
/// payslip doing nothing until you pushed and popped once. The destination now lives on
/// `ExportView`'s root `Form`, which is why `viewModel` is injected rather than owned
/// here — `ExportView` needs the same instance to build `PayslipDetailView`.
struct PayslipLibraryView: View {
    @ObservedObject var viewModel: PayslipLibraryViewModel
    @ObservedObject var appViewModel: AppViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    init(appViewModel: AppViewModel, viewModel: PayslipLibraryViewModel) {
        self.appViewModel = appViewModel
        self.viewModel = viewModel
    }

    var body: some View {
        ZStack {
            HomeNeon.bg.ignoresSafeArea()

            if viewModel.payslips.isEmpty {
                emptyState
            } else {
                gridContent
            }
        }
        .navigationTitle(L10n.payslipLibraryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(HomeNeon.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.showUpload = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(HomeNeon.accent)
                }
                .accessibilityLabel(L10n.payslipUploadAction)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(PayslipSortOption.allCases) { option in
                        Button {
                            viewModel.sortOption = option
                        } label: {
                            if option == viewModel.sortOption {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundStyle(HomeNeon.accent)
                }
                .accessibilityLabel(L10n.payslipSortAccessibility)
            }
        }
        .sheet(isPresented: $viewModel.showUpload, onDismiss: {
            viewModel.reload()
        }) {
            PayslipUploadReviewView(settings: appViewModel.settings) { _ in
                appViewModel.showSuccessToast(L10n.payslipSavedToast)
            }
        }
        .onAppear { viewModel.reload() }
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
                    // Plain, not ScalePressButtonStyle: that style's own `.animation(value:)`
                    // fought with the NavigationStack's push transition — the detail view
                    // would silently not render until a second navigation event (e.g. going
                    // back) forced a redraw. NavigationLink content should stay unstyled.
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 52))
                .foregroundStyle(HomeNeon.accent)
                .symbolRenderingMode(.hierarchical)
                .shadow(color: HomeNeon.accent.opacity(0.35), radius: 16)

            Text(L10n.payslipLibraryEmptyTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(L10n.payslipLibraryEmptySubtitle)
                .font(.body)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                viewModel.showUpload = true
            } label: {
                Label(L10n.payslipUploadAction, systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeNeon.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(HomeNeon.accent, in: Capsule())
                    .shadow(color: HomeNeon.accent.opacity(0.35), radius: 12, y: 4)
            }
            .buttonStyle(ScalePressButtonStyle())
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
                            .strokeBorder(HomeNeon.accent.opacity(0.18), lineWidth: 1)
                    }

                if needsReviewBadge {
                    Text(L10n.payslipNeedsReview)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(HomeNeon.coral.opacity(0.92), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(8)
                }
            }

            Text(periodLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(netLabel)
                .font(.headline.monospacedDigit())
                .foregroundStyle(HomeNeon.accent)
                .lineLimit(1)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(HomeNeon.card)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(HomeNeon.accent.opacity(0.14), lineWidth: 1)
                )
        )
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
                HomeNeon.card
                ProgressView()
                    .tint(HomeNeon.accent)
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
