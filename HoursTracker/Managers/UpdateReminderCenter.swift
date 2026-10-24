import Foundation
import os
import UIKit

/// Asks users who are behind to update, politely and a limited number of times.
///
/// The App Store's lookup service says which version is live. When it is newer than the
/// installed one (and the iPhone's iOS can run it), a pop-up offers "Update" (opens the
/// App Store page) or "Later". Each time the pop-up is shown counts as one attempt; the
/// next one waits longer (3, 7, 14, 21 days), and after 5 attempts for the same version
/// it stops for good. Installing the update ends it on its own — the live version is then
/// no longer newer. It only appears while the app is open, never as a push.
@MainActor
final class UpdateReminderCenter: ObservableObject {
    static let shared = UpdateReminderCenter()

    static let appStoreID = "6790862413"
    static let storeURL = URL(string: "https://apps.apple.com/app/id\(appStoreID)")
    static let maxAttempts = 5
    /// Days to wait after attempt 1, 2, 3, 4 (the 5th is the last).
    static let gapsInDays = [3, 7, 14, 21]
    /// How often the store is asked, at most.
    static let checkInterval: TimeInterval = 12 * 3600

    private enum Key {
        static let lastCheck = "update.lastCheck"
        static let latestVersion = "update.latestVersion"
        static let minimumOS = "update.minimumOS"
        static let attemptsVersion = "update.attemptsVersion"
        static let attempts = "update.attempts"
        static let nextEligible = "update.nextEligible"
    }

    /// A reminder is due; the pop-up shows once the app is free to (see `MainTabView`).
    @Published private(set) var promptPending = false
    @Published private(set) var latestVersion = ""

    private static let logger = Logger(subsystem: "com.hourstracker.app", category: "update")
    private let defaults: UserDefaults
    private let session: URLSession

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
    }

    // MARK: Pure rules (unit-tested)

    /// True when `candidate` is a higher version than `installed` ("1.10" > "1.9").
    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = installed.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// When the next reminder may appear after `attempts` have been shown (nil = stop).
    static func nextEligibleDate(afterAttempts attempts: Int, from now: Date) -> Date? {
        guard attempts >= 1, attempts < maxAttempts, attempts <= gapsInDays.count else { return nil }
        return now.addingTimeInterval(TimeInterval(gapsInDays[attempts - 1]) * 86_400)
    }

    // MARK: Flow

    /// Call when the app is open and free to show a pop-up.
    func evaluate(now: Date = Date()) async {
        guard !AnnouncementCenter.isAutomatedRun else { return }
        #if targetEnvironment(simulator)
        return
        #else
        let installed = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let lastCheck = defaults.object(forKey: Key.lastCheck) as? Date ?? .distantPast
        if now.timeIntervalSince(lastCheck) >= Self.checkInterval {
            if let found = await fetchLiveVersion() {
                defaults.set(found.version, forKey: Key.latestVersion)
                defaults.set(found.minimumOS, forKey: Key.minimumOS)
                defaults.set(now, forKey: Key.lastCheck)
            }
        }
        let latest = defaults.string(forKey: Key.latestVersion) ?? ""
        guard !latest.isEmpty, Self.isNewer(latest, than: installed),
              Self.canRun(minimumOS: defaults.string(forKey: Key.minimumOS)) else {
            promptPending = false
            return
        }
        if defaults.string(forKey: Key.attemptsVersion) != latest {
            // A new version is out: the count starts over.
            defaults.set(latest, forKey: Key.attemptsVersion)
            defaults.set(0, forKey: Key.attempts)
            defaults.removeObject(forKey: Key.nextEligible)
        }
        guard defaults.integer(forKey: Key.attempts) < Self.maxAttempts else { return }
        if let next = defaults.object(forKey: Key.nextEligible) as? Date, now < next { return }
        latestVersion = latest
        promptPending = true
        #endif
    }

    /// The pop-up appeared: that is one attempt, and the next one is scheduled.
    func registerShown(now: Date = Date()) {
        let attempts = defaults.integer(forKey: Key.attempts) + 1
        defaults.set(attempts, forKey: Key.attempts)
        if let next = Self.nextEligibleDate(afterAttempts: attempts, from: now) {
            defaults.set(next, forKey: Key.nextEligible)
        } else {
            defaults.set(Date.distantFuture, forKey: Key.nextEligible)
        }
    }

    func dismiss() {
        promptPending = false
    }

    func openStore() {
        promptPending = false
        guard let url = Self.storeURL else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Store lookup

    private static func canRun(minimumOS: String?) -> Bool {
        guard let minimumOS, !minimumOS.isEmpty else { return true }
        return !isNewer(minimumOS, than: UIDevice.current.systemVersion)
    }

    private func fetchLiveVersion() async -> (version: String, minimumOS: String)? {
        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(Self.appStoreID)&country=il") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            struct Lookup: Decodable {
                struct Result: Decodable { let version: String; let minimumOsVersion: String? }
                let results: [Result]
            }
            guard let first = try JSONDecoder().decode(Lookup.self, from: data).results.first else { return nil }
            return (first.version, first.minimumOsVersion ?? "")
        } catch {
            Self.logger.error("version lookup failed: \(error.localizedDescription)")
            return nil
        }
    }
}
