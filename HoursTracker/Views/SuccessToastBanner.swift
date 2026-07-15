import SwiftUI

/// Short-lived bottom confirmation used for successful user actions.
struct SuccessToastBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.green.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            .accessibilityAddTraits(.isStaticText)
    }
}
