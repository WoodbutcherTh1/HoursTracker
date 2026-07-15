import SwiftUI

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
}

/// Soft drifting aurora band across the top of Home.
struct HomeAuroraRibbon: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
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
                    context.stroke(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [
                                Color.cyan.opacity(0),
                                Color.teal.opacity(0.45 - Double(i) * 0.1),
                                Color.mint.opacity(0.35),
                                Color.cyan.opacity(0)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 18 - CGFloat(i) * 4, lineCap: .round)
                    )
                }
            }
        }
        .blur(radius: 10)
        .opacity(0.85)
        .allowsHitTesting(false)
    }
}

/// Floating luminous dots near the greeting.
struct HomeFloatingParticles: View {
    private let dots: [(x: CGFloat, y: CGFloat, size: CGFloat, speed: Double)] = [
        (0.12, 0.25, 5, 2.8),
        (0.28, 0.70, 3.5, 3.4),
        (0.55, 0.20, 4, 2.2),
        (0.78, 0.55, 3, 3.1),
        (0.90, 0.30, 4.5, 2.6)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                ForEach(Array(dots.enumerated()), id: \.offset) { index, dot in
                    let wave = sin(t * (1.1 + Double(index) * 0.35) / dot.speed)
                    Circle()
                        .fill(Color.cyan.opacity(0.35 + 0.25 * (wave + 1) / 2))
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

/// Breathing glow rings around the primary clock button.
struct HomePulseRings: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<2, id: \.self) { ring in
                    let cycle = (t / (2.4 + Double(ring) * 0.55)).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(color.opacity(0.35 * (1 - cycle)), lineWidth: 2)
                        .frame(width: 168 + CGFloat(cycle) * 56, height: 168 + CGFloat(cycle) * 56)
                        .scaleEffect(0.92 + CGFloat(ring) * 0.04)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Animated week hours sparkline with a traveling glow.
struct HomeWeekSparkline: View {
    let dailyHours: [Double]
    let weekdayLabels: [String]
    var accent: Color = Color(red: 0.05, green: 0.62, blue: 0.48)

    /// Seconds for one full loop along the mountains.
    private let loopSeconds: Double = 5.5

    var body: some View {
        VStack(spacing: 12) {
            weekdayRow

            GeometryReader { geo in
                let values = mountainValues(dailyHours)
                let path = mountainPath(values: values, in: geo.size)

                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let travel = CGFloat((t / loopSeconds).truncatingRemainder(dividingBy: 1))
                    let trailStart = max(0, travel - 0.18)

                    ZStack {
                        // Soft filled mountain underlay
                        closedMountainPath(values: values, in: geo.size)
                            .fill(
                                LinearGradient(
                                    colors: [accent.opacity(0.16), accent.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        // Base ridge
                        path
                            .stroke(accent.opacity(0.28), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                        // Lit trail behind the comet
                        path
                            .trim(from: trailStart, to: travel)
                            .stroke(
                                LinearGradient(
                                    colors: [accent.opacity(0.05), accent.opacity(0.85), Color.white.opacity(0.95)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                            )
                            .shadow(color: accent.opacity(0.55), radius: 6)

                        if let point = pointOnPath(values: values, in: geo.size, progress: travel) {
                            travelingShine(at: point, pulse: t)
                        }
                    }
                }
            }
            .frame(height: 72)
        }
        .padding(.horizontal, 4)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var weekdayRow: some View {
        HStack {
            ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { index, label in
                TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let pulse = (sin(t * 2.2 + Double(index) * 0.7) + 1) / 2
                    VStack(spacing: 6) {
                        Text(label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.secondary.opacity(0.55 + 0.45 * pulse))
                        Circle()
                            .fill(accent.opacity(0.35 + 0.55 * pulse))
                            .frame(width: 5, height: 5)
                            .shadow(color: accent.opacity(0.5 * pulse), radius: 3)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func travelingShine(at point: CGPoint, pulse t: Double) -> some View {
        let twinkle = 0.75 + 0.25 * sin(t * 8)
        return ZStack {
            // Outer bloom
            Circle()
                .fill(accent.opacity(0.28 * twinkle))
                .frame(width: 28, height: 28)
                .blur(radius: 8)

            // Mid glow ring
            Circle()
                .stroke(accent.opacity(0.7), lineWidth: 1.5)
                .frame(width: 16, height: 16)
                .blur(radius: 0.5)

            // Bright core
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white,
                            Color.white.opacity(0.95),
                            accent,
                            accent.opacity(0.2)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 8
                    )
                )
                .frame(width: 11, height: 11)
                .shadow(color: accent.opacity(0.95), radius: 8)
                .shadow(color: Color.white.opacity(0.7), radius: 3)

            // Specular sparkle
            Circle()
                .fill(Color.white.opacity(0.9 * twinkle))
                .frame(width: 3, height: 3)
                .offset(x: -2, y: -2)
        }
        .position(point)
    }

    /// Prefer real hours; if the week is empty, keep gentle decorative mountains so motion stays visible.
    private func mountainValues(_ hours: [Double]) -> [CGFloat] {
        let safe = hours.isEmpty ? Array(repeating: 0.0, count: 7) : hours
        let peak = safe.max() ?? 0
        if peak <= 0.01 {
            // Decorative ridge silhouette (always has peaks to travel).
            let wave: [CGFloat] = [0.28, 0.55, 0.38, 0.82, 0.48, 0.70, 0.34]
            return wave
        }
        return safe.map { CGFloat($0 / peak) }
    }

    private func mountainPath(values: [CGFloat], in size: CGSize) -> Path {
        let points = controlPoints(values: values, in: size)
        guard points.count > 1 else { return Path() }

        var path = Path()
        path.move(to: points[0])
        for index in 0..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            let mid = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
            path.addQuadCurve(to: mid, control: current)
            if index == points.count - 2 {
                path.addQuadCurve(to: next, control: next)
            }
        }
        return path
    }

    private func controlPoints(values: [CGFloat], in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let x = CGFloat(index) * step
            let y = size.height - value * (size.height - 10) - 6
            return CGPoint(x: x, y: y)
        }
    }

    private func pointOnPath(values: [CGFloat], in size: CGSize, progress: CGFloat) -> CGPoint? {
        let points = controlPoints(values: values, in: size)
        guard points.count > 1 else { return nil }

        // Approximate along chord lengths for steadier travel speed.
        var lengths: [CGFloat] = [0]
        var total: CGFloat = 0
        for index in 0..<(points.count - 1) {
            let dx = points[index + 1].x - points[index].x
            let dy = points[index + 1].y - points[index].y
            total += sqrt(dx * dx + dy * dy)
            lengths.append(total)
        }
        guard total > 0 else { return points.first }

        let target = min(max(progress, 0), 1) * total
        for index in 0..<(points.count - 1) {
            let start = lengths[index]
            let end = lengths[index + 1]
            if target <= end || index == points.count - 2 {
                let span = max(end - start, 0.0001)
                let frac = (target - start) / span
                let a = points[index]
                let b = points[index + 1]
                // Sample the same quadratic midpoint style used by the path.
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                if frac < 0.5 {
                    let local = frac * 2
                    return quadPoint(from: a, control: a, to: mid, t: local)
                } else {
                    let local = (frac - 0.5) * 2
                    return quadPoint(from: mid, control: b, to: b, t: local)
                }
            }
        }
        return points.last
    }

    private func quadPoint(from start: CGPoint, control: CGPoint, to end: CGPoint, t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
            y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
        )
    }
}

struct HomeStatChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
