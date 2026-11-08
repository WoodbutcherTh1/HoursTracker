import SwiftUI

/// One Home stat: icon + title, then a large plain number. Deliberately no
/// progress ring/bar — that was tried and reverted (too cluttered for three
/// cards in a row); the Cyan glow treatment lives on the Home door only.
struct HomeStatCard: View {
    let title: String
    /// Spoken instead of `title` when the card shows a shortened one.
    var accessibilityTitle: String?
    let value: String
    let systemImage: String
    /// 0…1 against the user's own goal (`HomeStatGoals`) — no longer drawn as a
    /// ring/bar, kept only so `targetText` still reads out correctly below.
    var progress: Double?
    /// Spoken after the value, e.g. "goal 8:24".
    var targetText: String?
    var accent: Color
    /// Unused since the ring was removed; kept so call sites don't need to
    /// change. See `HomeView.ringColor(for:)`.
    var ringColor: Color?
    var compact: Bool = false

    /// A real goal with nothing done yet (e.g. a workday not started).
    private var notStarted: Bool { progress.map { $0 <= 0 } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.xxs) {
                Image(systemName: systemImage)
                    .htFont(size: 12, relativeTo: .footnote, weight: .semibold)
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                Text(title)
                    .dsFont(.meta, weight: .medium)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Text(value)
                .htFont(size: compact ? 20 : 24, relativeTo: .title2, weight: .semibold, design: .rounded)
                .monospacedDigit()
                .environment(\.layoutDirection, .leftToRight)
                .foregroundStyle(notStarted ? DS.Palette.textSecondary : DS.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .padding(.vertical, compact ? DS.Space.sm : DS.Space.md)
        .padding(.horizontal, compact ? DS.Space.xs + 2 : DS.Space.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dsCard(radius: DS.Radius.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle ?? title)
        .accessibilityValue(targetText.map { "\(value), \($0)" } ?? value)
    }
}

/// Shown in place of the stat cards until the first shift, so a new user sees an
/// invitation instead of three cards of zeros.
struct HomeStatsWelcomeCard: View {
    var accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            Image(systemName: "sparkles")
                .htFont(size: 20, relativeTo: .title3, weight: .semibold)
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(L10n.homeStatsWelcomeTitle)
                    .dsFont(.headline)
                    .foregroundStyle(DS.Palette.textPrimary)
                Text(L10n.homeStatsWelcomeBody)
                    .dsFont(.sub)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.md)
        .frame(maxWidth: .infinity)
        .dsCard(radius: DS.Radius.md)
        .accessibilityElement(children: .combine)
    }
}
