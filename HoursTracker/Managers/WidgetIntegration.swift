import ActivityKit
import CoreFoundation
import Foundation
import UIKit
import WidgetKit

// MARK: - App → widget bridge (uses app-only types that the widget cannot see)

extension WidgetBridge {
    static func snapshot(from settings: WorkplaceSettings) -> WidgetSettings {
        WidgetSettings(
            hourlyRate: settings.hourlyRate,
            dailyGasAllowance: settings.dailyGasAllowance,
            standardDayHours: settings.standardDayHours,
            ot125HoursCap: settings.ot125HoursCap,
            breakMinutes: settings.defaultBreakMinutes,
            currencyCode: settings.currencyCode,
            weeklyStandardHours: settings.weeklyStandardHours,
            weeklyOvertimeCapHours: settings.weeklyOvertimeCapHours
        )
    }

    static func snapshot(from session: WorkSession) -> WidgetSession {
        WidgetSession(
            id: session.id,
            clockIn: session.clockIn,
            clockOut: session.clockOut,
            breakMinutes: session.breakMinutes,
            isNightShift: session.isNightShift
        )
    }

    static func pushUpdate(settings: WorkplaceSettings, sessions: [WorkSession]) {
        update(settings: snapshot(from: settings))
        update(sessions: sessions.map(snapshot(from:)))
        reloadWidgetTimelines()
    }
}

// MARK: - Widget timeline refresh (app-only — WidgetKit lives in this target)

extension WidgetBridge {
    /// Rebuilds every widget timeline. Kept OUT of the shared bridge file so
    /// `WidgetCenter` (and the WidgetKit framework) never leaks into targets
    /// that only compile the snapshot types (app tests, for example).
    static func reloadWidgetTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Live Activity attributes factory (app-only conversion)

extension HoursActivityAttributes {
    static func from(session: WorkSession, settings: WorkplaceSettings) -> HoursActivityAttributes {
        HoursActivityAttributes(
            clockInTime: session.clockIn,
            hourlyRate: settings.hourlyRate,
            currencyCode: settings.currencyCode,
            standardDayHours: settings.standardDayHours,
            ot125HoursCap: settings.ot125HoursCap,
            dailyGasAllowance: settings.dailyGasAllowance,
            breakMinutes: settings.defaultBreakMinutes
        )
    }
}

// MARK: - Widget action broadcasting (app side)

/// Installs a Darwin-notification observer so the app learns about widget button
/// taps even when it is backgrounded. Safe to register exactly once per launch.
final class WidgetActionBroadcaster {
    static let shared = WidgetActionBroadcaster()

    /// Local notification name re-posted on the main thread after a Darwin wake.
    static let didReceiveAction = Notification.Name("htw.widget.action.didReceive")

    private var installed = false

    func installIfNeeded() {
        guard !installed else { return }
        installed = true

        let handler: CFNotificationCenterCallback = { _, _, _, _, _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.didReceiveAction, object: nil)
            }
        }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            handler,
            WidgetBridge.darwinActionNotification,
            nil,
            .deliverImmediately
        )
    }
}

// MARK: - Quick actions (long-press the app icon)

/// Manages the state-aware home-screen quick actions.
enum AppShortcutManager {
    static func refresh(isClockedIn: Bool) {
        var items: [UIApplicationShortcutItem] = []

        if isClockedIn {
            items.append(UIApplicationShortcutItem(
                type: "com.hourstracker.app.clockOut",
                localizedTitle: L10n.homeClockOutShortcut,
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "stop.circle.fill")
            ))
        } else {
            items.append(UIApplicationShortcutItem(
                type: "com.hourstracker.app.clockIn",
                localizedTitle: L10n.homeClockInShortcut,
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "play.circle.fill")
            ))
        }

        items.append(UIApplicationShortcutItem(
            type: "com.hourstracker.app.addTime",
            localizedTitle: L10n.quickAddHours,
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: "plus.circle.fill")
        ))
        items.append(UIApplicationShortcutItem(
            type: "com.hourstracker.app.scan",
            localizedTitle: L10n.quickScanTimesheet,
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: "text.viewfinder")
        ))

        UIApplication.shared.shortcutItems = items
    }

    /// Map a tapped shortcut to a deep-link URL the SwiftUI layer already handles.
    static func url(for type: String) -> URL? {
        switch type {
        case "com.hourstracker.app.clockIn":
            return URL(string: "hourstracker://action/clockIn")
        case "com.hourstracker.app.clockOut":
            return URL(string: "hourstracker://action/clockOut")
        case "com.hourstracker.app.addTime":
            return URL(string: "hourstracker://tab/history")
        case "com.hourstracker.app.scan":
            return URL(string: "hourstracker://action/scan")
        default:
            return nil
        }
    }
}