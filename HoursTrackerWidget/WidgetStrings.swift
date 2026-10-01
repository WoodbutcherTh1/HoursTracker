import SwiftUI

/// The widget's and Live Activity's own text in Hebrew, Arabic, English and Russian.
///
/// Hardcoded per language (the same pattern `AppLocale` uses for notification
/// text) rather than read from the String Catalog, which proved unreliable in
/// the extension. The language is the one chosen **inside the app** — the app
/// writes it to the App Group (`WidgetSettings.languageCode`) — so an Arabic
/// user on an English phone still gets an Arabic widget. Falls back to the
/// device language before the app has written it.
enum WidgetL10n {
    enum Language { case en, he, ar, ru }

    static var language: Language {
        let code = WidgetBridge.readSettings().languageCode
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"
        switch code {
        case "he", "iw": return .he
        case "ar": return .ar
        case "ru": return .ru
        default: return .en
        }
    }

    static var layoutDirection: LayoutDirection {
        language == .he || language == .ar ? .rightToLeft : .leftToRight
    }

    private static func pick(_ en: String, _ he: String, _ ar: String, _ ru: String) -> String {
        switch language {
        case .en: return en
        case .he: return he
        case .ar: return ar
        case .ru: return ru
        }
    }

    // MARK: Status

    static var working: String { pick("Working", "בעבודה", "بالشغل", "На работе") }
    static var onBreak: String { pick("On break", "בהפסקה", "باستراحة", "Перерыв") }
    static var onBreakLower: String { pick("on break", "בהפסקה", "باستراحة", "перерыв") }
    static var clockedIn: String { pick("Clocked In", "בעבודה", "داخل الوردية", "На смене") }
    static var done: String { pick("Done", "הסתיים", "خلص", "Готово") }
    static var shiftComplete: String { pick("Shift complete", "המשמרת הסתיימה", "الوردية خلصت", "Смена окончена") }
    static var startYourShift: String { pick("Start your shift", "התחלת משמרת", "ابدأ ورديتك", "Начните смену") }
    static var readyToWork: String { pick("Ready to work?", "מוכנים לעבודה?", "جاهز للشغل؟", "Готовы к работе?") }
    static var oneTapStarts: String { pick("One tap starts today's shift", "לחיצה אחת מתחילה את המשמרת", "كبسة وحدة بتبلّش وردية اليوم", "Одно касание — и смена началась") }

    // MARK: Labels

    static var today: String { pick("today", "היום", "اليوم", "сегодня") }
    static var gross: String { pick("gross", "ברוטו", "إجمالي", "брутто") }
    static var earnings: String { pick("Earnings", "הכנסה", "الدخل", "Заработок") }
    static var elapsed: String { pick("Elapsed", "זמן", "المدة", "Время") }
    static var elapsedLower: String { pick("elapsed", "עברו", "مرّت", "прошло") }
    static var hours: String { pick("Hours", "שעות", "ساعات", "Часы") }
    static var thisWeek: String { pick("This week", "השבוע", "هالأسبوع", "Эта неделя") }
    static var thisMonth: String { pick("This month", "החודש", "هالشهر", "Этот месяц") }
    static var workingThisWeek: String { pick("Working — this week", "בעבודה — השבוע", "بالشغل — هالأسبوع", "На работе — эта неделя") }
    static var estimatedNet: String { pick("estimated net", "נטו משוער", "صافي تقريبي", "нетто, примерно") }
    static var estimatedGross: String { pick("estimated gross", "ברוטו משוער", "إجمالي تقريبي", "брутто, примерно") }
    /// Short unit after an hours figure ("7.5h").
    static var hoursUnit: String { pick("h", "ש׳", "س", "ч") }
    static var perHour: String { pick("/h", "/שעה", "/ساعة", "/ч") }

    static func thisWeekTapForHistory(_ hours: String) -> String {
        pick("This week \(hours) · tap for history", "השבוע \(hours) · להיסטוריה", "هالأسبوع \(hours) · للسجل", "Неделя \(hours) · к истории")
    }

    static var sincePrefix: String { pick("since", "מ-", "من", "с") }

    static func standardDay(_ hours: String) -> String {
        pick("\(hours)h standard", "תקן \(hours) ש׳", "الدوام \(hours) س", "норма \(hours) ч")
    }

    static func hoursShort(_ hours: Double) -> String {
        String(format: "%.1f", hours) + hoursUnit
    }

    // MARK: Buttons

    static var clockIn: String { pick("Clock In", "כניסה", "دخول", "Начать") }
    static var clockOut: String { pick("Clock Out", "יציאה", "خروج", "Закончить") }
    static var imBack: String { pick("I'm back", "חזרתי", "رجعت", "Продолжить") }
    static var back: String { pick("Back", "חזרתי", "رجعت", "Продолжить") }
    static var breakButton: String { pick("Break", "הפסקה", "استراحة", "Перерыв") }
    static var inShort: String { pick("In", "כניסה", "دخول", "Начало") }
    static var outShort: String { pick("Out", "יציאה", "خروج", "Конец") }

    // MARK: Widget gallery

    static var displayName: String { "Hours Tracker" }
    static var smallDescription: String {
        pick("Today's hours and earnings at a glance.",
             "השעות וההכנסה של היום במבט אחד.",
             "ساعات ودخل اليوم بنظرة وحدة.",
             "Часы и заработок за сегодня — одним взглядом.")
    }
    static var mediumDescription: String {
        pick("Detailed hours and pay breakdown. Clock in, out and take breaks right from the home screen.",
             "פירוט שעות ושכר. כניסה, יציאה והפסקה ישר ממסך הבית.",
             "تفاصيل الساعات والراتب. دخول وخروج واستراحة مباشرة من الشاشة الرئيسية.",
             "Подробные часы и оплата. Начинайте и заканчивайте смену и берите перерыв прямо с экрана «Домой».")
    }
}
