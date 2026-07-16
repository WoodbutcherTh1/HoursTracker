import SwiftUI

/// Centered desktop-style conflict dialog for import overwrites.
struct ImportConflictPopup: View {
    let dates: [Date]
    let currentDate: Date
    let onReplace: () -> Void
    let onApplyAll: () -> Void
    let onKeep: () -> Void

    private var dateFormatter: DateFormatter {
        AppLocale.makeDateFormatter(template: "dd/MM/yy")
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { /* block background taps */ }

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)

                Text(L10n.scannerConflictTitle)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text(L10n.scannerConflictMessage(dateFormatter.string(from: currentDate)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Small date box listing all conflicting shifts
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.scannerConflictDatesHeader)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(dates, id: \.self) { day in
                                HStack(spacing: 8) {
                                    Image(systemName: calendar.isDate(day, inSameDayAs: currentDate)
                                          ? "arrow.right.circle.fill"
                                          : "calendar")
                                        .font(.caption)
                                        .foregroundStyle(
                                            calendar.isDate(day, inSameDayAs: currentDate)
                                            ? Color.accentColor
                                            : Color.secondary
                                        )
                                    Text(dateFormatter.string(from: day))
                                        .font(.subheadline.monospacedDigit().weight(
                                            calendar.isDate(day, inSameDayAs: currentDate) ? .semibold : .regular
                                        ))
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: min(CGFloat(dates.count) * 28, 140))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(spacing: 10) {
                    Button(action: onReplace) {
                        Text(L10n.scannerConflictReplace)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)

                    if dates.count > 1 {
                        Button(action: onApplyAll) {
                            Text(L10n.scannerConflictApplyAll)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(role: .cancel, action: onKeep) {
                        Text(L10n.scannerConflictKeep)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: 340)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
            .padding(.horizontal, 28)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var calendar: Calendar { .current }
}
