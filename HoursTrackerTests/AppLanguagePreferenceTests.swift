import XCTest
@testable import HoursTracker

final class AppLanguagePreferenceTests: XCTestCase {
    func testSystemFollowsPreferredLanguages() {
        XCTAssertEqual(
            AppLocale.resolve(preference: .system, preferredLanguages: ["en-US"]),
            .english
        )
        XCTAssertEqual(
            AppLocale.resolve(preference: .system, preferredLanguages: ["he-IL", "en"]),
            .hebrew
        )
        XCTAssertEqual(
            AppLocale.resolve(preference: .system, preferredLanguages: ["iw"]),
            .hebrew
        )
        XCTAssertEqual(
            AppLocale.resolve(preference: .system, preferredLanguages: ["ar-SA"]),
            .arabic
        )
    }

    func testOverrideWinsOverSystemPreferredLanguages() {
        XCTAssertEqual(
            AppLocale.resolve(preference: .hebrew, preferredLanguages: ["en-US"]),
            .hebrew
        )
        XCTAssertEqual(
            AppLocale.resolve(preference: .english, preferredLanguages: ["he-IL"]),
            .english
        )
        XCTAssertEqual(
            AppLocale.resolve(preference: .arabic, preferredLanguages: ["en"]),
            .arabic
        )
    }

    func testLoadDefaultsToSystemWhenUnset() {
        let defaults = UserDefaults(suiteName: "AppLanguagePreferenceTests-unset-\(UUID().uuidString)")!
        XCTAssertEqual(AppLanguageOption.load(from: defaults), .system)
    }

    @MainActor
    func testControllerPersistsOverrideAndSetsAppleLanguages() {
        let suite = "AppLanguagePreferenceTests-ctrl-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        let controller = AppLanguageController(defaults: defaults)
        XCTAssertEqual(controller.preference, .system)
        XCTAssertNil(defaults.persistentDomain(forName: suite)?[AppLanguageOption.appleLanguagesKey])

        controller.preference = .hebrew
        XCTAssertEqual(defaults.string(forKey: AppLanguageOption.storageKey), AppLanguageOption.hebrew.rawValue)
        XCTAssertEqual(
            defaults.persistentDomain(forName: suite)?[AppLanguageOption.appleLanguagesKey] as? [String],
            ["he"]
        )
        XCTAssertEqual(
            AppLocale.resolve(
                preference: AppLanguageOption.load(from: defaults),
                preferredLanguages: ["en"]
            ),
            .hebrew
        )

        controller.preference = .system
        XCTAssertEqual(defaults.string(forKey: AppLanguageOption.storageKey), AppLanguageOption.system.rawValue)
        // removeObject clears the suite entry (array(forKey:) may still fall through to global).
        XCTAssertNil(defaults.persistentDomain(forName: suite)?[AppLanguageOption.appleLanguagesKey])
    }

    func testLayoutDirectionForForcedLanguages() {
        XCTAssertEqual(AppLanguageOption.english.layoutDirection, .leftToRight)
        XCTAssertEqual(AppLanguageOption.hebrew.layoutDirection, .rightToLeft)
        XCTAssertEqual(AppLanguageOption.arabic.layoutDirection, .rightToLeft)
    }

    /// Guards the exact regression that made the in-app language switcher a no-op:
    /// `localizedString(_:language:)` used to resolve through `String(localized:locale:)`,
    /// whose `locale:` argument only formats interpolated values and does not select a
    /// language. Every language therefore returned whatever the host app was running in,
    /// so all three of these came back identical.
    func testEachLanguageResolvesIndependentlyOfTheHostAppLanguage() {
        for key in ["tab.home", "home.clockIn", "history.emptyPeriod"] {
            let values = [AppLocale.Language.english, .hebrew, .arabic]
                .map { AppLocale.localizedString(key, language: $0) }

            XCTAssertEqual(
                Set(values).count,
                3,
                "\(key) resolved to \(values) — each language must get its own string"
            )
            XCTAssertFalse(
                values.contains(key),
                "\(key) fell back to the raw catalog key in at least one language"
            )
        }
    }

    /// A key with no translation must show the development language, not a dotted
    /// identifier — the English fallback has to survive the reordering above.
    func testUntranslatedKeyFallsBackToEnglishRatherThanTheRawKey() {
        let missing = "definitely.not.a.real.key.\(UUID().uuidString)"
        XCTAssertEqual(AppLocale.localizedString(missing, language: .hebrew), missing)

        // A key deliberately identical in all three languages must still resolve — the
        // fallback chain has to distinguish "same in every language" from "not found".
        XCTAssertEqual(AppLocale.localizedString("app.brandName", language: .hebrew), "HoursTracker")
        XCTAssertEqual(AppLocale.localizedString("app.brandName", language: .arabic), "HoursTracker")
    }

    func testLocalizedStringsComeFromLanguageSpecificLproj() {
        let english = AppLocale.localizedString("tab.home", language: .english)
        let hebrew = AppLocale.localizedString("tab.home", language: .hebrew)
        let arabic = AppLocale.localizedString("tab.home", language: .arabic)

        XCTAssertEqual(english, "Home")
        XCTAssertEqual(hebrew, "בית")
        XCTAssertEqual(arabic, "الرئيسية")
        XCTAssertNotEqual(english, hebrew)
        XCTAssertNotEqual(english, arabic)

        XCTAssertEqual(
            AppLocale.localizedString("home.clockIn", language: .hebrew),
            "כניסה"
        )
        XCTAssertEqual(
            AppLocale.localizedString("settings.appLanguage", language: .arabic),
            "لغة التطبيق"
        )
        XCTAssertEqual(
            AppLocale.localizedString("history.emptyPeriod", language: .hebrew),
            "אין משמרות ביום זה"
        )
    }

    func testHomeLiveGrossBasicLocalizedInAllLanguages() {
        let english = AppLocale.localizedString("home.liveGrossBasic", language: .english)
        let hebrew = AppLocale.localizedString("home.liveGrossBasic", language: .hebrew)
        let arabic = AppLocale.localizedString("home.liveGrossBasic", language: .arabic)

        XCTAssertEqual(english, "Basic Gross")
        XCTAssertEqual(hebrew, "ברוטו בסיסי")
        XCTAssertEqual(arabic, "إجمالي أساسي")
        // Must never fall back to the raw catalog key on any supported language.
        XCTAssertNotEqual(english, "home.liveGrossBasic")
        XCTAssertNotEqual(hebrew, "home.liveGrossBasic")
        XCTAssertNotEqual(arabic, "home.liveGrossBasic")
        XCTAssertNotEqual(english, hebrew)
        XCTAssertNotEqual(english, arabic)
    }

    func testHomeForgotClockInAndWeekLoadingLocalizedInAllLanguages() {
        XCTAssertEqual(
            AppLocale.localizedString("home.weekLoading", language: .hebrew),
            "בטעינה…"
        )
        XCTAssertEqual(
            AppLocale.localizedString("home.forgotClockIn", language: .hebrew),
            "שכחת להחתים?"
        )
        XCTAssertEqual(
            AppLocale.localizedString("home.forgotClockIn", language: .english),
            "Forgot to clock in?"
        )
        XCTAssertEqual(
            AppLocale.localizedString("home.forgotClockIn", language: .arabic),
            "نسيت تسجّل دخول؟"
        )
        XCTAssertEqual(
            AppLocale.localizedString("home.forgotClockIn.arrivalPrompt", language: .arabic),
            "وينتا وصلت عالشغل؟"
        )
    }

    func testDateLabelsFollowExplicitAppLocaleNotDevice() {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 16
        let date = Calendar(identifier: .gregorian).date(from: components)!

        let hebrewMonth = HistoryPeriodHelper.monthTitle(
            for: date,
            locale: Locale(identifier: "he")
        )
        let englishMonth = HistoryPeriodHelper.monthTitle(
            for: date,
            locale: Locale(identifier: "en")
        )
        XCTAssertTrue(hebrewMonth.contains("2026"))
        XCTAssertFalse(hebrewMonth.localizedCaseInsensitiveContains("July"))
        XCTAssertTrue(englishMonth.localizedCaseInsensitiveContains("July"))

        let hebrewLetter = HistoryPeriodHelper.weekdayLetter(
            for: date,
            locale: Locale(identifier: "he")
        )
        let englishLetter = HistoryPeriodHelper.weekdayLetter(
            for: date,
            locale: Locale(identifier: "en")
        )
        XCTAssertEqual(englishLetter, "T") // Thursday
        XCTAssertNotEqual(hebrewLetter, englishLetter)
    }
}
