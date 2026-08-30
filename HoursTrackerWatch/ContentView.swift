import SwiftUI

/// Minimal watch UI: current status plus one big clock in/out button. English-only for
/// now (the watch target has no string catalog of its own yet) — the phone app's
/// ar/he/en localization does not carry over automatically to a separate target.
///
/// NOT verified against a real build — written and reasoned through without Xcode or
/// a watchOS simulator available in this environment.
struct ContentView: View {
    @ObservedObject var connectivity: WatchConnectivityManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Text(connectivity.isClockedIn ? "Clocked In" : "Clocked Out")
                    .font(.headline)
                    .foregroundStyle(connectivity.isClockedIn ? .green : .secondary)

                if connectivity.isClockedIn, let clockInDate = connectivity.clockInDate {
                    Text(clockInDate, style: .timer)
                        .font(.system(.title2, design: .rounded).monospacedDigit())
                }

                Button {
                    connectivity.toggleClock()
                } label: {
                    Text(connectivity.isClockedIn ? "Clock Out" : "Clock In")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .tint(connectivity.isClockedIn ? .red : .green)
                .disabled(connectivity.isSending)

                if let message = connectivity.lastErrorMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                NavigationLink {
                    HistoryView(sessions: connectivity.recentSessions)
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                        .font(.footnote)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}
