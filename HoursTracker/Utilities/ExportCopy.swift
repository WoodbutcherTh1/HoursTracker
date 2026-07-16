import Foundation

/// All user-facing strings for an exported report, resolved for a specific language
/// so the report is entirely in one language — never a Hebrew/English mix.
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

    private func format(_ key: String, _ value: String) -> String {
        // Single-argument %@ templates only. Avoid `String(format:locale:arguments:)` —
        // Xcode 16.4 rejects that overload as ambiguous even with an explicit `[Any]`.
        String(format: t(key), value)
    }

    // MARK: Titles & sections

    var title: String { t("report.title") }
    var payrollSummary: String { t("report.payrollSummary") }
    var hoursChart: String { t("report.hoursChart") }
    var payChart: String { t("report.payChart") }
    var deductionsChart: String { t("report.deductionsChart") }
    var dailyTable: String { t("report.dailyTable") }
    var allDays: String { t("report.allDays") }

    func yearLabel(_ year: Int) -> String {
        format("report.year %@", String(year))
    }
    var total: String { t("report.total") }

    // MARK: Full data export (PDF / CSV headers)

    var fullExportTitle: String { t("fullExport.title") }
    var fullExportExportedAt: String { t("fullExport.exportedAt") }
    var fullExportProfile: String { t("fullExport.profile") }
    var fullExportStatistics: String { t("fullExport.statistics") }
    var fullExportSessions: String { t("fullExport.sessions") }
    var fullExportActivityLog: String { t("fullExport.activityLog") }
    var fullExportTotalShifts: String { t("fullExport.totalShifts") }
    var fullExportOpenShifts: String { t("fullExport.openShifts") }
    var fullExportOpen: String { t("fullExport.open") }
    var fullExportNotes: String { t("fullExport.notes") }
    var fullExportPayrollStart: String { t("fullExport.payrollStart") }
    var fullExportCurrency: String { t("fullExport.currency") }

    var fullExportCSVField: String { t("fullExport.csv.field") }
    var fullExportCSVValue: String { t("fullExport.csv.value") }
    var fullExportCSVId: String { t("fullExport.csv.id") }
    var fullExportCSVIsOpen: String { t("fullExport.csv.isOpen") }
    var fullExportCSVManual: String { t("fullExport.csv.manual") }
    var fullExportCSVAIImported: String { t("fullExport.csv.aiImported") }
    var fullExportCSVDayType: String { t("fullExport.csv.dayType") }
    var fullExportCSVNight: String { t("fullExport.csv.night") }
    var fullExportCSVModifiedAt: String { t("fullExport.csv.modifiedAt") }
    var fullExportCSVEffectiveHours: String { t("fullExport.csv.effectiveHours") }
    var fullExportCSVBasePay: String { t("fullExport.csv.basePay") }
    var fullExportCSVOT125Pay: String { t("fullExport.csv.ot125Pay") }
    var fullExportCSVOT150Pay: String { t("fullExport.csv.ot150Pay") }
    var fullExportCSVIncomeTax: String { t("fullExport.csv.incomeTax") }
    var fullExportCSVNationalInsurance: String { t("fullExport.csv.nationalInsurance") }
    var fullExportCSVHealthTax: String { t("fullExport.csv.healthTax") }
    var fullExportCSVTimestamp: String { t("fullExport.csv.timestamp") }
    var fullExportCSVLevel: String { t("fullExport.csv.level") }
    var fullExportCSVCategory: String { t("fullExport.csv.category") }
    var fullExportCSVMessage: String { t("fullExport.csv.message") }
    var fullExportCSVDetails: String { t("fullExport.csv.details") }

    // MARK: Header fields

    func worker(_ name: String) -> String { format("report.worker %@", name) }
    func idNumber(_ id: String) -> String { format("report.id %@", id) }
    func employee(_ num: String) -> String { format("report.employee %@", num) }
    func workplace(_ name: String) -> String { format("report.workplace %@", name) }
    func contractor(_ name: String) -> String { format("report.contractor %@", name) }
    func period(_ period: String) -> String { format("report.period %@", period) }
    func creditPoints(_ points: String) -> String { format("report.creditPoints %@", points) }

    // MARK: Daily table columns (classic payroll timesheet)

    var colDay: String { t("report.col.day") }
    var colDate: String { t("report.col.date") }
    var colIn: String { t("report.col.in") }
    var colOut: String { t("report.col.out") }
    var colBreak: String { t("report.col.break") }
    var colTotalHours: String { t("report.col.totalHours") }
    /// Rate columns stay numeric (100% / 125% / 150%) in every language — not a language mix.
    var colRate100: String { "100%" }
    var colRate125: String { "125%" }
    var colRate150: String { "150%" }
    var colTravel: String { t("report.col.travel") }
    var colDailyWage: String { t("report.col.dailyWage") }

    // MARK: Summary / chart labels

    var colSummaryTotalHours: String { t("report.summary.totalHours") }
    var colGrossPay: String { t("report.summary.grossPay") }
    var colNetPay: String { t("report.summary.netPay") }
    var colDeductions: String { t("report.summary.deductions") }
    var colRegular: String { t("report.col.regular") }
    var colOT125: String { t("report.col.ot125") }
    var colOT150: String { t("report.col.ot150") }
    var colGas: String { t("report.col.travel") }
    var colIncomeTax: String { t("report.col.incomeTax") }
    var colNationalInsurance: String { t("report.col.nationalInsurance") }
    var colHealthTax: String { t("report.col.healthTax") }

    /// Explicit table so each export language is complete and self-contained.
    private static let table: [String: [AppLocale.Language: String]] = [
        "report.title": [
            .english: "Monthly Hours Report",
            .arabic: "تقرير الساعات الشهري",
            .hebrew: "דוח שעות חודשי"
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
        "report.deductionsChart": [
            .english: "Estimated deductions",
            .arabic: "الخصومات التقديرية",
            .hebrew: "ניכויים משוערים"
        ],
        "report.col.incomeTax": [
            .english: "Income tax",
            .arabic: "ضريبة دخل",
            .hebrew: "מס הכנסה"
        ],
        "report.col.nationalInsurance": [
            .english: "National insurance",
            .arabic: "تأمين وطني",
            .hebrew: "ביטוח לאומי"
        ],
        "report.col.healthTax": [
            .english: "Health tax",
            .arabic: "ضريبة صحة",
            .hebrew: "מס בריאות"
        ],
        "report.dailyTable": [
            .english: "Daily details",
            .arabic: "تفاصيل الأيام",
            .hebrew: "פירוט ימים"
        ],
        "report.allDays": [
            .english: "All days",
            .arabic: "جميع الأيام",
            .hebrew: "כל הימים"
        ],
        "report.year %@": [
            .english: "%@",
            .arabic: "%@",
            .hebrew: "%@"
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
            .english: "ID number: %@",
            .arabic: "رقم الهوية: %@",
            .hebrew: "תעודת זהות: %@"
        ],
        "report.employee %@": [
            .english: "Employee number: %@",
            .arabic: "رقم الموظف: %@",
            .hebrew: "מספר עובד: %@"
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
            .english: "Credit points: %@",
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
        "report.col.break": [
            .english: "Break",
            .arabic: "استراحة",
            .hebrew: "הפסקה"
        ],
        "report.col.totalHours": [
            .english: "Total",
            .arabic: "المجموع",
            .hebrew: "סה״כ"
        ],
        "report.col.regular": [
            .english: "Regular",
            .arabic: "عادي",
            .hebrew: "רגיל"
        ],
        "report.col.ot125": [
            .english: "Overtime 125%",
            .arabic: "إضافي 125%",
            .hebrew: "שעות נוספות 125%"
        ],
        "report.col.ot150": [
            .english: "Overtime 150%",
            .arabic: "إضافي 150%",
            .hebrew: "שעות נוספות 150%"
        ],
        "report.col.travel": [
            .english: "Travel",
            .arabic: "مواصلات",
            .hebrew: "נסיעות"
        ],
        "report.col.dailyWage": [
            .english: "Daily wage",
            .arabic: "الأجر اليومي",
            .hebrew: "שכר יומי"
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
            .english: "Day: weekday name.",
            .arabic: "اليوم: اسم يوم الأسبوع.",
            .hebrew: "יום: שם יום השבוע."
        ],
        "report.legend.date": [
            .english: "Date: the work day date.",
            .arabic: "التاريخ: تاريخ يوم العمل.",
            .hebrew: "תאריך: תאריך יום העבודה."
        ],
        "report.legend.in": [
            .english: "In: clock-in time.",
            .arabic: "دخول: وقت بداية الوردية.",
            .hebrew: "כניסה: שעת התחלת המשמרת."
        ],
        "report.legend.out": [
            .english: "Out: clock-out time.",
            .arabic: "خروج: وقت نهاية الوردية.",
            .hebrew: "יציאה: שעת סיום המשמרת."
        ],
        "report.legend.break": [
            .english: "Break: unpaid break in hours.",
            .arabic: "استراحة: مدة الاستراحة غير المدفوعة بالساعات.",
            .hebrew: "הפסקה: משך הפסקה ללא תשלום בשעות."
        ],
        "report.legend.totalHours": [
            .english: "Total: paid hours after break.",
            .arabic: "المجموع: الساعات المدفوعة بعد خصم الاستراحة.",
            .hebrew: "סה״כ: שעות בתשלום אחרי הפסקה."
        ],
        "report.legend.rate100": [
            .english: "100%: regular-rate hours.",
            .arabic: "100%: الساعات بالأجر العادي.",
            .hebrew: "100%: שעות בתעריף רגיל."
        ],
        "report.legend.rate125": [
            .english: "125%: first overtime tier.",
            .arabic: "125%: الشريحة الأولى من الساعات الإضافية.",
            .hebrew: "125%: שכבת שעות נוספות ראשונה."
        ],
        "report.legend.rate150": [
            .english: "150%: second overtime tier.",
            .arabic: "150%: الشريحة الثانية من الساعات الإضافية.",
            .hebrew: "150%: שכבת שעות נוספות שנייה."
        ],
        "report.legend.travel": [
            .english: "Travel: daily travel allowance.",
            .arabic: "مواصلات: بدل المواصلات اليومي.",
            .hebrew: "נסיעות: תוספת נסיעות יומית."
        ],
        "report.legend.dailyWage": [
            .english: "Daily wage: gross pay for that day.",
            .arabic: "الأجر اليومي: الأجر الإجمالي لذلك اليوم.",
            .hebrew: "שכר יומי: השכר ברוטו לאותו יום."
        ],
        "fullExport.title": [
            .english: "HoursTracker — Full Data Export",
            .arabic: "HoursTracker — تصدير كامل للبيانات",
            .hebrew: "HoursTracker — ייצוא נתונים מלא"
        ],
        "fullExport.exportedAt": [
            .english: "Exported",
            .arabic: "تاريخ التصدير",
            .hebrew: "יוצא בתאריך"
        ],
        "fullExport.profile": [
            .english: "Profile & settings",
            .arabic: "الملف الشخصي والإعدادات",
            .hebrew: "פרופיל והגדרות"
        ],
        "fullExport.statistics": [
            .english: "Lifetime statistics",
            .arabic: "إحصاءات إجمالية",
            .hebrew: "סטטיסטיקה מצטברת"
        ],
        "fullExport.sessions": [
            .english: "All work sessions",
            .arabic: "كل الورديات",
            .hebrew: "כל המשמרות"
        ],
        "fullExport.activityLog": [
            .english: "Activity log",
            .arabic: "سجل النشاط",
            .hebrew: "יומן פעילות"
        ],
        "fullExport.totalShifts": [
            .english: "Total shifts",
            .arabic: "إجمالي الورديات",
            .hebrew: "סה״כ משמרות"
        ],
        "fullExport.openShifts": [
            .english: "Open shifts",
            .arabic: "ورديات مفتوحة",
            .hebrew: "משמרות פתוחות"
        ],
        "fullExport.open": [
            .english: "Open",
            .arabic: "مفتوحة",
            .hebrew: "פתוחה"
        ],
        "fullExport.notes": [
            .english: "Notes",
            .arabic: "ملاحظات",
            .hebrew: "הערות"
        ],
        "fullExport.payrollStart": [
            .english: "Payroll start day",
            .arabic: "يوم بداية شهر الراتب",
            .hebrew: "יום תחילת חודש שכר"
        ],
        "fullExport.currency": [
            .english: "Currency",
            .arabic: "العملة",
            .hebrew: "מטבע"
        ],
        "fullExport.csv.field": [
            .english: "Field",
            .arabic: "الحقل",
            .hebrew: "שדה"
        ],
        "fullExport.csv.value": [
            .english: "Value",
            .arabic: "القيمة",
            .hebrew: "ערך"
        ],
        "fullExport.csv.id": [
            .english: "ID",
            .arabic: "المعرّف",
            .hebrew: "מזהה"
        ],
        "fullExport.csv.isOpen": [
            .english: "Open",
            .arabic: "مفتوحة",
            .hebrew: "פתוחה"
        ],
        "fullExport.csv.manual": [
            .english: "Manual",
            .arabic: "يدوي",
            .hebrew: "ידני"
        ],
        "fullExport.csv.aiImported": [
            .english: "AI imported",
            .arabic: "مستورد بالذكاء الاصطناعي",
            .hebrew: "יובא בבינה מלאכותית"
        ],
        "fullExport.csv.dayType": [
            .english: "Day type",
            .arabic: "نوع اليوم",
            .hebrew: "סוג יום"
        ],
        "fullExport.csv.night": [
            .english: "Night shift",
            .arabic: "وردية ليلية",
            .hebrew: "משמרת לילה"
        ],
        "fullExport.csv.modifiedAt": [
            .english: "Modified",
            .arabic: "آخر تعديل",
            .hebrew: "עודכן"
        ],
        "fullExport.csv.effectiveHours": [
            .english: "Effective hours",
            .arabic: "ساعات فعّالة",
            .hebrew: "שעות אפקטיביות"
        ],
        "fullExport.csv.basePay": [
            .english: "Base pay",
            .arabic: "أجر أساسي",
            .hebrew: "שכר בסיס"
        ],
        "fullExport.csv.ot125Pay": [
            .english: "125% pay",
            .arabic: "أجر 125%",
            .hebrew: "שכר 125%"
        ],
        "fullExport.csv.ot150Pay": [
            .english: "150% pay",
            .arabic: "أجر 150%",
            .hebrew: "שכר 150%"
        ],
        "fullExport.csv.incomeTax": [
            .english: "Income tax",
            .arabic: "ضريبة دخل",
            .hebrew: "מס הכנסה"
        ],
        "fullExport.csv.nationalInsurance": [
            .english: "National insurance",
            .arabic: "تأمين وطني",
            .hebrew: "ביטוח לאומי"
        ],
        "fullExport.csv.healthTax": [
            .english: "Health tax",
            .arabic: "ضريبة صحة",
            .hebrew: "מס בריאות"
        ],
        "fullExport.csv.timestamp": [
            .english: "Timestamp",
            .arabic: "الطابع الزمني",
            .hebrew: "חותמת זמן"
        ],
        "fullExport.csv.level": [
            .english: "Level",
            .arabic: "المستوى",
            .hebrew: "רמה"
        ],
        "fullExport.csv.category": [
            .english: "Category",
            .arabic: "الفئة",
            .hebrew: "קטגוריה"
        ],
        "fullExport.csv.message": [
            .english: "Message",
            .arabic: "الرسالة",
            .hebrew: "הודעה"
        ],
        "fullExport.csv.details": [
            .english: "Details",
            .arabic: "التفاصيل",
            .hebrew: "פרטים"
        ]
    ]
}
