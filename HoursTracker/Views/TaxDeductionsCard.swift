import SwiftUI

/// Estimated employee-side deductions (income tax, National Insurance, health tax)
/// for a given period — shown alongside `GrossNetBadge` so the user can see not
/// just gross vs. net, but what makes up the difference. `DayPayBreakdown` already
/// computes these via `IsraeliTaxEstimator`, factoring in hours worked, credit
/// points (marital status / children), and age (retirement-age NI reduction).
struct TaxDeductionsCard: View {
    let breakdown: DayPayBreakdown

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(AppLocale.tr("tax.deductionsTitle"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            row(AppLocale.tr("tax.incomeTax"), amount: breakdown.incomeTax)
            row(AppLocale.tr("tax.nationalInsurance"), amount: breakdown.nationalInsurance)
            row(AppLocale.tr("tax.healthTax"), amount: breakdown.healthTax)

            Text(AppLocale.tr("tax.estimateNote"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func row(_ title: String, amount: Double) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text("-" + breakdown.formatted(amount))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.red)
        }
    }
}
