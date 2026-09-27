import XCTest
@testable import HoursTracker

@MainActor
final class AnnouncementTests: XCTestCase {
    // MARK: Draft

    func testDraftNeedsABodyAndADeliveryChannel() {
        var draft = AnnouncementDraft()
        XCTAssertFalse(draft.isSendable)
        draft.bodies["ar"] = "  "
        XCTAssertFalse(draft.isSendable)
        draft.bodies["ar"] = "مرحبا"
        XCTAssertTrue(draft.isSendable)
        draft.push = false
        draft.inApp = false
        XCTAssertFalse(draft.isSendable)
    }

    func testMissingLanguagesWarnsAboutUntranslatedCopies() {
        var draft = AnnouncementDraft()
        XCTAssertEqual(draft.missingLanguages, [])
        draft.bodies["he"] = "שלום"
        XCTAssertEqual(draft.missingLanguages, ["ar", "en"])
        draft.bodies["ar"] = "مرحبا"
        draft.bodies["en"] = "Hello"
        XCTAssertEqual(draft.missingLanguages, [])
    }

    func testTrimmedDropsEmptyLanguages() {
        let draft = AnnouncementDraft()
        XCTAssertEqual(draft.trimmed(["en": " Hi ", "he": "", "ar": "\n"]), ["en": "Hi"])
    }

    // MARK: Targeting

    func testTargetEncodesOnlyTheFieldsInUse() throws {
        let target = AnnouncementTarget(kind: .language, languages: ["ar"])
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(target), encoding: .utf8))
        XCTAssertTrue(json.contains("\"kind\":\"language\""))
        XCTAssertTrue(json.contains("\"languages\":[\"ar\"]"))
        XCTAssertFalse(json.contains("emails"))
    }

    func testSplitAcceptsCommasSpacesAndNewlines() {
        XCTAssertEqual(
            AdminComposeView.split("a@x.com, b@y.com\nc@z.com;  "),
            ["a@x.com", "b@y.com", "c@z.com"]
        )
    }

    // MARK: Registration

    func testRegistrationIsThrottledUnlessSomethingChanged() {
        let now = Date()
        let recent = now.addingTimeInterval(-60)
        let old = now.addingTimeInterval(-(AnnouncementCenter.refreshInterval + 1))
        XCTAssertFalse(AnnouncementCenter.shouldRegister(force: false, changed: false, lastRegistered: recent, now: now))
        XCTAssertTrue(AnnouncementCenter.shouldRegister(force: false, changed: true, lastRegistered: recent, now: now))
        XCTAssertTrue(AnnouncementCenter.shouldRegister(force: true, changed: false, lastRegistered: recent, now: now))
        XCTAssertTrue(AnnouncementCenter.shouldRegister(force: false, changed: false, lastRegistered: old, now: now))
    }

    func testInstallIDIsStableAndForgettable() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AnnouncementTests-\(UUID().uuidString)"))
        let center = AnnouncementCenter(defaults: defaults)
        let first = center.installID
        XCTAssertEqual(center.installID, first)
        center.forget()
        XCTAssertNotEqual(center.installID, first)
    }

    func testDecodesServerAnnouncementWithPostgresTimestamp() throws {
        let json = """
        {"id":"5B0E2C1A-8F5D-4D2B-9C3E-1A2B3C4D5E6F","title":"שלום","body":"גרסה חדשה",
         "createdAt":"2026-09-27T10:15:30.123456+00:00"}
        """
        let item = try AnnouncementCenter.decoder.decode(Announcement.self, from: Data(json.utf8))
        XCTAssertEqual(item.title, "שלום")
        XCTAssertNotNil(item.createdAt)
        XCTAssertNotEqual(item.createdAt, .distantPast)
    }

    func testParsesTimestampsWithAndWithoutFractions() {
        XCTAssertNotNil(AnnouncementCenter.parseDate("2026-09-27T10:15:30Z"))
        XCTAssertNotNil(AnnouncementCenter.parseDate("2026-09-27T10:15:30.5+00:00"))
        XCTAssertNotNil(AnnouncementCenter.parseDate("2026-09-27T10:15:30.123456+00:00"))
        XCTAssertNil(AnnouncementCenter.parseDate("yesterday"))
    }
}
