import SwiftUI
import XCTest
@testable import HoursTracker

/// The shared loading/empty/error component: pins the copy contract through the
/// pure `HTStateCopy` mapping (the same struct `HTStateView` renders from) so
/// tests don't fight SwiftUI's rendering internals, plus a catalog-integrity
/// test that guards every key the Watch resolves through `AppLocale.tr` — a
/// missing translation would render a raw key on the user's wrist.
@MainActor
final class HTStateViewTests: XCTestCase {

    func testLoadingCarriesLabelAndNoAffordances() {
        let copy = HTStateCopy.make(from: .loading(label: "Analyzing timesheet…"))
        XCTAssertEqual(copy.title, "Analyzing timesheet…")
        XCTAssertNil(copy.actionTitle)
        XCTAssertNil(copy.retryTitle)
        XCTAssertEqual(copy.symbol, "", "loading shows a spinner, not a symbol")
    }

    func testEmptyCarriesTitleHintAndAction() {
        let copy = HTStateCopy.make(from: .empty(
            icon: "hand.draw", title: "No shifts", hint: "Clock in first.", actionTitle: "Show all", action: {}
        ))
        XCTAssertEqual(copy.symbol, "hand.draw")
        XCTAssertEqual(copy.title, "No shifts")
        XCTAssertEqual(copy.hint, "Clock in first.")
        XCTAssertEqual(copy.actionTitle, "Show all")
    }

    func testErrorWithoutRetryOmitsRetryTitle() {
        let copy = HTStateCopy.make(from: .error(message: "iPhone not reachable."))
        XCTAssertEqual(copy.title, "iPhone not reachable.")
        XCTAssertNil(copy.retryTitle, "no closure → no retry button, so no localized fallback either")
    }

    func testErrorWithRetryFallsBackToLocalizedRetryTitle() {
        let copy = HTStateCopy.make(from: .error(message: "boom", retry: {}))
        XCTAssertEqual(copy.retryTitle, AppLocale.tr("common.retry"))
        XCTAssertNotEqual(copy.retryTitle, "common.retry", "the raw key must never leak into UI")
    }

    func testCatalogKeysExistForWatchSurface() {
        for key in [
            "common.retry",
            "watch.syncHint",
            "watch.noShifts",
            "watch.exportNoData",
            "watch.exportPhoneOnly",
            "watch.settings.phoneOnly",
            "watch.settings.startsOnDay %@",
            "watch.settings.startsOnLabel",
            "watch.a11y.clockInHint",
            "watch.a11y.clockOutHint",
        ] {
            for language in [AppLocale.Language.english, .hebrew, .arabic] {
                let value = AppLocale.localizedString(key, language: language)
                XCTAssertNotEqual(value, key, "key \(key) missing for \(language)")
            }
        }
    }

    func testGreetingCatalogSharedByBothTargets() {
        // DaypartGreeting resolves through the same L10n path on Watch and phone;
        // these keys must exist in all three languages for both surfaces.
        for key in [
            "home.greeting.morning", "home.greeting.afternoon",
            "home.greeting.evening", "home.greeting.night",
            "home.greeting.morningName %@", "home.greeting.nightName %@",
        ] {
            for language in [AppLocale.Language.english, .hebrew, .arabic] {
                XCTAssertNotEqual(
                    AppLocale.localizedString(key, language: language), key,
                    "greeting key \(key) missing for \(language)"
                )
            }
        }
    }
}
