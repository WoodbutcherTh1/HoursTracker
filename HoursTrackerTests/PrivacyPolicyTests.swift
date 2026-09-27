import SwiftUI
import XCTest
@testable import HoursTracker

/// The in-app privacy policy is the only copy (there is no web page), so every
/// section must exist in all three languages and the screen must build and scroll.
@MainActor
final class PrivacyPolicyTests: XCTestCase {
    private let keys = [
        "privacy.title", "privacy.updated",
        "privacy.section.data", "privacy.body.data",
        "privacy.section.icloud", "privacy.body.icloud",
        "privacy.section.location", "privacy.body.location",
        "privacy.section.camera", "privacy.body.camera",
        "privacy.section.tracking", "privacy.body.tracking",
        "privacy.section.controls", "privacy.body.controls",
        "privacy.section.contact", "privacy.body.contact"
    ]

    func testEverySectionIsTranslatedInAllThreeLanguages() {
        for language in [AppLocale.Language.english, .hebrew, .arabic] {
            for key in keys {
                let value = AppLocale.localizedString(key, language: language)
                XCTAssertFalse(value.isEmpty, "\(key) is empty in \(language)")
                XCTAssertNotEqual(value, key, "\(key) is missing in \(language)")
            }
        }
        // Not silently falling back to English.
        let english = AppLocale.localizedString("privacy.body.data", language: .english)
        XCTAssertNotEqual(AppLocale.localizedString("privacy.body.data", language: .hebrew), english)
        XCTAssertNotEqual(AppLocale.localizedString("privacy.body.data", language: .arabic), english)
    }

    /// Builds the real view on a small screen and checks the long text lives in a
    /// scroll view taller than the screen, so nothing is cut off.
    func testPolicyBuildsAndScrollsOnASmallScreen() throws {
        let host = UIHostingController(rootView: NavigationStack { PrivacyPolicyView() })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.view.layoutIfNeeded()

        let scrollView = try XCTUnwrap(Self.firstScrollView(in: host.view), "PrivacyPolicyView has no scroll view")
        XCTAssertGreaterThan(scrollView.contentSize.height, scrollView.bounds.height,
                             "Policy text should be longer than an SE screen and scroll")
        window.isHidden = true
    }

    private static func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }
}
