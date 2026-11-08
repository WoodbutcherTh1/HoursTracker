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

    /// Only shown when a report's rows actually span more than one workplace.
    var colWorkplace: String { t("report.col.workplace") }
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
            .hebrew: "דוח שעות חודשי",
            .russian: "Ежемесячный отчёт о часах",
            .thai: "รายงานชั่วโมงทำงานรายเดือน"
        ],
        "report.payrollSummary": [
            .english: "Payroll summary",
            .arabic: "ملخص الرواتب",
            .hebrew: "סיכום שכר",
            .russian: "Сводка по зарплате",
            .thai: "สรุปเงินเดือน"
        ],
        "report.hoursChart": [
            .english: "Hours breakdown",
            .arabic: "توزيع الساعات",
            .hebrew: "פילוח שעות",
            .russian: "Распределение часов",
            .thai: "รายละเอียดชั่วโมงทำงาน"
        ],
        "report.payChart": [
            .english: "Pay breakdown",
            .arabic: "توزيع الأجر",
            .hebrew: "פילוח שכר",
            .russian: "Распределение оплаты",
            .thai: "รายละเอียดค่าจ้าง"
        ],
        "report.deductionsChart": [
            .english: "Estimated deductions",
            .arabic: "الخصومات التقديرية",
            .hebrew: "ניכויים משוערים",
            .russian: "Примерные удержания",
            .thai: "ยอดหักประมาณการ"
        ],
        "report.col.incomeTax": [
            .english: "Income tax",
            .arabic: "ضريبة دخل",
            .hebrew: "מס הכנסה",
            .russian: "Подоходный налог",
            .thai: "ภาษีเงินได้"
        ],
        "report.col.nationalInsurance": [
            .english: "National insurance",
            .arabic: "تأمين وطني",
            .hebrew: "ביטוח לאומי",
            .russian: "Битуах леуми",
            .thai: "ประกันสังคม"
        ],
        "report.col.healthTax": [
            .english: "Health tax",
            .arabic: "ضريبة صحة",
            .hebrew: "מס בריאות",
            .russian: "Налог на здравоохранение",
            .thai: "ภาษีสุขภาพ"
        ],
        "report.dailyTable": [
            .english: "Daily details",
            .arabic: "تفاصيل الأيام",
            .hebrew: "פירוט ימים",
            .russian: "Данные по дням",
            .thai: "รายละเอียดประจำวัน"
        ],
        "report.allDays": [
            .english: "All days",
            .arabic: "جميع الأيام",
            .hebrew: "כל הימים",
            .russian: "Все дни",
            .thai: "ทุกวัน"
        ],
        "report.year %@": [
            .english: "%@",
            .arabic: "%@",
            .hebrew: "%@",
            .russian: "%@",
            .thai: "%@"
        ],
        "report.total": [
            .english: "Total",
            .arabic: "الإجمالي",
            .hebrew: "סה״כ",
            .russian: "Итого",
            .thai: "รวม"
        ],
        "report.legend.title": [
            .english: "Column guide",
            .arabic: "شرح أعمدة الجدول",
            .hebrew: "מדריך עמודות",
            .russian: "Пояснения к столбцам",
            .thai: "คำอธิบายคอลัมน์"
        ],
        "report.worker %@": [
            .english: "Worker: %@",
            .arabic: "العامل: %@",
            .hebrew: "עובד: %@",
            .russian: "Работник: %@",
            .thai: "พนักงาน: %@"
        ],
        "report.id %@": [
            .english: "ID number: %@",
            .arabic: "رقم الهوية: %@",
            .hebrew: "תעודת זהות: %@",
            .russian: "Номер удостоверения: %@",
            .thai: "เลขประจำตัว: %@"
        ],
        "report.employee %@": [
            .english: "Employee number: %@",
            .arabic: "رقم الموظف: %@",
            .hebrew: "מספר עובד: %@",
            .russian: "Табельный номер: %@",
            .thai: "เลขที่พนักงาน: %@"
        ],
        "report.workplace %@": [
            .english: "Workplace: %@",
            .arabic: "مكان العمل: %@",
            .hebrew: "מקום עבודה: %@",
            .russian: "Место работы: %@",
            .thai: "สถานที่ทำงาน: %@"
        ],
        "report.contractor %@": [
            .english: "Contractor: %@",
            .arabic: "المقاول: %@",
            .hebrew: "קבלן: %@",
            .russian: "Подрядчик: %@",
            .thai: "ผู้รับเหมา: %@"
        ],
        "report.period %@": [
            .english: "Period: %@",
            .arabic: "الفترة: %@",
            .hebrew: "תקופה: %@",
            .russian: "Период: %@",
            .thai: "ช่วงเวลา: %@"
        ],
        "report.creditPoints %@": [
            .english: "Credit points: %@",
            .arabic: "نقاط الائتمان: %@",
            .hebrew: "נקודות זיכוי: %@",
            .russian: "Налоговые пункты: %@",
            .thai: "แต้มเครดิตภาษี: %@"
        ],
        "report.col.workplace": [
            .english: "Workplace",
            .arabic: "مكان العمل",
            .hebrew: "מקום עבודה",
            .russian: "Место работы",
            .thai: "สถานที่ทำงาน"
        ],
        "report.col.day": [
            .english: "Day",
            .arabic: "اليوم",
            .hebrew: "יום",
            .russian: "День",
            .thai: "วัน"
        ],
        "report.col.date": [
            .english: "Date",
            .arabic: "التاريخ",
            .hebrew: "תאריך",
            .russian: "Дата",
            .thai: "วันที่"
        ],
        "report.col.in": [
            .english: "In",
            .arabic: "دخول",
            .hebrew: "כניסה",
            .russian: "Начало",
            .thai: "เข้า"
        ],
        "report.col.out": [
            .english: "Out",
            .arabic: "خروج",
            .hebrew: "יציאה",
            .russian: "Конец",
            .thai: "ออก"
        ],
        "report.col.break": [
            .english: "Break",
            .arabic: "استراحة",
            .hebrew: "הפסקה",
            .russian: "Перерыв",
            .thai: "พัก"
        ],
        "report.col.totalHours": [
            .english: "Total",
            .arabic: "المجموع",
            .hebrew: "סה״כ",
            .russian: "Итого",
            .thai: "รวม"
        ],
        "report.col.regular": [
            .english: "Regular",
            .arabic: "عادي",
            .hebrew: "רגיל",
            .russian: "Обычные",
            .thai: "ปกติ"
        ],
        "report.col.ot125": [
            .english: "Overtime 125%",
            .arabic: "إضافي 125%",
            .hebrew: "שעות נוספות 125%",
            .russian: "Сверхурочные 125%",
            .thai: "ล่วงเวลา 125%"
        ],
        "report.col.ot150": [
            .english: "Overtime 150%",
            .arabic: "إضافي 150%",
            .hebrew: "שעות נוספות 150%",
            .russian: "Сверхурочные 150%",
            .thai: "ล่วงเวลา 150%"
        ],
        "report.col.travel": [
            .english: "Travel",
            .arabic: "مواصلات",
            .hebrew: "נסיעות",
            .russian: "Проезд",
            .thai: "ค่าเดินทาง"
        ],
        "report.col.dailyWage": [
            .english: "Daily wage",
            .arabic: "الأجر اليومي",
            .hebrew: "שכר יומי",
            .russian: "Оплата за день",
            .thai: "ค่าจ้างต่อวัน"
        ],
        "report.summary.totalHours": [
            .english: "Total hours",
            .arabic: "إجمالي الساعات",
            .hebrew: "סה״כ שעות",
            .russian: "Всего часов",
            .thai: "ชั่วโมงรวม"
        ],
        "report.summary.grossPay": [
            .english: "Gross pay",
            .arabic: "الأجر الإجمالي",
            .hebrew: "שכר ברוטו",
            .russian: "Брутто",
            .thai: "เงินเดือนรวม"
        ],
        "report.summary.netPay": [
            .english: "Net pay",
            .arabic: "الأجر الصافي",
            .hebrew: "שכר נטו",
            .russian: "Нетто",
            .thai: "เงินเดือนสุทธิ"
        ],
        "report.summary.deductions": [
            .english: "Deductions",
            .arabic: "الخصومات",
            .hebrew: "ניכויים",
            .russian: "Удержания",
            .thai: "รายการหัก"
        ],
        "report.legend.day": [
            .english: "Day: weekday name.",
            .arabic: "اليوم: اسم يوم الأسبوع.",
            .hebrew: "יום: שם יום השבוע.",
            .russian: "День: день недели.",
            .thai: "วัน: ชื่อวันในสัปดาห์"
        ],
        "report.legend.date": [
            .english: "Date: the work day date.",
            .arabic: "التاريخ: تاريخ يوم العمل.",
            .hebrew: "תאריך: תאריך יום העבודה.",
            .russian: "Дата: дата рабочего дня.",
            .thai: "วันที่: วันที่ทำงาน"
        ],
        "report.legend.in": [
            .english: "In: clock-in time.",
            .arabic: "دخول: وقت بداية الوردية.",
            .hebrew: "כניסה: שעת התחלת המשמרת.",
            .russian: "Начало: время начала смены.",
            .thai: "เข้า: เวลาเข้างาน"
        ],
        "report.legend.out": [
            .english: "Out: clock-out time.",
            .arabic: "خروج: وقت نهاية الوردية.",
            .hebrew: "יציאה: שעת סיום המשמרת.",
            .russian: "Конец: время окончания смены.",
            .thai: "ออก: เวลาออกงาน"
        ],
        "report.legend.break": [
            .english: "Break: unpaid break in hours.",
            .arabic: "استراحة: مدة الاستراحة غير المدفوعة بالساعات.",
            .hebrew: "הפסקה: משך הפסקה ללא תשלום בשעות.",
            .russian: "Перерыв: неоплачиваемый перерыв в часах.",
            .thai: "พัก: เวลาพักที่ไม่รับค่าจ้าง (ชั่วโมง)"
        ],
        "report.legend.totalHours": [
            .english: "Total: paid hours after break.",
            .arabic: "المجموع: الساعات المدفوعة بعد خصم الاستراحة.",
            .hebrew: "סה״כ: שעות בתשלום אחרי הפסקה.",
            .russian: "Итого: оплачиваемые часы за вычетом перерыва.",
            .thai: "รวม: ชั่วโมงที่รับค่าจ้างหลังหักเวลาพัก"
        ],
        "report.legend.rate100": [
            .english: "100%: regular-rate hours.",
            .arabic: "100%: الساعات بالأجر العادي.",
            .hebrew: "100%: שעות בתעריף רגיל.",
            .russian: "100%: часы по обычной ставке.",
            .thai: "100%: ชั่วโมงอัตราปกติ"
        ],
        "report.legend.rate125": [
            .english: "125%: first overtime tier.",
            .arabic: "125%: الشريحة الأولى من الساعات الإضافية.",
            .hebrew: "125%: שכבת שעות נוספות ראשונה.",
            .russian: "125%: первая ступень сверхурочных.",
            .thai: "125%: ล่วงเวลาระดับแรก"
        ],
        "report.legend.rate150": [
            .english: "150%: second overtime tier.",
            .arabic: "150%: الشريحة الثانية من الساعات الإضافية.",
            .hebrew: "150%: שכבת שעות נוספות שנייה.",
            .russian: "150%: вторая ступень сверхурочных.",
            .thai: "150%: ล่วงเวลาระดับที่สอง"
        ],
        "report.legend.travel": [
            .english: "Travel: daily travel allowance.",
            .arabic: "مواصلات: بدل المواصلات اليومي.",
            .hebrew: "נסיעות: תוספת נסיעות יומית.",
            .russian: "Проезд: ежедневная компенсация проезда.",
            .thai: "ค่าเดินทาง: เงินช่วยค่าเดินทางต่อวัน"
        ],
        "report.legend.dailyWage": [
            .english: "Daily wage: gross pay for that day.",
            .arabic: "الأجر اليومي: الأجر الإجمالي لذلك اليوم.",
            .hebrew: "שכר יומי: השכר ברוטו לאותו יום.",
            .russian: "Оплата за день: брутто за этот день.",
            .thai: "ค่าจ้างต่อวัน: เงินรวมก่อนหักของวันนั้น"
        ],
        "fullExport.title": [
            .english: "HoursTracker — Full Data Export",
            .arabic: "HoursTracker — تصدير كامل للبيانات",
            .hebrew: "HoursTracker — ייצוא נתונים מלא",
            .russian: "HoursTracker — полный экспорт данных",
            .thai: "HoursTracker — ส่งออกข้อมูลทั้งหมด"
        ],
        "fullExport.exportedAt": [
            .english: "Exported",
            .arabic: "تاريخ التصدير",
            .hebrew: "יוצא בתאריך",
            .russian: "Дата экспорта",
            .thai: "ส่งออกเมื่อ"
        ],
        "fullExport.profile": [
            .english: "Profile & settings",
            .arabic: "الملف الشخصي والإعدادات",
            .hebrew: "פרופיל והגדרות",
            .russian: "Профиль и настройки",
            .thai: "โปรไฟล์และการตั้งค่า"
        ],
        "fullExport.statistics": [
            .english: "Lifetime statistics",
            .arabic: "إحصاءات إجمالية",
            .hebrew: "סטטיסטיקה מצטברת",
            .russian: "Общая статистика",
            .thai: "สถิติทั้งหมด"
        ],
        "fullExport.sessions": [
            .english: "All work sessions",
            .arabic: "كل الورديات",
            .hebrew: "כל המשמרות",
            .russian: "Все смены",
            .thai: "กะงานทั้งหมด"
        ],
        "fullExport.activityLog": [
            .english: "Activity log",
            .arabic: "سجل النشاط",
            .hebrew: "יומן פעילות",
            .russian: "Журнал действий",
            .thai: "บันทึกกิจกรรม"
        ],
        "fullExport.totalShifts": [
            .english: "Total shifts",
            .arabic: "إجمالي الورديات",
            .hebrew: "סה״כ משמרות",
            .russian: "Всего смен",
            .thai: "จำนวนกะงานทั้งหมด"
        ],
        "fullExport.openShifts": [
            .english: "Open shifts",
            .arabic: "ورديات مفتوحة",
            .hebrew: "משמרות פתוחות",
            .russian: "Открытые смены",
            .thai: "กะงานที่ยังเปิดอยู่"
        ],
        "fullExport.open": [
            .english: "Open",
            .arabic: "مفتوحة",
            .hebrew: "פתוחה",
            .russian: "Открыта",
            .thai: "เปิดอยู่"
        ],
        "fullExport.notes": [
            .english: "Notes",
            .arabic: "ملاحظات",
            .hebrew: "הערות",
            .russian: "Заметки",
            .thai: "บันทึกย่อ"
        ],
        "fullExport.payrollStart": [
            .english: "Payroll start day",
            .arabic: "يوم بداية شهر الراتب",
            .hebrew: "יום תחילת חודש שכר",
            .russian: "День начала расчётного периода",
            .thai: "วันเริ่มรอบเงินเดือน"
        ],
        "fullExport.currency": [
            .english: "Currency",
            .arabic: "العملة",
            .hebrew: "מטבע",
            .russian: "Валюта",
            .thai: "สกุลเงิน"
        ],
        "fullExport.csv.field": [
            .english: "Field",
            .arabic: "الحقل",
            .hebrew: "שדה",
            .russian: "Поле",
            .thai: "ฟิลด์"
        ],
        "fullExport.csv.value": [
            .english: "Value",
            .arabic: "القيمة",
            .hebrew: "ערך",
            .russian: "Значение",
            .thai: "ค่า"
        ],
        "fullExport.csv.id": [
            .english: "ID",
            .arabic: "المعرّف",
            .hebrew: "מזהה",
            .russian: "ID",
            .thai: "รหัส"
        ],
        "fullExport.csv.isOpen": [
            .english: "Open",
            .arabic: "مفتوحة",
            .hebrew: "פתוחה",
            .russian: "Открыта",
            .thai: "เปิดอยู่"
        ],
        "fullExport.csv.manual": [
            .english: "Manual",
            .arabic: "يدوي",
            .hebrew: "ידני",
            .russian: "Вручную",
            .thai: "บันทึกเอง"
        ],
        "fullExport.csv.aiImported": [
            .english: "AI imported",
            .arabic: "مستورد بالذكاء الاصطناعي",
            .hebrew: "יובא בבינה מלאכותית",
            .russian: "Импорт с ИИ",
            .thai: "นำเข้าด้วย AI"
        ],
        "fullExport.csv.dayType": [
            .english: "Day type",
            .arabic: "نوع اليوم",
            .hebrew: "סוג יום",
            .russian: "Тип дня",
            .thai: "ประเภทวัน"
        ],
        "fullExport.csv.night": [
            .english: "Night shift",
            .arabic: "وردية ليلية",
            .hebrew: "משמרת לילה",
            .russian: "Ночная смена",
            .thai: "กะกลางคืน"
        ],
        "fullExport.csv.modifiedAt": [
            .english: "Modified",
            .arabic: "آخر تعديل",
            .hebrew: "עודכן",
            .russian: "Изменено",
            .thai: "แก้ไขเมื่อ"
        ],
        "fullExport.csv.effectiveHours": [
            .english: "Effective hours",
            .arabic: "ساعات فعّالة",
            .hebrew: "שעות אפקטיביות",
            .russian: "Эффективные часы",
            .thai: "ชั่วโมงที่มีผล"
        ],
        "fullExport.csv.basePay": [
            .english: "Base pay",
            .arabic: "أجر أساسي",
            .hebrew: "שכר בסיס",
            .russian: "Базовая оплата",
            .thai: "ค่าจ้างพื้นฐาน"
        ],
        "fullExport.csv.ot125Pay": [
            .english: "125% pay",
            .arabic: "أجر 125%",
            .hebrew: "שכר 125%",
            .russian: "Оплата 125%",
            .thai: "ค่าจ้าง 125%"
        ],
        "fullExport.csv.ot150Pay": [
            .english: "150% pay",
            .arabic: "أجر 150%",
            .hebrew: "שכר 150%",
            .russian: "Оплата 150%",
            .thai: "ค่าจ้าง 150%"
        ],
        "fullExport.csv.incomeTax": [
            .english: "Income tax",
            .arabic: "ضريبة دخل",
            .hebrew: "מס הכנסה",
            .russian: "Подоходный налог",
            .thai: "ภาษีเงินได้"
        ],
        "fullExport.csv.nationalInsurance": [
            .english: "National insurance",
            .arabic: "تأمين وطني",
            .hebrew: "ביטוח לאומי",
            .russian: "Битуах леуми",
            .thai: "ประกันสังคม"
        ],
        "fullExport.csv.healthTax": [
            .english: "Health tax",
            .arabic: "ضريبة صحة",
            .hebrew: "מס בריאות",
            .russian: "Налог на здравоохранение",
            .thai: "ภาษีสุขภาพ"
        ],
        "fullExport.csv.timestamp": [
            .english: "Timestamp",
            .arabic: "الطابع الزمني",
            .hebrew: "חותמת זמן",
            .russian: "Время",
            .thai: "เวลา"
        ],
        "fullExport.csv.level": [
            .english: "Level",
            .arabic: "المستوى",
            .hebrew: "רמה",
            .russian: "Уровень",
            .thai: "ระดับ"
        ],
        "fullExport.csv.category": [
            .english: "Category",
            .arabic: "الفئة",
            .hebrew: "קטגוריה",
            .russian: "Категория",
            .thai: "หมวดหมู่"
        ],
        "fullExport.csv.message": [
            .english: "Message",
            .arabic: "الرسالة",
            .hebrew: "הודעה",
            .russian: "Сообщение",
            .thai: "ข้อความ"
        ],
        "fullExport.csv.details": [
            .english: "Details",
            .arabic: "التفاصيل",
            .hebrew: "פרטים",
            .russian: "Подробности",
            .thai: "รายละเอียด"
        ]
    ]
}
