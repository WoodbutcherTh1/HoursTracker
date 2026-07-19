import SwiftUI
import HoursTrackerKit
import WatchKit

/// Watch Clock root — circular door (green ↔ red). Never the legacy
/// `.borderedProminent` green/orange text pill (`כניסה` / `יציאה`).
struct ClockScreenView: View {
    @ObservedObject var viewModel: WatchAppViewModel
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let locale = viewModel.locale
        TimelineView(.periodic(from: .now, by: isLuminanceReduced ? 60 : 1)) { context in
            let now = context.date
            VStack(spacing: 4) {
                if let open = viewModel.activeSession {
                    Text(WatchL10n.elapsed(from: open.clockIn, now: now, locale: locale))
                        .font(.system(.title3, design: .rounded).monospacedDigit().weight(.semibold))
                        .foregroundStyle(isLuminanceReduced ? .secondary : WatchDoorPalette.openRed)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                } else {
                    Text(WatchL10n.clockTitle(locale: locale))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                WatchCircularDoorButton(
                    isClockedIn: viewModel.isClockedIn,
                    title: viewModel.isClockedIn
                        ? WatchL10n.clockOut(locale: locale)
                        : WatchL10n.clockIn(locale: locale)
                ) {
                    viewModel.toggleClock()
                }
                .accessibilityIdentifier("watch.clock.door")

                Text(todayLine(now: now, locale: locale))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle(WatchL10n.clockTitle(locale: locale))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func todayLine(now: Date, locale: Locale) -> String {
        let hours = viewModel.todayHours(now: now)
        let pay = viewModel.todayGross(now: now)
        let hoursText = WatchL10n.hoursShort(hours, locale: locale)
        let money = PayFormatter.string(
            pay,
            currencyCode: viewModel.paySettings.currencyCode,
            locale: locale
        )
        return "\(WatchL10n.todaySummary(locale: locale)): \(hoursText) · \(money)"
    }
}

/// Explicit RGB — green closed / true red open (not system `.orange`).
enum WatchDoorPalette {
    /// Closed / ready to clock in — matches iPhone Home neon green.
    static let closedGreen = Color(red: 0.15, green: 0.95, blue: 0.45)
    static let closedGreenDeep = Color(red: 0.05, green: 0.55, blue: 0.28)
    /// Open / ready to clock out — true red (NOT orange).
    /// Old watch pill used `.orange` ≈ (1.0, 0.58, 0.0). This is real red.
    static let openRed = Color(red: 0.92, green: 0.10, blue: 0.16)
    static let openRedDeep = Color(red: 0.62, green: 0.04, blue: 0.10)
    static let frame = Color(red: 0.10, green: 0.11, blue: 0.13)
}

/// Circular door control for watchOS HIG. Defined in the watch target so installing
/// HoursTrackerWatch from this branch is unmistakable vs. the old text pill.
struct WatchCircularDoorButton: View {
    let isClockedIn: Bool
    let title: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOpen: Bool
    @State private var isBusy = false

    private let diameter: CGFloat = 78
    private let doorW: CGFloat = 34
    private let doorH: CGFloat = 44

    init(isClockedIn: Bool, title: String, action: @escaping () -> Void) {
        self.isClockedIn = isClockedIn
        self.title = title
        self.action = action
        _isOpen = State(initialValue: isClockedIn)
    }

    private var doorColor: Color {
        isOpen ? WatchDoorPalette.openRed : WatchDoorPalette.closedGreen
    }

    var body: some View {
        Button {
            guard !isBusy else { return }
            isBusy = true
            WKInterfaceDevice.current().play(.click)

            // clock-in (closed/green) → open/red; clock-out (open/red) → closed/green
            let willBeOpen = !isClockedIn
            let duration: TimeInterval = reduceMotion ? 0.12 : 0.35
            withAnimation(.spring(response: duration, dampingFraction: 0.82)) {
                isOpen = willBeOpen
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                action()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    isBusy = false
                }
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    // Outer circular hit target — NOT a capsule/pill.
                    Circle()
                        .fill(WatchDoorPalette.frame)
                        .frame(width: diameter, height: diameter)
                        .overlay(
                            Circle()
                                .stroke(doorColor, lineWidth: 3)
                        )
                        .shadow(color: doorColor.opacity(0.55), radius: 8, y: 2)

                    doorGlyph
                        .frame(width: doorW, height: doorH)
                }
                .frame(width: diameter + 8, height: diameter + 8)

                // Plain caption under the circle — never `.borderedProminent`.
                Text(title)
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(doorColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(title)
        .onChange(of: isClockedIn) { _, clockedIn in
            isOpen = clockedIn
            isBusy = false
        }
    }

    /// Door leaf inside the circle (closed = green panel; open = swung + red interior).
    private var doorGlyph: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        return ZStack {
            shape.fill(WatchDoorPalette.frame)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isOpen
                                ? [
                                    Color(red: 0.40, green: 0.02, blue: 0.06),
                                    WatchDoorPalette.openRed.opacity(0.65),
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
                    .padding(3)

                ZStack(alignment: .trailing) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    doorColor,
                                    doorColor.opacity(0.78),
                                    isOpen ? WatchDoorPalette.openRedDeep : WatchDoorPalette.closedGreenDeep
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )

                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 5, height: 5)
                        .padding(.trailing, 4)
                }
                .padding(3)
                .rotation3DEffect(
                    .degrees(isOpen ? -78 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .leading,
                    perspective: 0.9
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous).inset(by: 2))

            shape
                .stroke(doorColor.opacity(0.85), lineWidth: 1.5)
        }
        .animation(.easeInOut(duration: 0.3), value: isOpen)
    }
}
