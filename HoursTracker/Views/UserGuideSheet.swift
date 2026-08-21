import SwiftUI

/// In-app onboarding guide reachable from the Home toolbar. Every slide reuses the
/// real component/strings it's teaching — `HomeAnimatedDoorButton` for clock-in, the
/// exact swatch visuals from `HomeThemePickerSheet`, the real `DayType` picker and
/// `L10n.manualHolidayAutoFilled*` strings from `ManualEntryView`, and the real
/// `L10n.scannerCloudEnabled` toggle from `SettingsView` — rather than illustrations
/// that could drift from what the app actually does.
///
/// The language pill lets you preview the guide's own authored captions in
/// EN/HE/AR independently of the app's language — chrome position is forced
/// `.leftToRight` regardless, so the pill, dots, and Next/Done button never move.
/// It intentionally does **not** re-language the embedded real components (the
/// Day Type picker, the cloud-AI toggle, …): `L10n`/`AppLocale` resolve strings
/// from the app's actual language setting, not from SwiftUI's `\.locale`
/// environment, so those slides correctly keep showing exactly what a real user
/// would see in the app's current language — faking that would be less honest
/// to "1:1 with the real app," not more.
struct UserGuideSheet: View {
    @ObservedObject private var homeTheme = HomeAccentTheme.shared
    @ObservedObject private var appBackground = AppBackgroundTheme.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page = 0
    @State private var guideLanguage: GuideLanguage

    init() {
        _guideLanguage = State(initialValue: GuideLanguage.matching(AppLanguageController.shared.preference))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            TabView(selection: $page) {
                slide(0, copy: GuideCopy.home) { GuideHomePage(accent: homeTheme.accent) }
                slide(1, copy: GuideCopy.theme) { GuideThemePage() }
                slide(2, copy: GuideCopy.history) { GuideHistoryPage() }
                slide(3, copy: GuideCopy.payslips) { GuidePayslipsPage(accent: homeTheme.accent) }
                slide(4, copy: GuideCopy.shiftDetail) { GuideShiftDetailPage() }
                slide(5, copy: GuideCopy.settings) { GuideSettingsPage() }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            footer
        }
        .background(appBackground.background.ignoresSafeArea())
    }

    private func slide<Content: View>(
        _ index: Int,
        copy: GuideCopy,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let text = copy.pair(for: guideLanguage)
        let alignment: HorizontalAlignment = guideLanguage == .en ? .leading : .trailing
        return ZStack(alignment: .bottom) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: alignment, spacing: 4) {
                Text(text.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(text.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.72))
            }
            .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
            .multilineTextAlignment(guideLanguage == .en ? .leading : .trailing)
            .padding(16)
            .background(
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
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
                ForEach(0..<6, id: \.self) { i in
                    Circle()
                        .fill(i == page ? homeTheme.accent : Color.white.opacity(0.18))
                        .frame(width: 6, height: 6)
                        .scaleEffect(i == page ? 1.25 : 1)
                }
            }

            Spacer()

            Button {
                if page < 5 {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { page += 1 }
                } else {
                    dismiss()
                }
            } label: {
                Text(page == 5 ? guideLanguage.done : guideLanguage.next)
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
        .overlay(alignment: .top) {
            Divider().background(Color.white.opacity(0.08))
        }
    }

    private func cycleLanguage() {
        guideLanguage = guideLanguage.cycled
    }
}

// MARK: - Guide-local language (independent of the app's own language setting)

private enum GuideLanguage: CaseIterable, Equatable {
    case en, he, ar

    static func matching(_ preference: AppLanguageOption) -> GuideLanguage {
        switch preference {
        case .english: return .en
        case .hebrew: return .he
        case .arabic: return .ar
        case .system:
            switch AppLocale.language(fromPreferredLanguages: Locale.preferredLanguages) {
            case .hebrew: return .he
            case .arabic: return .ar
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
        }
    }

    var title: String {
        switch self {
        case .en: return "User Guide"
        case .he: return "מדריך למשתמש"
        case .ar: return "دليل المستخدم"
        }
    }

    var done: String {
        switch self {
        case .en: return "Done"
        case .he: return "סיום"
        case .ar: return "تم"
        }
    }

    var next: String {
        switch self {
        case .en: return "Next"
        case .he: return "הבא"
        case .ar: return "التالي"
        }
    }
}

// MARK: - Slide copy (title, subtitle) per language

private struct GuideCopy {
    let en: (title: String, subtitle: String)
    let he: (title: String, subtitle: String)
    let ar: (title: String, subtitle: String)

    func pair(for language: GuideLanguage) -> (title: String, subtitle: String) {
        switch language {
        case .en: return en
        case .he: return he
        case .ar: return ar
        }
    }

    static let home = GuideCopy(
        en: ("Clock in with one tap", "The door swings open and turns coral — you are clocked in."),
        he: ("כניסה בלחיצה אחת", "הדלת נפתחת והופכת לאדום-אלמוגי - נרשמה כניסה."),
        ar: ("تسجيل الدخول بلمسة واحدة", "يُفتح الباب ويتحول إلى اللون المرجاني — تم تسجيل الدخول.")
    )

    static let theme = GuideCopy(
        en: ("Make it yours", "Tap a color — a ring confirms it, and it applies app-wide."),
        he: ("התאימו את האפליקציה", "הקישו על צבע - טבעת מאשרת את הבחירה, והיא חלה בכל האפליקציה."),
        ar: ("اجعله خاصًا بك", "اضغط على لون — تؤكده حلقة، ويُطبَّق على مستوى التطبيق.")
    )

    static let history = GuideCopy(
        en: ("Mark a day as Holiday", "Pick Holiday as the day type — hours auto-fill from your typical shift."),
        he: ("סמנו יום כחג", "בחרו חג כסוג היום - השעות יתמלאו אוטומטית לפי המשמרת הרגילה שלכם."),
        ar: ("حدد يومًا كعطلة", "اختر عطلة كنوع اليوم — تُملأ الساعات تلقائيًا حسب مناوبتك المعتادة.")
    )

    static let payslips = GuideCopy(
        en: ("Every payslip, organized", "Tap a payslip to open it, then share or export the PDF."),
        he: ("כל תלוש, מסודר", "הקישו על תלוש כדי לפתוח אותו, ואז שתפו או ייצאו כ-PDF."),
        ar: ("كل قسيمة راتب، منظمة", "اضغط على قسيمة لفتحها، ثم شاركها أو صدّرها كملف PDF.")
    )

    static let shiftDetail = GuideCopy(
        en: ("Every shift, itemized", "Regular, overtime, and pay — broken down clearly."),
        he: ("כל משמרת, מפורטת", "שעות רגילות, נוספות ותשלום - בפירוט מלא."),
        ar: ("كل مناوبة، بالتفصيل", "الساعات العادية والإضافية والأجر — موضحة بدقة.")
    )

    static let settings = GuideCopy(
        en: ("Your data stays yours", "The scanner works fully on-device unless you turn cloud AI on."),
        he: ("המידע שלכם נשאר שלכם", "הסורק פועל במכשיר בלבד, אלא אם מפעילים AI בענן."),
        ar: ("بياناتك تبقى لك", "يعمل الماسح على الجهاز فقط ما لم تُفعّل الذكاء الاصطناعي السحابي.")
    )
}

// MARK: - Slide 1: Home / clock in — the real HomeAnimatedDoorButton

private struct GuideHomePage: View {
    let accent: Color

    var body: some View {
        VStack {
            Spacer()
            HomeAnimatedDoorButton(mode: .clockIn, title: L10n.homeClockIn, accent: accent) {
                // Guide demo only — no real session is created.
            }
            .frame(height: 140)
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
    @State private var dayType: DayType = .regular

    var body: some View {
        Form {
            Section(L10n.settingsWorkRules) {
                Picker(L10n.sessionDayType, selection: $dayType) {
                    ForEach(DayType.allCases) { type in
                        Text(type.localizedName).tag(type)
                    }
                }
            }

            if dayType == .holiday {
                Section(L10n.manualHolidayAutoFilledTitle) {
                    LabeledContent(L10n.editClockIn, value: "08:30")
                    LabeledContent(L10n.editClockOut, value: "17:00")
                    Text(L10n.manualHolidayAutoFilledHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }
}

// MARK: - Slide 4: Payslips — illustrative cards, honest about where a tap leads

private struct GuidePayslipsPage: View {
    let accent: Color
    @State private var selected: String = ""

    private let sample: [(month: String, amount: String, hex: String)] = [
        ("July 2026", "₪14,810.00", "6b4a7a"),
        ("June 2026", "₪15,940.25", "2f4f77")
    ]

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

// MARK: - Slide 5: Shift detail — static breakdown, no interaction

private struct GuideShiftDetailPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(L10n.payslipHoursRegular, "62.10")
            row(L10n.payslipHoursOT, "2.00")
            row(L10n.payslipGross, "₪3,450.25")
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

// MARK: - Slide 6: Settings — the real cloud-AI toggle and privacy copy

private struct GuideSettingsPage: View {
    @State private var cloudEnabled = false

    var body: some View {
        Form {
            Section {
                Toggle(L10n.scannerCloudEnabled, isOn: $cloudEnabled.animation())
                Text(L10n.scannerCloudPrivacyNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }
}
