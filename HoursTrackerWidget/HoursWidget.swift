import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Theme

/// Widget color palette matching the main app's dark teal neon theme.
private enum WidgetTheme {
    /// Deep teal background — matches AppBackgroundTheme.teal.
    static let background = Color(red: 0.027, green: 0.102, blue: 0.122) // #071a1f
    static let surface = Color(red: 0.016, green: 0.086, blue: 0.102) // #03282b
    static let accent = Color(red: 0.180, green: 0.831, blue: 0.769) // #2dd4bf
    static let accentLight = Color(red: 0.369, green: 0.918, blue: 0.831) // #5eead4
    static let cyan = Color(red: 0.133, green: 0.827, blue: 0.933) // #22d3ee
    static let moneyGreen = Color(red: 0.345, green: 0.851, blue: 0.471) // #4ade80
    static let textPrimary = Color(red: 0.918, green: 1.0, blue: 0.984) // #eafffb
    static let textSecondary = Color.white.opacity(0.5)
    static let textTertiary = Color.white.opacity(0.3)
    static let workingDot = Color(red: 0.369, green: 0.918, blue: 0.831) // #5eead4
    static let doneDot = Color(red: 0.180, green: 0.831, blue: 0.769) // #2dd4bf

    /// Gradient for the active (working) state background.
    static let activeGradient = LinearGradient(
        colors: [
            Color(red: 0.027, green: 0.141, blue: 0.145), // #07242a
            Color(red: 0.027, green: 0.102, blue: 0.122), // #071a1f
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Subtle border for card elements.
    static let cardBorder = Color.white.opacity(0.06)

    /// Teal glow for active indicators.
    static let glow = Color(red: 0.180, green: 0.831, blue: 0.769).opacity(0.15)

    /// Accent gradient for pay amounts.
    static let payGradient = LinearGradient(
        colors: [moneyGreen, accentLight],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Accent gradient for icons.
    static let iconGradient = LinearGradient(
        colors: [accent, cyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Shared Components

/// Pulsing dot indicating an active state.
private struct PulseDot: View {
    let color: Color
    var size: CGFloat = 7

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: size * 2, height: size * 2)
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
    }
}

/// A compact stat card with icon, value, and label.
private struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let valueColor: Color
    var iconColor: Color = WidgetTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(label.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetTheme.textTertiary)
                    .tracking(0.5)
            }
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(valueColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// Progress ring showing hours worked toward standard day.
private struct HoursRing: View {
    let elapsed: Double
    let standard: Double

    private var progress: Double {
        guard standard > 0 else { return 0 }
        return min(elapsed / standard, 1.0)
    }

    private var ringColor: Color {
        elapsed >= standard ? WidgetTheme.cyan : WidgetTheme.accent
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(WidgetTheme.accent.opacity(0.1), lineWidth: 4)
            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            // Center text
            VStack(spacing: 0) {
                Text(String(format: "%.1f", elapsed))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetTheme.textPrimary)
                    .monospacedDigit()
                Text("h")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetTheme.textSecondary)
            }
        }
    }
}

/// Rounded interactive button used across widget sizes.
private struct WidgetActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let intent: any AppIntent

    @ViewBuilder
    var body: some View {
        if let clockIn = intent as? ClockInIntent {
            Button(intent: clockIn) { label }
        } else if let clockOut = intent as? ClockOutIntent {
            Button(intent: clockOut) { label }
        } else {
            label
        }
    }

    private var label: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(WidgetTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(tint.opacity(0.18), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Timeline Entry

/// One day bar for the large widget's week chart.
struct DayBar: Identifiable {
    let id: Int
    let label: String
    let hours: Double
}

struct HoursEntry: TimelineEntry {
    let date: Date
    let isOpen: Bool
    let session: WidgetSession?
    let elapsedHours: Double
    let estimatedPay: Double
    let todayCompletedHours: Double
    let todayCompletedPay: Double
    let weeklyHours: Double
    let weeklyPay: Double
    let monthHours: Double
    let monthPay: Double
    let weekBars: [DayBar]
    let settings: WidgetSettings
}

// MARK: - Timeline Provider

struct HoursTimelineProvider: TimelineProvider {
    typealias Entry = HoursEntry

    func placeholder(in context: Context) -> HoursEntry {
        HoursEntry(
            date: Date(),
            isOpen: false,
            session: nil,
            elapsedHours: 0,
            estimatedPay: 0,
            todayCompletedHours: 8.5,
            todayCompletedPay: 950,
            weeklyHours: 38,
            weeklyPay: 4100,
            monthHours: 148,
            monthPay: 16200,
            weekBars: sampleBars,
            settings: .empty
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (HoursEntry) -> Void) {
        completion(buildEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HoursEntry>) -> Void) {
        let entry = buildEntry()
        let refreshInterval: TimeInterval = entry.isOpen ? 180 : 900
        let nextUpdate = Date().addingTimeInterval(refreshInterval)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private var sampleBars: [DayBar] {
        let labels = ["S", "M", "T", "W", "T", "F", "S"]
        let hours = [0.0, 8.4, 8.1, 8.7, 8.2, 4.6, 0.0]
        return labels.enumerated().map { DayBar(id: $0.offset, label: $0.element, hours: hours[$0.offset]) }
    }

    private func buildEntry() -> HoursEntry {
        let settings = WidgetBridge.readSettings()
        let sessions = WidgetBridge.readSessions()
        let calendar = Calendar.current

        let todayCompleted = WidgetBridge.todayCompletedSessions(from: sessions, calendar: calendar)
        let completedHours = todayCompleted.reduce(0) { $0 + $1.effectiveHours }
        let completedPay = todayCompleted.reduce(0) {
            $0 + WidgetBridge.estimatePay(elapsedHours: $1.effectiveHours, settings: settings)
        }

        let weekSessions = WidgetBridge.weekSessions(from: sessions, calendar: calendar)
        let weeklyHours = weekSessions.reduce(0) { $0 + $1.effectiveHours }
        let weeklyPay = weekSessions.reduce(0) {
            $0 + WidgetBridge.estimatePay(elapsedHours: $1.effectiveHours, settings: settings)
        }

        let monthSessions = WidgetBridge.monthSessions(from: sessions, calendar: calendar)
        let monthHours = monthSessions.reduce(0) { $0 + $1.effectiveHours }
        let monthPay = monthSessions.reduce(0) {
            $0 + WidgetBridge.estimatePay(elapsedHours: $1.effectiveHours, settings: settings)
        }

        let bars = weekBars(from: sessions, calendar: calendar)

        if let open = WidgetBridge.openSession(from: sessions) {
            let elapsed = open.effectiveHours
            let pay = WidgetBridge.estimatePay(elapsedHours: elapsed, settings: settings)
            return HoursEntry(
                date: Date(), isOpen: true, session: open,
                elapsedHours: elapsed, estimatedPay: pay,
                todayCompletedHours: completedHours, todayCompletedPay: completedPay,
                weeklyHours: weeklyHours, weeklyPay: weeklyPay,
                monthHours: monthHours, monthPay: monthPay,
                weekBars: bars, settings: settings
            )
        } else {
            return HoursEntry(
                date: Date(), isOpen: false, session: nil,
                elapsedHours: 0, estimatedPay: 0,
                todayCompletedHours: completedHours, todayCompletedPay: completedPay,
                weeklyHours: weeklyHours, weeklyPay: weeklyPay,
                monthHours: monthHours, monthPay: monthPay,
                weekBars: bars, settings: settings
            )
        }
    }

    private func weekBars(from sessions: [WidgetSession], calendar: Calendar) -> [DayBar] {
        let today = calendar.startOfDay(for: Date())
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let weekDays = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek) }
        return weekDays.enumerated().map { index, day in
            let hours = sessions
                .filter { calendar.isDate($0.clockIn, inSameDayAs: day) }
                .reduce(0) { $0 + $1.effectiveHours }
            let label = String(calendar.shortWeekdaySymbols[calendar.component(.weekday, from: day) - 1].prefix(1))
            return DayBar(id: index, label: label, hours: hours)
        }
    }
}

// MARK: - Widget Background

/// Custom dark background for the widget.
private struct WidgetBackground: View {
    var body: some View {
        WidgetTheme.background
    }
}

// MARK: - Small Widget

struct HoursSmallWidget: Widget {
    let kind: String = "HoursSmallWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HoursTimelineProvider()) { entry in
            HoursSmallWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackground()
                }
        }
        .configurationDisplayName("Hours Tracker")
        .description("Today's hours and earnings at a glance.")
        .supportedFamilies([.systemSmall])
    }
}

struct HoursSmallWidgetView: View {
    let entry: HoursEntry

    var body: some View {
        Group {
            if entry.isOpen, let session = entry.session {
                activeView(session: session)
            } else if entry.todayCompletedHours > 0 {
                completedView
            } else {
                emptyView
            }
        }
        .widgetURL(URL(string: WidgetBridge.deepLinkHome))
    }

    // MARK: Active State

    private func activeView(session: WidgetSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status bar
            HStack(spacing: 5) {
                PulseDot(color: WidgetTheme.workingDot, size: 5)
                Text("Working")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetTheme.accentLight)
                Spacer()
                Text(session.clockIn, style: .time)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetTheme.textTertiary)
            }

            // Hours ring + pay
            HStack(spacing: 10) {
                HoursRing(elapsed: entry.elapsedHours, standard: entry.settings.standardDayHours)
                    .frame(width: 54, height: 54)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(payText(entry.estimatedPay))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(WidgetTheme.payGradient)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                    Text("today")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(WidgetTheme.textTertiary)
                        .textCase(.uppercase)
                }
            }

            // Clock out — the whole point: one tap from the home screen.
            WidgetActionButton(
                title: "Clock Out",
                systemImage: "stop.fill",
                tint: WidgetTheme.accent,
                intent: ClockOutIntent()
            )
            .frame(maxWidth: .infinity)
        }
        .padding(12)
    }

    // MARK: Completed State

    private var completedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status bar
            HStack(spacing: 5) {
                PulseDot(color: WidgetTheme.doneDot, size: 5)
                Text("Done")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetTheme.accent)
                Spacer()
                Text(formattedHours(entry.todayCompletedHours))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetTheme.textTertiary)
                    .monospacedDigit()
            }

            // Ring + pay
            HStack(spacing: 10) {
                HoursRing(elapsed: entry.todayCompletedHours, standard: entry.settings.standardDayHours)
                    .frame(width: 54, height: 54)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(payText(entry.todayCompletedPay))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(WidgetTheme.payGradient)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                    Text("gross")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(WidgetTheme.textTertiary)
                        .textCase(.uppercase)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(WidgetTheme.moneyGreen)
                Text("Shift complete")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetTheme.textSecondary)
                Spacer()
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 10))
                    .foregroundStyle(WidgetTheme.textTertiary)
            }
        }
        .padding(12)
    }

    // MARK: Empty State

    private var emptyView: some View {
        VStack(spacing: 9) {
            Spacer()
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(WidgetTheme.iconGradient)
            Text("Start your shift")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetTheme.textPrimary)
            WidgetActionButton(
                title: "Clock In",
                systemImage: "play.fill",
                tint: WidgetTheme.moneyGreen,
                intent: ClockInIntent()
            )
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(12)
    }

    private func payText(_ amount: Double) -> String {
        WidgetBridge.format(amount: amount, currencyCode: entry.settings.currencyCode)
    }

    private func formattedHours(_ hours: Double) -> String {
        String(format: "%.1fh", hours)
    }
}

// MARK: - Medium + Large Widget (one configuration, adaptive layout)

struct HoursMediumWidget: Widget {
    let kind: String = "HoursMediumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HoursTimelineProvider()) { entry in
            HoursHomeWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackground()
                }
        }
        .configurationDisplayName("Hours Tracker")
        .description("Detailed hours and pay breakdown. Interactive buttons let you clock in and out from the home screen.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct HoursHomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HoursEntry

    var body: some View {
        Group {
            if family == .systemLarge {
                largeView
            } else if entry.isOpen {
                mediumActiveView
            } else if entry.todayCompletedHours > 0 {
                mediumCompletedView
            } else {
                mediumEmptyView
            }
        }
        .widgetURL(URL(string: entry.isOpen ? WidgetBridge.deepLinkHome : WidgetBridge.deepLinkHistory))
    }

    // MARK: Medium — Active

    private var mediumActiveView: some View {
        HStack(spacing: 14) {
            // Left: ring + status
            VStack(spacing: 8) {
                HoursRing(elapsed: entry.elapsedHours, standard: entry.settings.standardDayHours)
                    .frame(width: 66, height: 66)

                HStack(spacing: 5) {
                    PulseDot(color: WidgetTheme.workingDot, size: 4)
                    Text("Working")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(WidgetTheme.accentLight)
                }
            }

            RoundedRectangle(cornerRadius: 0.5)
                .fill(WidgetTheme.cardBorder)
                .frame(width: 1)

            // Right: stats + action
            VStack(alignment: .leading, spacing: 6) {
                StatCard(
                    icon: "banknote.fill",
                    value: payText(entry.estimatedPay),
                    label: "Earnings",
                    valueColor: WidgetTheme.moneyGreen,
                    iconColor: WidgetTheme.moneyGreen
                )
                StatCard(
                    icon: "clock.fill",
                    value: formattedElapsed(entry.elapsedHours),
                    label: "Elapsed",
                    valueColor: WidgetTheme.accentLight,
                    iconColor: WidgetTheme.accent
                )
                WidgetActionButton(
                    title: "Clock Out",
                    systemImage: "stop.fill",
                    tint: WidgetTheme.accent,
                    intent: ClockOutIntent()
                )
            }
        }
        .padding(14)
    }

    // MARK: Medium — Completed

    private var mediumCompletedView: some View {
        HStack(spacing: 14) {
            VStack(spacing: 8) {
                HoursRing(elapsed: entry.todayCompletedHours, standard: entry.settings.standardDayHours)
                    .frame(width: 66, height: 66)

                HStack(spacing: 5) {
                    PulseDot(color: WidgetTheme.doneDot, size: 4)
                    Text("Done")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(WidgetTheme.accent)
                }
            }

            RoundedRectangle(cornerRadius: 0.5)
                .fill(WidgetTheme.cardBorder)
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 8) {
                StatCard(
                    icon: "banknote.fill",
                    value: payText(entry.todayCompletedPay),
                    label: "Earnings",
                    valueColor: WidgetTheme.moneyGreen,
                    iconColor: WidgetTheme.moneyGreen
                )
                StatCard(
                    icon: "clock.fill",
                    value: formattedElapsed(entry.todayCompletedHours),
                    label: "Hours",
                    valueColor: WidgetTheme.accentLight,
                    iconColor: WidgetTheme.accent
                )
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(WidgetTheme.moneyGreen)
                    Text("This week \(formattedElapsed(entry.weeklyHours)) · tap for history")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(WidgetTheme.textTertiary)
                }
            }
        }
        .padding(14)
    }

    // MARK: Medium — Empty

    private var mediumEmptyView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(WidgetTheme.iconGradient)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ready to work?")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(WidgetTheme.textPrimary)
                    Text("One tap starts today's shift")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(WidgetTheme.textTertiary)
                }
            }
            Spacer()
            WidgetActionButton(
                title: "Clock In",
                systemImage: "play.fill",
                tint: WidgetTheme.moneyGreen,
                intent: ClockInIntent()
            )
        }
        .padding(16)
    }

    // MARK: Large — week overview (home screen + StandBy)

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                PulseDot(color: entry.isOpen ? WidgetTheme.workingDot : WidgetTheme.doneDot, size: 5)
                Text(entry.isOpen ? "Working — this week" : "This week")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        entry.isOpen ? WidgetTheme.accentLight : WidgetTheme.accent
                    )
                Spacer()
                Text("\(formattedElapsed(entry.weeklyHours)) / \(formattedElapsed(entry.settings.weeklyStandardHours))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetTheme.textPrimary)
                    .monospacedDigit()
            }

            // 7-day bar chart
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(entry.weekBars) { bar in
                    VStack(spacing: 3) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(WidgetTheme.accent.opacity(0.08))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    bar.hours >= entry.settings.standardDayHours
                                        ? AnyShapeStyle(WidgetTheme.cyan)
                                        : AnyShapeStyle(WidgetTheme.accent)
                                )
                                .frame(height: barHeight(bar.hours))
                        }
                        .frame(height: 44)
                        Text(bar.label)
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundStyle(WidgetTheme.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 2)

            RoundedRectangle(cornerRadius: 0.5)
                .fill(WidgetTheme.cardBorder)
                .frame(height: 1)

            // Week + month totals
            HStack(spacing: 10) {
                largeStat(label: "This week", value: payText(entry.weeklyPay), color: WidgetTheme.moneyGreen, icon: "banknote.fill")
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(WidgetTheme.cardBorder)
                    .frame(width: 1)
                largeStat(label: "This month", value: payText(entry.monthPay), color: WidgetTheme.accentLight, icon: "calendar")
                Spacer(minLength: 0)
                if entry.isOpen {
                    WidgetActionButton(
                        title: "Out",
                        systemImage: "stop.fill",
                        tint: WidgetTheme.accent,
                        intent: ClockOutIntent()
                    )
                }
            }
        }
        .padding(14)
    }

    private func largeStat(label: String, value: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color)
                Text(label.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetTheme.textTertiary)
                    .tracking(0.4)
            }
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private func barHeight(_ hours: Double) -> CGFloat {
        let maxHours = max(entry.settings.standardDayHours, 8)
        let ratio = min(hours / maxHours, 1.0)
        return max(2, CGFloat(ratio) * 44)
    }

    private func payText(_ amount: Double) -> String {
        WidgetBridge.format(amount: amount, currencyCode: entry.settings.currencyCode)
    }

    private func formattedElapsed(_ hours: Double) -> String {
        String(format: "%.1fh", hours)
    }
}

// MARK: - Widget Bundle

@main
struct HoursWidgetBundle: WidgetBundle {
    var body: some Widget {
        HoursSmallWidget()
        HoursMediumWidget()
        HoursLiveActivity()
    }
}

// MARK: - Live Activity Widget

struct HoursLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HoursActivityAttributes.self) { context in
            HoursLiveActivityView(
                attributes: context.attributes,
                state: context.state
            )
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    HoursLiveActivityExpanded(
                        attributes: context.attributes,
                        state: context.state
                    )
                }
            } compactLeading: {
                HoursLiveActivityMinimal(
                    attributes: context.attributes,
                    state: context.state
                )
            } compactTrailing: {
                Text(livePayText(context.state.estimatedPay, currency: context.attributes.currencyCode))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetTheme.moneyGreen)
            } minimal: {
                Image(systemName: "clock.fill")
                    .foregroundStyle(WidgetTheme.accent)
            }
        }
    }

    private func livePayText(_ amount: Double, currency: String) -> String {
        WidgetBridge.format(amount: amount, currencyCode: currency)
    }
}