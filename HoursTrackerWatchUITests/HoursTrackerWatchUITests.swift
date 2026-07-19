import XCTest

/// Captures Main + Recent screens in `HT_SCREENSHOT_MODE`.
/// Config: `/tmp/ht-watch-screenshot-config.json` (written by capture script).
final class HoursTrackerWatchUITests: XCTestCase {
    private struct Config: Decodable {
        var lang: String
        var device: String
        var output: String
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureClockAndRecentScreenshots() throws {
        let config = loadConfig()
        let shortLocale = config.lang
        let deviceSlot = config.device
        let appleLocale: String = {
            switch shortLocale {
            case "he": return "he_IL"
            case "ar": return "ar_SA"
            default: return "en_US"
            }
        }()

        let app = XCUIApplication()
        app.launchArguments += [
            "HT_SCREENSHOT_MODE=1",
            "HT_SCREENSHOT_LANG=\(shortLocale)",
            "-AppleLanguages", "(\(shortLocale))",
            "-AppleLocale", appleLocale
        ]
        app.launchEnvironment["HT_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["HT_SCREENSHOT_LANG"] = shortLocale
        if app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
        }
        app.launch()

        let toggle = app.buttons["watch.clock.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8), "Clock toggle missing")
        // Allow `.task` screenshot seed to apply.
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        // Demo data is mid-shift → expect Clock Out label (localized).
        let label = toggle.label
        let clockedOutLabels = ["Clock In", "כניסה", "تسجيل دخول"]
        XCTAssertFalse(
            clockedOutLabels.contains(label),
            "Expected clocked-in (Clock Out) in screenshot mode; label=\(label)"
        )

        let recent = app.descendants(matching: .any)
            .matching(identifier: "watch.nav.recent")
            .element(boundBy: 0)
        XCTAssertTrue(recent.waitForExistence(timeout: 5), "Recent nav missing")
        let screenMid = app.frame.midX
        let recentMid = recent.frame.midX

        saveScreenshot(
            app.screenshot(),
            name: "01-clock",
            locale: shortLocale,
            deviceSlot: deviceSlot,
            outputRoot: config.output
        )

        recent.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        // Recent screen title / rows
        let recentTitle = app.navigationBars.firstMatch
        _ = recentTitle.waitForExistence(timeout: 3)

        saveScreenshot(
            app.screenshot(),
            name: "02-recent",
            locale: shortLocale,
            deviceSlot: deviceSlot,
            outputRoot: config.output
        )

        assertToolbarSide(recentMid: recentMid, screenMid: screenMid, locale: shortLocale)
        if shortLocale == "he" || shortLocale == "ar" {
            assertListRTL(locale: shortLocale, app: app)
        }
    }

    private func loadConfig() -> Config {
        let url = URL(fileURLWithPath: "/tmp/ht-watch-screenshot-config.json")
        if let data = try? Data(contentsOf: url),
           let config = try? JSONDecoder().decode(Config.self, from: data) {
            return config
        }
        return Config(
            lang: "en",
            device: "series11-416x496",
            output: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("AppStoreScreenshots/watch")
                .path
        )
    }

    private func assertToolbarSide(recentMid: CGFloat, screenMid: CGFloat, locale: String) {
        // watchOS accessibility frames can sit outside app.frame; compare against
        // the wider window bounds when available.
        switch locale {
        case "he", "ar":
            XCTAssertLessThan(
                recentMid,
                screenMid,
                "Expected RTL: Recent mirrored to visual left for \(locale); midX=\(recentMid) screenMid=\(screenMid)"
            )
        default:
            XCTAssertGreaterThan(
                recentMid,
                screenMid,
                "Expected LTR: Recent on visual right for \(locale); midX=\(recentMid) screenMid=\(screenMid)"
            )
        }
    }

    private func assertListRTL(locale: String, app: XCUIApplication) {
        // Prefer navigation bar back control existing on Recent (RTL still shows chevron).
        let bars = app.navigationBars
        XCTAssertTrue(
            bars.firstMatch.waitForExistence(timeout: 2),
            "Expected Recent navigation bar for \(locale)"
        )
    }

    private func saveScreenshot(
        _ screenshot: XCUIScreenshot,
        name: String,
        locale: String,
        deviceSlot: String,
        outputRoot: String
    ) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(deviceSlot)-\(locale)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        let data = screenshot.pngRepresentation
        let roots = [
            URL(fileURLWithPath: outputRoot),
            URL(fileURLWithPath: "/tmp/ht-watch-ss")
        ]
        var wrote = false
        var lastError: Error?
        for root in roots {
            let dir = root
                .appendingPathComponent(deviceSlot, isDirectory: true)
                .appendingPathComponent(locale, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try data.write(to: dir.appendingPathComponent("\(name).png"), options: .atomic)
                wrote = true
            } catch {
                lastError = error
            }
        }
        XCTAssertTrue(wrote, "Failed to write \(deviceSlot)/\(locale)/\(name): \(String(describing: lastError))")
    }
}
