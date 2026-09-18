import Foundation
import WatchConnectivity
import Combine

/// Watch-side counterpart to the phone's `WatchConnectivityManager`. Holds the
/// latest `WatchSnapshot` (cached to disk so the UI has something to show the
/// instant the app launches, before any fresh context arrives) and sends
/// clock-in/out requests to the phone.
///
/// Not `@MainActor` itself — `WCSessionDelegate` callbacks land on an arbitrary
/// background queue; every `@Published` mutation hops to the main actor explicitly.
final class WatchSessionStore: NSObject, ObservableObject {
    static let shared = WatchSessionStore()

    @Published private(set) var snapshot: WatchSnapshot = .empty
    @Published private(set) var isReachable = false
    @Published var lastErrorMessage: String?

    private let cacheKey = "com.hourstracker.watch.lastSnapshot"

    private override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(WatchSnapshot.self, from: data) {
            snapshot = cached
        }
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Asks the phone to clock in/out. The phone owns persistence, Live Activity,
    /// and sync — the Watch only signals intent and displays the reply.
    func requestClockAction(_ action: WatchAction) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.isReachable else {
            lastErrorMessage = "Open HoursTracker on your iPhone nearby to sync."
            return
        }
        session.sendMessage(
            [WatchMessageKey.action: action.rawValue],
            replyHandler: { [weak self] reply in
                guard let updated = WatchSnapshot.from(message: reply) else { return }
                Task { @MainActor in self?.apply(updated) }
            },
            errorHandler: { [weak self] error in
                Task { @MainActor in self?.lastErrorMessage = error.localizedDescription }
            }
        )
    }

    @MainActor
    private func apply(_ snapshot: WatchSnapshot) {
        self.snapshot = snapshot
        self.lastErrorMessage = nil
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
}

extension WatchSessionStore: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in self.isReachable = session.isReachable }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.isReachable = session.isReachable }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let snapshot = WatchSnapshot.from(message: applicationContext) else { return }
        Task { @MainActor in self.apply(snapshot) }
    }
}
