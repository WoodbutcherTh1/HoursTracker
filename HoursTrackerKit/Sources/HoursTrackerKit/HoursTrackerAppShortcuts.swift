import AppIntents
import Foundation

/// Official Siri / Shortcuts phrases for HoursTracker clock actions.
/// Linked via HoursTrackerKit into both the iPhone app and the Watch app so
/// “Hey Siri, Clock in” works on either device without opening the UI.
public struct HoursTrackerAppShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ClockInIntent(),
            phrases: [
                "Clock in with \(.applicationName)",
                "Clock in on \(.applicationName)",
                "Start shift with \(.applicationName)",
                "Start work with \(.applicationName)",
                "כניסה עם \(.applicationName)",
                "כניסה ל\(.applicationName)",
                "התחל משמרת עם \(.applicationName)",
                "התחל עבודה עם \(.applicationName)",
                "سجل دخول مع \(.applicationName)",
                "تسجيل دخول مع \(.applicationName)",
                "دخول مع \(.applicationName)",
                "ابدأ وردية مع \(.applicationName)"
            ],
            shortTitle: "Clock In",
            systemImageName: "door.left.hand.open"
        )

        AppShortcut(
            intent: ClockOutIntent(),
            phrases: [
                "Clock out with \(.applicationName)",
                "Clock out on \(.applicationName)",
                "End shift with \(.applicationName)",
                "End work with \(.applicationName)",
                "יציאה עם \(.applicationName)",
                "יציאה מ\(.applicationName)",
                "סיים משמרת עם \(.applicationName)",
                "סיים עבודה עם \(.applicationName)",
                "سجل خروج مع \(.applicationName)",
                "تسجيل خروج مع \(.applicationName)",
                "خروج مع \(.applicationName)",
                "أنهِ وردية مع \(.applicationName)"
            ],
            shortTitle: "Clock Out",
            systemImageName: "door.left.hand.closed"
        )

        // Explicit in/out wording so Siri does not advertise a vague “Clock” toggle.
        AppShortcut(
            intent: ToggleClockIntent(),
            phrases: [
                "Toggle clock in or out with \(.applicationName)",
                "Switch clock in or out with \(.applicationName)",
                "החלף כניסה או יציאה עם \(.applicationName)",
                "החלף מצב משמרת עם \(.applicationName)",
                "بدّل الدخول أو الخروج مع \(.applicationName)",
                "بدّل حالة الوردية مع \(.applicationName)"
            ],
            shortTitle: "Toggle Clock In/Out",
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}
