import SwiftUI

/// The Pay Card: one hero amount, the hours split into pay tiers
/// (100% / 125% / 150%), and a couple of detail rows. Shared by the onboarding
/// preview and (next) the end-of-shift Day Summary so the reward looks the same
/// everywhere.
struct PayCardView: View {
    struct Row: Identifiable {
        let label: String
        let value: String
        /// 6pt tier dot on the leading edge — pay-tier rows only (100/125/150%).
        var dot: Color?
        var id: String { label }
    }

    let amount: Double
    let currencyCode: String
    let caption: String
    /// Small second line under the caption (e.g. "estimate only · before tax").
    var note: String?
    var title: String?
    var regularHours: Double = 0
    var ot125Hours: Double = 0
    var ot150Hours: Double = 0
    /// Real tiers (with the rate actually paid). When set, they replace the three hour
    /// buckets above — needed for rest days / holidays, where the base is 150%.
    var tiers: [PayTier]?
    var rows: [Row] = []
    var accent: Color
    /// Count up from zero once when the card appears (skipped under Reduce Motion).
    var countsUp = true
    /// Settle from 98% to full size when the card appears (skipped under Reduce Motion).
    var popsIn = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0
    @State private var hasRevealed = false
    @State private var popped = false

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
                if let note {
                    Text(note)
                        .dsFont(.meta)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                [PayFormatter.string(amount, currencyCode: currencyCode), caption, note]
                    .compactMap { $0 }
                    .joined(separator: ", ")
            )

            PayTierBar(segments: barSegments, accent: accent)

            if !rows.isEmpty {
                VStack(spacing: DS.Space.xs) {
                    ForEach(rows) { row in
                        HStack(spacing: DS.Space.xs) {
                            if let dot = row.dot {
                                Circle()
                                    .fill(dot)
                                    .frame(width: 6, height: 6)
                                    .accessibilityHidden(true)
                            }
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
        .scaleEffect(popsIn && !popped && !reduceMotion ? 0.98 : 1)
        .onAppear {
            reveal()
            if popsIn, !reduceMotion {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { popped = true }
            }
        }
        .onChange(of: amount) { _, newValue in
            // A later change (gross ↔ net, an edit) moves from the current figure
            // to the new one — only the first appearance counts up from zero.
            if reduceMotion {
                shown = newValue
            } else {
                withAnimation(DS.Motion.state) { shown = newValue }
            }
        }
    }

    private var barSegments: [(hours: Double, percent: Int)] {
        if let tiers { return tiers.map { ($0.hours, $0.percent) } }
        return [(regularHours, 100), (ot125Hours, 125), (ot150Hours, 150)]
    }

    private func reveal() {
        guard !hasRevealed else { return }
        hasRevealed = true
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

extension PayTier {
    /// Tier colour for `PayTier.tone(percent:)`.
    static func color(percent: Int, accent: Color) -> Color {
        switch tone(percent: percent) {
        case .accent: return accent
        case .gold: return DS.Palette.ot125
        case .orange: return DS.Palette.ot150
        }
    }
}

/// Hours split by pay tier. Empty tiers are left out; nothing is drawn with no hours.
struct PayTierBar: View {
    let segments: [(hours: Double, percent: Int)]
    var accent: Color

    private var visible: [(hours: Double, percent: Int)] {
        segments.filter { $0.hours > 0.001 }
    }

    var body: some View {
        let total = visible.reduce(0.0) { $0 + $1.hours }
        if total > 0 {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(visible.enumerated()), id: \.offset) { _, segment in
                        Capsule(style: .continuous)
                            .fill(PayTier.color(percent: segment.percent, accent: accent))
                            .frame(width: max(4, (geo.size.width - 4) * segment.hours / total))
                    }
                }
            }
            .frame(height: 8)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityElement()
            .accessibilityLabel(
                visible
                    .map { L10n.payTierAt(HistoryPeriodHelper.formatHoursClock($0.hours), $0.percent) }
                    .joined(separator: ", ")
            )
        }
    }
}
