import SwiftUI
import UIKit

/// Grid library of saved payslips — the root of its own "Payslips" tab (`PayslipsTabView`).
///
/// Relies on the parent `NavigationStack` for push navigation and deliberately does
/// **not** declare its own `.navigationDestination(for: PayslipRecord.self)`: that
/// destination is registered once at `PayslipsTabView`'s stack root. A destination
/// declared here could end up registered twice as you navigate in and out, which
/// SwiftUI resolves by honoring only the copy closest to the root — seen before as a
/// tap silently pushing the detail view without repainting. That's why `viewModel` is
/// injected rather than owned here: the parent needs the same instance to build
/// `PayslipDetailView`.
struct PayslipLibraryView: View {
    @ObservedObject var viewModel: PayslipLibraryViewModel
    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject private var theme = HomeAccentTheme.shared
    @ObservedObject private var appBackground = AppBackgroundTheme.shared

    /// Set by a long-press on a grid card — deletes directly from the grid without
    /// requiring a trip into `PayslipDetailView` first.
    @State private var pendingDeleteRecord: PayslipRecord?
    @State private var deleteError: String?

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
            appBackground.background.ignoresSafeArea()

            if viewModel.payslips.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    PayslipDashboardHeader(
                        totalNet: dashboardTotalNet,
                        totalTaxes: dashboardTotalTaxes,
                        count: viewModel.payslips.count,
                        currencyCode: dashboardCurrencyCode
                    )
                    gridContent
                }
            }
        }
        .navigationTitle(L10n.payslipLibraryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(appBackground.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.showUpload = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(theme.accent)
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
                        .foregroundStyle(theme.accent)
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
        .confirmationDialog(
            L10n.payslipDeleteConfirmTitle,
            isPresented: Binding(
                get: { pendingDeleteRecord != nil },
                set: { if !$0 { pendingDeleteRecord = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.payslipDelete, role: .destructive) {
                if let record = pendingDeleteRecord {
                    deleteFromGrid(record)
                }
            }
            Button(L10n.editCancel, role: .cancel) { pendingDeleteRecord = nil }
        } message: {
            Text(L10n.payslipDeleteConfirmMessage)
        }
        .alert(L10n.payslipDeleteFailed, isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button(L10n.editCancel, role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }

    /// Across every saved payslip — net pay and deductions add in their own
    /// currency's units; mixed-currency libraries are rare enough that showing
    /// everything under the first record's (or the active workplace's) currency
    /// symbol is the right tradeoff over a more elaborate multi-currency total.
    private var dashboardTotalNet: Decimal {
        viewModel.payslips.reduce(Decimal(0)) { $0 + ($1.effectiveNetPay ?? 0) }
    }

    private var dashboardTotalTaxes: Decimal {
        viewModel.payslips.reduce(Decimal(0)) { $0 + ($1.effectiveDeductionsTotal ?? 0) }
    }

    private var dashboardCurrencyCode: String {
        viewModel.payslips.first?.userOverrides?.currencyCode
            ?? viewModel.payslips.first?.extraction.currencyCode
            ?? appViewModel.activeSettings.currencyCode
    }

    private func deleteFromGrid(_ record: PayslipRecord) {
        pendingDeleteRecord = nil
        do {
            try viewModel.delete(record)
            appViewModel.showSuccessToast(L10n.payslipDeletedToast)
        } catch {
            deleteError = error.localizedDescription
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(viewModel.payslips) { record in
                    NavigationLink(value: record) {
                        PayslipGridCard(
                            record: record,
                            accent: theme.accent,
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
                    // `.highPriorityGesture` (not `.simultaneousGesture`): a plain Button/
                    // NavigationLink counts ANY press-then-release-inside-bounds as a tap
                    // regardless of how long the hold was, so a simultaneous long-press
                    // gesture would fire *and then* the tap would still navigate on release
                    // — showing the delete confirmation and pushing the detail view at
                    // once. Giving the long press priority means once it recognizes (at
                    // 0.25s) it claims the touch, so the tap never also fires; releasing
                    // before 0.25s lets the claim fail and the tap through normally.
                    .highPriorityGesture(
                        LongPressGesture(minimumDuration: 0.25)
                            .onEnded { _ in
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                pendingDeleteRecord = record
                            }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollContentBackground(.hidden)
    }

    /// Explicitly Cyan→Green here (not the personalized accent) — the brief
    /// calls for this exact glow on the empty state specifically, same brand
    /// pairing as the Export button and the Account Sync button.
    private static let emptyStateCyan = Color(hex: "00E5FF")
    private static let emptyStateGreen = Color(hex: "26F273")

    private var emptyState: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Self.emptyStateCyan.opacity(0.22), Self.emptyStateGreen.opacity(0.22)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 128, height: 128)
                    .blur(radius: 18)

                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 52))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Self.emptyStateCyan, Self.emptyStateGreen],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolRenderingMode(.hierarchical)
                    .shadow(color: Self.emptyStateCyan.opacity(0.45), radius: 16)
            }

            Text(L10n.payslipLibraryEmptyTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(L10n.payslipLibraryEmptyMotivation)
                .font(.body)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                viewModel.showUpload = true
            } label: {
                Label(L10n.payslipUploadAction, systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Self.emptyStateCyan, Self.emptyStateGreen],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .shadow(color: Self.emptyStateGreen.opacity(0.35), radius: 14, y: 6)
            }
            .buttonStyle(ScalePressButtonStyle())
            .padding(.horizontal, 28)

            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Dashboard header

/// Totals across every saved payslip — Onyx card, Cyan border, Neon Green for
/// the money figure, matching the fixed card styling below rather than the
/// user's personalized accent (this is a library-wide summary, not a themed
/// decoration).
private struct PayslipDashboardHeader: View {
    let totalNet: Decimal
    let totalTaxes: Decimal
    let count: Int
    let currencyCode: String

    private static let cyan = Color(hex: "00E5FF")
    private static let green = Color(hex: "26F273")

    var body: some View {
        HStack(spacing: 10) {
            stat(L10n.payslipDashboardNet, PayslipDisplayFormatting.money(totalNet, currencyCode: currencyCode), color: Self.green)
            Divider().frame(height: 30).overlay(Color.white.opacity(0.1))
            stat(L10n.payslipDashboardTaxes, PayslipDisplayFormatting.money(totalTaxes, currencyCode: currencyCode), color: Self.cyan)
            Divider().frame(height: 30).overlay(Color.white.opacity(0.1))
            stat(L10n.payslipDashboardCount, "\(count)", color: Self.cyan)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: "0D0D0D")))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Self.cyan.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func stat(_ label: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Grid card

private struct PayslipGridCard: View {
    let record: PayslipRecord
    var accent: Color = HomeNeon.accent
    /// Fixed Cyan/Green card styling, distinct from `accent` (used only for the
    /// thumbnail placeholder's spinner, which stays personalized like the rest
    /// of the screen's chrome).
    private static let cardBackground = Color(hex: "0D0D0D")
    private static let cyan = Color(hex: "00E5FF")
    private static let green = Color(hex: "26F273")
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
                            .strokeBorder(Self.cyan.opacity(0.3), lineWidth: 1)
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
                .foregroundStyle(Self.green)
                .lineLimit(1)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Self.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Self.cyan.opacity(0.3), lineWidth: 1)
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
                    .tint(accent)
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
