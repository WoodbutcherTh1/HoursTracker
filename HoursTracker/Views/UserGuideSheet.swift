import SwiftUI

/// In-app onboarding guide reachable from the Home toolbar. Every slide reuses the
/// real component/strings it's teaching — `HomeAnimatedDoorButton` for clock-in, the
/// exact swatch visuals from `HomeThemePickerSheet`, the real `DayType` picker and
/// `L10n.manualHolidayAutoFilled*` strings from `ManualEntryView`, the real
/// `L10n.scannerCloudEnabled` toggle from `SettingsView`, and the real
/// `AssistantToolbarButton` / `AssistantWelcomeView` for the assistant — rather than
/// illustrations that could drift from what the app actually does.
///
/// Only the assistant slide got a page of its own in the August 2026 batch. The Home
/// gross/net switch and History's worked-days badge are small enough to teach as an
/// extra line and an extra real element inside the slides that already cover those
/// screens; a whole slide each would pad the guide without telling anyone more.
///
/// September 2026 QA pass: slide copy re-verified against the shipping app and two
/// drifts fixed — the assistant moved from a floating overlay into each tab's
/// navigation bar (`MainTabView` comment), and the payslips slide no longer promises
/// share/export, which `PayslipDetailView` does not offer (it is preview/review/delete;
/// reports live in the Export tab).
///
/// The language pill lets you preview the guide's own authored captions in
/// EN/HE/AR/RU/TH independently of the app's language — chrome position is forced
/// `.leftToRight` regardless, so the pill, dots, and Next/Done button never move.
/// It intentionally does **not** re-language the embedded real components (the
/// Day Type picker, the cloud-AI toggle, …): `L10n`/`AppLocale` resolve strings
/// from the app's actual language setting, not from SwiftUI's `\.locale`
/// environment, so those slides correctly keep showing exactly what a real user
/// would see in the app's current language — faking that would be less honest
/// to "1:1 with the real app," not more.
struct UserGuideSheet: View {
    /// `WorkplaceSettings.workerFullName`, so the assistant slide previews the same
    /// personalized greeting the real chat will show rather than a generic stand-in.
    var workerName: String?

    @ObservedObject private var homeTheme = HomeAccentTheme.shared
    @ObservedObject private var appBackground = AppBackgroundTheme.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page = 0
    @State private var guideLanguage: GuideLanguage

    init(workerName: String? = nil) {
        self.workerName = workerName
        _guideLanguage = State(initialValue: GuideLanguage.matching(AppLanguageController.shared.preference))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            // The footer used to be a plain sibling row below the TabView; it now
            // reserves its space via `.safeAreaInset` instead, matching the same
            // pattern `slide()` uses for its own caption — belt-and-braces against
            // any slide content ever rendering taller than its allotted page height
            // and visually spilling into the footer's row.
            TabView(selection: $page) {
                slide(0, copy: GuideCopy.home) { GuideHomePage(accent: homeTheme.accent, guideLanguage: guideLanguage) }
                slide(1, copy: GuideCopy.theme) { GuideThemePage() }
                slide(2, copy: GuideCopy.history) { GuideHistoryPage(guideLanguage: guideLanguage) }
                slide(3, copy: GuideCopy.payslips) { GuidePayslipsPage(accent: homeTheme.accent, guideLanguage: guideLanguage) }
                slide(4, copy: GuideCopy.export) { GuideExportPage(accent: homeTheme.accent, guideLanguage: guideLanguage) }
                slide(5, copy: GuideCopy.shiftDetail) { GuideShiftDetailPage(guideLanguage: guideLanguage) }
                slide(6, copy: GuideCopy.settings) { GuideSettingsPage(guideLanguage: guideLanguage) }
                slide(7, copy: GuideCopy.widget) { GuideWidgetPage(accent: homeTheme.accent, guideLanguage: guideLanguage) }
                slide(8, copy: GuideCopy.assistant) {
                    GuideAssistantPage(accent: homeTheme.accent, workerName: workerName)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer
            }
        }
        .background(appBackground.background.ignoresSafeArea())
    }

    /// The caption used to be a `ZStack(alignment: .bottom)` overlay drawn on top of the
    /// slide's own content — content never knew space was reserved for it, so a tall
    /// caption (long subtitle) or content that itself reached toward the bottom (the
    /// History slide's `WorkedDaysBadge` "+1?" pill) could visually collide with it, and
    /// a caption tall enough could spill past the TabView page into the footer below.
    /// `.safeAreaInset` reserves real, non-overlapping space instead — any `ScrollView`
    /// inside `content()` automatically shrinks its content area to stop above it.
    private func slide<Content: View>(
        _ index: Int,
        copy: GuideCopy,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let text = copy.pair(for: guideLanguage)
        let alignment: HorizontalAlignment = guideLanguage.isRTL ? .trailing : .leading
        let caption = VStack(alignment: alignment, spacing: 4) {
            Text(text.title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            Text(text.subtitle)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
        .multilineTextAlignment(guideLanguage.isRTL ? .trailing : .leading)
        .padding(16)
        .background(.ultraThinMaterial)

        return content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                caption
            }
            .tag(index)
    }

    private var header: some View {
        HStack {
            Button(action: cycleLanguage) {
                Text(guideLanguage.label)
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(HomeNeon.card, in: Capsule())
            }

            Spacer()

            Text(guideLanguage.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(8)
                    .background(HomeNeon.card, in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .environment(\.layoutDirection, .leftToRight)
        .overlay(alignment: .bottom) {
            Divider().background(Color.white.opacity(0.08))
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<Self.slideCount, id: \.self) { i in
                    Circle()
                        .fill(i == page ? homeTheme.accent : Color.white.opacity(0.18))
                        .frame(width: 6, height: 6)
                        .scaleEffect(i == page ? 1.25 : 1)
                }
            }

            Spacer()

            Button {
                if page < Self.lastSlideIndex {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { page += 1 }
                } else {
                    dismiss()
                }
            } label: {
                Text(page == Self.lastSlideIndex ? guideLanguage.done : guideLanguage.next)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(homeTheme.accent, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .environment(\.layoutDirection, .leftToRight)
        // Solid, not translucent — this sits right below the TabView page as a
        // `.safeAreaInset`, so nothing should ever be scrolling underneath it, but
        // a solid fill is the cheap guarantee that the dots/button stay fully
        // legible even if a slide's content were ever taller than expected.
        .background(Color(hex: "0D0D0D"))
        .overlay(alignment: .top) {
            Divider().background(Color.white.opacity(0.08))
        }
    }

    /// Kept as constants because the count is otherwise repeated in three places —
    /// the TabView tags, the page dots, and the Next/Done switch — and adding a slide
    /// while missing one of them is an easy and silent mistake.
    private static let slideCount = 9
    private static var lastSlideIndex: Int { slideCount - 1 }

    private func cycleLanguage() {
        guideLanguage = guideLanguage.cycled
    }
}

// MARK: - Guide-local language (independent of the app's own language setting)

private enum GuideLanguage: CaseIterable, Equatable {
    case en, he, ar, ru, th

    static func matching(_ preference: AppLanguageOption) -> GuideLanguage {
        switch preference {
        case .english: return .en
        case .hebrew: return .he
        case .arabic: return .ar
        case .russian: return .ru
        case .thai: return .th
        case .system:
            switch AppLocale.language(fromPreferredLanguages: Locale.preferredLanguages) {
            case .hebrew: return .he
            case .arabic: return .ar
            case .russian: return .ru
            case .thai: return .th
            default: return .en
            }
        }
    }

    var cycled: GuideLanguage {
        let all = Self.allCases
        let i = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }

    var label: String {
        switch self {
        case .en: return "EN"
        case .he: return "HE"
        case .ar: return "AR"
        case .ru: return "RU"
        case .th: return "TH"
        }
    }

    var isRTL: Bool { self == .he || self == .ar }

    /// Maps to `AppLocale`'s language type so guide mockups can resolve
    /// L10n-driven text in the guide's own selected language, instead of
    /// the app's actual current language (which is what every `L10n.xxx`
    /// call reads by default).
    var appLocaleLanguage: AppLocale.Language {
        switch self {
        case .en: return .english
        case .he: return .hebrew
        case .ar: return .arabic
        case .ru: return .russian
        case .th: return .thai
        }
    }

    var title: String {
        switch self {
        case .en: return "User Guide"
        case .he: return "מדריך למשתמש"
        case .ar: return "دليل المستخدم"
        case .ru: return "Руководство"
        case .th: return "คู่มือการใช้งาน"
        }
    }

    var done: String {
        switch self {
        case .en: return "Done"
        case .he: return "סיום"
        case .ar: return "تم"
        case .ru: return "Готово"
        case .th: return "เสร็จสิ้น"
        }
    }

    var next: String {
        switch self {
        case .en: return "Next"
        case .he: return "הבא"
        case .ar: return "التالي"
        case .ru: return "Далее"
        case .th: return "ถัดไป"
        }
    }
}

// MARK: - Slide copy (title, subtitle) per language

private struct GuideCopy {
    let en: (title: String, subtitle: String)
    let he: (title: String, subtitle: String)
    let ar: (title: String, subtitle: String)
    let ru: (title: String, subtitle: String)
    let th: (title: String, subtitle: String)

    func pair(for language: GuideLanguage) -> (title: String, subtitle: String) {
        switch language {
        case .en: return en
        case .he: return he
        case .ar: return ar
        case .ru: return ru
        case .th: return th
        }
    }

    static let home = GuideCopy(
        en: (
            "Clock in with one tap",
            "Idle: the door is closed, ready for you. Active: it swings open and turns coral while your shift runs — "
                + "switch the live counter between gross and net anytime. Completed: once you clock out, "
                + "your day's total and this week's hours at a glance replace the door. "
                + "Need help? The chat bubble beside the door gets you straight to us."
        ),
        he: (
            "כניסה בלחיצה אחת",
            "ממתינה: הדלת סגורה ומוכנה. פעילה: היא נפתחת והופכת לאדום-אלמוגי במהלך המשמרת - "
                + "אפשר להחליף בין ברוטו לנטו במונה החי בכל שלב. הושלמה: לאחר היציאה, "
                + "סך היום והשעות של השבוע הנוכחי מופיעים במקום הדלת. "
                + "צריכים עזרה? בועת הצ'אט ליד הדלת מעבירה אתכם אלינו ישירות."
        ),
        ar: (
            "تسجيل الدخول بلمسة واحدة",
            "خامل: الباب مغلق وجاهز. نشط: يُفتح ويتحول إلى اللون المرجاني طوال المناوبة — "
                + "بدّل العدّاد الحي بين الإجمالي والصافي في أي وقت. مكتمل: بعد تسجيل الخروج، "
                + "يظهر إجمالي يومك وساعات هذا الأسبوع مكان الباب. "
                + "تحتاج مساعدة؟ فقاعة المحادثة بجانب الباب توصلك إلينا مباشرة."
        ),
        ru: (
            "Начните смену одним касанием",
            "Ожидание: дверь закрыта и готова. Активна: она открывается и становится коралловой на всю смену — "
                + "переключайте живой счётчик между брутто и нетто в любой момент. Завершена: после выхода "
                + "на месте двери появляются итог дня и часы за эту неделю. "
                + "Нужна помощь? Значок чата рядом с дверью сразу соединит вас с нами."
        ),
        th: (
            "ลงเวลาเข้างานด้วยการแตะครั้งเดียว",
            "ไม่ได้ทำงาน: ประตูปิดอยู่ พร้อมให้คุณเริ่ม ทำงานอยู่: ประตูเปิดออกและเปลี่ยนเป็นสีส้มคอรัลตลอดกะ — "
                + "สลับตัวนับสดระหว่างยอดรวมและยอดสุทธิได้ทุกเมื่อ เสร็จสิ้น: หลังจากลงเวลาออก "
                + "ยอดรวมของวันนี้และชั่วโมงทำงานของสัปดาห์นี้จะแสดงแทนที่ประตู "
                + "ต้องการความช่วยเหลือ? ไอคอนแชทข้างประตูพาคุณไปหาเราได้ทันที"
        )
    )

    static let theme = GuideCopy(
        en: ("Make it yours", "Tap a color — a ring confirms it, and it applies app-wide."),
        he: ("התאימו את האפליקציה", "הקישו על צבע - טבעת מאשרת את הבחירה, והיא חלה בכל האפליקציה."),
        ar: ("اجعله خاصًا بك", "اضغط على لون — تؤكده حلقة، ويُطبَّق على مستوى التطبيق."),
        ru: ("Под себя", "Нажмите на цвет — кольцо подтвердит выбор, и он применится во всём приложении."),
        th: ("ปรับแต่งให้เป็นของคุณ", "แตะเลือกสี — วงแหวนจะยืนยันการเลือก และสีนั้นจะถูกใช้ทั่วทั้งแอป")
    )

    static let history = GuideCopy(
        en: (
            "Mark a day as Holiday — and manage shifts fast",
            "Pick Holiday as the day type — hours auto-fill from your typical shift. "
                + "Swipe a shift to delete it, or select several at once from the toolbar — a quick haptic "
                + "buzz confirms it, no animation to wait for. "
                + "A holiday you didn't work counts as a paid day off, not as a worked holiday."
        ),
        he: (
            "סמנו יום כחג - וניהול משמרות מהיר",
            "בחרו חג כסוג היום - השעות יתמלאו אוטומטית לפי המשמרת הרגילה שלכם. "
                + "החליקו על משמרת למחיקה, או בחרו כמה בבת אחת מסרגל הכלים - רטט קצר מאשר את הפעולה, "
                + "בלי אנימציה שצריך להמתין לה. "
                + "חג שלא עבדתם בו נספר כיום חג משולם, ולא כחג שעבדתם בו."
        ),
        ar: (
            "حدد يومًا كعطلة — وتعامل مع المناوبات بسرعة",
            "اختر عطلة كنوع اليوم — تُملأ الساعات تلقائيًا حسب مناوبتك المعتادة. "
                + "اسحب مناوبة لحذفها، أو حدد عدة مناوبات دفعة واحدة من شريط الأدوات — رجّة لمسية سريعة تؤكد الحذف "
                + "بدون أي انتظار لرسوم متحركة. "
                + "العيد اللي ما اشتغلت فيه بيُحسب كيوم عيد مدفوع، مش كعيد اشتغلت فيه."
        ),
        ru: (
            "Отметьте день как праздник — и управляйте сменами быстро",
            "Выберите «Праздник» как тип дня — часы заполнятся по вашей обычной смене. "
                + "Смахните смену, чтобы удалить её, или выберите сразу несколько на панели инструментов — "
                + "короткая вибрация подтверждает удаление, никакой анимации ждать не нужно. "
                + "Праздник, в который вы не работали, считается оплачиваемым выходным, а не отработанным праздником."
        ),
        th: (
            "ตั้งวันเป็นวันหยุด — และจัดการกะงานได้รวดเร็ว",
            "เลือกวันหยุดเป็นประเภทของวัน — ชั่วโมงจะกรอกอัตโนมัติตามกะปกติของคุณ "
                + "ปัดกะงานเพื่อลบ หรือเลือกหลายรายการพร้อมกันจากแถบเครื่องมือ — การสั่นสั้น ๆ ยืนยันการลบ "
                + "โดยไม่ต้องรอแอนิเมชัน "
                + "วันหยุดที่คุณไม่ได้ทำงานจะถูกนับเป็นวันหยุดที่ได้รับค่าจ้าง ไม่ใช่วันหยุดที่ทำงาน"
        )
    )

    static let export = GuideCopy(
        en: (
            "Export, built for trust",
            "Quick pills jump straight to This/Last Month or Week — the mini-receipt right below previews your "
                + "day count, hours, and net pay the moment you pick a range. The \"What's included\" "
                + "checklist shows exactly what the report calculates — overtime, breaks, daily breakdown. "
                + "The PDF itself only prints real data: nothing blank, nothing left over from an employer "
                + "you've since changed."
        ),
        he: (
            "ייצוא שאפשר לסמוך עליו",
            "כפתורי קיצור מעבירים ישירות לחודש/שבוע הנוכחי או הקודם - הקבלה המוקטנת שמתחת מציגה מספר ימים, "
                + "שעות ונטו לתשלום ברגע שבוחרים טווח. הרשימה \"מה כלול בדוח\" "
                + "מציגה בדיוק מה הדוח מחשב - שעות נוספות, הפסקות, פירוט יומי. "
                + "ה-PDF עצמו מדפיס רק מידע אמיתי - בלי שורות ריקות, ובלי שום דבר שנשאר ממעסיק שכבר עזבתם."
        ),
        ar: (
            "تصدير مبني على الثقة",
            "أزرار سريعة تنقلك مباشرة إلى هذا الشهر/الأسبوع أو السابق — والإيصال المصغّر أسفلها يعرض عدد الأيام "
                + "والساعات وصافي الأجر لحظة اختيار الفترة. قائمة \"ما الذي يشمله التقرير\" "
                + "تُظهر بالضبط ما يحسبه التقرير — الساعات الإضافية، الاستراحات، التفصيل اليومي. "
                + "ملف PDF نفسه يطبع فقط البيانات الحقيقية — بلا سطور فارغة، وبلا أي أثر لموظّف سابق غادرت العمل معه."
        ),
        ru: (
            "Экспорт, которому можно доверять",
            "Быстрые кнопки сразу переключают на этот/прошлый месяц или неделю — мини-чек под ними показывает "
                + "число дней, часы и чистую сумму сразу после выбора периода. Список «Что включено» "
                + "показывает, что именно считает отчёт — сверхурочные, перерывы, разбивку по дням. "
                + "Сам PDF печатает только реальные данные — ни одной пустой строки и ничего от работодателя, "
                + "у которого вы больше не работаете."
        ),
        th: (
            "การส่งออกที่เชื่อถือได้",
            "ปุ่มลัดพาไปยังเดือน/สัปดาห์นี้หรือก่อนหน้าได้ทันที — ใบเสร็จย่อด้านล่างแสดงจำนวนวัน ชั่วโมง "
                + "และยอดสุทธิทันทีที่คุณเลือกช่วงเวลา รายการ \"สิ่งที่รวมอยู่ในรายงาน\" "
                + "แสดงให้เห็นชัดเจนว่ารายงานคำนวณอะไรบ้าง — ค่าล่วงเวลา การหักเวลาพัก รายละเอียดรายวัน "
                + "ไฟล์ PDF จะพิมพ์เฉพาะข้อมูลจริงเท่านั้น — ไม่มีบรรทัดว่าง "
                + "และไม่มีร่องรอยของนายจ้างเก่าที่คุณเปลี่ยนไปแล้ว"
        )
    )

    static let payslips = GuideCopy(
        en: (
            "Every payslip, organized",
            "The dashboard header sums what's uploaded at a glance. Tap a payslip to open its PDF — "
                + "pinch or double-tap to zoom in on any number — review what the Smart Scanner extracted, "
                + "and confirm or delete it. Full reports live in the Export tab."
        ),
        he: (
            "כל תלוש, מסודר",
            "כותרת לוח המחוונים מסכמת מה שהועלה במבט אחד. הקישו על תלוש כדי לפתוח את ה-PDF - "
                + "צבטו או הקישו פעמיים להתקרבות על כל מספר - בדקו מה הסורק החכם חילץ, "
                + "ואשרו או מחקו. דוחות מלאים נמצאים בלשונית ייצוא."
        ),
        ar: (
            "كل قسيمة راتب، منظمة",
            "رأس لوحة التحكم يلخّص ما تم رفعه بنظرة واحدة. اضغط على قسيمة لفتح ملف PDF — "
                + "استخدم إيماءة القرص أو النقر المزدوج للتكبير على أي رقم — راجع ما استخرجه الماسح الذكي، "
                + "وأكّد القسيمة أو احذفها. التقارير الكاملة في تبويب التصدير."
        ),
        ru: (
            "Все расчётные листы по порядку",
            "Заголовок панели сразу суммирует всё загруженное. Нажмите на лист, чтобы открыть PDF — "
                + "сведите или разведите пальцы (или нажмите дважды), чтобы увеличить любую цифру — "
                + "проверьте, что извлёк умный сканер, и подтвердите или удалите лист. "
                + "Полные отчёты — во вкладке «Экспорт»."
        ),
        th: (
            "สลิปเงินเดือนทุกใบ จัดเรียงอย่างเป็นระบบ",
            "ส่วนหัวของแดชบอร์ดสรุปสิ่งที่อัปโหลดไว้ให้ดูได้ในมองแรก แตะสลิปเพื่อเปิดไฟล์ PDF — "
                + "ใช้สองนิ้วบีบหรือแตะสองครั้งเพื่อซูมดูตัวเลขใด ๆ — ตรวจสอบสิ่งที่สแกนเนอร์อัจฉริยะดึงข้อมูลออกมา "
                + "แล้วยืนยันหรือลบ รายงานฉบับสมบูรณ์อยู่ในแท็บส่งออก"
        )
    )

    static let shiftDetail = GuideCopy(
        en: ("Every shift, itemized", "Regular, overtime, and pay — broken down clearly."),
        he: ("כל משמרת, מפורטת", "שעות רגילות, נוספות ותשלום - בפירוט מלא."),
        ar: ("كل مناوبة، بالتفصيل", "الساعات العادية والإضافية والأجر — موضحة بدقة."),
        ru: ("Каждая смена в деталях", "Обычные часы, сверхурочные и оплата — всё наглядно."),
        th: ("ทุกกะงาน แยกรายละเอียดชัดเจน", "ชั่วโมงปกติ ล่วงเวลา และค่าจ้าง — แยกให้เห็นอย่างชัดเจน")
    )

    static let settings = GuideCopy(
        en: (
            "Your data stays yours",
            "Settings opens to four groups — Work & Pay, Reminders, Privacy, and Data & Tools — so related "
                + "options live together instead of one long list. Your profile card shows a private HT-XXXXX "
                + "ID — share it only if you ever need support. The scanner works fully on-device unless you "
                + "turn cloud AI on, and the whole app speaks 5 languages: English, Hebrew, Arabic, Russian, "
                + "and Thai."
        ),
        he: (
            "המידע שלכם נשאר שלכם",
            "ההגדרות נפתחות לארבע קבוצות - עבודה ושכר, תזכורות, פרטיות, ונתונים וכלים - כך שאפשרויות קשורות "
                + "נמצאות יחד במקום רשימה אחת ארוכה. כרטיס הפרופיל שלכם מציג מזהה פרטי מהצורה HT-XXXXX - "
                + "שתפו אותו רק אם צריך תמיכה. הסורק פועל במכשיר בלבד, אלא אם מפעילים AI בענן, והאפליקציה כולה "
                + "מדברת 5 שפות: עברית, אנגלית, ערבית, רוסית ותאית."
        ),
        ar: (
            "بياناتك تبقى لك",
            "تُفتح الإعدادات على أربع مجموعات — العمل والراتب، التذكيرات، الخصوصية، والبيانات والأدوات — بحيث "
                + "تبقى الخيارات المرتبطة ببعضها معًا بدلًا من قائمة طويلة واحدة. تُظهر بطاقة ملفك الشخصي معرّفًا "
                + "خاصًا بصيغة HT-XXXXX — شاركه فقط إذا احتجت الدعم. يعمل الماسح على الجهاز فقط ما لم تُفعّل "
                + "الذكاء الاصطناعي السحابي، والتطبيق بالكامل يتحدث 5 لغات: الإنجليزية والعبرية والعربية "
                + "والروسية والتايلاندية."
        ),
        ru: (
            "Ваши данные — только ваши",
            "Настройки открываются в четырёх группах — Работа и оплата, Напоминания, Приватность и Данные и "
                + "инструменты — так связанные пункты не теряются в одном длинном списке. На карточке профиля "
                + "показан личный ID вида HT-XXXXX — делитесь им только если понадобится поддержка. Сканер "
                + "работает только на устройстве, пока вы не включите облачный ИИ, а всё приложение говорит "
                + "на 5 языках: английском, иврите, арабском, русском и тайском."
        ),
        th: (
            "ข้อมูลของคุณยังคงเป็นของคุณ",
            "หน้าตั้งค่าแบ่งเป็น 4 กลุ่ม — งานและค่าจ้าง การแจ้งเตือน ความเป็นส่วนตัว และข้อมูลและเครื่องมือ — "
                + "ตัวเลือกที่เกี่ยวข้องกันจึงอยู่ด้วยกันแทนที่จะเป็นรายการยาวรายการเดียว การ์ดโปรไฟล์ของคุณแสดง"
                + "รหัสส่วนตัวรูปแบบ HT-XXXXX — แชร์เฉพาะเมื่อต้องการความช่วยเหลือเท่านั้น "
                + "สแกนเนอร์ทำงานบนอุปกรณ์ทั้งหมด เว้นแต่คุณเปิดใช้ AI บนคลาวด์ และแอปทั้งหมดรองรับ 5 ภาษา: "
                + "อังกฤษ ฮีบรู อาหรับ รัสเซีย และไทย"
        )
    )

    static let widget = GuideCopy(
        en: (
            "On your Home Screen, Lock Screen, and your wrist",
            "The widget mirrors your day in 3 states — Idle, Active, and Completed — so a glance "
                + "tells you whether you're clocked in without opening the app. Clock in and a Live Activity "
                + "appears on your Lock Screen and in the Dynamic Island, ticking your pay in real time — "
                + "the exact same numbers as the widget, always in sync. "
                + "On Apple Watch, clock in, take a break, and export your hours — straight from your wrist."
        ),
        he: (
            "במסך הבית, במסך הנעילה, ועל פרק היד",
            "הווידג'ט משקף את היום שלכם ב-3 מצבים - ממתין, פעיל והושלם - כך שמבט אחד "
                + "אומר אם נרשמה כניסה בלי לפתוח את האפליקציה. כשנכנסים, Live Activity מופיע במסך הנעילה "
                + "וב-Dynamic Island ומתעדכן בזמן אמת - בדיוק אותם המספרים כמו בווידג'ט, תמיד מסונכרנים. "
                + "ב-Apple Watch אפשר להיכנס, לצאת להפסקה ולייצא את השעות - ישירות מפרק היד."
        ),
        ar: (
            "على الشاشة الرئيسية وشاشة القفل ومعصمك",
            "يعكس الودجت يومك في 3 حالات — خامل، نشط، ومكتمل — بنظرة واحدة "
                + "تعرف إن كنت مسجّل دخول من دون فتح التطبيق. عند تسجيل الدخول، يظهر Live Activity على شاشة "
                + "القفل وفي Dynamic Island ويتحدّث لحظيًا — بنفس أرقام الودجت تمامًا، ومتزامن معه دائمًا. "
                + "على Apple Watch، سجّل الدخول وخذ استراحة وصدّر ساعاتك — مباشرة من معصمك."
        ),
        ru: (
            "На главном экране, экране блокировки и запястье",
            "Виджет отражает ваш день в 3 состояниях — ожидание, активна, завершена — так что "
                + "одного взгляда достаточно, чтобы понять, начата ли смена, не открывая приложение. "
                + "При старте смены на экране блокировки и в Dynamic Island появляется Live Activity с оплатой "
                + "в реальном времени — те же цифры, что и в виджете, всегда синхронно. "
                + "На Apple Watch можно начать смену, взять перерыв и экспортировать часы — прямо с запястья."
        ),
        th: (
            "บนหน้าจอหลัก หน้าจอล็อก และข้อมือของคุณ",
            "วิดเจ็ตแสดงสถานะของวันคุณใน 3 รูปแบบ — ไม่ได้ทำงาน ทำงานอยู่ และเสร็จสิ้น — เพียงมองแวบเดียว "
                + "ก็รู้ว่าลงเวลาเข้างานแล้วหรือยังโดยไม่ต้องเปิดแอป เมื่อคุณลงเวลาเข้างาน Live Activity "
                + "จะปรากฏบนหน้าจอล็อกและใน Dynamic Island พร้อมอัปเดตค่าจ้างแบบเรียลไทม์ — ตัวเลขเดียวกับ"
                + "วิดเจ็ตทุกประการและซิงค์กันเสมอ "
                + "บน Apple Watch คุณลงเวลาเข้างาน พักงาน และส่งออกชั่วโมงทำงานได้โดยตรงจากข้อมือ"
        )
    )

    static let assistant = GuideCopy(
        en: (
            "Ask your assistant",
            "Tap the sparkles icon in any tab's top bar and ask about your hours, overtime, or a payslip — it only ever answers from your real data. Free plan: 3 questions a day, 10 a week."
        ),
        he: (
            "שאלו את העוזר שלכם",
            "הקישו על סמל הניצוצות בסרגל העליון של כל לשונית ושאלו על השעות, השעות הנוספות או תלוש שכר - התשובות מתבססות רק על הנתונים האמיתיים שלכם. תוכנית חינמית: 3 שאלות ביום, 10 בשבוע."
        ),
        ar: (
            "اسأل مساعدك",
            "اضغط على أيقونة البريق في الشريط العلوي لأي تبويب واسأل عن ساعاتك أو العمل الإضافي أو قسيمة راتب — الإجابات تأتي من بياناتك الحقيقية فقط. الخطة المجانية: 3 أسئلة يوميًا و10 أسبوعيًا."
        ),
        ru: (
            "Спросите помощника",
            "Нажмите значок с искрами на верхней панели любой вкладки и спросите про часы, сверхурочные или расчётный лист — ответы берутся только из ваших реальных данных. Бесплатный план: 3 вопроса в день, 10 в неделю."
        ),
        th: (
            "ถามผู้ช่วยของคุณ",
            "แตะไอคอนประกายดาวบนแถบด้านบนของแท็บใด ๆ แล้วถามเกี่ยวกับชั่วโมงทำงาน ค่าล่วงเวลา หรือสลิปเงินเดือน — คำตอบมาจากข้อมูลจริงของคุณเท่านั้น แผนฟรี: 3 คำถามต่อวัน 10 คำถามต่อสัปดาห์"
        )
    )
}

// MARK: - Slide 1: Home / clock in — the real HomeAnimatedDoorButton

private struct GuideHomePage: View {
    let accent: Color
    let guideLanguage: GuideLanguage
    /// The real gross/net control from the clocked-in screen, not a picture of one.
    @State private var payMode: PayDisplayMode = .gross

    private func t(_ key: String) -> String {
        AppLocale.localizedString(key, language: guideLanguage.appLocaleLanguage)
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            HomeAnimatedDoorButton(mode: .clockIn, title: t("home.clockIn"), accent: accent) {
                // Guide demo only — no real session is created.
            }
            .frame(height: 140)

            Picker("", selection: $payMode) {
                ForEach(PayDisplayMode.allCases) { mode in
                    Text(mode == .net ? t("history.payNet") : t("history.payGross")).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            .colorScheme(.dark)
            .tint(accent)

            Spacer()
            Spacer()
        }
    }
}

// MARK: - Slide 2: Theme picker — the real swatch visual from HomeThemePickerSheet

private struct GuideThemePage: View {
    @State private var selectedHex = HomeAccentTheme.presets[2].hex // Cyan, matches the verified demo

    private let columns = [
        GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
    ]

    var body: some View {
        VStack {
            Spacer()
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(HomeAccentTheme.presets, id: \.hex) { preset in
                    swatch(preset)
                }
            }
            .padding(.horizontal, 30)
            Spacer()
            Spacer()
        }
    }

    private func swatch(_ preset: (name: String, hex: String)) -> some View {
        let color = Color(hex: preset.hex)
        let isSelected = selectedHex == preset.hex

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedHex = preset.hex }
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 38, height: 38)
                    .overlay(Circle().stroke(.white, lineWidth: isSelected ? 2.5 : 0))
                    .overlay(
                        Circle()
                            .stroke(color.opacity(0.4), lineWidth: isSelected ? 6 : 0)
                            .blur(radius: 4)
                    )
                    .shadow(color: color.opacity(isSelected ? 0.6 : 0), radius: 8)

                Text(preset.name)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

// MARK: - Slide 3: History / Holiday — the real DayType picker + auto-fill section

private struct GuideHistoryPage: View {
    let guideLanguage: GuideLanguage
    @State private var dayType: DayType = .regular

    private func t(_ key: String) -> String {
        AppLocale.localizedString(key, language: guideLanguage.appLocaleLanguage)
    }

    private func dayTypeName(_ type: DayType) -> String {
        switch type {
        case .regular: return t("dayType.regular")
        case .restDay: return t("dayType.restDay")
        case .holiday: return t("dayType.holiday")
        case .sick: return t("dayType.sick")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(t("settings.workRules")) {
                    Picker(t("session.dayType"), selection: $dayType) {
                        ForEach(DayType.allCases) { type in
                            Text(dayTypeName(type)).tag(type)
                        }
                    }
                }

                if dayType == .holiday {
                    Section(t("manual.holidayAutoFilledTitle")) {
                        LabeledContent(t("edit.clockIn"), value: "08:30")
                        LabeledContent(t("edit.clockOut"), value: "17:00")
                        Text(t("manual.holidayAutoFilledHint"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)

            // The real summary-bar badge, in its mid-shift state. No longer needs a large
            // bottom-padding hack to dodge the caption — `slide()` now reserves real,
            // non-overlapping space for the caption via `.safeAreaInset` instead of
            // drawing it as an overlay, so this just needs normal breathing room.
            WorkedDaysBadge(dayCount: 12, showsPendingDay: true, alignment: .center)
                .padding(.vertical, 16)
        }
    }
}

// MARK: - Slide 4: Payslips — illustrative cards, honest about where a tap leads

private struct GuidePayslipsPage: View {
    let accent: Color
    let guideLanguage: GuideLanguage
    @State private var selected: String = ""

    /// Sample month labels, generated in the guide's own selected language
    /// rather than hardcoded English — these are fake demo dates, but the
    /// month name still needs to match whatever language the guide shows.
    private var sample: [(month: String, amount: String, hex: String)] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: guideLanguage.appLocaleLanguage.localeIdentifier)
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents(year: 2026, day: 1)
        components.month = 7
        let july = calendar.date(from: components) ?? Date()
        components.month = 6
        let june = calendar.date(from: components) ?? Date()
        return [
            (formatter.string(from: july), "₪14,810.00", "6b4a7a"),
            (formatter.string(from: june), "₪15,940.25", "2f4f77")
        ]
    }

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 14) {
                ForEach(sample, id: \.month) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { selected = item.month }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(hex: item.hex))
                                .frame(height: 92)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(.white, lineWidth: selected == item.month ? 2 : 0)
                                )
                            Text(item.month)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white)
                            Text(item.amount)
                                .font(.caption)
                                .foregroundStyle(accent)
                        }
                    }
                    .buttonStyle(ScalePressButtonStyle())
                }
            }
            .padding(.horizontal, 28)
            Spacer()
            Spacer()
        }
    }
}

// MARK: - Slide: Export — illustrative quick pills + "what's included" checklist,
// mirroring the real ExportView without embedding the whole live screen.

private struct GuideExportPage: View {
    let accent: Color
    let guideLanguage: GuideLanguage

    private func t(_ key: String) -> String {
        AppLocale.localizedString(key, language: guideLanguage.appLocaleLanguage)
    }

    private var pillLabels: [String] {
        [t("export.thisMonth"), t("export.lastMonth"), t("export.thisWeek")]
    }

    private var checklist: [String] {
        [
            t("export.whatsIncluded.overtime"),
            t("export.whatsIncluded.breaks"),
            t("export.whatsIncluded.dailyBreakdown")
        ]
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            HStack(spacing: 8) {
                ForEach(Array(pillLabels.enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(index == 0 ? Color(hex: "00E5FF").opacity(0.18) : Color.white.opacity(0.06))
                        )
                        .overlay(
                            Capsule().stroke(index == 0 ? Color(hex: "00E5FF") : Color.white.opacity(0.12), lineWidth: index == 0 ? 1.5 : 1)
                        )
                        .foregroundStyle(index == 0 ? Color(hex: "00E5FF") : .white.opacity(0.75))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(t("export.whatsIncluded.title"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                ForEach(checklist, id: \.self) { item in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(hex: "26F273"))
                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .padding(16)
            .background(Color(hex: "0D0D0D"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 28)

            Spacer()
            Spacer()
        }
        .environment(\.layoutDirection, guideLanguage.isRTL ? .rightToLeft : .leftToRight)
    }
}

// MARK: - Slide 5: Shift detail — static breakdown, no interaction

private struct GuideShiftDetailPage: View {
    let guideLanguage: GuideLanguage

    private func t(_ key: String) -> String {
        AppLocale.localizedString(key, language: guideLanguage.appLocaleLanguage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(t("payslip.hoursRegular"), "62.10")
            row(t("payslip.hoursOT"), "2.00")
            row(t("payslip.gross"), "₪3,450.25")
        }
        .padding(20)
        .background(HomeNeon.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 28)
        .frame(maxHeight: .infinity)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.white.opacity(0.75))
            Spacer()
            Text(value).foregroundStyle(.white).fontWeight(.semibold)
        }
        .font(.subheadline)
    }
}

// MARK: - Slide 7: Assistant — the real toolbar icon and the real empty chat state

/// Both halves are the shipping views: the assistant now lives in each tab's
/// navigation bar (same `sparkles` symbol as `AssistantToolbarButton` renders),
/// and `AssistantWelcomeView` is exactly what the chat sheet opens on, down to
/// the personalized greeting. Only the taps are disabled — this is a guide, so
/// selecting a suggestion here shouldn't fire a real API call.
private struct GuideAssistantPage: View {
    let accent: Color
    let workerName: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: AssistantAppearance.shared.style.systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(accent)

                AssistantWelcomeView(
                    accent: accent,
                    workerName: workerName,
                    isInteractive: false
                )
            }
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - Slide 6: Settings — the real cloud-AI toggle and privacy copy

private struct GuideSettingsPage: View {
    let guideLanguage: GuideLanguage
    @State private var cloudEnabled = false

    private func t(_ key: String) -> String {
        AppLocale.localizedString(key, language: guideLanguage.appLocaleLanguage)
    }

    var body: some View {
        Form {
            Section {
                Toggle(t("scanner.cloudEnabled"), isOn: $cloudEnabled.animation())
                Text(t("scanner.cloudPrivacyNotice"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }
}

// MARK: - Slide: Widget / Watch — illustrative 3-state tiles, since the real
// widget renders inside a separate WidgetKit extension that can't be embedded here.

private struct GuideWidgetPage: View {
    let accent: Color
    let guideLanguage: GuideLanguage

    private enum WidgetState: CaseIterable {
        case idle, active, completed
    }

    private func label(for state: WidgetState) -> String {
        switch state {
        case .idle: return AppLocale.localizedString("home.readyToStart", language: guideLanguage.appLocaleLanguage)
        case .active: return AppLocale.localizedString("home.clockedIn", language: guideLanguage.appLocaleLanguage)
        case .completed: return guideLanguage.done
        }
    }

    private func color(for state: WidgetState) -> Color {
        switch state {
        case .idle: return .white.opacity(0.35)
        case .active: return HomeNeon.coral
        case .completed: return Color(hex: "26F273")
        }
    }

    private func icon(for state: WidgetState) -> String {
        switch state {
        case .idle: return "door.left.hand.closed"
        case .active: return "door.left.hand.open"
        case .completed: return "checkmark.circle.fill"
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            HStack(spacing: 12) {
                ForEach(WidgetState.allCases, id: \.self) { state in
                    VStack(spacing: 8) {
                        Image(systemName: icon(for: state))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(color(for: state))
                        Text(label(for: state))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(width: 84, height: 84)
                    .background(HomeNeon.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(color(for: state).opacity(0.4), lineWidth: 1)
                    )
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "applewatch")
                    .foregroundStyle(accent)
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(accent)
            }
            .font(.title3)
            .padding(.top, 4)

            Spacer()
            Spacer()
        }
        .environment(\.layoutDirection, guideLanguage.isRTL ? .rightToLeft : .leftToRight)
    }
}
