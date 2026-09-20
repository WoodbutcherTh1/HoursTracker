import SwiftUI

/// Watch mirror of the phone's Export tab. A full export form (custom ranges, 5
/// file formats, day-type filters, the payslip library) doesn't fit — and a PDF
/// can't be shared from the watch anyway — so this keeps the tab's actual purpose
/// (see what a range would export, then export it) with the two ranges people
/// reach for on Export: this payroll month and this year. Requesting an export
/// generates the real file on the phone and opens its native share sheet there.
struct WatchExportView: View {
    @EnvironmentObject private var store: WatchSessionStore

    private var snapshot: WatchSnapshot { store.snapshot }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Label(L10n.tabExport, systemImage: "square.and.arrow.up.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Color.accentColor)

                previewCard(title: AppLocale.tr("watch.exportThisMonth"), icon: "calendar", preview: snapshot.exportThisMonth, rangeKey: "thisMonth")
                previewCard(title: AppLocale.tr("watch.exportThisYear"), icon: "calendar.badge.clock", preview: snapshot.exportThisYear, rangeKey: "thisYear")

                if let confirmation = store.lastExportConfirmation {
                    Text(confirmation)
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .multilineTextAlignment(.center)
                }
                if let error = store.lastErrorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                Text(AppLocale.tr("watch.exportPhoneOnly"))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .navigationTitle(L10n.tabExport)
    }

    private func previewCard(title: String, icon: String, preview: WatchExportPreview, rangeKey: String) -> some View {
        VStack(spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .labelStyle(.titleAndIcon)
            Text(preview.rangeLabel)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            if preview.hasData {
                HStack(spacing: 10) {
                    previewStat(value: "\(preview.dayCount)", label: AppLocale.tr("watch.days"))
                    previewStat(value: formattedHours(preview.totalHours), label: AppLocale.tr("watch.hours"))
                    previewStat(value: formattedPay(preview.net), label: L10n.historyPayNet)
                }
            } else {
                HTStateView(kind: .empty(
                    icon: "calendar.badge.exclamationmark",
                    title: AppLocale.tr("watch.exportNoData")
                ))
            }

            Button {
                store.lastExportConfirmation = nil
                store.requestExport(rangeKey: rangeKey)
            } label: {
                Label(L10n.tabExport, systemImage: "square.and.arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor.opacity(0.85))
            .disabled(!preview.hasData)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    private func previewStat(value: String, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formattedHours(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return String(format: "%d:%02d", h, m)
    }

    private func formattedPay(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = snapshot.currencyCode.isEmpty ? "ILS" : snapshot.currencyCode
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.0f", amount)
    }
}
