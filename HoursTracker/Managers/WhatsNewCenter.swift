import Foundation

/// One line of the "what's new" list: an SF Symbol and the text per language.
struct WhatsNewItem: Identifiable {
    let icon: String
    let title: [String: String]
    let text: [String: String]
    /// Optional small, dim line under `text` — e.g. spelling out "5 languages" as
    /// the actual 5 names instead of leaving the reader to guess which ones.
    var subtitle: [String: String]? = nil
    /// Optional emphasized line shown as-is, in its own fixed script, regardless of
    /// the reader's in-app language — e.g. a Thai greeting on the languages card,
    /// so a Thai reader notices the update immediately even if they haven't
    /// switched the app's language yet.
    var nativeHighlight: String? = nil
    var id: String { title["en"] ?? icon }

    func localizedTitle(_ language: String) -> String { title[language] ?? title["en"] ?? "" }
    func localizedText(_ language: String) -> String { text[language] ?? text["en"] ?? "" }
    func localizedSubtitle(_ language: String) -> String? { subtitle?[language] ?? subtitle?["en"] }
}

struct WhatsNewRelease {
    let version: String
    let items: [WhatsNewItem]
}

/// The release notes. Add an entry for every `MARKETING_VERSION` you ship; a version
/// without an entry shows no pop-up. Languages: en (default), he, ar, ru, th —
/// `localizedTitle`/`localizedText` fall back to en for any release written before
/// a given language existed.
enum WhatsNewContent {
    static func release(for version: String) -> WhatsNewRelease? {
        all.first { $0.version == version }
    }

    static let all: [WhatsNewRelease] = [
        WhatsNewRelease(version: "1.11", items: [
            WhatsNewItem(
                icon: "paintpalette.fill",
                title: [
                    "en": "A fresh Cyan & Green look",
                    "he": "מראה חדש בציאן וירוק",
                    "ar": "مظهر جديد بالسماوي والأخضر",
                    "ru": "Новый облик: бирюзовый и зелёный",
                    "th": "ดีไซน์ใหม่โทนฟ้าและเขียว"
                ],
                text: [
                    "en": "We introduced a stunning new theme — and you can still fully customize your own colors.",
                    "he": "הצגנו ערכת נושא מהממת חדשה - ועדיין אפשר להתאים אישית את הצבעים שלכם במלואם.",
                    "ar": "قدّمنا سمة جديدة مذهلة — ولا يزال بإمكانك تخصيص ألوانك الخاصة بالكامل.",
                    "ru": "Мы представили потрясающую новую тему — а свои цвета по-прежнему можно настроить полностью.",
                    "th": "เราเปิดตัวธีมใหม่สุดสวย — และคุณยังคงปรับแต่งสีของคุณเองได้เต็มที่"
                ]
            ),
            WhatsNewItem(
                icon: "globe",
                title: [
                    "en": "Now in 5 languages",
                    "he": "עכשיו ב-5 שפות",
                    "ar": "الآن بـ 5 لغات",
                    "ru": "Теперь на 5 языках",
                    "th": "ตอนนี้รองรับ 5 ภาษาแล้ว"
                ],
                text: [
                    "en": "Welcome to our Thai-speaking users — the whole app now speaks your language.",
                    "he": "ברוכים הבאים למשתמשים דוברי התאית - כל האפליקציה מדברת עכשיו בשפתכם.",
                    "ar": "أهلاً بمستخدمينا الناطقين بالتايلاندية — التطبيق بالكامل يتحدث الآن بلغتكم.",
                    "ru": "Добро пожаловать, тайскоязычные пользователи — всё приложение теперь говорит на вашем языке.",
                    "th": "ยินดีต้อนรับผู้ใช้ชาวไทย — แอปทั้งหมดตอนนี้พูดภาษาของคุณแล้ว"
                ],
                subtitle: [
                    "en": "Hebrew, Arabic, English, Russian, and Thai",
                    "he": "עברית, ערבית, אנגלית, רוסית ותאילנדית",
                    "ar": "العبرية، العربية، الإنجليزية، الروسية، والتايلاندية",
                    "ru": "иврит, арабский, английский, русский и тайский",
                    "th": "ฮีบรู อาหรับ อังกฤษ รัสเซีย และไทย"
                ],
                // Always in Thai, regardless of the reader's own in-app language —
                // a Thai reader notices this the moment the card appears, even
                // before they've found the language switch themselves.
                nativeHighlight: "ยินดีต้อนรับผู้ใช้ที่พูดภาษาไทย! ตอนนี้แอปของเรารองรับภาษาของคุณแล้ว"
            ),
            WhatsNewItem(
                icon: "square.and.arrow.up.fill",
                title: [
                    "en": "Faster, smarter export",
                    "he": "ייצוא מהיר וחכם יותר",
                    "ar": "تصدير أسرع وأذكى",
                    "ru": "Экспорт быстрее и умнее",
                    "th": "ส่งออกเร็วและฉลาดขึ้น"
                ],
                text: [
                    "en": "Export your reports in one tap. Everything fits on one screen, empty fields are hidden, and an old contractor's name disappears automatically if you switched jobs.",
                    "he": "ייצוא הדוחות בלחיצה אחת. הכול נכנס למסך אחד, שדות ריקים מוסתרים, ושם קבלן ישן נעלם אוטומטית אם עברתם מקום עבודה.",
                    "ar": "صدّر تقاريرك بلمسة واحدة. كل شيء يناسب شاشة واحدة، الحقول الفارغة مخفية، واسم مقاول قديم يختفي تلقائيًا إذا غيّرت وظيفتك.",
                    "ru": "Экспортируйте отчёты одним касанием. Всё помещается на одном экране, пустые поля скрыты, а имя старого подрядчика исчезает автоматически при смене работы.",
                    "th": "ส่งออกรายงานของคุณได้ด้วยการแตะครั้งเดียว ทุกอย่างพอดีในหน้าจอเดียว ช่องว่างถูกซ่อน และชื่อผู้รับเหมาเดิมจะหายไปอัตโนมัติเมื่อคุณเปลี่ยนงาน"
                ]
            ),
            WhatsNewItem(
                icon: "person.text.rectangle.fill",
                title: [
                    "en": "A redesigned Account & Settings",
                    "he": "חשבון והגדרות בעיצוב חדש",
                    "ar": "حساب وإعدادات بتصميم جديد",
                    "ru": "Обновлённые профиль и настройки",
                    "th": "โปรไฟล์และการตั้งค่าออกแบบใหม่"
                ],
                text: [
                    "en": "Your profile now has a unique ID (HT-XXXXX). Settings are cleaner, with a search bar to find anything instantly.",
                    "he": "לפרופיל שלכם יש עכשיו מזהה ייחודי (HT-XXXXX). ההגדרות נקיות יותר, עם שורת חיפוש למציאת כל דבר מיד.",
                    "ar": "لملفك الشخصي الآن معرّف فريد (HT-XXXXX). الإعدادات أنظف، مع شريط بحث للعثور على أي شيء فورًا.",
                    "ru": "У вашего профиля теперь есть уникальный ID (HT-XXXXX). Настройки стали чище, с поиском, который сразу находит нужное.",
                    "th": "โปรไฟล์ของคุณตอนนี้มีรหัสเฉพาะตัว (HT-XXXXX) การตั้งค่าดูสะอาดตาขึ้น พร้อมแถบค้นหาที่หาทุกอย่างได้ทันที"
                ]
            ),
            WhatsNewItem(
                icon: "applewatch",
                title: [
                    "en": "Watch & widget upgrades",
                    "he": "שדרוגים לשעון ולווידג'טים",
                    "ar": "ترقيات للساعة والودجت",
                    "ru": "Обновления часов и виджетов",
                    "th": "อัปเกรดนาฬิกาและวิดเจ็ต"
                ],
                text: [
                    "en": "Your Watch and Home Screen widgets now show 3 distinct states — Idle, Working, Completed — with beautiful colors.",
                    "he": "הווידג'טים בשעון ובמסך הבית מציגים עכשיו 3 מצבים ברורים - ממתין, עובד, הושלם - בצבעים יפהפיים.",
                    "ar": "ودجت الساعة والشاشة الرئيسية تعرض الآن 3 حالات واضحة — خامل، يعمل، مكتمل — بألوان جميلة.",
                    "ru": "Виджеты на часах и на главном экране теперь показывают 3 чётких состояния — ожидание, работа, завершено — в красивых цветах.",
                    "th": "วิดเจ็ตบน Apple Watch และหน้าจอหลักตอนนี้แสดง 3 สถานะชัดเจน — ไม่ได้ทำงาน กำลังทำงาน เสร็จสิ้น — ด้วยสีสันสวยงาม"
                ]
            ),
            WhatsNewItem(
                icon: "wand.and.rays",
                title: [
                    "en": "A smarter Smart Scanner",
                    "he": "סורק חכם, חכם יותר",
                    "ar": "ماسح ذكي أكثر ذكاءً",
                    "ru": "Умный сканер стал умнее",
                    "th": "สแกนเนอร์อัจฉริยะที่ฉลาดยิ่งขึ้น"
                ],
                text: [
                    "en": "The AI Scanner now reads Israeli payslips (Bruto/Neto) more accurately, and you can pinch to zoom in on any preview image.",
                    "he": "הסורק החכם קורא עכשיו תלושי שכר ישראליים (ברוטו/נטו) בדיוק רב יותר, ואפשר לצבוט להתקרבות על כל תמונת תצוגה מקדימה.",
                    "ar": "الماسح الذكي يقرأ الآن قسائم الرواتب الإسرائيلية (إجمالي/صافي) بدقة أكبر، ويمكنك استخدام إيماءة القرص للتكبير على أي صورة معاينة.",
                    "ru": "ИИ-сканер теперь точнее читает израильские расчётные листы (брутто/нетто), а любое изображение предпросмотра можно увеличить двумя пальцами.",
                    "th": "สแกนเนอร์ AI อ่านสลิปเงินเดือนของอิสราเอล (Bruto/Neto) ได้แม่นยำขึ้น และคุณสามารถบีบนิ้วเพื่อซูมดูภาพตัวอย่างได้"
                ]
            )
        ]),
        WhatsNewRelease(version: "1.10", items: [
            WhatsNewItem(
                icon: "bubble.left.and.bubble.right.fill",
                title: ["en": "Chat with the developer", "he": "שיחה עם המפתח", "ar": "الدردشة مع المطوّر", "ru": "Чат с разработчиком"],
                text: [
                    "en": "Open Feedback and tap Chat. My replies reach you right here in the app, with a notification.",
                    "he": "פתחו משוב ולחצו על צ'אט. התשובות שלי יגיעו אליכם ישירות לאפליקציה, עם התראה.",
                    "ar": "افتح الملاحظات واضغط على الدردشة. ستصلك ردودي هنا في التطبيق مع إشعار.",
                    "ru": "Откройте «Помощь и отзывы» и нажмите «Чат». Мои ответы придут прямо в приложение, с уведомлением."
                ]
            ),
            WhatsNewItem(
                icon: "person.2.badge.gearshape.fill",
                title: ["en": "Contractor or company employee", "he": "עובד קבלן או עובד חברה", "ar": "عامل קבלן أو موظف شركة", "ru": "Подрядчик или сотрудник компании"],
                text: [
                    "en": "Tell us how you're employed. When the company takes you on directly, add the move in Settings: new rate, and pension and severance are counted from that day.",
                    "he": "ספרו לנו איך אתם מועסקים. כשהחברה קולטת אתכם ישירות, הוסיפו את המעבר בהגדרות: תעריף חדש, ופנסיה ופיצויים נספרים מאותו יום.",
                    "ar": "أخبرنا كيف يتم توظيفك. عندما توظفك الشركة مباشرة، أضف الانتقال في الإعدادات: أجر جديد، ويُحتسب التقاعد والتعويضات من ذلك اليوم.",
                    "ru": "Укажите, как вы трудоустроены. Когда компания примет вас напрямую, добавьте переход в настройках: новая ставка, а пенсия и выходное пособие считаются с этого дня."
                ]
            ),
            WhatsNewItem(
                icon: "star.circle.fill",
                title: ["en": "Edit your holidays", "he": "עריכת חגים", "ar": "تعديل العطل", "ru": "Редактирование праздников"],
                text: [
                    "en": "Settings → Work rules → Holidays: add, remove, rename or move holiday dates for each workplace.",
                    "he": "הגדרות ← כללי עבודה ← חגים: הוספה, הסרה, שינוי שם או תאריך של חגים לכל מקום עבודה.",
                    "ar": "الإعدادات ← قواعد العمل ← العطل: أضف العطل أو احذفها أو غيّر اسمها أو تاريخها لكل مكان عمل.",
                    "ru": "Настройки → Правила работы → Праздники: добавляйте, убирайте, переименовывайте и переносите праздники для каждого места работы."
                ]
            ),
            WhatsNewItem(
                icon: "rectangle.grid.1x2.fill",
                title: ["en": "Clearer widgets and History", "he": "ווידג'טים והיסטוריה ברורים יותר", "ar": "ويدجت وسجل أوضح", "ru": "Понятнее виджеты и история"],
                text: [
                    "en": "A live timer in the widget ring and on the Lock Screen, week and month totals that match History, and bigger daily amounts in the full month view.",
                    "he": "שעון חי בטבעת הווידג'ט ובמסך הנעילה, סכומי שבוע וחודש שתואמים להיסטוריה, וסכומים יומיים גדולים יותר בתצוגת החודש המלאה.",
                    "ar": "مؤقت حي في حلقة الويدجت وعلى شاشة القفل، ومجاميع الأسبوع والشهر مطابقة للسجل، ومبالغ يومية أكبر في عرض الشهر الكامل.",
                    "ru": "Живой таймер в кольце виджета и на экране блокировки, итоги недели и месяца как в истории и более крупные суммы по дням в полном виде месяца."
                ]
            ),
            WhatsNewItem(
                icon: "sun.and.horizon.fill",
                title: ["en": "Morning, evening or night", "he": "בוקר, ערב או לילה", "ar": "صباح أو مساء أو ليل", "ru": "Утро, вечер или ночь"],
                text: [
                    "en": "Every shift now has its name. Night is counted the way the law does: at least 2 hours between 22:00 and 06:00 — and it handles the clock change too.",
                    "he": "לכל משמרת יש עכשיו שם. לילה נספר לפי החוק: לפחות שעתיים בין 22:00 ל-06:00 — וגם מעבר השעון נלקח בחשבון.",
                    "ar": "لكل وردية الآن اسمها. الليل يُحسب كما في القانون: ساعتان على الأقل بين 22:00 و06:00 — ويراعي تغيير الساعة أيضًا.",
                    "ru": "У каждой смены теперь есть название. Ночь считается по закону: не менее 2 часов между 22:00 и 06:00 — с учётом перевода часов."
                ]
            ),
            WhatsNewItem(
                icon: "list.bullet.indent",
                title: ["en": "Settings that are easy to follow", "he": "הגדרות קלות לניווט", "ar": "إعدادات سهلة التتبع", "ru": "Настройки, в которых легко ориентироваться"],
                text: [
                    "en": "Settings now opens group by group, with short screens, so you never get lost. Tabs also come back tidy when you return to them.",
                    "he": "ההגדרות נפתחות עכשיו קבוצה אחר קבוצה, במסכים קצרים, כך שלא הולכים לאיבוד. גם הלשוניות חוזרות מסודרות כשחוזרים אליהן.",
                    "ar": "تُفتح الإعدادات الآن مجموعة بعد مجموعة بشاشات قصيرة فلا تضيع. كما تعود التبويبات مرتبة عند الرجوع إليها.",
                    "ru": "Настройки открываются по группам короткими экранами, так что вы не потеряетесь. Вкладки тоже возвращаются в аккуратном виде."
                ]
            ),
            WhatsNewItem(
                icon: "mic.fill",
                title: ["en": "Siri understands more Hebrew", "he": "סירי מבינה יותר עברית", "ar": "سيري تفهم العبرية أكثر", "ru": "Siri лучше понимает иврит"],
                text: [
                    "en": "Hebrew Siri phrases now include the feminine and masculine forms, like “תחתימי כניסה עם HoursTracker”.",
                    "he": "ביטויי סירי בעברית כוללים עכשיו גם לשון זכר וגם נקבה, כמו „תחתימי כניסה עם HoursTracker”.",
                    "ar": "عبارات سيري بالعبرية تشمل الآن صيغتي المذكر والمؤنث، مثل «תחתימי כניסה עם HoursTracker».",
                    "ru": "Фразы Siri на иврите теперь включают мужскую и женскую формы, например «תחתימי כניסה עם HoursTracker»."
                ]
            ),
            WhatsNewItem(
                icon: "paintpalette.fill",
                title: ["en": "Your color, everywhere", "he": "הצבע שבחרתם, בכל מקום", "ar": "لونك في كل مكان", "ru": "Ваш цвет везде"],
                text: [
                    "en": "Buttons and highlights now keep your chosen color instead of flipping to blue.",
                    "he": "כפתורים והדגשות שומרים על הצבע שבחרתם ולא עוברים לכחול.",
                    "ar": "الأزرار والتمييزات تحتفظ بلونك المختار ولا تتحول إلى الأزرق.",
                    "ru": "Кнопки и выделения сохраняют выбранный вами цвет и больше не становятся синими."
                ]
            ),
            WhatsNewItem(
                icon: "hand.raised.fill",
                title: ["en": "Updated terms and privacy", "he": "תנאי שימוש ופרטיות מעודכנים", "ar": "شروط وخصوصية محدّثة", "ru": "Обновлённые условия и конфиденциальность"],
                text: [
                    "en": "They now explain how the chat stores who wrote to us. Please read and agree.",
                    "he": "הם מסבירים עכשיו איך הצ'אט שומר מי כתב לנו. אנא קראו ואשרו.",
                    "ar": "توضح الآن كيف تحفظ الدردشة هوية من كتب إلينا. يُرجى القراءة والموافقة.",
                    "ru": "Теперь они объясняют, как чат сохраняет данные автора сообщения. Пожалуйста, прочитайте и согласитесь."
                ]
            )
        ])
    ]
}

/// Decides when to greet a user who just updated. The first launch of a new version
/// opens the pop-up once and starts a 24-hour window in which About → "What's new"
/// reopens it. A fresh install gets nothing (it has onboarding instead).
@MainActor
final class WhatsNewCenter: ObservableObject {
    static let shared = WhatsNewCenter()

    static let window: TimeInterval = 24 * 3600

    private enum Key {
        static let lastVersion = "whatsNew.lastVersion"
        static let version = "whatsNew.version"
        static let windowStart = "whatsNew.windowStart"
        static let popupPending = "whatsNew.popupPending"
    }

    /// The pop-up over the app.
    @Published private(set) var showPopup = false
    /// Bumped on each evaluation so views re-read `activeRelease` as time passes.
    @Published private(set) var tick = 0

    private let defaults: UserDefaults
    /// Unit/UI test runs must not show real pop-ups; the unit tests of this class turn it off.
    private let ignoresAutomatedRuns: Bool

    init(defaults: UserDefaults = .standard, ignoresAutomatedRuns: Bool = true) {
        self.defaults = defaults
        self.ignoresAutomatedRuns = ignoresAutomatedRuns
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// Call once the user can actually see the app (terms agreed, onboarding done).
    /// `hasOnboarded` is false for a brand-new install.
    func evaluate(hasOnboarded: Bool, now: Date = Date(), currentVersion: String? = nil) {
        let currentVersion = currentVersion ?? Self.currentVersion
        var forced = false
        #if DEBUG
        forced = ProcessInfo.processInfo.arguments.contains("UITEST_WHATS_NEW")
        #endif
        guard !(ignoresAutomatedRuns && AnnouncementCenter.isAutomatedRun) || forced else { return }
        let last = defaults.string(forKey: Key.lastVersion)
        if last != currentVersion {
            defaults.set(currentVersion, forKey: Key.lastVersion)
            // No record yet and not onboarded: a fresh install, nothing to announce.
            let isUpdate = last != nil || hasOnboarded
            if isUpdate, WhatsNewContent.release(for: currentVersion) != nil {
                defaults.set(currentVersion, forKey: Key.version)
                defaults.set(now.timeIntervalSince1970, forKey: Key.windowStart)
                defaults.set(true, forKey: Key.popupPending)
            }
        }
        showPopup = defaults.bool(forKey: Key.popupPending) && activeRelease(now: now) != nil
        tick += 1
    }

    /// The release to show, only within 24 hours of the first launch after the update.
    func activeRelease(now: Date = Date()) -> WhatsNewRelease? {
        guard let version = defaults.string(forKey: Key.version) else { return nil }
        let start = defaults.double(forKey: Key.windowStart)
        guard start > 0, now.timeIntervalSince1970 - start < Self.window else { return nil }
        return WhatsNewContent.release(for: version)
    }

    /// Whole hours (rounded up) of the 24-hour window still left, or nil once it is down
    /// to the last hour — the card then stops mentioning it, since it is about to go.
    func hoursLeft(now: Date = Date()) -> Int? {
        let start = defaults.double(forKey: Key.windowStart)
        guard start > 0 else { return nil }
        let remaining = Self.window - (now.timeIntervalSince1970 - start)
        guard remaining > 3600 else { return nil }
        return min(24, Int((remaining / 3600).rounded(.up)))
    }

    /// Closing the pop-up (X or the button): it won't open by itself again, but the
    /// About entry stays until the 24 hours are over.
    func dismissPopup() {
        defaults.set(false, forKey: Key.popupPending)
        showPopup = false
    }
}
