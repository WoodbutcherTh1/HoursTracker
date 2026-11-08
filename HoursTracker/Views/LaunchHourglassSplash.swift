import SwiftUI

/// Launch splash: a continuously spinning, floating, glowing cyan/green
/// hourglass over deep onyx, matching the app's Cyan/Green brand theme.
/// `Color(hex:)` is the app-wide one declared in `HomeAccentTheme.swift` —
/// not redeclared here.
struct LaunchHourglassSplash: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotationDegrees: Double = 0
    @State private var floatOffset: CGFloat = 0
    @State private var isGlowing = false
    @State private var textOpacity: Double = 0

    private static let cyan = Color(hex: "00E5FF")
    private static let green = Color(hex: "26F273")

    var body: some View {
        ZStack {
            Color(red: 13 / 255, green: 13 / 255, blue: 13 / 255)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "hourglass")
                    .font(.system(size: 72, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Self.cyan, Self.green],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Self.cyan.opacity(0.6), radius: isGlowing ? 25 : 15)
                    .shadow(color: Self.green.opacity(0.4), radius: isGlowing ? 20 : 10)
                    .rotation3DEffect(.degrees(rotationDegrees), axis: (x: 0, y: 1, z: 0))
                    .offset(y: floatOffset)
                    .accessibilityHidden(true)

                Text(L10n.brandName)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color.gray.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .opacity(textOpacity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.brandName)
        .onAppear {
            guard !reduceMotion else {
                textOpacity = 1
                return
            }
            // Continuous spin — one full turn every 3s, never reversing.
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                rotationDegrees = 360
            }
            // Floating bob, synchronized to start with the spin (half its
            // period, so the float completes two full up-down cycles per
            // rotation) rather than one `linear`/non-reversing tween driving
            // both — a float needs to ease back down, which `autoreverses:
            // false` on a single shared value can't do without also undoing
            // the spin's continuous direction.
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                floatOffset = -10
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                isGlowing = true
            }
            withAnimation(.easeIn(duration: 0.5).delay(0.5)) {
                textOpacity = 1
            }
        }
        // Lifecycle (2.1s delay) is handled in HoursTrackerApp.swift.
    }
}

#Preview {
    LaunchHourglassSplash()
}
