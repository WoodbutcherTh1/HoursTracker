import Foundation
import WatchConnectivity

/// Phone-side half of the Apple Watch companion app. Two jobs: relay a clock-in/out
/// action tapped on the watch into the same `AppViewModel.clockIn()/clockOut()` path
/// the phone UI uses (no parallel state-mutation route), and push status + recent
/// history back to the watch via `updateApplicationContext` so it can show something
/// useful even when it hasn't been reachable for a live round trip.
///
/// NOT verified against a real build — written and reasoned through without Xcode or
/// a watchOS simulator available in this environment. Treat as a first draft to
/// compile and test on a real Mac, not as validated working code.
final class WatchConnectivityBridge: NSObject {
    private weak var viewModel: AppViewModel?

    /// How many recent completed sessions to send — `updateApplicationContext` has no
    /// hard documented byte cap but is meant for small state, not the full history.
    private static let maxHistoryRows = 20

    func attach(to viewModel: AppViewModel) {
        self.viewModel = viewModel
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Call after every clock-in/out, and after any edit/delete/import that could change
    /// history, so the watch's cached status and history stay current even when it isn't
    /// reachable right now — `updateApplicationContext` delivers the latest value next
    /// time it wakes, superseding any earlier undelivered context.
    func refresh(sessions: [WorkSession], settings: WorkplaceSettings) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }

        let activeSession = sessions.filter(\.isOpen).max { $0.clockIn < $1.clockIn }
        let recent = sessions
            .filter { $0.clockOut != nil }
            .sorted { $0.clockIn > $1.clockIn }
            .prefix(Self.maxHistoryRows)
            .map { session -> [String: Any] in
                let breakdown = OvertimeCalculator.breakdown(for: session, in: sessions, settings: settings)
                return [
                    "date": session.date.timeIntervalSince1970,
                    "clockIn": session.clockIn.timeIntervalSince1970,
                    "clockOut": (session.clockOut ?? session.clockIn).timeIntervalSince1970,
                    "totalHours": breakdown.totalHours
                ]
            }

        var context: [String: Any] = [
            "isClockedIn": activeSession != nil,
            "recentSessions": Array(recent)
        ]
        if let clockIn = activeSession?.clockIn {
            context["clockInDate"] = clockIn.timeIntervalSince1970
        }
        try? WCSession.default.updateApplicationContext(context)
    }
}

extension WatchConnectivityBridge: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, let viewModel = self.viewModel else { return }
            self.refresh(sessions: viewModel.sessions, settings: viewModel.settings)
        }
    }

    /// Live tap from the watch while both sides are reachable.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let action = message["action"] as? String else {
            replyHandler(["ok": false])
            return
        }
        Task { @MainActor [weak self] in
            guard let self, let viewModel = self.viewModel else {
                replyHandler(["ok": false])
                return
            }
            switch action {
            case "clockIn":
                if viewModel.canClockIn { viewModel.clockIn() }
            case "clockOut":
                if viewModel.isClockedIn { viewModel.clockOut() }
            default:
                replyHandler(["ok": false])
                return
            }
            self.refresh(sessions: viewModel.sessions, settings: viewModel.settings)
            replyHandler(["ok": true, "isClockedIn": viewModel.isClockedIn])
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // A new watch was paired — re-activate to start pairing with it.
        session.activate()
    }
}
