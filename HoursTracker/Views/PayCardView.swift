import SwiftUI

/// The Pay Card: one hero amount, the hours split into pay tiers
/// (100% / 125% / 150%), and a couple of detail rows. Shared by the onboarding
/// preview and (next) the end-of-shift Day Summary so the reward looks the same
/// everywhere.
struct PayCardView: View {
    struct Row: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    let amount: Double
    let currencyCode: String
    let caption: String
    var title: String?
    var regularHours: Double = 0
    var ot125Hours: Double = 0
    var ot150Hours: Double = 0
    var rows: [Row] = []
    var accent: Color
    /// Count up from zero once when the card appears (skipped under Reduce Motion).
    var countsUp = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            if let title {
                Text(title)
                    .dsFont(.meta)
                    .foregroundStyle(DS.Palette.textTertiary)
            }

            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                CountingAmount(value: shown, currencyCode: currencyCode)
                    .dsFont(.numHero)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(caption)
                    .dsFont(.meta)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(PayFormatter.string(amount, currencyCode: currencyCode)), \(caption)")

            PayTierBar(regular: regularHours, ot125: ot125Hours, ot150: ot150Hours, accent: accent)

            if !rows.isEmpty {
                VStack(spacing: DS.Space.xs) {
                    ForEach(rows) { row in
                        HStack {
                            Text(row.label)
                                .dsFont(.sub)
                                .foregroundStyle(DS.Palette.textSecondary)
                            Spacer()
                            Text(verbatim: row.value)
                                .dsFont(.sub, weight: .semibold)
                                .monospacedDigit()
                                .foregroundStyle(DS.Palette.textPrimary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(DS.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(radius: DS.Radius.xl)
        .onAppear { reveal() }
        .onChange(of: amount) { _, _ in reveal() }
    }

    private func reveal() {
        guard countsUp, !reduceMotion else {
            shown = amount
            return
        }
        shown = 0
        withAnimation(.easeOut(duration: 0.6)) { shown = amount }
    }
}

/// Animatable currency text so the hero amount counts up instead of jumping.
private struct CountingAmount: View, Animatable {
    var value: Double
    let currencyCode: String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(verbatim: PayFormatter.string(value, currencyCode: currencyCode))
    }
}

/// Hours split by pay tier. Empty tiers are left out; nothing is drawn with no hours.
struct PayTierBar: View {
    let regular: Double
    let ot125: Double
    let ot150: Double
    var accent: Color

    private var segments: [(Double, Color)] {
        [(regular, accent), (ot125, DS.Palette.ot125), (ot150, DS.Palette.ot150)].filter { $0.0 > 0.001 }
    }

    var body: some View {
        let total = segments.reduce(0.0) { $0 + $1.0 }
        if total > 0 {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        Capsule(style: .continuous)
                            .fill(segment.1)
                            .frame(width: max(4, (geo.size.width - 4) * segment.0 / total))
                    }
                }
            }
            .frame(height: 8)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityElement()
            .accessibilityLabel(accessibilityText)
        }
    }

    private var accessibilityText: String {
        var parts = [L10n.payTier100(HistoryPeriodHelper.formatHoursClock(regular))]
        if ot125 > 0.001 { parts.append(L10n.payTier125(HistoryPeriodHelper.formatHoursClock(ot125))) }
        if ot150 > 0.001 { parts.append(L10n.payTier150(HistoryPeriodHelper.formatHoursClock(ot150))) }
        return parts.joined(separator: ", ")
    }
}
