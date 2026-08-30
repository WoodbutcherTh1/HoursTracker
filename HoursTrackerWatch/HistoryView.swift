import SwiftUI

/// Read-only list of recent completed sessions, synced from the phone via
/// `WatchConnectivityManager.recentSessions` (see WatchConnectivityBridge.swift on the
/// phone side). No editing here — the watch has no path to mutate session data other
/// than the clock in/out message handled in ContentView.
///
/// English-only for now (the watch target has no string catalog of its own yet).
struct HistoryView: View {
    let sessions: [WatchSessionSummary]

    var body: some View {
        Group {
            if sessions.isEmpty {
                Text("No sessions yet")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                List(sessions) { session in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.date, style: .date)
                            .font(.headline)
                        HStack {
                            Text(session.clockIn, style: .time)
                            Text("–")
                            Text(session.clockOut, style: .time)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Text(String(format: "%.1f h", session.totalHours))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .navigationTitle("History")
    }
}
