import ActivityKit
import SwiftUI

// MARK: - Theme (shared with HoursWidget.swift)
//
// Updated for the 2026 theme refresh to the same Neon Cyan / Neon Green / Onyx
// values as `WidgetTheme` in HoursWidget.swift and the phone app's defaults, so
// the Live Activity reads as the same product as Home and the home-screen widget.

private enum LATheme {
    static let background = Color(red: 0, green: 0, blue: 0) // Onyx #000000
    static let accent = Color(red: 0.0, green: 0.898, blue: 1.0) // #00E5FF Neon Cyan
    static let accentLight = Color(red: 0.435, green: 0.953, blue: 1.0) // #6FF3FF
    static let cyan = Color(red: 0.0, green: 0.898, blue: 1.0) // #00E5FF
    static let moneyGreen = Color(red: 0.149, green: 0.949, blue: 0.451) // #26F273 Neon Green
    static let textPrimary = Color(red: 0.918, green: 1.0, blue: 0.984)
    static let textSecondary = Color.white.opacity(0.5)
    static let textTertiary = Color.white.opacity(0.3)
    static let glow = Color(red: 0.0, green: 0.898, blue: 1.0).opacity(0.15)
    static let coral = Color(red: 1.0, green: 0.420, blue: 0.482) // #FF6B7B — break state
}

// MARK: - Lock Screen Banner

/// Full-width Lock Screen banner with dark theme, progress ring, and pay.
struct HoursLiveActivityView: View {
    let attributes: HoursActivityAttributes
    let state: HoursActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                // Progress ring
                ZStack {
                    Circle()
                        .stroke(LATheme.accent.opacity(0.15), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: ringProgress)
                        .stroke(
                            ringProgress >= 1 ? LATheme.cyan : LATheme.accent,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(LATheme.accentLight)
                    }
                }
                .frame(width: 44, height: 44)
                // Purely decorative — the same elapsed-time info is read from the
                // stats text next to it.
                .accessibilityHidden(true)

                // Stats
                VStack(alignment: .leading, spacing: 3) {
                    // The one worked-time figure: a system timer that ticks every second
                    // (frozen while the paid clock is stopped).
                    paidClockText(state, fallback: formattedTime(state.elapsedTime))
                        .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(LATheme.textPrimary)

                    livePayText(attributes, state)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [LATheme.moneyGreen, LATheme.accentLight],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .accessibilityElement(children: .combine)

                Spacer()

                // Time + since (or the break countdown while on break)
                VStack(alignment: .trailing, spacing: 3) {
                    if let breakStart = state.breakStart, let breakEnd = state.breakEnd {
                        HStack(spacing: 3) {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(LATheme.coral)
                                .accessibilityHidden(true)
                            Text(timerInterval: min(breakStart, breakEnd)...breakEnd, countsDown: true)
                                .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(LATheme.textPrimary)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 60, alignment: .trailing)
                        }

                        Text(verbatim: WidgetL10n.onBreakLower)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(LATheme.coral)
                    } else {
                        Text("\(WidgetL10n.sincePrefix) \(attributes.clockInTime, style: .time)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(LATheme.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            // Full control from the Lock Screen — runs in the app, never opens it.
            LiveActivityControls(isOnBreak: state.isOnBreak)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(LATheme.background)
    }

    private var ringProgress: Double {
        guard attributes.standardDayHours > 0 else { return 0 }
        return min(state.elapsedHours / attributes.standardDayHours, 1.0)
    }

    private func formattedTime(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        return String(format: "%d:%02d", h, m)
    }
}

// MARK: - Dynamic Island — Minimal

struct HoursLiveActivityMinimal: View {
    let attributes: HoursActivityAttributes
    let state: HoursActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 4) {
            // Not purely decorative here — break vs. working isn't said anywhere
            // else in this compact view, so the icon carries real state and needs
            // a spoken label instead of its raw SF Symbol name.
            Image(systemName: state.isOnBreak ? "cup.and.saucer.fill" : "bolt.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(state.isOnBreak ? LATheme.coral : LATheme.accent)
                .accessibilityLabel(state.isOnBreak ? WidgetL10n.onBreak : WidgetL10n.clockedIn)
            paidClockText(state, fallback: formattedTime(state.elapsedTime))
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(LATheme.textPrimary)
                .frame(maxWidth: 56)
        }
        .accessibilityElement(children: .combine)
    }

    private func formattedTime(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        return String(format: "%d:%02d", h, m)
    }
}

// MARK: - Dynamic Island — Expanded

struct HoursLiveActivityExpanded: View {
    let attributes: HoursActivityAttributes
    let state: HoursActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 14) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [LATheme.accent, LATheme.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        // The text right next to it already says "Clocked In" / "On break".
                        .accessibilityHidden(true)
                    Text(verbatim: state.isOnBreak ? WidgetL10n.onBreak : WidgetL10n.clockedIn)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(state.isOnBreak ? LATheme.coral : LATheme.textPrimary)
                }
                Spacer()
                if let breakStart = state.breakStart, let breakEnd = state.breakEnd {
                    Text(timerInterval: min(breakStart, breakEnd)...breakEnd, countsDown: true)
                        .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(LATheme.coral)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 70, alignment: .trailing)
                } else {
                    Text("\(WidgetL10n.sincePrefix) \(attributes.clockInTime, style: .time)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(LATheme.textSecondary)
                }
            }

            // Timer + Pay — main stats
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    paidClockText(state, fallback: formattedTime(state.elapsedTime))
                        .font(.system(size: 44, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(LATheme.textPrimary)

                    Text(verbatim: WidgetL10n.elapsedLower)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(LATheme.textTertiary)
                        .textCase(.uppercase)
                }
                .accessibilityElement(children: .combine)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    livePayText(attributes, state)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [LATheme.moneyGreen, LATheme.accentLight],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Explicitly scoped to this shift — the home-screen widget shows
                    // the same figure under the same label, so the two never read as
                    // different metrics even though they refresh independently.
                    Text(verbatim: state.payIsNet == true ? WidgetL10n.currentShiftNet : WidgetL10n.currentShiftGross)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(LATheme.textTertiary)
                        .textCase(.uppercase)
                }
                .accessibilityElement(children: .combine)
            }

            // Bottom bar — rate + standard hours
            HStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(LATheme.accent.opacity(0.3))
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                    Text(WidgetBridge.format(amount: attributes.hourlyRate, currencyCode: attributes.currencyCode))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(LATheme.textSecondary)
                    Text(verbatim: WidgetL10n.perHour)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(LATheme.textTertiary)
                }
                .accessibilityElement(children: .combine)
                Spacer()
                if attributes.standardDayHours > 0 {
                    Text(verbatim: WidgetL10n.standardDay(String(format: "%.1f", attributes.standardDayHours)))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(LATheme.textTertiary)
                }
            }
            .padding(.top, 2)

            LiveActivityControls(isOnBreak: state.isOnBreak)
        }
        .padding(16)
        .background(LATheme.background)
    }

    private func formattedTime(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        let s = Int(interval) % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }
}


// MARK: - Paid clock

/// Paid shift time. While the paid clock runs it's a system-driven timer, so the Lock
/// Screen / Dynamic Island tick every second with no app updates; while it's stopped
/// (unpaid break) or the shift is over it's the frozen value the app last pushed.
@ViewBuilder
private func paidClockText(_ state: HoursActivityAttributes.ContentState, fallback: String) -> some View {
    if let start = state.paidClockStart {
        Text(timerInterval: start...Date.distantFuture, countsDown: false)
    } else {
        Text(fallback)
    }
}

// MARK: - Live pay

/// Pay used to freeze at whatever `LiveActivityManager` last pushed — once iOS fully
/// suspended the app, nothing updated it again until the app was reopened. A
/// `TimelineView` ticks this locally between pushes instead: `initialPay +
/// ratePerSecond * secondsSincePush`, where `initialPay`/`ratePerSecond` are the
/// exact pay and the curve's own exact local slope at the moment of the last push.
/// The app re-pushes roughly every 60s (and on any break/settings change), so the
/// flat rate only has to hold for a minute of whichever overtime tier the shift is
/// currently in — it does not re-derive pay from `hourlyRate` with a different,
/// simpler formula (that was the original bug: the widget's `HoursEntry.livePay`
/// reads the real `LivePayCurve`, while this view used `WidgetBridge.estimatePay`'s
/// plain daily-OT quick-estimate, so the two surfaces showed different numbers for
/// the same second).
@ViewBuilder
func livePayText(_ attributes: HoursActivityAttributes, _ state: HoursActivityAttributes.ContentState) -> some View {
    let net = state.payIsNet ?? false
    let initial = net ? state.initialNetPay : state.initialGrossPay
    let rate = net ? state.netRatePerSecond : state.grossRatePerSecond
    if let pushedAt = state.payPushedAt, let initial, let rate {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let secondsSincePush = context.date.timeIntervalSince(pushedAt)
            let amount = initial + rate * secondsSincePush
            Text(WidgetBridge.format(amount: amount, currencyCode: attributes.currencyCode))
        }
    } else {
        Text(WidgetBridge.format(amount: initial ?? state.estimatedPay, currencyCode: attributes.currencyCode))
    }
}

// MARK: - Controls (Lock Screen banner + expanded Dynamic Island)

/// Break / back and clock-out buttons. The intents are `LiveActivityIntent`s, so iOS
/// runs them in the app's process without opening it. As on the widgets, each
/// `Button(intent:)` names its intent literally so WidgetKit's metadata scan finds it.
struct LiveActivityControls: View {
    let isOnBreak: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isOnBreak {
                Button(intent: EndBreakIntent()) {
                    controlLabel(WidgetL10n.imBack, systemImage: "arrow.uturn.backward", fill: LATheme.accent, dark: true)
                }
            } else {
                Button(intent: StartBreakIntent()) {
                    controlLabel(WidgetL10n.breakButton, systemImage: "cup.and.saucer.fill", fill: Color.white.opacity(0.16), dark: false)
                }
            }
            Button(intent: ClockOutIntent()) {
                controlLabel(WidgetL10n.clockOut, systemImage: "stop.fill", fill: LATheme.coral, dark: true)
            }
        }
        .buttonStyle(.plain)
    }

    private func controlLabel(_ title: String, systemImage: String, fill: Color, dark: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(dark ? Color.black.opacity(0.85) : LATheme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(fill, in: Capsule())
    }
}
