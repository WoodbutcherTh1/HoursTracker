import XCTest
@testable import HoursTracker

@MainActor
final class LegalConsentTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "LegalConsentTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testANewUserMustAgreeFirst() {
        let consent = LegalConsent(defaults: defaults, skipsGate: false)
        XCTAssertFalse(consent.isAccepted)
        XCTAssertFalse(consent.isReconsent)
        XCTAssertNil(consent.acceptedAt)
    }

    func testAgreeingUnlocksTheAppAndIsRemembered() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        LegalConsent(defaults: defaults, skipsGate: false).accept(now: now)

        let reloaded = LegalConsent(defaults: defaults, skipsGate: false)
        XCTAssertTrue(reloaded.isAccepted)
        XCTAssertEqual(reloaded.acceptedVersion, LegalConsent.currentVersion)
        XCTAssertEqual(reloaded.acceptedAt, now)
    }

    func testAnOlderAgreementAsksAgain() {
        defaults.set(LegalConsent.currentVersion - 1, forKey: LegalConsent.versionKey)
        let consent = LegalConsent(defaults: defaults, skipsGate: false)
        XCTAssertFalse(consent.isAccepted)
        // Version 0 means "never agreed": a first consent, not an update.
        XCTAssertEqual(consent.isReconsent, LegalConsent.currentVersion > 1)
    }

    func testAutomatedRunsSkipTheGate() {
        XCTAssertTrue(LegalConsent(defaults: defaults, skipsGate: true).isAccepted)
    }
}
