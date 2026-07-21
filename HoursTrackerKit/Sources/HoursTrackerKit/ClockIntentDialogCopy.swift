import Foundation

extension WatchLanguageCode {
    /// Locale for short Siri / intent dialogs (matches in-app language when mirrored).
    public var dialogLocale: Locale {
        switch self {
        case .hebrew: return Locale(identifier: "he")
        case .arabic: return Locale(identifier: "ar")
        case .english, .system: return Locale(identifier: "en")
        }
    }
}

/// Short spoken/text confirmations for Clock In/Out App Intents.
/// Uses the App Group snapshot language — no duplicated clock math.
public enum ClockIntentDialogCopy {
    public static func formatTime(_ date: Date, language: WatchLanguageCode) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.dialogLocale
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    /// Reads current App Group snapshot for language + open-session context.
    public static func dialogMessage(for outcome: WidgetClockService.Outcome) -> String {
        let snapshot = WatchSharedStore.loadSnapshot()
        let language = snapshot?.paySettings.language ?? .english
        let open = snapshot?.sessions.filter(\.isOpen).max(by: { $0.clockIn < $1.clockIn })
        let lastClosed = snapshot?.sessions
            .filter { !$0.isOpen }
            .max(by: { ($0.clockOut ?? $0.clockIn) < ($1.clockOut ?? $1.clockIn) })

        switch outcome {
        case .clockedIn:
            let time = formatTime(open?.clockIn ?? Date(), language: language)
            return clockedIn(time: time, language: language, isRestDay: open?.dayType == .restDay)
        case .clockedOut:
            let time = formatTime(lastClosed?.clockOut ?? Date(), language: language)
            return clockedOut(time: time, language: language)
        case .rejectedAlreadyIn:
            let time = open.map { formatTime($0.clockIn, language: language) }
            return alreadyIn(existingTime: time, language: language)
        case .rejectedNoOpenSession:
            return notClockedIn(language: language)
        case .rejectedNoSnapshot:
            return needsSync(language: language)
        }
    }

    public static func clockedIn(time: String, language: WatchLanguageCode, isRestDay: Bool) -> String {
        if isRestDay {
            switch language {
            case .hebrew: return "יום מנוחה — נרשמה כניסה בשעה \(time)"
            case .arabic: return "يوم راحة — تم تسجيل الدخول الساعة \(time)"
            case .english, .system: return "Rest day — clocked in at \(time)"
            }
        }
        switch language {
        case .hebrew: return "נרשמה כניסה בשעה \(time)"
        case .arabic: return "تم تسجيل الدخول الساعة \(time)"
        case .english, .system: return "Clocked in at \(time)"
        }
    }

    public static func clockedOut(time: String, language: WatchLanguageCode) -> String {
        switch language {
        case .hebrew: return "נרשמה יציאה בשעה \(time)"
        case .arabic: return "تم تسجيل الخروج الساعة \(time)"
        case .english, .system: return "Clocked out at \(time)"
        }
    }

    public static func alreadyIn(existingTime: String?, language: WatchLanguageCode) -> String {
        if let existingTime {
            switch language {
            case .hebrew: return "כבר במשמרת פתוחה מאז \(existingTime)"
            case .arabic: return "أنت أصلاً في وردية مفتوحة منذ \(existingTime)"
            case .english, .system: return "Already clocked in since \(existingTime)"
            }
        }
        switch language {
        case .hebrew: return "כבר במשמרת פתוחה"
        case .arabic: return "أنت أصلاً في وردية مفتوحة"
        case .english, .system: return "Already clocked in"
        }
    }

    public static func notClockedIn(language: WatchLanguageCode) -> String {
        switch language {
        case .hebrew: return "אין משמרת פתוחה"
        case .arabic: return "لا توجد وردية مفتوحة"
        case .english, .system: return "Not clocked in"
        }
    }

    public static func needsSync(language: WatchLanguageCode) -> String {
        switch language {
        case .hebrew: return "פתחו את HoursTracker פעם אחת לסנכרון"
        case .arabic: return "افتح HoursTracker مرة واحدةً للمزامنة"
        case .english, .system: return "Open HoursTracker once to sync"
        }
    }
}
