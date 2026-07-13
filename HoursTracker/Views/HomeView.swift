import SwiftUI

struct LiveTimerView: View {
    let startDate: Date
    @State private var now = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(elapsedFormatted)
            .font(.system(size: 56, weight: .light, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .onReceive(timer) { date in
                now = date
            }
    }

    private var elapsedFormatted: String {
        let elapsed = max(0, Int(now.timeIntervalSince(startDate)))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

struct HomeView: View {
    @ObservedObject var viewModel: AppViewModel

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                if let session = viewModel.activeSession {
                    clockedInView(session: session)
                } else if viewModel.canClockInToday {
                    clockedOutView
                } else {
                    dayCompletedView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L10n.homeTitle)
            .sheet(isPresented: $viewModel.showDaySummary) {
                if let breakdown = viewModel.lastCompletedBreakdown {
                    DaySummarySheet(breakdown: breakdown) {
                        viewModel.dismissDaySummary()
                    }
                }
            }
        }
    }

    private var dayCompletedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)

            Text(L10n.homeShiftComplete)
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    private var clockedOutView: some View {
        VStack(spacing: 24) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)

            Text(L10n.homeReadyToStart)
                .font(.title2)
                .foregroundStyle(.secondary)

            Button {
                viewModel.clockIn()
            } label: {
                Label(L10n.homeClockIn, systemImage: "arrow.right.circle.fill")
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)
        }
    }

    private func clockedInView(session: WorkSession) -> some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text(L10n.homeClockedIn)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(L10n.homeSince(timeFormatter.string(from: session.clockIn)))
                    .font(.headline)
            }

            LiveTimerView(startDate: session.clockIn)

            Button(role: .destructive) {
                viewModel.clockOut()
            } label: {
                Label(L10n.homeClockOut, systemImage: "arrow.left.circle.fill")
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .padding(.horizontal, 40)
        }
    }
}

struct DaySummarySheet: View {
    let breakdown: DayPayBreakdown
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)

                Text(L10n.summaryDayComplete)
                    .font(.title2.weight(.semibold))

                VStack(spacing: 12) {
                    summaryRow(L10n.summaryRegular, value: L10n.hoursLong(breakdown.regularHours))
                    summaryRow(L10n.summaryOT125, value: L10n.hoursLong(breakdown.ot125Hours))
                    summaryRow(L10n.summaryOT150, value: L10n.hoursLong(breakdown.ot150Hours))
                    Divider()
                    summaryRow(L10n.summaryTodaysPay, value: breakdown.formattedTotalPay, bold: true)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 32)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.summaryDone, action: onDismiss)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func summaryRow(_ label: String, value: String, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(bold ? .headline : .body)
            Spacer()
            Text(value)
                .font(bold ? .headline : .body)
                .monospacedDigit()
        }
    }
}
