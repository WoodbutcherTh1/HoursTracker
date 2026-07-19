import SwiftUI
import HoursTrackerKit
import WatchKit

/// Watch Clock — circular green/red door control.
///
/// Build stamp: if you do **not** see `b14` under the door on a physical watch,
/// Xcode did not install this binary (you are still on the old text-pill app).
struct ClockScreenView: View {
    @ObservedObject var viewModel: WatchAppViewModel
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    /// Bump when shipping a watch UI change the user must verify on-device.
    private static let watchUIBuildStamp = "b14"

    var body: some View {
        let locale = viewModel.locale
        let clockedIn = viewModel.isClockedIn

        TimelineView(.periodic(from: .now, by: isLuminanceReduced ? 60 : 1)) { context in
            let now = context.date
            VStack(spacing: 6) {
                if let open = viewModel.activeSession {
                    Text(WatchL10n.elapsed(from: open.clockIn, now: now, locale: locale))
                        .font(.system(.title3, design: .rounded).monospacedDigit().weight(.semibold))
                        .foregroundStyle(isLuminanceReduced ? Color.secondary : WatchDoorPalette.openRed)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                } else {
                    Text(WatchL10n.clockTitle(locale: locale))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                // Ultra-simple circular door — SF Symbol + solid fill.
                // No 3D, no borderedProminent, no orange.
                Button {
                    WKInterfaceDevice.current().play(.click)
                    viewModel.toggleClock()
                } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(clockedIn ? WatchDoorPalette.openRed : WatchDoorPalette.closedGreen)
                                .frame(width: 84, height: 84)
                                .shadow(
                                    color: (clockedIn ? WatchDoorPalette.openRed : WatchDoorPalette.closedGreen)
                                        .opacity(0.55),
                                    radius: 6,
                                    y: 2
                                )

                            Image(systemName: clockedIn ? "door.left.hand.open" : "door.left.hand.closed")
                                .font(.system(size: 38, weight: .bold))
                                .foregroundStyle(.white)
                                .symbolRenderingMode(.monochrome)
                        }
                        .frame(width: 88, height: 88)

                        Text(
                            clockedIn
                                ? WatchL10n.clockOut(locale: locale)
                                : WatchL10n.clockIn(locale: locale)
                        )
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(clockedIn ? WatchDoorPalette.openRed : WatchDoorPalette.closedGreen)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("watch.clock.door")
                .accessibilityLabel(
                    clockedIn
                        ? WatchL10n.clockOut(locale: locale)
                        : WatchL10n.clockIn(locale: locale)
                )

                Text(todayLine(now: now, locale: locale))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)

                // Proof this binary is installed (remove after device sign-off).
                Text(Self.watchUIBuildStamp)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .accessibilityIdentifier("watch.clock.buildStamp")
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

enum WatchDoorPalette {
    /// Closed / ready to clock in.
    static let closedGreen = Color(red: 0.12, green: 0.82, blue: 0.38)
    /// Open / ready to clock out — true red (not `.orange`).
    static let openRed = Color(red: 0.95, green: 0.08, blue: 0.14)
}
