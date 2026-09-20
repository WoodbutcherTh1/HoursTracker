import SwiftUI

/// Dynamic Type–safe fixed-size font. The app's display numerals (live timer,
/// stat cards, preview values) use exact point sizes for pixel-tuned layout,
/// but plain `.system(size:)` ignores the user's text size entirely. Wrapping
/// the size in `@ScaledMetric(relativeTo:)` keeps the exact default size while
/// scaling with the Dynamic Type setting — the accessibility fix with zero
/// visual change at default text sizes.
///
/// Compiled into both the app and the Watch target (see project.yml).
private struct HTScaledFont: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, relativeTo style: Font.TextStyle, weight: Font.Weight, design: Font.Design) {
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: scaledSize, weight: weight, design: design))
    }
}

extension View {
    /// Fixed default size, Dynamic Type–scaled. Numerals should pair with
    /// `.monospacedDigit()`.
    func htFont(
        size: CGFloat,
        relativeTo style: Font.TextStyle,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(HTScaledFont(size: size, relativeTo: style, weight: weight, design: design))
    }
}

/// What a state says, decided in one pure place so tests can pin the copy
/// contract (including the localized retry fallback) without fighting SwiftUI's
/// rendering internals. `HTStateView` renders exactly from this.
struct HTStateCopy: Equatable {
    /// SF Symbol shown above the title (never announced — decoration only).
    let symbol: String
    let title: String
    let hint: String?
    let actionTitle: String?
    let retryTitle: String?

    static func make(from kind: HTStateView.Kind) -> HTStateCopy {
        switch kind {
        case .loading(let label):
            return HTStateCopy(symbol: "", title: label, hint: nil, actionTitle: nil, retryTitle: nil)
        case .empty(let icon, let title, let hint, let actionTitle, _):
            return HTStateCopy(symbol: icon, title: title, hint: hint, actionTitle: actionTitle, retryTitle: nil)
        case .error(let message, let retryTitle, let retry):
            // A retry affordance without a closure is meaningless — the fallback
            // localized title only appears when there is something to retry.
            return HTStateCopy(
                symbol: "exclamationmark.triangle",
                title: message,
                hint: nil,
                actionTitle: nil,
                retryTitle: retry == nil ? nil : (retryTitle ?? AppLocale.tr("common.retry"))
            )
        }
    }
}

/// The app's one loading / empty / error state component (P0 roadmap item).
/// Every async surface shows all three with the same layout language so state
/// never reads as a bare spinner or an unexplained blank.
///
/// Compiled into both targets: the Watch's plain-caption empty/error states
/// ("No shifts", "No data in this range") migrate onto this, matching the
/// phone's established History/Payslip empty-state pattern. All copy comes
/// from the caller (localized); the retry fallback label resolves through
/// `AppLocale` like every other string.
struct HTStateView: View {
    enum Kind {
        /// Indeterminate work with a localized explanation of *what* is loading.
        case loading(label: String)
        /// Nothing to show yet. `action` is the way out (e.g. "Show all", "Sync").
        case empty(
            icon: String,
            title: String,
            hint: String? = nil,
            actionTitle: String? = nil,
            action: (() -> Void)? = nil
        )
        /// Something failed. `retry` re-triggers the failed operation inline.
        case error(message: String, retryTitle: String? = nil, retry: (() -> Void)? = nil)
    }

    let kind: Kind

    private var copy: HTStateCopy { HTStateCopy.make(from: kind) }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var retryInProgress = false

    var body: some View {
        VStack(spacing: 10) {
            switch kind {
            case .loading:
                ProgressView()
                stateText
                    // One element for VoiceOver: "Loading — analyzing timesheet".
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(copy.title)

            case .empty(let icon, _, let hint, let actionTitle, let action):
                Image(systemName: icon)
                    .htFont(size: 24, relativeTo: .title2)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
                stateText
                if let hint, !hint.isEmpty {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 2)
                }

            case .error(_, let retryTitle, let retry):
                Image(systemName: copy.symbol)
                    .htFont(size: 20, relativeTo: .title3)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                stateText
                if let retry, !retryInProgress {
                    Button {
                        retryInProgress = true
                        retry()
                        // Re-enable after a beat so a failing retry doesn't
                        // leave the affordance permanently hidden.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            retryInProgress = false
                        }
                    } label: {
                        Label(retryTitle ?? copy.retryTitle ?? AppLocale.tr("common.retry"), systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: retryInProgress)
    }

    private var stateText: some View {
        Text(copy.title)
            .font(kind.isTitleProminent ? .subheadline.weight(.semibold) : .footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}

private extension HTStateView.Kind {
    /// Empty states lead with a semibold title; loading/error carry a footnote.
    var isTitleProminent: Bool {
        if case .empty = self { return true }
        return false
    }
}
