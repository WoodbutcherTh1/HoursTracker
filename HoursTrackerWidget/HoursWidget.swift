import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Theme

/// Widget color palette — "Aurora": a near-black surface with a green → cyan →
/// purple gradient ring/button, chosen from a set of style mockups the user
/// picked between.
private enum WidgetTheme {
    /// Near-black background.
    static let background = Color(red: 0.020, green: 0.027, blue: 0.039) // #05070A
    static let surface = Color(red: 0.043, green: 0.059, blue: 0.078) // #0B0F14
    static let accent = Color(red: 0.133, green: 0.780, blue: 0.878) // #22C7E0 (aurora cyan)
    static let accentLight = Color(red: 0.486, green: 0.906, blue: 0.949) // #7CE7F2
    static let cyan = Color(red: 0.133, green: 0.780, blue: 0.878) // #22C7E0
    static let purple = Color(red: 0.659, green: 0.333, blue: 0.969) // #A855F7
    static let moneyGreen = Color(red: 0.173, green: 0.961, blue: 0.596) // #2CF598 (aurora green)
    /// Warm "stop" color for Clock Out — matches the phone app's fixed coral
    /// active-session color, kept semantically distinct from the cool aurora gradient.
    static let coral = Color(red: 1.0, green: 0.420, blue: 0.482) // #FF6B7B
    static let textPrimary = Color(red: 0.945, green: 0.988, blue: 0.980) // #F1FCFA
    static let textSecondary = Color.white.opacity(0.5)
    static let textTertiary = Color.white.opacity(0.3)
    static let workingDot = accentLight
    static let doneDot = moneyGreen

    /// Gradient for the active (working) state background.
    static let activeGradient = LinearGradient(
        colors: [
            Color(red: 0.055, green: 0.086, blue: 0.078), // faint green cast
            Color(red: 0.020, green: 0.027, blue: 0.039), // #05070A
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Subtle border for card elements.
    static let cardBorder = Color.white.opacity(0.06)

    /// Aurora glow for active indicators.
    static let glow = moneyGreen.opacity(0.18)

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

    /// The signature Aurora sweep — used on the progress ring and the Clock In button.
    static let auroraSweep = AngularGradient(
        colors: [moneyGreen, cyan, purple, moneyGreen],
        center: .center
    )
    static let auroraButtonGradient = LinearGradient(
        colors: [moneyGreen, cyan, purple],
        startPoint: .leading,
        endPoint: .trailing
    )
    /// Warm counterpart for Clock Out, same treatment as the aurora gradient.
    static let stopButtonGradient = LinearGradient(
        colors: [coral, Color(red: 1.0, green: 0.596, blue: 0.267)],
        startPoint: .leading,
        endPoint: .trailing
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

/// Progress ring showing hours worked toward standard day — the Aurora sweep,
/// a green → cyan → purple gradient with a soft glow, matching Apple's own
/// multi-color activity rings.
private struct HoursRing: View {
    let elapsed: Double
    let standard: Double

    private var progress: Double {
        guard standard > 0 else { return 0 }
        return min(elapsed / standard, 1.0)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 9)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    WidgetTheme.auroraSweep,
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: WidgetTheme.moneyGreen.opacity(0.45), radius: 6)
            // Center text
            VStack(spacing: 0) {
                Text(String(format: "%.1f", elapsed))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(WidgetTheme.textPrimary)
                    .monospacedDigit()
                Text(verbatim: WidgetL10n.hoursUnit)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetTheme.textSecondary)
            }
        }
    }
}

/// Shared visual styling for the widget's Clock In/Out capsule — a solid
/// Aurora-gradient capsule (cool green→cyan→purple for Clock In, warm
/// coral→amber for Clock Out) with dark text for contrast and a soft
/// matching glow.
///
/// Deliberately NOT a generic wrapper around `Button(intent:)`. WidgetKit's
/// interactive buttons are wired up by a build-time "AppIntents metadata
/// extraction" step that statically scans source for `Button(intent:)` call
/// sites with a concrete intent literal. A previous version here boxed the
/// intent as `any AppIntent` — that defeated the scan outright. Switching to
/// a generic `<Intent: AppIntent>` wrapper (storing `intent: Intent` and
/// forwarding it as `Button(intent: intent)`) still isn't enough: the intent
/// at that inner call site is a generic property, not a literal concrete
/// type, which the scanner can also fail to pick up — the button renders but
/// never registers as interactive, and every tap falls through to the
/// widget's `.widgetURL` instead. Each call site below must spell out
/// `Button(intent: ClockInIntent())` / `Button(intent: ClockOutIntent())`
/// literally; only the label styling is shared.
private func widgetActionLabel(title: String, systemImage: String, isClockIn: Bool) -> some View {
    Label(title, systemImage: systemImage)
        .font(.system(size: 12, weight: .heavy, design: .rounded))
        .foregroundStyle(Color.black.opacity(0.82))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            isClockIn ? WidgetTheme.auroraButtonGradient : WidgetTheme.stopButtonGradient,
            in: Capsule()
        )
        .shadow(color: (isClockIn ? WidgetTheme.moneyGreen : WidgetTheme.coral).opacity(0.4), radius: 8, y: 2)
}

/// Round coffee-cup button face for "start break" (label only — each call site
/// spells out `Button(intent: StartBreakIntent())` literally, see above).
private var widgetBreakIcon: some View {
    Image(systemName: "cup.and.saucer.fill")
        .font(.system(size: 11, weight: .heavy))
        .foregroundStyle(WidgetTheme.textPrimary)
        .frame(width: 28, height: 28)
        .background(Color.white.opacity(0.14), in: Circle())
}

/// End of the planned break for an on-break session (nil when working).
private func plannedBreakEnd(for session: WidgetSession) -> Date? {
    guard let start = session.breakStart else { return nil }
    let minutes = WidgetBridge.readSettings().breakTargetMinutes ?? 30
    return start.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
}

/// System-driven countdown to the end of the planned break — ticks by itself on
/// the home screen without timeline reloads. Stops at 0:00 once the break is over.
private func breakCountdown(start: Date, end: Date) -> some View {
    Text(timerInterval: min(start, end)...end, countsDown: true)
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(WidgetTheme.coral)
        .multilineTextAlignment(.trailing)
        .lineLimit(1)
}

/// Paid shift time ticking every second on the home screen — a system timer from the
/// app's live pay curve, so it matches Home, the Watch and the Lock Screen.
private func paidClockTimer(_ curve: LivePayCurve) -> some View {
    Text(timerInterval: curve.paidClockStart...Date.distantFuture, countsDown: false)
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(WidgetTheme.accentLight)
        .multilineTextAlignment(.trailing)
        .lineLimit(1)
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
    /// Live pay curve of the open shift (same figures as the app), when available.
    var livePay: LivePayCurve? = nil
    /// Whether `estimatedPay` is net — follows the app's gross/net choice.
    var payIsNet: Bool = false
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
        let now = Date()
        let entry = buildEntry(at: now)
        // While the paid clock runs, lay out one entry per minute for the next hour
        // from the app's live pay curve: the money ticks up minute by minute with no
        // app involvement (the hours tick by themselves via a system timer). Entries
        // are free; only reloads count against WidgetKit's budget.
        if entry.isOpen, let curve = entry.livePay, !curve.isPaused {
            let entries = [entry] + (1...60).map { minute in
                buildEntry(at: now.addingTimeInterval(TimeInterval(minute * 60)))
            }
            completion(Timeline(entries: entries, policy: .atEnd))
            return
        }
        let refreshInterval: TimeInterval = entry.isOpen ? 180 : 900
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(refreshInterval))))
    }

    private var sampleBars: [DayBar] {
        let labels = ["S", "M", "T", "W", "T", "F", "S"]
        let hours = [0.0, 8.4, 8.1, 8.7, 8.2, 4.6, 0.0]
        return labels.enumerated().map { DayBar(id: $0.offset, label: $0.element, hours: hours[$0.offset]) }
    }

    private func buildEntry(at date: Date = Date()) -> HoursEntry {
        let settings = WidgetBridge.readSettings()
        let sessions = WidgetBridge.readSessions()
        let calendar = Calendar.current
        let showsNet = WidgetBridge.livePayShowsNet

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
            // Prefer the app's live curve (real pay engine: tiers, rest-day rates, net)
            // so the widget shows exactly what Home shows; fall back to the quick
            // estimate if the app hasn't written one yet.
            let curve = WidgetBridge.readLivePay().flatMap { $0.sessionID == open.id ? $0 : nil }
            let elapsed = curve?.paidHours(at: date) ?? open.effectiveHours
            let pay = curve?.pay(at: date, net: showsNet)
                ?? WidgetBridge.estimatePay(elapsedHours: elapsed, settings: settings)
            return HoursEntry(
                date: date, isOpen: true, session: open,
                elapsedHours: elapsed, estimatedPay: pay,
                todayCompletedHours: completedHours, todayCompletedPay: completedPay,
                weeklyHours: weeklyHours, weeklyPay: weeklyPay,
                monthHours: monthHours, monthPay: monthPay,
                weekBars: bars, settings: settings,
                livePay: curve, payIsNet: curve != nil && showsNet
            )
        } else {
            return HoursEntry(
                date: date, isOpen: false, session: nil,
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
                .environment(\.layoutDirection, WidgetL10n.layoutDirection)
                .containerBackground(for: .widget) {
                    WidgetBackground()
                }
        }
        .configurationDisplayName(WidgetL10n.displayName)
        .description(WidgetL10n.smallDescription)
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
                PulseDot(color: session.isOnBreak ? WidgetTheme.coral : WidgetTheme.workingDot, size: 5)
                Text(verbatim: session.isOnBreak ? WidgetL10n.onBreak : WidgetL10n.working)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(session.isOnBreak ? WidgetTheme.coral : WidgetTheme.accentLight)
                Spacer()
                if !session.isOnBreak {
                    Button(intent: StartBreakIntent()) {
                        widgetBreakIcon
                    }
                    .buttonStyle(.plain)
                }
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
                    if let breakEnd = plannedBreakEnd(for: session) {
                        breakCountdown(start: session.breakStart ?? entry.date, end: breakEnd)
                    } else if let curve = entry.livePay, !curve.isPaused {
                        paidClockTimer(curve)
                    } else {
                        Text(verbatim: WidgetL10n.today)
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundStyle(WidgetTheme.textTertiary)
                            .textCase(.uppercase)
                    }
                }
            }

            // Clock out (or back from break) — one tap from the home screen.
            if session.isOnBreak {
                Button(intent: EndBreakIntent()) {
                    widgetActionLabel(title: WidgetL10n.imBack, systemImage: "arrow.uturn.backward", isClockIn: true)
                }
                .frame(maxWidth: .infinity)
            } else {
                Button(intent: ClockOutIntent()) {
                    widgetActionLabel(title: WidgetL10n.clockOut, systemImage: "stop.fill", isClockIn: false)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
    }

    // MARK: Completed State

    private var completedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status bar
            HStack(spacing: 5) {
                PulseDot(color: WidgetTheme.doneDot, size: 5)
                Text(verbatim: WidgetL10n.done)
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
                    Text(verbatim: WidgetL10n.gross)
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
                Text(verbatim: WidgetL10n.shiftComplete)
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
            Text(verbatim: WidgetL10n.startYourShift)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetTheme.textPrimary)
            Button(intent: ClockInIntent()) {
                widgetActionLabel(title: WidgetL10n.clockIn, systemImage: "play.fill", isClockIn: true)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(12)
    }

    private func payText(_ amount: Double) -> String {
        WidgetBridge.format(amount: amount, currencyCode: entry.settings.currencyCode)
    }

    private func formattedHours(_ hours: Double) -> String {
        WidgetL10n.hoursShort(hours)
    }
}

// MARK: - Medium + Large Widget (one configuration, adaptive layout)

struct HoursMediumWidget: Widget {
    let kind: String = "HoursMediumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HoursTimelineProvider()) { entry in
            HoursHomeWidgetView(entry: entry)
                .environment(\.layoutDirection, WidgetL10n.layoutDirection)
                .containerBackground(for: .widget) {
                    WidgetBackground()
                }
        }
        .configurationDisplayName(WidgetL10n.displayName)
        .description(WidgetL10n.mediumDescription)
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
                    PulseDot(color: entry.session?.isOnBreak == true ? WidgetTheme.coral : WidgetTheme.workingDot, size: 4)
                    Text(verbatim: entry.session?.isOnBreak == true ? WidgetL10n.onBreak : WidgetL10n.working)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(entry.session?.isOnBreak == true ? WidgetTheme.coral : WidgetTheme.accentLight)
                }

                if let session = entry.session, let breakEnd = plannedBreakEnd(for: session) {
                    breakCountdown(start: session.breakStart ?? entry.date, end: breakEnd)
                } else if let curve = entry.livePay, !curve.isPaused {
                    paidClockTimer(curve)
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
                    label: WidgetL10n.earnings,
                    valueColor: WidgetTheme.moneyGreen,
                    iconColor: WidgetTheme.moneyGreen
                )
                StatCard(
                    icon: "clock.fill",
                    value: formattedElapsed(entry.elapsedHours),
                    label: WidgetL10n.elapsed,
                    valueColor: WidgetTheme.accentLight,
                    iconColor: WidgetTheme.accent
                )
                HStack(spacing: 6) {
                    if entry.session?.isOnBreak == true {
                        Button(intent: EndBreakIntent()) {
                            widgetActionLabel(title: WidgetL10n.back, systemImage: "arrow.uturn.backward", isClockIn: true)
                        }
                    } else {
                        Button(intent: StartBreakIntent()) {
                            widgetBreakIcon
                        }
                        .buttonStyle(.plain)
                    }
                    Button(intent: ClockOutIntent()) {
                        widgetActionLabel(title: WidgetL10n.outShort, systemImage: "stop.fill", isClockIn: false)
                    }
                }
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
                    Text(verbatim: WidgetL10n.done)
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
                    label: WidgetL10n.earnings,
                    valueColor: WidgetTheme.moneyGreen,
                    iconColor: WidgetTheme.moneyGreen
                )
                StatCard(
                    icon: "clock.fill",
                    value: formattedElapsed(entry.todayCompletedHours),
                    label: WidgetL10n.hours,
                    valueColor: WidgetTheme.accentLight,
                    iconColor: WidgetTheme.accent
                )
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(WidgetTheme.moneyGreen)
                    Text(verbatim: WidgetL10n.thisWeekTapForHistory(formattedElapsed(entry.weeklyHours)))
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
                    Text(verbatim: WidgetL10n.readyToWork)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(WidgetTheme.textPrimary)
                    Text(verbatim: WidgetL10n.oneTapStarts)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(WidgetTheme.textTertiary)
                }
            }
            Spacer()
            Button(intent: ClockInIntent()) {
                widgetActionLabel(title: WidgetL10n.clockIn, systemImage: "play.fill", isClockIn: true)
            }
        }
        .padding(16)
    }

    // MARK: Large — week overview (home screen + StandBy)

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                PulseDot(color: entry.isOpen ? WidgetTheme.workingDot : WidgetTheme.doneDot, size: 5)
                Text(verbatim: entry.isOpen ? WidgetL10n.workingThisWeek : WidgetL10n.thisWeek)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        entry.isOpen ? WidgetTheme.accentLight : WidgetTheme.accent
                    )
                Spacer()
                Text(verbatim: "\(formattedElapsed(entry.weeklyHours)) / \(formattedElapsed(entry.settings.weeklyStandardHours))")
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
                                        ? AnyShapeStyle(WidgetTheme.moneyGreen)
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
                largeStat(label: WidgetL10n.thisWeek, value: payText(entry.weeklyPay), color: WidgetTheme.moneyGreen, icon: "banknote.fill")
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(WidgetTheme.cardBorder)
                    .frame(width: 1)
                largeStat(label: WidgetL10n.thisMonth, value: payText(entry.monthPay), color: WidgetTheme.accentLight, icon: "calendar")
                Spacer(minLength: 0)
                if entry.session?.isOnBreak == true {
                    Button(intent: EndBreakIntent()) {
                        widgetActionLabel(title: WidgetL10n.back, systemImage: "arrow.uturn.backward", isClockIn: true)
                    }
                } else if entry.isOpen {
                    Button(intent: ClockOutIntent()) {
                        widgetActionLabel(title: WidgetL10n.outShort, systemImage: "stop.fill", isClockIn: false)
                    }
                } else {
                    Button(intent: ClockInIntent()) {
                        widgetActionLabel(title: WidgetL10n.inShort, systemImage: "play.fill", isClockIn: true)
                    }
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
        WidgetL10n.hoursShort(hours)
    }
}

// MARK: - Widget Bundle

@main
struct HoursWidgetBundle: WidgetBundle {
    var body: some Widget {
        HoursSmallWidget()
        HoursMediumWidget()
        HoursLockScreenWidget()
        HoursLiveActivity()
        if #available(iOS 18.0, *) {
            ShiftControl()
        }
    }
}

// MARK: - Control Center control (iOS 18)

/// Clock in / out from Control Center, the Lock Screen controls or the Action
/// Button. On while a shift is open (read from the app's snapshot); tapping
/// runs `ToggleShiftIntent`, which the app performs in the background.
@available(iOS 18.0, *)
struct ShiftControl: ControlWidget {
    static let kind = "com.hourstracker.app.shiftControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: ShiftControlValue()) { isWorking in
            ControlWidgetToggle(
                WidgetL10n.displayName,
                isOn: isWorking,
                action: ToggleShiftIntent()
            ) { on in
                Label(
                    on ? WidgetL10n.clockOut : WidgetL10n.clockIn,
                    systemImage: on ? "stop.circle.fill" : "play.circle.fill"
                )
            }
        }
        .displayName("HoursTracker")
        .description("Clock in and out")
    }
}

@available(iOS 18.0, *)
struct ShiftControlValue: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        WidgetBridge.openSession(from: WidgetBridge.readSessions()) != nil
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
            .environment(\.layoutDirection, WidgetL10n.layoutDirection)
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
                if let breakStart = context.state.breakStart, let breakEnd = context.state.breakEnd {
                    // Break countdown, driven by the system clock (no app pushes needed).
                    Text(timerInterval: min(breakStart, breakEnd)...breakEnd, countsDown: true)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(WidgetTheme.coral)
                        .frame(maxWidth: 52)
                } else {
                    Text(livePayText(context.state.estimatedPay, currency: context.attributes.currencyCode))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(WidgetTheme.moneyGreen)
                }
            } minimal: {
                Image(systemName: context.state.isOnBreak ? "cup.and.saucer.fill" : "clock.fill")
                    .foregroundStyle(context.state.isOnBreak ? WidgetTheme.coral : WidgetTheme.accent)
            }
        }
    }

    private func livePayText(_ amount: Double, currency: String) -> String {
        WidgetBridge.format(amount: amount, currencyCode: currency)
    }
}