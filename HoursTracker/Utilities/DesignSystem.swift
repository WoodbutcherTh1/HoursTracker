import SwiftUI

/// "Calm Neon" design tokens — the one place colors, type, spacing, radii,
/// elevation and motion are defined (approved design system, Step 2).
///
/// Surfaces stay dark; depth comes from surface lightness + a hairline, not
/// shadows. One static glow per screen, behind the hero element only.
/// Contrast ratios in the comments are WCAG, against `bg.card` (#16191D).
enum DS {
    // MARK: Colors

    enum Palette {
        // Surfaces. `bg.base` is the user's chosen background (AppBackgroundTheme),
        // default #0A0D0F.
        static let card = Color(hex: "16191D")
        static let raised = Color(hex: "1E2227")
        static let hairline = Color.white.opacity(0.08)

        // Text
        static let textPrimary = Color(hex: "F2F4F5")    // 16.0:1
        static let textSecondary = Color(hex: "A3ABB2")  // 7.6:1
        static let textTertiary = Color(hex: "7C858D")   // 4.7:1 — metadata only
        /// Text on an accent-filled button (≥ 5:1 on every accent preset).
        static let ink = Color(hex: "06110B")

        // States (fixed — they carry meaning, never follow the accent)
        static let clockedIn = Color(hex: "FF6B6B")      // 6.4:1
        static let onBreak = Color(hex: "FFB547")        // 10.0:1
        static let overdue = Color(hex: "FF453A")        // 5.2:1
        static let success = Color(hex: "34D399")        // 9.2:1
        static let warning = Color(hex: "FBBF24")        // 10.6:1
        static let info = Color(hex: "60A5FA")           // 6.9:1

        // Pay tiers — warmer = more per hour
        static let ot125 = Color(hex: "F5B942")          // 10.0:1
        static let ot150 = Color(hex: "FF8A4C")          // 7.6:1
    }

    // MARK: Spacing (base 4)

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    // MARK: Corner radius (always .continuous)

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    // MARK: Motion

    enum Motion {
        static let press = Animation.easeOut(duration: 0.15)
        static let state = Animation.spring(response: 0.3, dampingFraction: 0.85)
        static let screen = Animation.spring(response: 0.4, dampingFraction: 0.9)
        /// What every movement collapses to under Reduce Motion.
        static let reduced = Animation.easeInOut(duration: 0.2)

        static func animation(_ base: Animation, reduceMotion: Bool) -> Animation {
            reduceMotion ? reduced : base
        }
    }
}

// MARK: - Typography

/// Type scale. Everything scales with Dynamic Type. Numbers use SF Pro Rounded
/// with monospaced digits and are forced left-to-right so they never reorder or
/// crowd inside Hebrew/Arabic layouts. Floors: 14pt content, 12pt metadata,
/// never below 11pt.
enum DSText {
    case numHero, numLarge
    case titleScreen, titleSection, headline, body, callout, sub, meta

    fileprivate var spec: (size: CGFloat, style: Font.TextStyle, weight: Font.Weight, rounded: Bool) {
        switch self {
        case .numHero: return (48, .largeTitle, .bold, true)
        case .numLarge: return (28, .title, .semibold, true)
        case .titleScreen: return (28, .title, .bold, false)
        case .titleSection: return (20, .title3, .semibold, false)
        case .headline: return (17, .headline, .semibold, false)
        case .body: return (17, .body, .regular, false)
        case .callout: return (16, .callout, .regular, false)
        case .sub: return (14, .subheadline, .regular, false)
        case .meta: return (12, .footnote, .regular, false)
        }
    }

    var isNumber: Bool { spec.rounded }
}

extension View {
    /// Applies a type-scale token. `weight` overrides the token's default weight
    /// (e.g. a Semibold `.sub` label).
    @ViewBuilder
    func dsFont(_ token: DSText, weight: Font.Weight? = nil) -> some View {
        let spec = token.spec
        if token.isNumber {
            self.htFont(size: spec.size, relativeTo: spec.style, weight: weight ?? spec.weight, design: .rounded)
                .monospacedDigit()
                .environment(\.layoutDirection, .leftToRight)
        } else {
            self.htFont(size: spec.size, relativeTo: spec.style, weight: weight ?? spec.weight)
        }
    }

    /// `elev.1`: card surface + hairline.
    func dsCard(radius: CGFloat = DS.Radius.lg, fill: Color = DS.Palette.card) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(DS.Palette.hairline, lineWidth: 1)
                )
        )
    }
}

// MARK: - Components

/// Primary CTA: accent fill, ink text, 56pt capsule. Press = scale 0.97 + the
/// accent glow (`elev.glow`) while held.
struct DSPrimaryButtonStyle: ButtonStyle {
    var accent: Color
    var isEnabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .dsFont(.headline)
            .foregroundStyle(DS.Palette.ink.opacity(isEnabled ? 1 : 0.5))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .background(Capsule(style: .continuous).fill(accent.opacity(isEnabled ? 1 : 0.35)))
            .shadow(color: configuration.isPressed && isEnabled ? accent.opacity(0.25) : .clear, radius: 16)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(DS.Motion.press, value: configuration.isPressed)
    }
}

/// The single static glow of a screen: a soft radial accent wash behind the hero.
struct DSHeroGlow: View {
    var color: Color

    var body: some View {
        RadialGradient(
            colors: [color.opacity(0.10), color.opacity(0)],
            center: .center,
            startRadius: 0,
            endRadius: 160
        )
        .frame(width: 320, height: 320)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
