import SwiftUI

/// One Home stat: a static icon, the title, the number and — only when there is a
/// real target — a thin progress bar. No decorative motion: the bar moves only when
/// the number does. Without a target the card shows the number alone (never an
/// empty 0% bar).
struct HomeStatCard: View {
    let title: String
    /// Spoken instead of `title` when the card shows a shortened one.
    var accessibilityTitle: String?
    let value: String
    let systemImage: String
    /// 0…1 against the user's own goal (`HomeStatGoals`), or `nil` for no bar.
    var progress: Double?
    /// Spoken after the value, e.g. "goal 8:24".
    var targetText: String?
    var accent: Color
    var compact: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var reachedGoal: Bool { (progress ?? 0) >= 1 }
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

            if let progress {
                bar(progress)
            }
        }
        .padding(.vertical, compact ? DS.Space.sm : DS.Space.md)
        .padding(.horizontal, compact ? DS.Space.xs + 2 : DS.Space.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dsCard(radius: DS.Radius.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle ?? title)
        .accessibilityValue(targetText.map { "\(value), \($0)" } ?? value)
    }

    /// Nothing done yet toward a real goal: the hairline track with a 4pt dot at
    /// its start — "the day is open", never a bar that reads as full or as 0%.
    private func bar(_ progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(DS.Palette.hairline)
                if progress <= 0 {
                    Circle().fill(accent).frame(width: 4, height: 4)
                } else {
                    Capsule()
                        .fill(reachedGoal ? DS.Palette.success : accent)
                        .frame(width: max(4, geo.size.width * progress))
                }
            }
        }
        .frame(height: 4)
        .animation(DS.Motion.animation(DS.Motion.state, reduceMotion: reduceMotion), value: progress)
        .accessibilityHidden(true)
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
