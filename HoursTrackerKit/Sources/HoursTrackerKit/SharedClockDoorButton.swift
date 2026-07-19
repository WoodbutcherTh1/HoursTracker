import SwiftUI

#if os(iOS)
import UIKit
#endif
#if os(watchOS)
import WatchKit
#endif

/// Shared neon palette (iPhone Home + watch Clock).
public enum SharedHomeNeon {
    public static let accent = Color(red: 0.15, green: 0.95, blue: 0.45)
    public static let accentDeep = Color(red: 0.05, green: 0.55, blue: 0.28)
    public static let coral = Color(red: 0.95, green: 0.28, blue: 0.35)
    public static let coralDeep = Color(red: 0.72, green: 0.12, blue: 0.22)
    public static let frame = Color(red: 0.10, green: 0.11, blue: 0.13)
}

/// Clock-in door: closed + green → press → opens + turns red.
/// Clock-out door: open + red → press → closes + turns green.
/// Shared by iPhone Home and watch Clock (size scales for watch HIG).
public struct SharedClockDoorButton: View {
    public enum Mode: Sendable {
        case clockIn
        case clockOut
    }

    public let mode: Mode
    public let title: String
    public let doorWidth: CGFloat
    public let doorHeight: CGFloat
    public let showTitle: Bool
    /// When `true`, uses subheadline (iPhone Home); otherwise caption (watch).
    public let largeTitle: Bool
    public let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isOpen: Bool
    @State private var isBusy = false

    public init(
        mode: Mode,
        title: String,
        doorWidth: CGFloat = 72,
        doorHeight: CGFloat = 86,
        showTitle: Bool = true,
        largeTitle: Bool = false,
        action: @escaping () -> Void
    ) {
        self.mode = mode
        self.title = title
        self.doorWidth = doorWidth
        self.doorHeight = doorHeight
        self.showTitle = showTitle
        self.largeTitle = largeTitle
        self.action = action
        _isOpen = State(initialValue: mode == .clockOut)
    }

    private var doorColor: Color {
        isOpen ? SharedHomeNeon.coral : SharedHomeNeon.accent
    }

    private var glowColor: Color {
        isOpen ? SharedHomeNeon.coral : SharedHomeNeon.accent
    }

    public var body: some View {
        Button {
            guard !isBusy else { return }
            isBusy = true
            playHaptic()

            let duration: TimeInterval = reduceMotion ? 0.15 : 0.4
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    isBusy = false
                    isOpen = (mode == .clockOut)
                }
            }
        } label: {
            VStack(spacing: showTitle ? 8 : 0) {
                ZStack {
                    SharedPulseRings(color: glowColor, size: doorWidth + 6)

                    doorScene
                        .frame(width: doorWidth, height: doorHeight)
                        .shadow(color: glowColor.opacity(0.4), radius: 10, y: 4)
                }
                .frame(width: doorWidth + 40, height: doorHeight + 20)

                if showTitle {
                    Text(title)
                        .font(
                            largeTitle
                                ? .system(.subheadline, design: .rounded).weight(.bold)
                                : .system(.caption, design: .rounded).weight(.bold)
                        )
                        .foregroundStyle(doorColor)
                        .shadow(color: doorColor.opacity(0.35), radius: largeTitle ? 5 : 4)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(SharedScalePressButtonStyle())
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
            shape.fill(SharedHomeNeon.frame)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isOpen
                                ? [
                                    Color(red: 0.35, green: 0.05, blue: 0.08),
                                    SharedHomeNeon.coral.opacity(0.55),
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
                                    SharedHomeNeon.coral.opacity(0.55),
                                    SharedHomeNeon.coral.opacity(0.0)
                                ],
                                center: .center,
                                startRadius: 3,
                                endRadius: 42
                            )
                            .blendMode(.plusLighter)
                        }
                    }
                    .padding(5)

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

            shape
                .stroke(doorColor.opacity(0.7), lineWidth: 2)
                .allowsHitTesting(false)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                .padding(4)
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.35), value: isOpen)
    }

    private var doorLeaf: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            doorColor,
                            doorColor.opacity(0.75),
                            (isOpen ? SharedHomeNeon.coralDeep : SharedHomeNeon.accentDeep)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                )

            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.black.opacity(0.18), lineWidth: 1.2)
                    .frame(maxHeight: .infinity)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.black.opacity(0.18), lineWidth: 1.2)
                    .frame(maxHeight: .infinity)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 7)
            .padding(.trailing, 6)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.95), Color.white.opacity(0.55)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 4
                    )
                )
                .frame(width: 6, height: 6)
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                .padding(.trailing, 7)
        }
        .animation(.easeInOut(duration: 0.35), value: isOpen)
    }

    private func playHaptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
    }
}

public struct SharedPulseRings: View {
    public var color: Color
    public var size: CGFloat

    public init(color: Color, size: CGFloat = 78) {
        self.color = color
        self.size = size
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<2, id: \.self) { ring in
                    let cycle = (t / (2.6 + Double(ring) * 0.7) + Double(ring) * 0.4)
                        .truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(color.opacity(0.22 * (1 - cycle)), lineWidth: 1.25)
                        .frame(
                            width: size + 12 + CGFloat(cycle) * 28,
                            height: size + 12 + CGFloat(cycle) * 28
                        )
                }

                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: size + 20, height: size + 20)
                    .blur(radius: 14)
            }
        }
        .allowsHitTesting(false)
    }
}

public struct SharedScalePressButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
