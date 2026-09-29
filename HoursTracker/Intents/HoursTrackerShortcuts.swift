import AppIntents

/// Siri phrases, Spotlight and the Shortcuts app's ready-made actions. Every phrase
/// must name the app (Apple's rule); people can add their own phrases in the
/// Shortcuts app. Translations live in AppShortcuts.xcstrings.
struct HoursTrackerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SiriStartShiftIntent(),
            phrases: [
                "Start my shift in \(.applicationName)",
                "Clock in with \(.applicationName)",
                "\(.applicationName) clock in"
            ],
            shortTitle: "Start Shift",
            systemImageName: "play.circle.fill"
        )
        AppShortcut(
            intent: SiriEndShiftIntent(),
            phrases: [
                "End my shift in \(.applicationName)",
                "Clock out with \(.applicationName)",
                "\(.applicationName) clock out"
            ],
            shortTitle: "End Shift",
            systemImageName: "stop.circle.fill"
        )
        AppShortcut(
            intent: SiriStartBreakIntent(),
            phrases: [
                "Start a break in \(.applicationName)",
                "\(.applicationName) break"
            ],
            shortTitle: "Start Break",
            systemImageName: "cup.and.saucer.fill"
        )
        AppShortcut(
            intent: SiriEndBreakIntent(),
            phrases: [
                "End my break in \(.applicationName)",
                "Back to work in \(.applicationName)"
            ],
            shortTitle: "End Break",
            systemImageName: "arrow.uturn.backward.circle.fill"
        )
        AppShortcut(
            intent: SiriShiftStatusIntent(),
            phrases: [
                "Am I clocked in with \(.applicationName)",
                "How long have I been working in \(.applicationName)",
                "\(.applicationName) status"
            ],
            shortTitle: "Shift Status",
            systemImageName: "clock.fill"
        )
        AppShortcut(
            intent: SiriEarningsIntent(),
            phrases: [
                "How much did I earn \(\.$period) in \(.applicationName)",
                "My hours \(\.$period) in \(.applicationName)",
                "\(.applicationName) earnings"
            ],
            shortTitle: "Hours and Earnings",
            systemImageName: "banknote.fill"
        )
        AppShortcut(
            intent: SiriExportReportIntent(),
            phrases: [
                "Export \(\.$period) report from \(.applicationName)",
                "Export my hours from \(.applicationName)"
            ],
            shortTitle: "Export Report",
            systemImageName: "doc.richtext.fill"
        )
        AppShortcut(
            intent: SiriAskIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask \(.applicationName) a question"
            ],
            shortTitle: "Ask HoursTracker",
            systemImageName: "sparkles"
        )
    }
}
