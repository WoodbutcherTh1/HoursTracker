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
    @State private var showDeleteConfirm = false
    @State private var previewImage: UIImage?

    private var currencyCode: String? {
        record.userOverrides?.currencyCode ?? record.extraction.currencyCode
    }

    var body: some View {
        ZStack {
            HomeNeon.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    previewSection

                    if record.reviewState != .confirmed || record.extraction.needsManualReview {
                        Label(L10n.payslipNeedsReview, systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HomeNeon.coral)
                    }

                    fieldSection

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
        .toolbarBackground(HomeNeon.bg, for: .navigationBar)
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
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
