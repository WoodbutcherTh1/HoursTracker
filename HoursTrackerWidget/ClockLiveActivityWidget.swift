import ActivityKit
import WidgetKit
import SwiftUI

/// Renders the Live Activity `LiveActivityController` (app target) starts/updates/ends.
/// Lock Screen banner + full Dynamic Island support. The elapsed timer is native
/// (`Text(date, style: .timer)` from `context.attributes.clockInDate`) and ticks without
/// any update from the app; only today's running pay comes from `context.state`.
///
/// NOT verified against a real build — ActivityKit/Dynamic Island need a real device or
/// a Live-Activity-enabled simulator, neither available in this environment.
struct ClockLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClockActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Clocked In", systemImage: "clock.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Text(context.state.formattedPay)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color(red: 0.15, green: 0.95, blue: 0.45))
                }
                Text(context.attributes.clockInDate, style: .timer)
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(.white)
            }
            .padding()
            .activityBackgroundTint(Color(red: 0.09, green: 0.10, blue: 0.12))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("In", systemImage: "clock.fill")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.formattedPay)
                        .font(.caption.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.clockInDate, style: .timer)
                        .font(.title3.monospacedDigit())
                }
            } compactLeading: {
                Image(systemName: "clock.fill")
            } compactTrailing: {
                Text(context.attributes.clockInDate, style: .timer)
                    .font(.caption2.monospacedDigit())
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "clock.fill")
            }
        }
    }
}

private extension ClockActivityAttributes.ContentState {
    var formattedPay: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 0
        return formatter.string(from: todayGrossPay as NSNumber) ?? "—"
    }
}
