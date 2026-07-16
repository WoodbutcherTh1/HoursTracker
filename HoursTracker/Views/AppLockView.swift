import SwiftUI

struct AppLockView: View {
    @ObservedObject var controller: AppLockController
    @State private var isAuthenticating = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text(L10n.appLockTitle)
                    .font(.title2.weight(.semibold))

                Text(L10n.appLockSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if let message = controller.authErrorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button {
                    Task {
                        isAuthenticating = true
                        await controller.unlock()
                        isAuthenticating = false
                    }
                } label: {
                    Label(L10n.appLockUnlock, systemImage: "faceid")
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAuthenticating)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Covers the UI in the app switcher / inactive state so snapshots don't show PII.
struct PrivacyOverlayView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(L10n.appName)
                    .font(.title3.weight(.semibold))
                Text(L10n.privacyOverlayMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
    }
}
