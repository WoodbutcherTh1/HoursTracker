import SwiftUI

/// Late clock-in flow: pick arrival time → confirm/edit → open a normal shift.
struct ForgotClockInSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    enum Step {
        case pickArrival
        case confirm
    }

    @State private var step: Step = .pickArrival
    @State private var arrival = ForgotClockInSheet.defaultArrival()

    private var timeFormatter: DateFormatter {
        AppLocale.makeDateFormatter(timeStyle: .short)
    }

    private var arrivalRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return start...Date()
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .pickArrival:
                    pickArrivalContent
                case .confirm:
                    confirmContent
                }
            }
            .background(HomeNeon.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.editCancel) { dismiss() }
                }
            }
            .toolbarBackground(HomeNeon.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private var pickArrivalContent: some View {
        VStack(spacing: 28) {
            Text(L10n.homeForgotClockInArrivalPrompt)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 28)

            DatePicker(
                "",
                selection: $arrival,
                in: arrivalRange,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .colorScheme(.dark)
            .environment(\.locale, AppLocale.resolvedLocale)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)

            Button {
                arrival = min(max(arrival, arrivalRange.lowerBound), arrivalRange.upperBound)
                step = .confirm
            } label: {
                Text(L10n.settingsArrivalContinue)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(HomeNeon.accent)
            .padding(.horizontal, 24)

            Spacer(minLength: 12)
        }
        .navigationTitle(L10n.homeForgotClockIn)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var confirmContent: some View {
        VStack(spacing: 24) {
            Text(L10n.homeForgotClockInConfirmTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.top, 28)

            Text(L10n.homeForgotClockInConfirmMessage(timeFormatter.string(from: arrival)))
                .font(.body)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Text(timeFormatter.string(from: arrival))
                .font(.system(size: 44, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(HomeNeon.accent)

            VStack(spacing: 12) {
                Button {
                    if viewModel.clockIn(at: arrival, isManual: true) {
                        dismiss()
                    }
                } label: {
                    Text(L10n.homeForgotClockInConfirm)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(HomeNeon.accent)

                Button {
                    step = .pickArrival
                } label: {
                    Text(L10n.editTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.85))
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 12)
        }
        .navigationTitle(L10n.homeForgotClockInConfirmTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Default suggested arrival: 08:00 today, or “now” if before 08:00.
    /// TODO(expectedShiftStart): Same temporary 08:00 default as
    /// `AppViewModel.shouldOfferForgotClockIn` — replace with settings
    /// `expectedShiftStart` when that optional field is added.
    static func defaultArrival(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: now)
        let eight = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: start) ?? start
        return min(max(eight, start), now)
    }
}
