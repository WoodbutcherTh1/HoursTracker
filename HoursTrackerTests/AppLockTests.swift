import XCTest
@testable import HoursTracker

final class AppLockPolicyTests: XCTestCase {
    func testGracePeriodRequiresThirtySecondsInBackground() {
        let backgrounded = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(
            AppLockPolicy.shouldLockOnResume(
                isEnabled: true,
                backgroundedAt: backgrounded,
                now: backgrounded.addingTimeInterval(29)
            )
        )
        XCTAssertTrue(
            AppLockPolicy.shouldLockOnResume(
                isEnabled: true,
                backgroundedAt: backgrounded,
                now: backgrounded.addingTimeInterval(30)
            )
        )
    }

    func testDisabledNeverLocksOnResume() {
        XCTAssertFalse(
            AppLockPolicy.shouldLockOnResume(
                isEnabled: false,
                backgroundedAt: Date().addingTimeInterval(-120)
            )
        )
    }

    func testNilBackgroundStampDoesNotLockOnResume() {
        // Cold-start locking is handled by the controller init, not resume policy.
        XCTAssertFalse(AppLockPolicy.shouldLockOnResume(isEnabled: true, backgroundedAt: nil))
    }

    func testMaskedNationalIDKeepsLastFour() {
        XCTAssertEqual(AppLockPolicy.maskedNationalID("123456782"), "•••••6782")
        XCTAssertEqual(AppLockPolicy.maskedNationalID("12"), "••")
        XCTAssertEqual(AppLockPolicy.maskedNationalID(""), "••••")
    }
}

@MainActor
final class AppLockControllerTests: XCTestCase {
    private final class MemoryPreference: AppLockPreferencing {
        var isEnabled: Bool
        init(_ enabled: Bool = false) { self.isEnabled = enabled }
    }

    private struct StubAuth: BiometricAuthenticating {
        var result: Result<Bool, Error> = .success(true)
        func authenticate(reason: String) async throws -> Bool {
            try result.get()
        }
    }

    func testDefaultPreferenceIsOff() {
        let defaults = UserDefaults(suiteName: "AppLockTests-\(UUID().uuidString)")!
        let pref = UserDefaultsAppLockPreference(defaults: defaults)
        XCTAssertFalse(pref.isEnabled)
    }

    func testStartsLockedWhenEnabled() {
        let controller = AppLockController(
            preference: MemoryPreference(true),
            authenticator: StubAuth()
        )
        XCTAssertTrue(controller.isEnabled)
        XCTAssertTrue(controller.isLocked)
    }

    func testStartsUnlockedWhenDisabled() {
        let controller = AppLockController(
            preference: MemoryPreference(false),
            authenticator: StubAuth()
        )
        XCTAssertFalse(controller.isLocked)
    }

    func testUnlockClearsLock() async {
        let controller = AppLockController(
            preference: MemoryPreference(true),
            authenticator: StubAuth(result: .success(true))
        )
        await controller.unlock()
        XCTAssertFalse(controller.isLocked)
    }

    func testFailedAuthKeepsLock() async {
        let controller = AppLockController(
            preference: MemoryPreference(true),
            authenticator: StubAuth(result: .failure(AppLockAuthError.failed))
        )
        await controller.unlock()
        XCTAssertTrue(controller.isLocked)
        XCTAssertNotNil(controller.authErrorMessage)
    }

    func testBackgroundPastGraceLocksOnActive() async {
        let controller = AppLockController(
            preference: MemoryPreference(true),
            authenticator: StubAuth()
        )
        await controller.unlock()
        XCTAssertFalse(controller.isLocked)

        let t0 = Date(timeIntervalSince1970: 5_000)
        controller.handleScenePhase(.background, now: t0)
        controller.handleScenePhase(.active, now: t0.addingTimeInterval(10))
        XCTAssertFalse(controller.isLocked, "within grace period should stay unlocked")

        controller.handleScenePhase(.background, now: t0.addingTimeInterval(20))
        controller.handleScenePhase(.active, now: t0.addingTimeInterval(20 + AppLockPolicy.gracePeriod + 1))
        XCTAssertTrue(controller.isLocked)
    }

    func testDisablingClearsLock() {
        let controller = AppLockController(
            preference: MemoryPreference(true),
            authenticator: StubAuth()
        )
        XCTAssertTrue(controller.isLocked)
        controller.isEnabled = false
        XCTAssertFalse(controller.isLocked)
    }
}
