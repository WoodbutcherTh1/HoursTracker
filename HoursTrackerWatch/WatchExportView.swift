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
                Text("Export")
                    .font(.system(size: 15, weight: .semibold))

                previewCard(title: "This month", preview: snapshot.exportThisMonth, rangeKey: "thisMonth")
                previewCard(title: "This year", preview: snapshot.exportThisYear, rangeKey: "thisYear")

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

                Text("PDF, full options, and the payslip library stay on iPhone.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .navigationTitle("Export")
    }

    private func previewCard(title: String, preview: WatchExportPreview, rangeKey: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(preview.rangeLabel)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            if preview.hasData {
                HStack(spacing: 10) {
                    previewStat(value: "\(preview.dayCount)", label: "Days")
                    previewStat(value: formattedHours(preview.totalHours), label: "Hours")
                    previewStat(value: formattedPay(preview.net), label: "Net")
                }
            } else {
                Text("No data in this range")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                store.lastExportConfirmation = nil
                store.requestExport(rangeKey: rangeKey)
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .disabled(!preview.hasData)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
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
