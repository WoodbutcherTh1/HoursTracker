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

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let values = normalized(dailyHours)
                let path = sparklinePath(values: values, in: geo.size)
                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let travel = CGFloat((t / 4).truncatingRemainder(dividingBy: 1))

                    ZStack {
                        path
                            .stroke(accent.opacity(0.22), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                        path
                            .trim(from: 0, to: min(1, travel + 0.08))
                            .stroke(
                                LinearGradient(
                                    colors: [accent.opacity(0.1), accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                            )

                        if let point = pointOnPath(values: values, in: geo.size, progress: travel) {
                            Circle()
                                .fill(accent)
                                .frame(width: 8, height: 8)
                                .shadow(color: accent.opacity(0.8), radius: 6)
                                .position(point)
                        }
                    }
                }
            }
            .frame(height: 56)

            HStack {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { index, label in
                    TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        let pulse = (sin(t * 2 + Double(index) * 0.7) + 1) / 2
                        Text(label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.secondary.opacity(0.55 + 0.45 * pulse))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func normalized(_ hours: [Double]) -> [CGFloat] {
        let safe = hours.isEmpty ? Array(repeating: 0.0, count: 7) : hours
        let peak = max(safe.max() ?? 1, 1)
        return safe.map { CGFloat($0 / peak) }
    }

    private func sparklinePath(values: [CGFloat], in size: CGSize) -> Path {
        guard values.count > 1 else { return Path() }
        let step = size.width / CGFloat(values.count - 1)
        var path = Path()
        for (index, value) in values.enumerated() {
            let x = CGFloat(index) * step
            let y = size.height - value * (size.height - 8) - 4
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }

    private func pointOnPath(values: [CGFloat], in size: CGSize, progress: CGFloat) -> CGPoint? {
        guard values.count > 1 else { return nil }
        let clamped = min(max(progress, 0), 1)
        let position = clamped * CGFloat(values.count - 1)
        let index = Int(position)
        let frac = position - CGFloat(index)
        let next = min(index + 1, values.count - 1)
        let step = size.width / CGFloat(values.count - 1)
        let y1 = size.height - values[index] * (size.height - 8) - 4
        let y2 = size.height - values[next] * (size.height - 8) - 4
        return CGPoint(
            x: CGFloat(index) * step + frac * step,
            y: y1 + (y2 - y1) * frac
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
