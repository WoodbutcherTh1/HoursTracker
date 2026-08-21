import SwiftUI

/// Shared neon palette for the Home screen design.
enum HomeNeon {
    static let accent = Color(red: 0.15, green: 0.95, blue: 0.45)
    static let accentDeep = Color(red: 0.05, green: 0.55, blue: 0.28)
    static let bg = Color(red: 0.04, green: 0.05, blue: 0.06)
    static let card = Color(red: 0.09, green: 0.10, blue: 0.12)
    static let coral = Color(red: 0.95, green: 0.28, blue: 0.35)
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
    var greetingFontSize: CGFloat { isVeryCompact ? 24 : (tight ? 27 : 31) }
    var statsSpacing: CGFloat { isCompact ? 6 : 10 }
    /// Matches `HomeAnimatedDoorButton(compact:)`'s real rendered height (door + spacing
    /// + label) plus a small buffer — must stay in sync with that view's own sizing or
    /// the button overflows this frame and overlaps whatever's below it.
    var doorHeight: CGFloat { tight ? 118 : 148 }
    var showStatSparkline: Bool { !isVeryCompact }
    var particleHeight: CGFloat { tight ? 44 : 56 }
}

/// Time-of-day greeting that flips automatically (morning → afternoon → evening → night).
enum DaypartGreeting: Equatable {
    case morning
    case afternoon
    case evening
    case night

    static func current(at date: Date = Date(), calendar: Calendar = .current) -> DaypartGreeting {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        default: return .night
        }
    }

    var title: String {
        switch self {
        case .morning: return L10n.homeGreetingMorning
        case .afternoon: return L10n.homeGreetingAfternoon
        case .evening: return L10n.homeGreetingEvening
        case .night: return L10n.homeGreetingNight
        }
    }

    /// Personalized greeting using the first token of `fullName`.
    /// Empty / whitespace-only names keep the plain `title` unchanged.
    func title(withName fullName: String?) -> String {
        guard let first = Self.firstName(from: fullName) else { return title }
        // Isolate the name so a Latin first name doesn't scramble RTL Hebrew/Arabic.
        let isolated = "\u{2068}\(first)\u{2069}"
        switch self {
        case .morning: return L10n.homeGreetingMorningName(isolated)
        case .afternoon: return L10n.homeGreetingAfternoonName(isolated)
        case .evening: return L10n.homeGreetingEveningName(isolated)
        case .night: return L10n.homeGreetingNightName(isolated)
        }
    }

    /// First whitespace-separated token, or `nil` when the name is blank.
    static func firstName(from fullName: String?) -> String? {
        let trimmed = (fullName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let token = trimmed.split(whereSeparator: \.isWhitespace).first else { return nil }
        let name = String(token)
        return name.isEmpty ? nil : name
    }
}

/// Soft drifting aurora band across the top of Home.
struct HomeAuroraRibbon: View {
    var accent: Color = HomeNeon.accent

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            HomeAuroraCanvas(date: timeline.date, accent: accent)
        }
        .blur(radius: 10)
        .opacity(0.9)
        .allowsHitTesting(false)
    }
}

private struct HomeAuroraCanvas: View {
    let date: Date
    var accent: Color = HomeNeon.accent

    var body: some View {
        Canvas { context, size in
            let t = date.timeIntervalSinceReferenceDate
            let drift = CGFloat(t.truncatingRemainder(dividingBy: 8) / 8)
            for i in 0..<3 {
                let offset = (drift + CGFloat(i) * 0.22).truncatingRemainder(dividingBy: 1)
                var path = Path()
                let yBase = size.height * (0.35 + CGFloat(i) * 0.18)
                path.move(to: CGPoint(x: -size.width * 0.2, y: yBase))
                path.addCurve(
                    to: CGPoint(x: size.width * 1.2, y: yBase + 8),
                    control1: CGPoint(x: size.width * (0.25 + offset * 0.3), y: yBase - 28),
                    control2: CGPoint(x: size.width * (0.55 + offset * 0.25), y: yBase + 34)
                )
                let colors: [Color] = [
                    accent.opacity(0),
                    accent.opacity(0.55 - Double(i) * 0.12),
                    Color.mint.opacity(0.35),
                    accent.opacity(0)
                ]
                context.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: colors),
                        startPoint: CGPoint(x: 0, y: yBase),
                        endPoint: CGPoint(x: size.width, y: yBase)
                    ),
                    style: StrokeStyle(lineWidth: 18 - CGFloat(i) * 4, lineCap: .round)
                )
            }
        }
    }
}

/// Floating luminous dots near the greeting.
struct HomeFloatingParticles: View {
    var accent: Color = HomeNeon.accent

    private let dots: [(x: CGFloat, y: CGFloat, size: CGFloat, speed: Double)] = [
        (0.12, 0.25, 5, 2.8),
        (0.28, 0.70, 3.5, 3.4),
        (0.55, 0.20, 4, 2.2),
        (0.78, 0.55, 3, 3.1),
        (0.90, 0.30, 4.5, 2.6)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                ForEach(Array(dots.enumerated()), id: \.offset) { index, dot in
                    let wave = sin(t * (1.1 + Double(index) * 0.35) / dot.speed)
                    Circle()
                        .fill(accent.opacity(0.35 + 0.25 * (wave + 1) / 2))
                        .frame(width: dot.size, height: dot.size)
                        .blur(radius: 0.4)
                        .position(
                            x: geo.size.width * dot.x,
                            y: geo.size.height * dot.y + CGFloat(wave) * 6
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Soft circular pulse rings behind the hero clock button.
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isOpen: Bool
    @State private var isBusy = false

    /// Scales down with `compact` so the button's real rendered size — door graphic +
    /// spacing + label — actually fits inside whatever `.frame(height:)` the caller
    /// gives it. Previously only the outer frame shrank for shorter screens while these
    /// stayed fixed, so the button silently overflowed its slot and overlapped the
    /// sibling below it.
    private var doorWidth: CGFloat { compact ? 60 : 72 }
    private var doorHeight: CGFloat { compact ? 70 : 86 }

    init(mode: Mode, title: String, compact: Bool = false, accent: Color = HomeNeon.accent, action: @escaping () -> Void) {
        self.mode = mode
        self.title = title
        self.compact = compact
        self.accent = accent
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
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

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
                    HomePulseRings(color: glowColor, size: compact ? 66 : 78)

                    doorScene
                        .frame(width: doorWidth, height: doorHeight)
                        .shadow(color: glowColor.opacity(0.4), radius: 12, y: 5)
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
        .onChange(of: mode) { _, newMode in
            isOpen = (newMode == .clockOut)
            isBusy = false
        }
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
                        .font(.system(size: compact ? 9 : 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(item.value)
                        .font(.system(size: compact ? 13 : 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(accent.opacity(0.85))
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

enum HomeStatIconKind {
    case calendar
    case chart
    case clock
}

/// Compact neon stats card with animated icon + mini waving sparkline.
struct HomeNeonStatCard: View {
    let title: String
    let value: String
    let icon: HomeStatIconKind
    var sparkSeed: Double = 0
    /// This card's value normalized to 0...1 against a reasonable max, so the mini
    /// sparkline's height reflects the real number instead of animating decoratively —
    /// 0 renders as a flat line, higher values sit higher with more motion.
    var level: Double = 0
    var compact: Bool = false
    var showSparkline: Bool = true
    /// User-customizable via the Home color picker; defaults to the original green.
    var accent: Color = HomeNeon.accent

    var body: some View {
        VStack(spacing: compact ? 5 : 8) {
            animatedIcon
                .frame(height: compact ? 22 : 28)

            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .multilineTextAlignment(.center)

            Text(value)
                .font((compact ? Font.callout : Font.title3).weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .minimumScaleFactor(0.55)
                .lineLimit(1)
                .multilineTextAlignment(.center)

            if showSparkline {
                MiniWaveSparkline(seed: sparkSeed, accent: accent, level: level)
                    .frame(height: compact ? 16 : 22)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, compact ? 8 : 12)
        .padding(.horizontal, compact ? 4 : 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: compact ? 14 : 16, style: .continuous)
                .fill(HomeNeon.card.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: compact ? 14 : 16, style: .continuous)
                        .stroke(accent.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: accent.opacity(0.12), radius: 10, y: 2)
        )
    }

    @ViewBuilder
    private var animatedIcon: some View {
        switch icon {
        case .calendar:
            AnimatedCalendarIcon(accent: accent)
        case .chart:
            AnimatedChartIcon(accent: accent)
        case .clock:
            AnimatedClockIcon(accent: accent)
        }
    }
}

/// Month digits flip inside a calendar outline.
struct AnimatedCalendarIcon: View {
    var accent: Color = HomeNeon.accent

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let cycle = (t * 1.2).truncatingRemainder(dividingBy: 12)
            let idx = Int(cycle)
            let frac = cycle - Double(idx)
            let current = (idx % 12) + 1
            let next = ((idx + 1) % 12) + 1

            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(accent, lineWidth: 1.5)
                    .frame(width: 22, height: 20)
                // Binding nubs
                HStack(spacing: 8) {
                    Capsule().fill(accent).frame(width: 2.5, height: 5)
                    Capsule().fill(accent).frame(width: 2.5, height: 5)
                }
                .offset(y: -11)

                Capsule()
                    .fill(accent.opacity(0.7))
                    .frame(width: 14, height: 1)
                    .offset(y: -5)

                ZStack {
                    Text("\(current)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(accent.opacity(1 - frac))
                        .offset(y: -CGFloat(frac) * 8)
                    Text("\(next)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(accent.opacity(frac))
                        .offset(y: (1 - CGFloat(frac)) * 8)
                }
                .frame(width: 14, height: 10)
                .clipped()
                .offset(y: 2)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Bars bounce inside a chart outline.
struct AnimatedChartIcon: View {
    var accent: Color = HomeNeon.accent

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    let h = 6 + 5 * (0.5 + 0.5 * sin(t * 2.8 + Double(i) * 1.1))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(accent)
                        .frame(width: 4, height: h)
                }
            }
            .frame(width: 22, height: 18, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}

/// Clock hands keep ticking inside the circle.
struct AnimatedClockIcon: View {
    var accent: Color = HomeNeon.accent

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle()
                    .stroke(accent, lineWidth: 1.5)
                    .frame(width: 20, height: 20)

                // Hour hand
                Capsule()
                    .fill(accent)
                    .frame(width: 1.5, height: 5)
                    .offset(y: -2)
                    .rotationEffect(.radians(t * 0.35))

                // Minute hand
                Capsule()
                    .fill(accent)
                    .frame(width: 1.2, height: 7)
                    .offset(y: -3)
                    .rotationEffect(.radians(t * 1.8))

                Circle()
                    .fill(.white)
                    .frame(width: 2.5, height: 2.5)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Tiny mountain line for each stats card — its height and liveliness now track a real
/// metric instead of being purely decorative. `level` is the value normalized to 0...1
/// (0 = nothing recorded, flat straight line; 1 = at/above the card's reasonable max,
/// tall and animated). Height and wiggle amplitude both scale with `level`, so "0 hours"
/// reads as a still, flat line and higher values sit visibly higher with more motion.
struct MiniWaveSparkline: View {
    let seed: Double
    var accent: Color = HomeNeon.accent
    var level: Double = 0

    private var clampedLevel: Double { min(max(level, 0), 1) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let level = clampedLevel
            Canvas { context, size in
                var path = Path()
                let steps = 24
                for i in 0...steps {
                    let u = CGFloat(i) / CGFloat(steps)
                    let x = u * size.width
                    let y = size.height - CGFloat(Self.ridge(u: Double(u), t: t, seed: seed, level: level)) * size.height
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(
                    path,
                    with: .color(accent.opacity(0.85)),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                )

                // Traveling glow dot only makes sense once there's something to trace;
                // at level 0 the line has just a subtle idle wobble, so skip the dot.
                guard level > 0.02 else { return }
                let progress = (t * 0.45 + seed * 0.1).truncatingRemainder(dividingBy: 1)
                let px = CGFloat(progress) * size.width
                let py = size.height - CGFloat(Self.ridge(u: progress, t: t, seed: seed, level: level)) * size.height
                let glow = Path(ellipseIn: CGRect(x: px - 2.5, y: py - 2.5, width: 5, height: 5))
                context.fill(glow, with: .color(.white))
            }
        }
        .allowsHitTesting(false)
    }

    /// Small always-present wobble amplitude, independent of `level` — a 0-hours day
    /// still reads as "alive" instead of a dead flat line.
    private static let idleAmplitude = 0.035

    /// Normalized (0...1) line height at horizontal position `u`. `level` scales the
    /// baseline height and adds extra wiggle/wave amplitude on top of the idle motion,
    /// so level 0 is a subtle gentle wobble and higher levels build into a full wave.
    private static func ridge(u: Double, t: Double, seed: Double, level: Double) -> Double {
        let baseline = 0.08 + level * 0.58
        let idleWiggle = idleAmplitude * sin(u * .pi * 2.2 + seed)
        let idleWave = idleAmplitude * 0.6 * sin(t * 2.0 + seed * 1.7)
        let levelWiggle = level * (0.16 * sin(u * .pi * 2.4 + seed) + 0.08 * sin(u * .pi * 5 + seed * 1.4))
        let levelWave = level * 0.10 * sin(u * .pi * 3.2 - t * 3.8 + seed)
        return baseline + idleWiggle + idleWave + levelWiggle + levelWave
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
                let tops = barTopPoints(
                    heights: barHeights,
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

                    if tops.count > 1, barHeights.contains(where: { $0 > 0 }) {
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
        let pulse = (sin(t * (isToday ? 3.4 : 2.2) + Double(index) * 0.7) + 1) / 2
        // Open shift today: breathe the bar instead of showing a misleading empty/00:00 value.
        let liveFill = 0.28 + 0.42 * pulse
        let barHeight = isLiveOpen
            ? CGFloat(liveFill) * barMaxHeight
            : CGFloat(heightFraction) * barMaxHeight
        let showLabel = hours > 0.01 || isToday
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
                } else {
                    Text(labelText)
                        .font(.system(size: 8, weight: isToday ? .bold : .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }
                .foregroundStyle(
                    isToday
                        ? accent.opacity(0.85 + 0.15 * pulse)
                        : Color.white.opacity(hours > 0.01 ? 0.55 : 0.2)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .frame(maxWidth: .infinity)
                .frame(height: labelRowHeight)
                .accessibilityLabel(isLiveOpen ? L10n.homeWeekLoading : labelText)

            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
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
                .opacity(hours > 0.01 || isLiveOpen ? 1 : 0.25)
                .shadow(
                    color: isToday ? accent.opacity(0.55 * pulse) : .clear,
                    radius: isToday ? 6 : 0
                )
        }
        .frame(maxHeight: .infinity)
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
