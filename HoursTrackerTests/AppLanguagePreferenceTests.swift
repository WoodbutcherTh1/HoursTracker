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
