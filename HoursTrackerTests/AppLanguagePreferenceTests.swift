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
}
