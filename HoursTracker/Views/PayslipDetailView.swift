import SwiftUI
import PDFKit
import UIKit

/// Read-only detail for a saved payslip. Editing re-uses Chunk 4 upload/review later;
/// this chunk supports preview + delete.
struct PayslipDetailView: View {
    let record: PayslipRecord
    let sourceURL: URL
    /// Returns whether the delete actually succeeded, so this view only pops back to
    /// the library on success — a failed delete (rare: disk error) leaves the user here
    /// with the error alert, matching the record still genuinely existing.
    let onDelete: () -> Bool

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var theme = HomeAccentTheme.shared
    @ObservedObject private var appBackground = AppBackgroundTheme.shared
    @State private var showDeleteConfirm = false
    @State private var previewImage: UIImage?
    @State private var showFullScreenImage = false

    private var currencyCode: String? {
        record.userOverrides?.currencyCode ?? record.extraction.currencyCode
    }

    var body: some View {
        ZStack {
            appBackground.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    previewSection

                    if record.reviewState != .confirmed || record.extraction.needsManualReview {
                        Label(L10n.payslipNeedsReview, systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HomeNeon.coral)
                    }

                    fieldSection

                    if !record.extraction.overtimeLinesOrEmpty.isEmpty {
                        overtimeBreakdownSection
                    }

                    if !record.extraction.deductionLinesOrEmpty.isEmpty {
                        deductionBreakdownSection
                    }

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label(L10n.payslipDelete, systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HomeNeon.coral)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                Capsule(style: .continuous)
                                    .stroke(HomeNeon.coral.opacity(0.55), lineWidth: 1.2)
                                    .background(Capsule().fill(HomeNeon.card))
                            )
                    }
                    .buttonStyle(ScalePressButtonStyle())
                    .padding(.top, 8)
                }
                .padding(16)
            }
        }
        .navigationTitle(periodTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(appBackground.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .confirmationDialog(
            L10n.payslipDeleteConfirmTitle,
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.payslipDelete, role: .destructive) {
                if onDelete() { dismiss() }
            }
            Button(L10n.editCancel, role: .cancel) {}
        } message: {
            Text(L10n.payslipDeleteConfirmMessage)
        }
        .onAppear { loadPreview() }
    }

    private var periodTitle: String {
        if let label = record.periodLabel, !label.isEmpty { return label }
        return PayslipDisplayFormatting.periodMonthLabel(record.effectivePeriodMonth)
    }

    private var previewSection: some View {
        Group {
            if let previewImage {
                ZoomableImageView(image: previewImage)
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onTapGesture { showFullScreenImage = true }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                            .padding(8)
                            .allowsHitTesting(false)
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(L10n.payslipZoomHint)
            } else if record.sourceKind == .pdf {
                PayslipDetailPDFPreview(url: sourceURL)
                    .frame(minHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Label(L10n.payslipPreviewUnavailable, systemImage: "doc")
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .accessibilityLabel(L10n.payslipPreview)
        .fullScreenCover(isPresented: $showFullScreenImage) {
            if let previewImage {
                PayslipImageFullScreenView(image: previewImage)
            }
        }
    }

    private var fieldSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            field(L10n.payslipNet, PayslipDisplayFormatting.optionalMoney(record.effectiveNetPay, currencyCode: currencyCode))
            field(L10n.payslipGross, PayslipDisplayFormatting.optionalMoney(record.effectiveGrossPay, currencyCode: currencyCode))
            field(L10n.payslipCurrency, currencyCode ?? "—")
            field(L10n.payslipPaymentMonth, PayslipDisplayFormatting.periodMonthLabel(record.effectivePeriodMonth))
            field(
                L10n.payslipPeriodStart,
                PayslipDisplayFormatting.optionalDate(record.userOverrides?.payPeriodStart ?? record.extraction.payPeriodStart)
            )
            field(
                L10n.payslipPeriodEnd,
                PayslipDisplayFormatting.optionalDate(record.userOverrides?.payPeriodEnd ?? record.extraction.payPeriodEnd)
            )
            field(L10n.payslipEmployer, record.userOverrides?.employerName ?? record.extraction.employerName ?? "—")
            field(L10n.payslipEmployee, record.userOverrides?.employeeName ?? record.extraction.employeeName ?? "—")
            field(
                L10n.payslipHoursRegular,
                PayslipDisplayFormatting.optionalDouble(record.userOverrides?.hoursRegular ?? record.extraction.hoursRegular)
            )
            field(
                L10n.payslipHoursOT,
                PayslipDisplayFormatting.optionalDouble(record.userOverrides?.hoursOT ?? record.extraction.hoursOT)
            )
            field(
                L10n.payslipDeductions,
                PayslipDisplayFormatting.optionalMoney(
                    record.userOverrides?.deductionsTotal ?? record.extraction.deductionsTotal,
                    currencyCode: currencyCode
                )
            )
            if let notes = record.notes, !notes.isEmpty {
                field(L10n.payslipNotes, notes)
            }
            field(L10n.payslipConfidence, "\(Int((record.extraction.confidence * 100).rounded()))%")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(HomeNeon.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(theme.accent.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private var overtimeBreakdownSection: some View {
        breakdownCard(title: L10n.payslipOvertimeBreakdownTitle) {
            ForEach(Array(record.extraction.overtimeLinesOrEmpty.enumerated()), id: \.offset) { _, line in
                field(L10n.payslipOvertimeLineLabel(line.ratePercent), overtimeLineValue(line))
            }
        }
    }

    private var deductionBreakdownSection: some View {
        breakdownCard(title: L10n.payslipDeductionBreakdownTitle) {
            ForEach(Array(record.extraction.deductionLinesOrEmpty.enumerated()), id: \.offset) { _, line in
                field(line.label, PayslipDisplayFormatting.money(line.amount, currencyCode: currencyCode))
            }
        }
    }

    /// Rows generated with `Self.field` are just hours; append the line's amount when
    /// the LLM captured one — the payslip's payment table always prices overtime, but the
    /// extractor may not have located the amount column even when it found the hours.
    private func overtimeLineValue(_ line: PayslipOvertimeLine) -> String {
        let hours = String(format: "%.2f", line.hours)
        guard let amount = line.amount else { return hours }
        return "\(hours) · \(PayslipDisplayFormatting.money(amount, currencyCode: currencyCode))"
    }

    private func breakdownCard<Content: View>(title: String, @ViewBuilder rows: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
            rows()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(HomeNeon.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(HomeNeon.accent.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private func field(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.body)
                .foregroundStyle(.white)
        }
    }

    private func loadPreview() {
        if record.sourceKind == .image,
           let data = try? Data(contentsOf: sourceURL),
           let image = UIImage(data: data) {
            previewImage = image
        } else if let cached = PayslipThumbnailCache.shared.cachedImage(for: record.id) {
            previewImage = cached
        }
    }
}

/// An image inside a `ScrollView`, pinch-zoomable via `MagnificationGesture`.
/// The image's *frame* (not just a cosmetic `.scaleEffect`) grows with the pinch,
/// so once zoomed in past the viewport, `ScrollView`'s own native panning works
/// correctly — a `.scaleEffect` alone doesn't change what `ScrollView` thinks
/// its content size is, so panning wouldn't track the visually-zoomed image.
struct ZoomableImageView: View {
    let image: UIImage
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1

    private static let minScale: CGFloat = 1
    private static let maxScale: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let fitted = Self.fittedSize(for: image.size, in: geo.size)
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: fitted.width * scale, height: fitted.height * scale)
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = min(max(baseScale * value, Self.minScale), Self.maxScale)
                    }
                    .onEnded { _ in
                        baseScale = scale
                    }
            )
        }
    }

    private static func fittedSize(for imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return containerSize
        }
        let ratio = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        return CGSize(width: imageSize.width * ratio, height: imageSize.height * ratio)
    }
}

/// Full-screen presentation of a payslip image — the same zoomable view, with
/// far more room to actually read a photographed payslip's fine print than the
/// detail screen's fixed-height preview allows.
struct PayslipImageFullScreenView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            ZoomableImageView(image: image)
                .ignoresSafeArea()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.4), radius: 6)
            }
            .padding(16)
            .accessibilityLabel(L10n.editCancel)
        }
    }
}

private struct PayslipDetailPDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}
