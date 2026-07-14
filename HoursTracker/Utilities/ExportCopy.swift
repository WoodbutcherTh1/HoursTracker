import Foundation

/// All user-facing strings for an exported report, resolved for a specific language
/// so the report language can differ from the app UI language.
struct ExportCopy {
    let locale: Locale
    let language: AppLocale.Language

    init(language: ExportLanguage) {
        self.language = language.resolvedLanguage
        self.locale = language.resolvedLocale
    }

    private func t(_ key: String) -> String {
        Self.table[key]?[language] ?? Self.table[key]?[.english] ?? key
    }

    private func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), locale: locale, arguments: args.map { $0 as Any })
    }

    // MARK: Titles & sections

    var title: String { t("report.title") }
    var payrollSummary: String { t("report.payrollSummary") }
    var hoursChart: String { t("report.hoursChart") }
    var payChart: String { t("report.payChart") }
    var dailyTable: String { t("report.dailyTable") }
    var allDays: String { t("report.allDays") }
    var total: String { t("report.total") }
    var legendTitle: String { t("report.legend.title") }

    // MARK: Header fields

    func worker(_ name: String) -> String { format("report.worker %@", name) }
    func idNumber(_ id: String) -> String { format("report.id %@", id) }
    func employee(_ num: String) -> String { format("report.employee %@", num) }
    func workplace(_ name: String) -> String { format("report.workplace %@", name) }
    func contractor(_ name: String) -> String { format("report.contractor %@", name) }
    func period(_ period: String) -> String { format("report.period %@", period) }
    func creditPoints(_ points: String) -> String { format("report.creditPoints %@", points) }

    // MARK: Columns

    var colDate: String { t("report.col.date") }
    var colDay: String { t("report.col.day") }
    var colIn: String { t("report.col.in") }
    var colOut: String { t("report.col.out") }
    var colRegular: String { t("report.col.regular") }
    var colOT125: String { t("report.col.ot125") }
    var colOT150: String { t("report.col.ot150") }
    var colGas: String { t("report.col.gas") }
    var colGross: String { t("report.col.gross") }
    var colNet: String { t("report.col.net") }
    var colType: String { t("report.col.type") }

    var colTotalHours: String { t("report.summary.totalHours") }
    var colGrossPay: String { t("report.summary.grossPay") }
    var colNetPay: String { t("report.summary.netPay") }
    var colDeductions: String { t("report.summary.deductions") }

    // MARK: Legend

    var legendLines: [String] {
        [
            t("report.legend.day"),
            t("report.legend.date"),
            t("report.legend.in"),
            t("report.legend.out"),
            t("report.legend.regular"),
            t("report.legend.ot125"),
            t("report.legend.ot150"),
            t("report.legend.gas"),
            t("report.legend.gross"),
            t("report.legend.net"),
            t("report.legend.type")
        ]
    }

    // MARK: Entry types

    var entryManual: String { t("entry.manual") }
    var entryAutomatic: String { t("entry.automatic") }
    var entryScanned: String { t("entry.ai") }

    /// Explicit table so export language is independent of the device UI locale.
    private static let table: [String: [AppLocale.Language: String]] = [
        "report.title": [
            .english: "Work Hours Report",
            .arabic: "تقرير ساعات العمل",
            .hebrew: "דוח שעות עבודה"
        ],
        "report.payrollSummary": [
            .english: "Payroll summary",
            .arabic: "ملخص الرواتب",
            .hebrew: "סיכום שכר"
        ],
        "report.hoursChart": [
            .english: "Hours breakdown",
            .arabic: "توزيع الساعات",
            .hebrew: "פילוח שעות"
        ],
        "report.payChart": [
            .english: "Pay breakdown",
            .arabic: "توزيع الأجر",
            .hebrew: "פילוח שכר"
        ],
        "report.dailyTable": [
            .english: "Daily details",
            .arabic: "تفاصيل الأيام",
            .hebrew: "פירוט ימים"
        ],
        "report.allDays": [
            .english: "All Days",
            .arabic: "جميع الأيام",
            .hebrew: "כל הימים"
        ],
        "report.total": [
            .english: "Total",
            .arabic: "الإجمالي",
            .hebrew: "סה״כ"
        ],
        "report.legend.title": [
            .english: "Column guide",
            .arabic: "شرح أعمدة الجدول",
            .hebrew: "מדריך עמודות"
        ],
        "report.worker %@": [
            .english: "Worker: %@",
            .arabic: "العامل: %@",
            .hebrew: "עובד: %@"
        ],
        "report.id %@": [
            .english: "ID: %@",
            .arabic: "الهوية: %@",
            .hebrew: "ת.ז.: %@"
        ],
        "report.employee %@": [
            .english: "Employee #: %@",
            .arabic: "رقم الموظف: %@",
            .hebrew: "מס׳ עובד: %@"
        ],
        "report.workplace %@": [
            .english: "Workplace: %@",
            .arabic: "مكان العمل: %@",
            .hebrew: "מקום עבודה: %@"
        ],
        "report.contractor %@": [
            .english: "Contractor: %@",
            .arabic: "المقاول: %@",
            .hebrew: "קבלן: %@"
        ],
        "report.period %@": [
            .english: "Period: %@",
            .arabic: "الفترة: %@",
            .hebrew: "תקופה: %@"
        ],
        "report.creditPoints %@": [
            .english: "Credit Points: %@",
            .arabic: "نقاط الائتمان: %@",
            .hebrew: "נקודות זיכוי: %@"
        ],
        "report.col.day": [
            .english: "Day",
            .arabic: "اليوم",
            .hebrew: "יום"
        ],
        "report.col.date": [
            .english: "Date",
            .arabic: "التاريخ",
            .hebrew: "תאריך"
        ],
        "report.col.in": [
            .english: "In",
            .arabic: "دخول",
            .hebrew: "כניסה"
        ],
        "report.col.out": [
            .english: "Out",
            .arabic: "خروج",
            .hebrew: "יציאה"
        ],
        "report.col.regular": [
            .english: "Regular",
            .arabic: "عادي",
            .hebrew: "רגיל"
        ],
        "report.col.ot125": [
            .english: "125% OT",
            .arabic: "إضافي 125%",
            .hebrew: "125% נוסף"
        ],
        "report.col.ot150": [
            .english: "150% OT",
            .arabic: "إضافي 150%",
            .hebrew: "150% נוסף"
        ],
        "report.col.gas": [
            .english: "Gas",
            .arabic: "وقود",
            .hebrew: "דלק"
        ],
        "report.col.gross": [
            .english: "Gross",
            .arabic: "إجمالي",
            .hebrew: "ברוטו"
        ],
        "report.col.net": [
            .english: "Net",
            .arabic: "صافي",
            .hebrew: "נטו"
        ],
        "report.col.type": [
            .english: "Type",
            .arabic: "النوع",
            .hebrew: "סוג"
        ],
        "report.summary.totalHours": [
            .english: "Total hours",
            .arabic: "إجمالي الساعات",
            .hebrew: "סה״כ שעות"
        ],
        "report.summary.grossPay": [
            .english: "Gross pay",
            .arabic: "الأجر الإجمالي",
            .hebrew: "שכר ברוטו"
        ],
        "report.summary.netPay": [
            .english: "Net pay",
            .arabic: "الأجر الصافي",
            .hebrew: "שכר נטו"
        ],
        "report.summary.deductions": [
            .english: "Deductions",
            .arabic: "الخصومات",
            .hebrew: "ניכויים"
        ],
        "report.legend.day": [
            .english: "Day: Weekday name.",
            .arabic: "اليوم: اسم يوم الأسبوع.",
            .hebrew: "יום: שם יום השבוע."
        ],
        "report.legend.date": [
            .english: "Date: The work day date.",
            .arabic: "التاريخ: تاريخ يوم العمل.",
            .hebrew: "תאריך: תאריך יום העבודה."
        ],
        "report.legend.in": [
            .english: "In: Clock-in / shift start time.",
            .arabic: "دخول: وقت بداية الوردية (تسجيل الدخول).",
            .hebrew: "כניסה: שעת תחילת המשמרת."
        ],
        "report.legend.out": [
            .english: "Out: Clock-out / shift end time.",
            .arabic: "خروج: وقت نهاية الوردية (تسجيل الخروج).",
            .hebrew: "יציאה: שעת סיום המשמרת."
        ],
        "report.legend.regular": [
            .english: "Regular: Base-rate hours (100% on regular days; 150% on rest days/holidays).",
            .arabic: "عادي: ساعات العمل العادية المدفوعة بنسبة 100% (أو 150% في يوم الراحة/العيد).",
            .hebrew: "רגיל: שעות במחיר הבסיס (100% ביום רגיל; 150% ביום מנוחה/חג)."
        ],
        "report.legend.ot125": [
            .english: "125% OT: First overtime tier (125% regular day; 175% rest day/holiday).",
            .arabic: "إضافي 125%: ساعات إضافية بالشريحة الأولى (125% في يوم عادي؛ 175% في يوم راحة/عيد).",
            .hebrew: "125% נוסף: שעות נוספות בשכבה הראשונה (125% ביום רגיל; 175% ביום מנוחה/חג)."
        ],
        "report.legend.ot150": [
            .english: "150% OT: Second overtime tier (150% regular day; 200% rest day/holiday).",
            .arabic: "إضافي 150%: ساعات إضافية بالشريحة الثانية (150% في يوم عادي؛ 200% في يوم راحة/عيد).",
            .hebrew: "150% נוסף: שעות נוספות בשכבה השנייה (150% ביום רגיל; 200% ביום מנוחה/חג)."
        ],
        "report.legend.gas": [
            .english: "Gas: Daily fuel/gas allowance from settings.",
            .arabic: "وقود: بدل الوقود اليومي حسب الإعدادات.",
            .hebrew: "דלק: תוספת דלק יומית לפי ההגדרות."
        ],
        "report.legend.gross": [
            .english: "Gross: Daily gross wage before deductions — regular + overtime + gas.",
            .arabic: "إجمالي: الأجر اليومي الإجمالي (بروطو) قبل الخصومات — يشمل الساعات العادية والإضافي وبدل الوقود.",
            .hebrew: "ברוטו: השכר היומי לפני ניכויים — כולל רגיל, שעות נוספות ודלק."
        ],
        "report.legend.net": [
            .english: "Net: Estimated daily net pay after income tax, National Insurance, and Health Tax.",
            .arabic: "صافي: تقدير الأجر الصافي لليوم بعد ضريبة الدخل والتأمين الوطني وضريبة الصحة.",
            .hebrew: "נטו: הערכת השכר נטו ליום אחרי מס הכנסה, ביטוח לאומי ומס בריאות."
        ],
        "report.legend.type": [
            .english: "Type: How the shift was recorded — automatic, manual, or scanned.",
            .arabic: "النوع: طريقة تسجيل الوردية — تلقائي، يدوي، أو عبر المسح الضوئي.",
            .hebrew: "סוג: איך נרשמה המשמרת — אוטומטי, ידני או סריקה."
        ],
        "entry.manual": [
            .english: "Manual",
            .arabic: "يدوي",
            .hebrew: "ידני"
        ],
        "entry.automatic": [
            .english: "Automatic",
            .arabic: "أوتوماتيكي",
            .hebrew: "אוטומטי"
        ],
        "entry.ai": [
            .english: "Scanned",
            .arabic: "مسح ضوئي",
            .hebrew: "סריקה"
        ]
    ]
}
