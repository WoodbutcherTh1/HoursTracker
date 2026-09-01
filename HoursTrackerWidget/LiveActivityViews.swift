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
}

// MARK: - Lock Screen Banner

/// Full-width Lock Screen banner with dark theme, progress ring, and pay.
struct HoursLiveActivityView: View {
    let attributes: HoursActivityAttributes
    let state: HoursActivityAttributes.ContentState

    var body: some View {
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
                    + Text("h")
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

            // Time + since
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 3) {
                    Image(systemName: "timer")
                        .font(.system(size: 9))
                        .foregroundStyle(LATheme.accent)
                    Text(formattedTime(state.elapsedTime))
                        .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(LATheme.textPrimary)
                }

                Text("since \(attributes.clockInTime, style: .time)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(LATheme.textTertiary)
            }
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
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LATheme.accent)
            Text(formattedTime(state.elapsedTime))
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(LATheme.textPrimary)
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
                    Text("Clocked In")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(LATheme.textPrimary)
                }
                Spacer()
                Text("since \(attributes.clockInTime, style: .time)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(LATheme.textSecondary)
            }

            // Timer + Pay — main stats
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(formattedTime(state.elapsedTime))
                        .font(.system(size: 44, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(LATheme.textPrimary)

                    Text("elapsed")
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

                    Text("estimated gross")
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
                    Text("/h")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(LATheme.textTertiary)
                }
                Spacer()
                if attributes.standardDayHours > 0 {
                    Text("\(attributes.standardDayHours, format: .number.precision(.fractionLength(1)))h standard")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(LATheme.textTertiary)
                }
            }
            .padding(.top, 2)
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
