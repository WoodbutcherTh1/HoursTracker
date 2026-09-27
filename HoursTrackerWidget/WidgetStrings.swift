import SwiftUI

/// The widget's and Live Activity's own text in Hebrew, Arabic and English.
///
/// Hardcoded per language (the same pattern `AppLocale` uses for notification
/// text) rather than read from the String Catalog, which proved unreliable in
/// the extension. The language is the one chosen **inside the app** — the app
/// writes it to the App Group (`WidgetSettings.languageCode`) — so an Arabic
/// user on an English phone still gets an Arabic widget. Falls back to the
/// device language before the app has written it.
enum WidgetL10n {
    enum Language { case en, he, ar }

    static var language: Language {
        let code = WidgetBridge.readSettings().languageCode
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"
        switch code {
        case "he", "iw": return .he
        case "ar": return .ar
        default: return .en
        }
    }

    static var layoutDirection: LayoutDirection {
        language == .en ? .leftToRight : .rightToLeft
    }

    private static func pick(_ en: String, _ he: String, _ ar: String) -> String {
        switch language {
        case .en: return en
        case .he: return he
        case .ar: return ar
        }
    }

    // MARK: Status

    static var working: String { pick("Working", "בעבודה", "بالشغل") }
    static var onBreak: String { pick("On break", "בהפסקה", "باستراحة") }
    static var onBreakLower: String { pick("on break", "בהפסקה", "باستراحة") }
    static var clockedIn: String { pick("Clocked In", "בעבודה", "داخل الوردية") }
    static var done: String { pick("Done", "הסתיים", "خلص") }
    static var shiftComplete: String { pick("Shift complete", "המשמרת הסתיימה", "الوردية خلصت") }
    static var startYourShift: String { pick("Start your shift", "התחלת משמרת", "ابدأ ورديتك") }
    static var readyToWork: String { pick("Ready to work?", "מוכנים לעבודה?", "جاهز للشغل؟") }
    static var oneTapStarts: String { pick("One tap starts today's shift", "לחיצה אחת מתחילה את המשמרת", "كبسة وحدة بتبلّش وردية اليوم") }

    // MARK: Labels

    static var today: String { pick("today", "היום", "اليوم") }
    static var gross: String { pick("gross", "ברוטו", "إجمالي") }
    static var earnings: String { pick("Earnings", "הכנסה", "الدخل") }
    static var elapsed: String { pick("Elapsed", "זמן", "المدة") }
    static var elapsedLower: String { pick("elapsed", "עברו", "مرّت") }
    static var hours: String { pick("Hours", "שעות", "ساعات") }
    static var thisWeek: String { pick("This week", "השבוע", "هالأسبوع") }
    static var thisMonth: String { pick("This month", "החודש", "هالشهر") }
    static var workingThisWeek: String { pick("Working — this week", "בעבודה — השבוע", "بالشغل — هالأسبوع") }
    static var estimatedNet: String { pick("estimated net", "נטו משוער", "صافي تقريبي") }
    static var estimatedGross: String { pick("estimated gross", "ברוטו משוער", "إجمالي تقريبي") }
    /// Short unit after an hours figure ("7.5h").
    static var hoursUnit: String { pick("h", "ש׳", "س") }
    static var perHour: String { pick("/h", "/שעה", "/ساعة") }

    static func thisWeekTapForHistory(_ hours: String) -> String {
        pick("This week \(hours) · tap for history", "השבוע \(hours) · להיסטוריה", "هالأسبوع \(hours) · للسجل")
    }

    static var sincePrefix: String { pick("since", "מ-", "من") }

    static func standardDay(_ hours: String) -> String {
        pick("\(hours)h standard", "תקן \(hours) ש׳", "الدوام \(hours) س")
    }

    static func hoursShort(_ hours: Double) -> String {
        String(format: "%.1f", hours) + hoursUnit
    }

    // MARK: Buttons

    static var clockIn: String { pick("Clock In", "כניסה", "دخول") }
    static var clockOut: String { pick("Clock Out", "יציאה", "خروج") }
    static var imBack: String { pick("I'm back", "חזרתי", "رجعت") }
    static var back: String { pick("Back", "חזרתי", "رجعت") }
    static var breakButton: String { pick("Break", "הפסקה", "استراحة") }
    static var inShort: String { pick("In", "כניסה", "دخول") }
    static var outShort: String { pick("Out", "יציאה", "خروج") }

    // MARK: Widget gallery

    static var displayName: String { "Hours Tracker" }
    static var smallDescription: String {
        pick("Today's hours and earnings at a glance.",
             "השעות וההכנסה של היום במבט אחד.",
             "ساعات ودخل اليوم بنظرة وحدة.")
    }
    static var mediumDescription: String {
        pick("Detailed hours and pay breakdown. Clock in, out and take breaks right from the home screen.",
             "פירוט שעות ושכר. כניסה, יציאה והפסקה ישר ממסך הבית.",
             "تفاصيل الساعات والراتب. دخول وخروج واستراحة مباشرة من الشاشة الرئيسية.")
    }
}
