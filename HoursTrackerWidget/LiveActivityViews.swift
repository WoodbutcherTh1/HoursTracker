import ActivityKit
import SwiftUI

// MARK: - Theme (shared with HoursWidget.swift)

private enum LATheme {
    static let background = Color(red: 0.027, green: 0.102, blue: 0.122)
    static let accent = Color(red: 0.180, green: 0.831, blue: 0.769) // #2dd4bf
    static let accentLight = Color(red: 0.369, green: 0.918, blue: 0.831) // #5eead4
    static let cyan = Color(red: 0.133, green: 0.827, blue: 0.933) // #22d3ee
    static let moneyGreen = Color(red: 0.345, green: 0.851, blue: 0.471) // #4ade80
    static let textPrimary = Color(red: 0.918, green: 1.0, blue: 0.984)
    static let textSecondary = Color.white.opacity(0.5)
    static let textTertiary = Color.white.opacity(0.3)
    static let glow = Color(red: 0.180, green: 0.831, blue: 0.769).opacity(0.15)
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

                // Stats
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(state.elapsedHours, format: .number.precision(.fractionLength(1)))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(LATheme.textPrimary)
                        + Text(verbatim: WidgetL10n.hoursUnit)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(LATheme.textSecondary)
                    }

                    Text(formattedPay(state.estimatedPay))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [LATheme.moneyGreen, LATheme.accentLight],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }

                Spacer()

                // Time + since (or the break countdown while on break)
                VStack(alignment: .trailing, spacing: 3) {
                    if let breakStart = state.breakStart, let breakEnd = state.breakEnd {
                        HStack(spacing: 3) {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(LATheme.coral)
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
                        HStack(spacing: 3) {
                            Image(systemName: "timer")
                                .font(.system(size: 9))
                                .foregroundStyle(LATheme.accent)
                            paidClockText(state, fallback: formattedTime(state.elapsedTime))
                                .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(LATheme.textPrimary)
                        }

                        Text("\(WidgetL10n.sincePrefix) \(attributes.clockInTime, style: .time)")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(LATheme.textTertiary)
                    }
                }
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

    private func formattedPay(_ amount: Double) -> String {
        WidgetBridge.format(amount: amount, currencyCode: attributes.currencyCode)
    }
}

// MARK: - Dynamic Island — Minimal

struct HoursLiveActivityMinimal: View {
    let attributes: HoursActivityAttributes
    let state: HoursActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: state.isOnBreak ? "cup.and.saucer.fill" : "bolt.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(state.isOnBreak ? LATheme.coral : LATheme.accent)
            paidClockText(state, fallback: formattedTime(state.elapsedTime))
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(LATheme.textPrimary)
                .frame(maxWidth: 56)
        }
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

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(formattedPay(state.estimatedPay))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [LATheme.moneyGreen, LATheme.accentLight],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Text(verbatim: state.payIsNet == true ? WidgetL10n.estimatedNet : WidgetL10n.estimatedGross)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(LATheme.textTertiary)
                        .textCase(.uppercase)
                }
            }

            // Bottom bar — rate + standard hours
            HStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(LATheme.accent.opacity(0.3))
                        .frame(width: 5, height: 5)
                    Text(WidgetBridge.format(amount: attributes.hourlyRate, currencyCode: attributes.currencyCode))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(LATheme.textSecondary)
                    Text(verbatim: WidgetL10n.perHour)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(LATheme.textTertiary)
                }
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

    private func formattedPay(_ amount: Double) -> String {
        WidgetBridge.format(amount: amount, currencyCode: attributes.currencyCode)
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
