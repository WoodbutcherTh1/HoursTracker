import Foundation
import WatchConnectivity
import Combine

/// Watch-side counterpart to the phone's `WatchConnectivityManager`. Holds the
/// latest `WatchSnapshot` (cached to disk so the UI has something to show the
/// instant the app launches, before any fresh context arrives), and sends every
/// user action — clock in/out, History paging, Settings toggles, export requests —
/// to the phone as a `WatchRequest`. The Watch has no business logic of its own: it
/// only asks the phone to act and displays whatever snapshot comes back.
///
/// Not `@MainActor` itself — `WCSessionDelegate` callbacks land on an arbitrary
/// background queue; every `@Published` mutation hops to the main actor explicitly.
final class WatchSessionStore: NSObject, ObservableObject {
    static let shared = WatchSessionStore()

    @Published private(set) var snapshot: WatchSnapshot = .empty
    @Published private(set) var isReachable = false
    @Published var lastErrorMessage: String?
    /// Set briefly after a successful export request so the Export tab can show a
    /// confirmation before the message fades.
    @Published var lastExportConfirmation: String?

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

    func clockIn() {
        send(WatchRequest(kind: .clockIn))
    }

    func clockOut() {
        send(WatchRequest(kind: .clockOut))
    }

    /// Moves the History tab's displayed payroll period by `delta` periods (±1).
    func shiftHistoryPeriod(by delta: Int) {
        send(WatchRequest(kind: .shiftHistoryPeriod, intValue: delta))
    }

    func toggleAppLock(_ enabled: Bool) {
        send(WatchRequest(kind: .toggleAppLock, boolValue: enabled))
    }

    func toggleHideWidgetPay(_ enabled: Bool) {
        send(WatchRequest(kind: .toggleHideWidgetPay, boolValue: enabled))
    }

    func toggleCloudSync(_ enabled: Bool) {
        send(WatchRequest(kind: .toggleCloudSync, boolValue: enabled))
    }

    func setLanguage(_ raw: String) {
        send(WatchRequest(kind: .setLanguage, stringValue: raw))
    }

    func refresh() {
        send(WatchRequest(kind: .requestFullSnapshot))
    }

    /// `rangeKey` is "thisMonth" or "thisYear" — see `WatchExportView`.
    func requestExport(rangeKey: String) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.isReachable else {
            lastErrorMessage = "Open HoursTracker on your iPhone nearby to export."
            return
        }
        let request = WatchRequest(kind: .requestExport, stringValue: rangeKey)
        session.sendMessage(
            request.asMessage(),
            replyHandler: { [weak self] reply in
                guard let ack = WatchAck.from(message: reply) else { return }
                Task { @MainActor in
                    if ack.success {
                        self?.lastErrorMessage = nil
                        self?.lastExportConfirmation = "Sent to iPhone — open HoursTracker to share it."
                    } else {
                        self?.lastErrorMessage = ack.message ?? "Export failed."
                    }
                }
            },
            errorHandler: { [weak self] error in
                Task { @MainActor in self?.lastErrorMessage = error.localizedDescription }
            }
        )
    }

    private func send(_ request: WatchRequest) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.isReachable else {
            lastErrorMessage = "Open HoursTracker on your iPhone nearby to sync."
            return
        }
        session.sendMessage(
            request.asMessage(),
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
