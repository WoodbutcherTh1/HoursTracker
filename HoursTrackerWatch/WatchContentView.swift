import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var store: WatchSessionStore
    @State private var isSending = false

    private var snapshot: WatchSnapshot { store.snapshot }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if !snapshot.workplaceName.isEmpty {
                    Text(snapshot.workplaceName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Button(action: toggleClock) {
                    VStack(spacing: 4) {
                        Image(systemName: snapshot.isClockedIn ? "stop.fill" : "play.fill")
                            .font(.system(size: 26))
                        Text(snapshot.isClockedIn ? "Clock Out" : "Clock In")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(snapshot.isClockedIn ? .red : .green)
                .disabled(isSending)

                if snapshot.isClockedIn, let clockInTime = snapshot.clockInTime {
                    Text(clockInTime, style: .timer)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }

                Divider()

                HStack {
                    statColumn(title: "Today", hours: snapshot.todayHours, pay: snapshot.todayNetPay)
                    statColumn(title: "This week", hours: snapshot.weekHours, pay: snapshot.weekNetPay)
                }

                if let error = store.lastErrorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                if snapshot.generatedAt == .distantPast {
                    Text("Open HoursTracker on your iPhone once to sync.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
    }

    private func statColumn(title: String, hours: Double, pay: Double) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(formattedHours(hours))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(formattedPay(pay))
                .font(.caption2)
                .foregroundStyle(.green)
        }
        .frame(maxWidth: .infinity)
    }

    private func toggleClock() {
        isSending = true
        store.requestClockAction(snapshot.isClockedIn ? .clockOut : .clockIn)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { isSending = false }
    }

    private func formattedHours(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return String(format: "%d:%02d", h, m)
    }

    private func formattedPay(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = snapshot.currencyCode.isEmpty ? "ILS" : snapshot.currencyCode
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.0f", amount)
    }
}
