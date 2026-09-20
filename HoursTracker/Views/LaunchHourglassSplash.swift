import SwiftUI

/// Simple launch splash matching Home neon style.
struct LaunchHourglassSplash: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var theme = HomeAccentTheme.shared
    @ObservedObject private var appBackground = AppBackgroundTheme.shared
    @State private var flipped = false
    @State private var pulse = false
    /// Drives the one-shot scale/fade the content enters with, separate from the
    /// looping `flipped`/`pulse` state below — this only ever animates 0 → 1 once.
    @State private var entered = false

    var body: some View {
        ZStack {
            appBackground.background.ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer(minLength: 0)

                Image(systemName: "hourglass")
                    .font(.system(size: 62, weight: .light))
                    .foregroundStyle(theme.accent)
                    .rotationEffect(.degrees(flipped ? 180 : 0))
                    .scaleEffect(pulse ? 1.04 : 0.98)
                    .shadow(color: theme.accent.opacity(pulse ? 0.5 : 0.22), radius: pulse ? 20 : 8)
                    .accessibilityHidden(true)

                Text(L10n.brandName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))

                Spacer(minLength: 0)
            }
            .scaleEffect(entered ? 1.0 : 0.8)
            .opacity(entered ? 1.0 : 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.brandName)
        .onAppear {
            guard !reduceMotion else {
                entered = true
                pulse = true
                return
            }
            withAnimation(.easeOut(duration: 0.4)) {
                entered = true
            }
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                flipped = true
            }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

#Preview {
    LaunchHourglassSplash()
}
