import SwiftUI

/// The assistant's empty state: greeting, what it can be asked, and what leaves the
/// phone. Split out from the chat sheet because the User Guide shows this exact view —
/// the guide teaches the real screen, never a drawing of it.
///
/// The suggestion chips do double duty. They save typing, and by showing the shape of an
/// answerable question they head off out-of-scope ones before they are asked.
struct AssistantWelcomeView: View {
    var accent: Color = HomeNeon.accent
    /// From `WorkplaceSettings.workerFullName` — the name already entered in Settings,
    /// not a new field. Blank means a plain greeting with no name in it.
    var workerName: String?
    var isInteractive: Bool = true
    var onSelect: (String) -> Void = { _ in }

    /// Computed, not a stored `static let`: a cached array would freeze these in
    /// whatever language was active the first time the assistant was opened, and the app
    /// lets you switch language without relaunching.
    static var suggestions: [String] {
        [
            L10n.assistantSuggestionOvertime,
            L10n.assistantSuggestionPayThisMonth,
            L10n.assistantSuggestionDaysOff,
            L10n.assistantSuggestionReport,
            L10n.assistantSuggestionPayslip
        ]
    }

    var body: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(accent.opacity(0.14))
                .frame(width: 64, height: 64)
                .overlay(Circle().stroke(accent.opacity(0.5), lineWidth: 1.5))
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(accent)
                )

            VStack(spacing: 6) {
                Text(greeting)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(L10n.assistantWelcomeSubtitle)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    suggestionChip(suggestion)
                }
            }

            Label(L10n.assistantPrivacyNote, systemImage: "lock.fill")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }

    private var greeting: String {
        guard let first = DaypartGreeting.firstName(from: workerName) else {
            return L10n.assistantWelcome
        }
        // Isolate so a Latin first name doesn't scramble the RTL sentence around it.
        return L10n.assistantWelcomeNamed("\u{2068}\(first)\u{2069}")
    }

    private func suggestionChip(_ text: String) -> some View {
        Button {
            onSelect(text)
        } label: {
            HStack(spacing: 8) {
                Text(text)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(accent.opacity(0.8))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(HomeNeon.card)
                    .overlay(Capsule(style: .continuous).stroke(accent.opacity(0.22), lineWidth: 1))
            )
        }
        .buttonStyle(ScalePressButtonStyle())
        .disabled(!isInteractive)
    }
}
