import SwiftUI

/// Shared neon palette for the Home screen design.
///
/// The screen background deliberately isn't here any more: it's user-customizable and
/// lives in `AppBackgroundTheme.shared.background`, whose default is the exact color this
/// enum used to hold. Keeping a second copy would let the two drift apart.
enum HomeNeon {
    static let accent = Color(red: 0.15, green: 0.95, blue: 0.45)
    static let accentDeep = Color(red: 0.05, green: 0.55, blue: 0.28)
    static let card = Color(red: 0.09, green: 0.10, blue: 0.12)
    /// The clocked-in state colour — same value as `DS.Palette.clockedIn`.
    static let coral = DS.Palette.clockedIn
    static let coralDeep = Color(red: 0.72, green: 0.12, blue: 0.22)
}

/// Width- and height-based spacing/type for Home so SE / 13 mini stay readable, and so
/// the whole dashboard fits without scrolling on ordinary-height phones too. Originally
/// only width drove compaction; that under-shot on standard-width phones once the nav
/// bar + a taller system tab bar (iOS 26's floating style) left less vertical room than
/// this layout assumed, so the sparkline row ended up needing a scroll to reach.
struct HomeLayoutMetrics {
    let width: CGFloat
    let height: CGFloat

    /// iPhone SE / 13 mini class (~375pt and below after padding).
    var isCompact: Bool { width < 390 }
    var isVeryCompact: Bool { width < 350 }
    /// Available height (already safe-area-reduced) is tighter than this layout's
    /// generous spacing was tuned for.
    var isShort: Bool { height < 700 }

    private var tight: Bool { isCompact || isShort }

    var horizontalPadding: CGFloat { isVeryCompact ? 12 : (isCompact ? 14 : 18) }
    var stackSpacing: CGFloat { tight ? 10 : 13 }
    var statsSpacing: CGFloat { isCompact ? 6 : 10 }
    /// Matches `HomeAnimatedDoorButton(compact:)`'s real rendered height (door + spacing
    /// + label) plus a small buffer — must stay in sync with that view's own sizing or
    /// the button overflows this frame and overlaps whatever's below it.
    var doorHeight: CGFloat { tight ? 118 : 148 }
}

/// Soft circular pulse rings (the Account sheet's hero; Home no longer uses them).
struct HomePulseRings: View {
    var color: Color = HomeNeon.accent
    var size: CGFloat = 132

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<2, id: \.self) { ring in
                    let cycle = (t / (2.6 + Double(ring) * 0.7) + Double(ring) * 0.4)
                        .truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(color.opacity(0.22 * (1 - cycle)), lineWidth: 1.25)
                        .frame(
                            width: size + 18 + CGFloat(cycle) * 42,
                            height: size + 18 + CGFloat(cycle) * 42
                        )
                }

                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: size + 28, height: size + 28)
                    .blur(radius: 22)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Clock-in door: closed + green → press → opens + turns red.
/// Clock-out door: open + red → press → closes + turns green.
struct HomeAnimatedDoorButton: View {
    enum Mode {
        case clockIn
        case clockOut
    }

    let mode: Mode
    let title: String
    let action: () -> Void
    var compact: Bool = false
    /// The "closed" (clock-in) door color — user-customizable. The "open" (clock-out /
    /// active-session) coral stays fixed since it's a semantic state color, not decor.
    var accent: Color = HomeNeon.accent
    /// Clock Out only: the door breathes (1.0 ↔ 1.03 over 3 s) to say the shift is
    /// running. Under Reduce Motion it stands still inside a thin ring of `stateColor`.
    var breathes: Bool = false
    /// A sheet covers Home — hold still (the ring, if any, stays).
    var breathingPaused: Bool = false
    /// Coral while working, amber on a break.
    var stateColor: Color = HomeNeon.coral

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var isOpen: Bool
    @State private var isBusy = false

    /// Scales down with `compact` so the button's real rendered size — door graphic +
    /// spacing + label — actually fits inside whatever `.frame(height:)` the caller
    /// gives it. Previously only the outer frame shrank for shorter screens while these
    /// stayed fixed, so the button silently overflowed its slot and overlapped the
    /// sibling below it.
    private var doorWidth: CGFloat { compact ? 60 : 72 }
    private var doorHeight: CGFloat { compact ? 70 : 86 }

    init(
        mode: Mode,
        title: String,
        compact: Bool = false,
        accent: Color = HomeNeon.accent,
        breathes: Bool = false,
        breathingPaused: Bool = false,
        stateColor: Color = HomeNeon.coral,
        action: @escaping () -> Void
    ) {
        self.mode = mode
        self.title = title
        self.compact = compact
        self.accent = accent
        self.breathes = breathes
        self.breathingPaused = breathingPaused
        self.stateColor = stateColor
        self.action = action
        _isOpen = State(initialValue: mode == .clockOut)
    }

    private var doorColor: Color {
        isOpen ? HomeNeon.coral : accent
    }

    private var glowColor: Color {
        isOpen ? HomeNeon.coral : accent
    }

    var body: some View {
        Button {
            guard !isBusy else { return }
            isBusy = true
            // Clock Out's one haptic is the Day Summary's success tap when it appears —
            // a second buzz here would crowd it.
            if mode == .clockIn {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }

            let duration: TimeInterval = reduceMotion ? 0.2 : 0.55
            withAnimation(.spring(response: duration, dampingFraction: 0.78)) {
                switch mode {
                case .clockIn:
                    isOpen = true
                case .clockOut:
                    isOpen = false
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                action()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    isBusy = false
                    isOpen = (mode == .clockOut)
                }
            }
        } label: {
            VStack(spacing: compact ? 6 : 10) {
                ZStack {
                    if breathes && reduceMotion {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(stateColor, lineWidth: 2)
                            .frame(width: doorWidth + 12, height: doorHeight + 12)
                    }

                    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isBreathing)) { context in
                        doorScene
                            .frame(width: doorWidth, height: doorHeight)
                            .shadow(color: glowColor.opacity(0.3), radius: 10, y: 4)
                            .scaleEffect(breathingScale(at: context.date))
                    }
                }
                .frame(width: doorWidth + (compact ? 44 : 56), height: doorHeight + (compact ? 22 : 28))

                Text(title)
                    .font(compact ? .footnote.weight(.bold) : .subheadline.weight(.bold))
                    .foregroundStyle(doorColor)
                    .shadow(color: doorColor.opacity(0.35), radius: 5)
            }
        }
        .buttonStyle(ScalePressButtonStyle())
        .disabled(isBusy)
        .accessibilityLabel(title)
        .accessibilityIdentifier(mode == .clockIn ? "home.clockIn" : "home.clockOut")
        .onChange(of: mode) { _, newMode in
            isOpen = (newMode == .clockOut)
            isBusy = false
        }
    }

    /// Breathing runs only while a shift is running AND the app is in front AND no
    /// sheet covers Home AND Reduce Motion is off. Anything else holds it at 1.0.
    private var isBreathing: Bool {
        breathes && !breathingPaused && scenePhase == .active && !reduceMotion
    }

    /// 1.0 → 1.03 → 1.0 every 3 s; 1 when not breathing.
    private func breathingScale(at date: Date) -> CGFloat {
        guard isBreathing else { return 1 }
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3
        return 1 + 0.015 * (1 - cos(phase * 2 * .pi))
    }

    private var doorScene: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        return ZStack {
            // Outer frame shell
            shape
                .fill(Color(red: 0.10, green: 0.11, blue: 0.13))

            // Everything inside the doorway is clipped so the leaf opens *into* the frame.
            ZStack(alignment: .leading) {
                // Interior room — glows red when the door is open
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isOpen
                                ? [
                                    Color(red: 0.35, green: 0.05, blue: 0.08),
                                    HomeNeon.coral.opacity(0.55),
                                    Color.black.opacity(0.9)
                                ]
                                : [
                                    Color.black.opacity(0.92),
                                    Color.black.opacity(0.75)
                                ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        if isOpen {
                            RadialGradient(
                                colors: [
                                    HomeNeon.coral.opacity(0.55),
                                    HomeNeon.coral.opacity(0.0)
                                ],
                                center: .center,
                                startRadius: 3,
                                endRadius: 42
                            )
                            .blendMode(.plusLighter)
                        }
                    }
                    .padding(5)

                // Door leaf swings inward (hinge on leading edge)
                doorLeaf
                    .padding(5)
                    .rotation3DEffect(
                        .degrees(isOpen ? -88 : 0),
                        axis: (x: 0, y: 1, z: 0),
                        anchor: .leading,
                        anchorZ: 0,
                        perspective: 0.85
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous).inset(by: 3))

            // Frame rim on top
            shape
                .stroke(doorColor.opacity(0.7), lineWidth: 2)
                .allowsHitTesting(false)

            // Inner threshold line
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                .padding(4)
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.45), value: isOpen)
    }

    private var doorLeaf: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            doorColor,
                            doorColor.opacity(0.75),
                            (isOpen ? HomeNeon.coralDeep : accent.darkened())
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                )

            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.black.opacity(0.18), lineWidth: 1.2)
                    .frame(maxHeight: .infinity)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.black.opacity(0.18), lineWidth: 1.2)
                    .frame(maxHeight: .infinity)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 9)
            .padding(.trailing, 7)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.95), Color.white.opacity(0.55)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 4
                    )
                )
                .frame(width: 7, height: 7)
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                .padding(.trailing, 8)
        }
        .animation(.easeInOut(duration: 0.45), value: isOpen)
    }
}

/// Circular hero clock-in / clock-out button (legacy, kept for reuse).
struct HomePrimaryActionButton: View {
    let title: String
    let systemImage: String
    let colors: [Color]
    let glow: Color
    let action: () -> Void

    private let diameter: CGFloat = 128

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.55),
                                glow.opacity(0.9),
                                glow.opacity(0.25)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: diameter + 10, height: diameter + 10)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                colors.first?.opacity(1) ?? glow,
                                colors.last ?? glow
                            ],
                            center: UnitPoint(x: 0.35, y: 0.28),
                            startRadius: 4,
                            endRadius: diameter * 0.72
                        )
                    )
                    .frame(width: diameter, height: diameter)
                    .overlay {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.28), Color.white.opacity(0)],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .padding(3)
                    }
                    .shadow(color: glow.opacity(0.55), radius: 22, y: 10)

                VStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 28, weight: .semibold))
                    Text(title)
                        .font(.headline.weight(.bold))
                }
                .foregroundStyle(.white)
            }
            .frame(width: diameter + 12, height: diameter + 12)
            .contentShape(Circle())
        }
        .buttonStyle(ScalePressButtonStyle())
        .accessibilityLabel(title)
    }
}

/// Brand mark: Hours (white) + Tracker (neon) — or the user's own replacement text
/// from the Home color picker, drawn in the accent color.
///
/// The two-tone mark is split across two `Text`s, so it is laid out by an `HStack` whose
/// order flips under an RTL interface language. That rendered the product name backwards
/// ("TrackerHours") in Hebrew/Arabic, so the stack is pinned `.leftToRight`: a wordmark
/// is a name, not prose, and must read the same way in every interface language. A custom
/// wordmark is a single `Text` instead, left to the system's bidi handling so someone can
/// put their own Hebrew or Arabic name here and have it render correctly.
struct HomeBrandTitle: View {
    var accent: Color = HomeNeon.accent
    @ObservedObject private var wordmark = HomeWordmark.shared

    var body: some View {
        Group {
            if let custom = wordmark.customText {
                Text(custom)
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel(custom)
            } else {
                HStack(spacing: 0) {
                    Text(verbatim: "Hours")
                        .foregroundStyle(.white)
                    Text(verbatim: "Tracker")
                        .foregroundStyle(accent)
                }
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.brandName)
            }
        }
        .font(.headline.weight(.bold))
    }
}

/// The same three Home stats, squeezed into one horizontal strip for the clocked-in
/// screen. While a shift is running the live timer is the subject and these are context,
/// so they stay readable but visually step back: one short row instead of three tall
/// cards, no sparklines, lower contrast.
struct HomeCompactStatsStrip: View {
    struct Item: Identifiable {
        let id: String
        let title: String
        let value: String
    }

    let items: [Item]
    var accent: Color = HomeNeon.accent
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1, height: 24)
                }

                VStack(spacing: 2) {
                    Text(item.title)
                        .dsFont(.meta, weight: .medium)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(item.value)
                        .htFont(size: 15, relativeTo: .subheadline, weight: .semibold, design: .rounded)
                        .monospacedDigit()
                        .environment(\.layoutDirection, .leftToRight)
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, compact ? 7 : 9)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(HomeNeon.card.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

/// Week hours chart: bar heights match real daily hours; glow traces the true tops.
struct HomeWeekSparkline: View {
    let dailyHours: [Double]
    let weekdayLabels: [String]
    /// Index 0...6 of "today" within the current week row; that day glows.
    var highlightedDayIndex: Int? = nil
    /// When true, today's column shows a live "loading" state instead of a frozen 00:00
    /// (open shifts are intentionally excluded from `dailyHours` totals).
    var isTodayShiftOpen: Bool = false
    var accent: Color = HomeNeon.accent

    private let loopSeconds: Double = 5.5
    private let chartHeight: CGFloat = 56
    private let labelRowHeight: CGFloat = 13

    private var hours: [Double] {
        dailyHours.count == 7 ? dailyHours : Array(repeating: 0, count: 7)
    }

    private var heights: [Double] {
        HistoryPeriodHelper.normalizedDayHeights(hours)
    }

    private var weekTotal: Double {
        hours.reduce(0, +)
    }

    static func liveOpenHeightFraction(pulseTime t: Double, index: Int, isToday: Bool) -> Double {
        let pulse = liveOpenPulse(pulseTime: t, index: index, isToday: isToday)
        return 0.28 + 0.42 * pulse
    }

    var body: some View {
        VStack(spacing: 7) {
            chart

            weekdayRow

            Text(L10n.homeWeekTotal(HistoryPeriodHelper.formatHoursClock(weekTotal)))
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.45))
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 4)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.homeWeekTotal(HistoryPeriodHelper.formatHoursClock(weekTotal))
        )
    }

    private var chart: some View {
        GeometryReader { geo in
            let barHeights = heights
            let columnWidth = geo.size.width / 7
            let barMaxHeight = max(0, geo.size.height - labelRowHeight - 4)

            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let ridgeHeights = ridgeHeightFractions(baseHeights: barHeights, pulseTime: t)
                let tops = barTopPoints(
                    heights: ridgeHeights,
                    columnWidth: columnWidth,
                    barMaxHeight: barMaxHeight,
                    chartHeight: geo.size.height
                )
                let ridge = ridgePath(points: tops)
                let travel = CGFloat((t / loopSeconds).truncatingRemainder(dividingBy: 1))
                let trailStart = max(0, travel - 0.18)

                ZStack(alignment: .topLeading) {
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(0..<7, id: \.self) { index in
                            dayColumn(
                                index: index,
                                hours: hours[index],
                                heightFraction: barHeights[index],
                                barMaxHeight: barMaxHeight,
                                pulseTime: t
                            )
                            .frame(width: columnWidth)
                        }
                    }

                    if tops.count > 1, ridgeHeights.contains(where: { $0 > 0 }) {
                        ridge
                            .stroke(accent.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                        ridge
                            .trim(from: trailStart, to: travel)
                            .stroke(
                                LinearGradient(
                                    colors: [accent.opacity(0.05), accent.opacity(0.9), Color.white.opacity(0.95)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                            )
                            .shadow(color: accent.opacity(0.55), radius: 5)

                        if let point = pointAlongPolyline(tops, progress: travel) {
                            travelingShine(at: point, pulse: t)
                        }
                    }
                }
            }
        }
        .frame(height: chartHeight + labelRowHeight)
    }

    private func dayColumn(
        index: Int,
        hours: Double,
        heightFraction: Double,
        barMaxHeight: CGFloat,
        pulseTime t: Double
    ) -> some View {
        let isToday = highlightedDayIndex == index
        let isLiveOpen = isToday && isTodayShiftOpen
        let pulse = Self.liveOpenPulse(pulseTime: t, index: index, isToday: isToday)
        // Open shift today: breathe the bar instead of showing a misleading empty/00:00 value.
        let liveFill = Self.liveOpenHeightFraction(pulseTime: t, index: index, isToday: isToday)
        let barHeight = isLiveOpen
            ? CGFloat(liveFill) * barMaxHeight
            : CGFloat(heightFraction) * barMaxHeight
        // Only days with hours get a value. Today with nothing yet stays marked by its
        // glowing bar and weekday, not by a lone "00:00" floating over an empty column.
        let showLabel = hours > 0.01
        let labelText: String = {
            if isLiveOpen { return L10n.homeWeekLoading }
            if showLabel { return HistoryPeriodHelper.formatHoursClock(hours) }
            return " "
        }()

        return VStack(spacing: 4) {
            Group {
                if isLiveOpen {
                    Text(labelText)
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .foregroundStyle(accent.opacity(0.55 + 0.1 * pulse))
                } else {
                    Text(labelText)
                        .font(.system(size: 8, weight: isToday ? .bold : .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(
                            isToday
                                ? accent.opacity(0.85 + 0.15 * pulse)
                                : Color.white.opacity(hours > 0.01 ? 0.55 : 0.2)
                        )
                }
            }
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .frame(maxWidth: .infinity)
                .frame(height: labelRowHeight)
                .accessibilityLabel(isLiveOpen ? L10n.homeWeekLoading : labelText)

            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isLiveOpen
                            ? [
                                accent.opacity(0.45),
                                accent.opacity(0.18)
                            ]
                            : [
                                accent.opacity(isToday ? 0.95 : 0.55),
                                accent.opacity(isToday ? 0.45 : 0.18)
                            ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(
                    width: isToday ? 12 : 9,
                    height: max(barHeight, (hours > 0.01 || isLiveOpen) ? 3 : 2)
                )
                // Open today: translucent (~0.45) so it never matches finished days.
                .opacity(isLiveOpen ? 0.45 : (hours > 0.01 ? 1 : 0.25))
                .shadow(
                    color: isLiveOpen
                        ? accent.opacity(0.2 * pulse)
                        : (isToday ? accent.opacity(0.55 * pulse) : .clear),
                    radius: isToday ? (isLiveOpen ? 3 : 6) : 0
                )
        }
        .frame(maxHeight: .infinity)
        .opacity(isLiveOpen ? 0.85 : 1)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { index, label in
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let isToday = highlightedDayIndex == index
                    let pulse = (sin(t * (isToday ? 3.4 : 2.2) + Double(index) * 0.7) + 1) / 2
                    VStack(spacing: 4) {
                        Text(label)
                            .font(.caption2.weight(isToday ? .bold : .semibold))
                            .foregroundStyle(
                                isToday
                                    ? accent.opacity(0.75 + 0.25 * pulse)
                                    : Color.white.opacity(0.40 + 0.25 * pulse)
                            )
                            .shadow(color: isToday ? accent.opacity(0.7 * pulse) : .clear, radius: isToday ? 6 : 0)

                        ZStack {
                            if isToday {
                                Circle()
                                    .fill(accent.opacity(0.28 + 0.35 * pulse))
                                    .frame(width: 14 + 4 * pulse, height: 14 + 4 * pulse)
                                    .blur(radius: 3)
                            }
                            Circle()
                                .fill(accent.opacity(isToday ? (0.75 + 0.25 * pulse) : (0.30 + 0.35 * pulse)))
                                .frame(width: isToday ? 7 : 5, height: isToday ? 7 : 5)
                                .shadow(
                                    color: accent.opacity(isToday ? 0.85 * pulse : 0.35 * pulse),
                                    radius: isToday ? 5 : 2
                                )
                        }
                        .frame(height: 12)
                    }
                    .frame(maxWidth: .infinity)
                    .scaleEffect(isToday ? 1.08 : 1.0)
                }
            }
        }
    }

    private func travelingShine(at point: CGPoint, pulse t: Double) -> some View {
        let twinkle = 0.75 + 0.25 * sin(t * 8)
        return ZStack {
            Circle()
                .fill(accent.opacity(0.28 * twinkle))
                .frame(width: 28, height: 28)
                .blur(radius: 8)
            Circle()
                .stroke(accent.opacity(0.7), lineWidth: 1.5)
                .frame(width: 16, height: 16)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white, Color.white.opacity(0.95), accent, accent.opacity(0.2)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 8
                    )
                )
                .frame(width: 11, height: 11)
                .shadow(color: accent.opacity(0.95), radius: 8)
            Circle()
                .fill(Color.white.opacity(0.9 * twinkle))
                .frame(width: 3, height: 3)
                .offset(x: -2, y: -2)
        }
        .position(point)
    }

    /// Tops of bars in chart coordinates (label row sits above the bars).
    private func ridgeHeightFractions(baseHeights: [Double], pulseTime t: Double) -> [Double] {
        guard isTodayShiftOpen, let highlightedDayIndex, baseHeights.indices.contains(highlightedDayIndex) else {
            return baseHeights
        }

        return baseHeights.enumerated().map { index, fraction in
            guard index == highlightedDayIndex else { return fraction }
            return Self.liveOpenHeightFraction(pulseTime: t, index: index, isToday: true)
        }
    }

    private func barTopPoints(
        heights: [Double],
        columnWidth: CGFloat,
        barMaxHeight: CGFloat,
        chartHeight: CGFloat
    ) -> [CGPoint] {
        heights.enumerated().map { index, fraction in
            let barHeight = CGFloat(fraction) * barMaxHeight
            let x = columnWidth * (CGFloat(index) + 0.5)
            let y = chartHeight - max(barHeight, fraction > 0 ? 3 : 2)
            return CGPoint(x: x, y: y)
        }
    }

    private func ridgePath(points: [CGPoint]) -> Path {
        guard points.count > 1 else { return Path() }
        var path = Path()
        path.move(to: points[0])
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: mid, control: previous)
            if index == points.count - 1 {
                path.addQuadCurve(to: current, control: current)
            }
        }
        return path
    }

    private static func liveOpenPulse(pulseTime t: Double, index: Int, isToday: Bool) -> Double {
        (sin(t * (isToday ? 3.4 : 2.2) + Double(index) * 0.7) + 1) / 2
    }

    private func pointAlongPolyline(_ points: [CGPoint], progress: CGFloat) -> CGPoint? {
        guard points.count > 1 else { return nil }
        let clamped = min(max(progress, 0), 0.999)
        let segments = points.count - 1
        let exact = clamped * CGFloat(segments)
        let index = min(Int(exact), segments - 1)
        let frac = exact - CGFloat(index)
        let a = points[index]
        let b = points[index + 1]
        return CGPoint(x: a.x + (b.x - a.x) * frac, y: a.y + (b.y - a.y) * frac)
    }
}
