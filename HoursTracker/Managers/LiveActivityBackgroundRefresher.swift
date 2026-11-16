import BackgroundTasks
import Foundation

/// Best-effort mitigation for the Live Activity going stale while the app is fully
/// suspended. `AppViewModel`'s 60s `syncWidget()` loop only runs while this process
/// actually has CPU time (foreground, or the brief grace period right after
/// backgrounding) — once iOS suspends the app, nothing pushes a fresh
/// `ContentState` again until the user reopens it or taps the Live Activity awake.
/// A `BGAppRefreshTask` asks iOS to occasionally wake this process just long enough
/// to push one more update using the exact same `syncWidget()` path already proven
/// correct in the foreground.
///
/// This is NOT a guarantee — iOS decides if and when to actually run it based on
/// battery, Low Power Mode, and the app's own usage pattern, and can go well past
/// an hour without granting one. The guaranteed fix for a shift left open for a
/// long background stretch is server-driven ActivityKit push updates
/// (`Activity.pushTokenUpdates` + APNs `apns-push-type: liveactivity`), which needs
/// new backend infrastructure and is tracked separately. This is the client-only
/// stopgap in the meantime.
enum LiveActivityBackgroundRefresher {
    static let taskIdentifier = "com.hourstracker.app.liveactivity-refresh"

    /// Call once at launch, before `application(_:didFinishLaunchingWithOptions:)`
    /// returns — `BGTaskScheduler` requires registration before the app finishes
    /// launching, every launch, whether or not a refresh is ever scheduled.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            // swiftlint:disable:next force_cast
            handle(task as! BGAppRefreshTask)
        }
    }

    /// Call when backgrounding with a shift open. No-ops with nothing open — there's
    /// nothing to keep fresh, and an app that never schedules unnecessary wake-ups
    /// is exactly what iOS's own throttling heuristics reward with more of them
    /// when it actually does need one.
    static func scheduleIfNeeded(hasOpenSession: Bool) {
        guard hasOpenSession else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        // A floor, not a promise — iOS can (and often does) run this later,
        // sometimes much later, depending on battery and usage heuristics.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        let work = Task { @MainActor in
            let viewModel = AppViewModel.shared
            let hasOpenSession = viewModel.activeSession != nil
            if hasOpenSession {
                viewModel.syncWidget()
            }
            // Only one BGAppRefreshTask fires per submission — resubmit now so the
            // chain continues for as long as the shift stays open.
            scheduleIfNeeded(hasOpenSession: hasOpenSession)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
