import Foundation
import UserNotifications

/// "Shift complete" local notification for a clock-out made outside the app — from
/// the Lock Screen, a widget, the Dynamic Island or the Watch. Inside the app the
/// Day Summary opens by itself, so nothing is posted then.
///
/// Local only (no server). Only posted when notifications are already allowed: a
/// background clock-out is not the moment to ask. Tapping it opens that shift's
/// Day Summary (`AppDelegate`).
enum ShiftSummaryNotifier {
    static let identifier = "shift-summary"
    static let sessionIDKey = "shiftSummarySessionID"

    /// "07:30–14:13 · 6:43 h · ≈ ₪337.63 gross". The amount is left out when pay is
    /// hidden on the widgets and Lock Screen. Pure, for tests.
    static func body(
        clockIn: Date,
        clockOut: Date,
        paidHours: Double,
        payText: String?,
        timeFormatter: DateFormatter
    ) -> String {
        var parts = [
            "\(timeFormatter.string(from: clockIn))–\(timeFormatter.string(from: clockOut))",
            L10n.notifShiftSummaryHours(hoursText(paidHours))
        ]
        if let payText { parts.append(payText) }
        return parts.joined(separator: " · ")
    }

    /// 6.72 → "6:43".
    static func hoursText(_ hours: Double) -> String {
        let minutes = Int((max(0, hours) * 60).rounded())
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    static func post(
        session: WorkSession,
        breakdown: DayPayBreakdown,
        showsNet: Bool,
        preferences: NotificationPreferences = .shared,
        center: UNUserNotificationCenter = .current()
    ) {
        guard preferences.shiftSummaryEnabled, let clockOut = session.clockOut else { return }
        // Resolve the copy now, on the main thread, in the current in-app language.
        let payText: String? = WidgetBridge.hidePay ? nil : L10n.notifShiftSummaryPay(
            showsNet ? breakdown.formattedNetPay : breakdown.formattedGrossPay,
            showsNet ? L10n.historyPayNet : L10n.historyPayGross
        )
        let content = UNMutableNotificationContent()
        content.title = L10n.sumTitle
        content.body = body(
            clockIn: session.clockIn,
            clockOut: clockOut,
            paidHours: session.effectiveHours,
            payText: payText,
            timeFormatter: AppLocale.makeDateFormatter(timeStyle: .short)
        )
        content.sound = .default
        content.userInfo = [sessionIDKey: session.id.uuidString]

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
            default:
                break
            }
        }
    }

    /// Clears it once the Day Summary has been seen in the app.
    static func clear(center: UNUserNotificationCenter = .current()) {
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
