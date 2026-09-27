import Foundation
import os
import UIKit
import WatchConnectivity
import WidgetKit

/// A message from the app owner, already in this device's language (the server
/// picks the he / ar / en copy that matches the in-app language).
struct Announcement: Codable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let body: String
    let createdAt: Date?
}

/// What this install tells the `register-device` Edge Function. Deliberately
/// small: a random install id (not the vendor id), the push token, the in-app
/// language and app version, and whether a Watch / widget is in use — nothing
/// about shifts, pay or the user's identity (the account, when signed in, comes
/// from the session token on the server side only).
struct DeviceRegistrationPayload: Encodable, Equatable {
    var action = "register"
    let deviceId: UUID
    let apnsToken: String?
    let apnsEnv: String
    let language: String
    let appVersion: String
    let build: String
    let osVersion: String
    let hasWatch: Bool
    let hasWidget: Bool
    let announcementsEnabled: Bool
}

/// Registers this install for owner announcements (push + in-app) and holds the
/// in-app announcement currently on screen. See `supabase/functions/register-device`.
@MainActor
final class AnnouncementCenter: ObservableObject {
    static let shared = AnnouncementCenter()

    /// The announcement shown in the in-app banner, one at a time.
    @Published private(set) var current: Announcement?

    private static let logger = Logger(subsystem: "com.hourstracker.app", category: "announcements")
    private static let functionURL = SupabaseConfig.projectURL
        .appendingPathComponent("functions/v1/register-device")
    /// Re-check at most this often when nothing about the device changed.
    static let refreshInterval: TimeInterval = 15 * 60

    private enum Key {
        static let installID = "announcements.installID"
        static let apnsToken = "announcements.apnsToken"
        static let lastPayload = "announcements.lastPayload"
        static let lastRegistered = "announcements.lastRegistered"
    }

    private let defaults: UserDefaults
    private let session: URLSession
    private var queue: [Announcement] = []
    private var inFlight = false

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
    }

    /// Random per-install id, created on first use and dropped by `forget()`.
    var installID: UUID {
        if let raw = defaults.string(forKey: Key.installID), let id = UUID(uuidString: raw) {
            return id
        }
        let id = UUID()
        defaults.set(id.uuidString, forKey: Key.installID)
        return id
    }

    // MARK: Push token

    func requestPushToken() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didReceivePushToken(_ token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        guard hex != defaults.string(forKey: Key.apnsToken) else { return }
        defaults.set(hex, forKey: Key.apnsToken)
        refresh(force: true)
    }

    // MARK: Registration

    /// Registers (or updates) this device and picks up unseen announcements.
    /// Throttled unless something about the device changed or `force` is set.
    func refresh(force: Bool = false) {
        guard !inFlight, !Self.isAutomatedRun else { return }
        Task { await refreshNow(force: force) }
    }

    func refreshNow(force: Bool = false) async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        let payload = await makePayload()
        let encoded = try? JSONEncoder().encode(payload)
        let lastRegistered = defaults.object(forKey: Key.lastRegistered) as? Date ?? .distantPast
        guard Self.shouldRegister(
            force: force,
            changed: encoded != defaults.data(forKey: Key.lastPayload),
            lastRegistered: lastRegistered
        ) else { return }

        guard let response: RegisterResponse = await post(payload) else { return }
        defaults.set(encoded, forKey: Key.lastPayload)
        defaults.set(Date(), forKey: Key.lastRegistered)
        if payload.announcementsEnabled {
            enqueue(response.announcements ?? [])
        }
    }

    /// Unit/UI test runs (CI simulators) must never register as real devices —
    /// they would show up in the owner's stats and audience counts.
    static var isAutomatedRun: Bool {
        let info = ProcessInfo.processInfo
        return info.environment["XCTestConfigurationFilePath"] != nil
            || info.arguments.contains("UITEST_SCREENSHOTS")
    }

    static func shouldRegister(force: Bool, changed: Bool, lastRegistered: Date, now: Date = Date()) -> Bool {
        force || changed || now.timeIntervalSince(lastRegistered) >= refreshInterval
    }

    /// The user closed the banner: mark it seen on the server so it isn't shown again.
    func dismissCurrent() {
        guard let shown = current else { return }
        current = nil
        let deviceId = installID
        Task {
            let _: RegisterResponse? = await post(AckRequest(deviceId: deviceId, seenIds: [shown.id]))
            showNext()
        }
    }

    /// Delete-all: removes this device from the registry and forgets the install id,
    /// so a later registration starts as a brand-new, unlinked device.
    func forget() {
        let deviceId = defaults.string(forKey: Key.installID).flatMap(UUID.init(uuidString:))
        for key in [Key.installID, Key.apnsToken, Key.lastPayload, Key.lastRegistered] {
            defaults.removeObject(forKey: key)
        }
        queue = []
        current = nil
        guard let deviceId else { return }
        Task {
            let _: RegisterResponse? = await post(ForgetRequest(deviceId: deviceId))
        }
    }

    // MARK: Internals

    private struct AckRequest: Encodable {
        var action = "ack"
        let deviceId: UUID
        let seenIds: [UUID]
    }

    private struct ForgetRequest: Encodable {
        var action = "forget"
        let deviceId: UUID
    }

    private struct RegisterResponse: Decodable {
        let announcements: [Announcement]?
    }

    private func enqueue(_ items: [Announcement]) {
        let known = Set(queue.map(\.id) + [current?.id].compactMap { $0 })
        queue += items.filter { !known.contains($0.id) }
        showNext()
    }

    private func showNext() {
        guard current == nil, !queue.isEmpty else { return }
        current = queue.removeFirst()
    }

    private func makePayload() async -> DeviceRegistrationPayload {
        let info = Bundle.main.infoDictionary ?? [:]
        // Completion-handler form: the async `currentConfigurations()` is iOS 18+.
        let hasWidget = await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                continuation.resume(returning: ((try? result.get()) ?? []).isEmpty == false)
            }
        }
        let hasWatch = WCSession.isSupported()
            && WCSession.default.activationState == .activated
            && WCSession.default.isPaired
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        return DeviceRegistrationPayload(
            deviceId: installID,
            apnsToken: defaults.string(forKey: Key.apnsToken),
            apnsEnv: environment,
            language: AppLocale.current.localeIdentifier,
            appVersion: info["CFBundleShortVersionString"] as? String ?? "",
            build: info["CFBundleVersion"] as? String ?? "",
            osVersion: UIDevice.current.systemVersion,
            hasWatch: hasWatch,
            hasWidget: hasWidget,
            announcementsEnabled: NotificationPreferences.shared.announcementsEnabled
        )
    }

    private func post<Body: Encodable, Response: Decodable>(_ body: Body) async -> Response? {
        guard !Self.isAutomatedRun else { return nil }
        var request = URLRequest(url: Self.functionURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        // Signed in: the session token lets the server link the device to the
        // account (for "selected users" targeting). Otherwise the publishable key.
        let token = (try? await SupabaseAuthManager.shared.client.auth.session.accessToken)
            ?? SupabaseConfig.publishableKey
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200..<300).contains(status) else {
                Self.logger.error("register-device failed: \(status)")
                return nil
            }
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            Self.logger.error("register-device error: \(error.localizedDescription)")
            return nil
        }
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            return AnnouncementCenter.parseDate(raw) ?? .distantPast
        }
        return decoder
    }()

    /// Postgres timestamps come back with up to 6 fractional digits and an offset;
    /// the fraction is dropped (second precision is plenty here) so the plain
    /// ISO 8601 parser always accepts it.
    nonisolated static func parseDate(_ raw: String) -> Date? {
        let normalized = raw.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: normalized)
    }
}
