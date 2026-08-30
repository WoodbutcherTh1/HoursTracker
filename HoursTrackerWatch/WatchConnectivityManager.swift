import Foundation
import WatchConnectivity

/// Watch-side counterpart to the phone's `WatchConnectivityBridge`. Sends a
/// clock-in/out tap to the phone with `sendMessage` (live round trip, phone must be
/// reachable) and separately keeps a cached status from `didReceiveApplicationContext`
/// so the watch UI has something to show even when the phone isn't reachable right now.
///
/// NOT verified against a real build — written and reasoned through without Xcode or
/// a watchOS simulator available in this environment.

/// One completed session, as sent by the phone's `WatchConnectivityBridge.refresh(sessions:settings:)`
/// (last 20 completed sessions, newest first). Read-only on the watch — no mutation path.
struct WatchSessionSummary: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let clockIn: Date
    let clockOut: Date
    let totalHours: Double
}

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    @Published private(set) var isClockedIn = false
    @Published private(set) var clockInDate: Date?
    @Published private(set) var isSending = false
    @Published var lastErrorMessage: String?
    @Published private(set) var recentSessions: [WatchSessionSummary] = []

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func toggleClock() {
        guard WCSession.isSupported(), WCSession.default.isReachable else {
            lastErrorMessage = "Open HoursTracker on your iPhone first."
            return
        }
        isSending = true
        let action = isClockedIn ? "clockOut" : "clockIn"
        WCSession.default.sendMessage(["action": action], replyHandler: { [weak self] reply in
            Task { @MainActor in
                guard let self else { return }
                self.isSending = false
                if let stillIn = reply["isClockedIn"] as? Bool {
                    self.isClockedIn = stillIn
                    if !stillIn { self.clockInDate = nil }
                }
            }
        }, errorHandler: { [weak self] error in
            Task { @MainActor in
                self?.isSending = false
                self?.lastErrorMessage = error.localizedDescription
            }
        })
    }

    private func applyContext(_ context: [String: Any]) {
        if let isClockedIn = context["isClockedIn"] as? Bool {
            self.isClockedIn = isClockedIn
        }
        if let interval = context["clockInDate"] as? TimeInterval {
            clockInDate = Date(timeIntervalSince1970: interval)
        } else {
            clockInDate = nil
        }
        if let raw = context["recentSessions"] as? [[String: Any]] {
            recentSessions = raw.compactMap { entry in
                guard
                    let date = entry["date"] as? TimeInterval,
                    let clockIn = entry["clockIn"] as? TimeInterval,
                    let clockOut = entry["clockOut"] as? TimeInterval,
                    let totalHours = entry["totalHours"] as? Double
                else { return nil }
                return WatchSessionSummary(
                    date: Date(timeIntervalSince1970: date),
                    clockIn: Date(timeIntervalSince1970: clockIn),
                    clockOut: Date(timeIntervalSince1970: clockOut),
                    totalHours: totalHours
                )
            }
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let context = session.receivedApplicationContext as [String: Any]?, !context.isEmpty {
            Task { @MainActor in
                self.applyContext(context)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.applyContext(applicationContext)
        }
    }
}
