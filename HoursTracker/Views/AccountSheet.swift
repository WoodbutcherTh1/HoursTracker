import AuthenticationServices
import SwiftUI
import PhotosUI

/// Which screen of the sign-up / sign-in flow is showing. Kept as one sheet
/// with an internal step, rather than a `NavigationStack` push per step, so
/// the whole flow can Cancel from a single toolbar button at any point.
private enum AccountFlowStep: Hashable {
    case welcome
    case signUp
    case verify(email: String, fullName: String, familyName: String)
    case signIn
    case forgotPassword
    case resetPassword(email: String)
}

/// Entry point from Settings' Account section. Shows the sign-up/sign-in
/// flow when signed out, or account status + sync controls when signed in.
struct AccountSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var auth = SupabaseAuthManager.shared
    @ObservedObject private var theme = HomeAccentTheme.shared
    @ObservedObject private var appBackground = AppBackgroundTheme.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if auth.isSignedIn {
                    AccountSignedInView(viewModel: viewModel)
                } else {
                    AccountFlowView(viewModel: viewModel)
                }
            }
            .background(appBackground.background.ignoresSafeArea())
            .navigationTitle(L10n.accountWelcomeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.onbBack) { dismiss() }
                        .tint(.white.opacity(0.8))
                }
            }
            .toolbarBackground(appBackground.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .tint(theme.accent)
    }
}

// MARK: - Signed-out flow

private struct AccountFlowView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var step: AccountFlowStep = .welcome

    var body: some View {
        ZStack {
            stepView
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.88), value: step)
    }

    @ViewBuilder
    private var stepView: some View {
        switch step {
        case .welcome:
            AccountWelcomeView(
                viewModel: viewModel,
                onCreateAccount: { step = .signUp },
                onSignIn: { step = .signIn }
            )
        case .signUp:
            SignUpFormView { email, fullName, familyName in
                step = .verify(email: email, fullName: fullName, familyName: familyName)
            }
        case .verify(let email, let fullName, let familyName):
            VerifyCodeView(
                viewModel: viewModel,
                email: email,
                fullName: fullName,
                familyName: familyName
            )
        case .signIn:
            SignInFormView(viewModel: viewModel, onForgotPassword: { step = .forgotPassword })
        case .forgotPassword:
            ForgotPasswordFormView(
                onCodeSent: { email in step = .resetPassword(email: email) },
                onBack: { step = .signIn }
            )
        case .resetPassword(let email):
            ResetPasswordView(email: email)
        }
    }
}

// MARK: - Shared premium components

/// A dark, rounded, icon-led field with a floating label: the placeholder sits
/// inside the empty field and glides up into a small caption above the text
/// once the field is focused or filled, so it never disappears while typing.
/// Focus is shown by an accent border and a soft glow that stays in place
/// (no lift or jump).
private struct AccountTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var autocapitalization: TextInputAutocapitalization = .sentences

    @FocusState private var isFocused: Bool
    @ObservedObject private var theme = HomeAccentTheme.shared
    @State private var isSecureVisible = false

    private var isFloating: Bool { isFocused || !text.isEmpty }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .htFont(size: 16, relativeTo: .body, weight: .medium)
                .foregroundStyle(isFocused ? theme.accent : .white.opacity(0.35))
                .frame(width: 20)

            ZStack(alignment: .leading) {
                Text(placeholder)
                    .font(isFloating ? .caption2.weight(.semibold) : .body)
                    .foregroundStyle(isFocused ? theme.accent.opacity(0.9) : .white.opacity(isFloating ? 0.45 : 0.32))
                    .offset(y: isFloating ? -12 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                Group {
                    if isSecure && !isSecureVisible {
                        SecureField("", text: $text)
                    } else {
                        TextField("", text: $text)
                    }
                }
                .focused($isFocused)
                .foregroundStyle(.white)
                .tint(theme.accent)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .offset(y: isFloating ? 7 : 0)
                .accessibilityLabel(placeholder)
            }
            .frame(height: 28)

            if isSecure {
                Button {
                    isSecureVisible.toggle()
                } label: {
                    Image(systemName: isSecureVisible ? "eye.slash" : "eye")
                        .htFont(size: 14, relativeTo: .footnote)
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isFocused ? theme.accent : Color.white.opacity(0.08), lineWidth: isFocused ? 1.5 : 1)
        )
        .shadow(color: isFocused ? theme.accent.opacity(0.16) : .clear, radius: 8)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isFloating)
        .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}

/// Eight separate digit boxes for the emailed code. A single hidden field
/// receives the input (so paste and the keyboard's one-time-code suggestion
/// still work); the boxes only draw it. The next empty box is highlighted, each
/// digit pops in, and a wrong code shakes the row.
private struct OneTimeCodeField: View {
    @Binding var code: String
    var length: Int = 8
    /// Bump to shake (after a rejected code).
    var shakeTrigger: Int = 0
    var autoFocus: Bool = true

    @FocusState private var isFocused: Bool
    @ObservedObject private var theme = HomeAccentTheme.shared

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(width: 1, height: 1)
                .opacity(0.02)
                .accessibilityLabel(L10n.accountCodePlaceholder)
                .onChange(of: code) { _, newValue in
                    let digits = String(newValue.filter(\.isNumber).prefix(length))
                    if digits != newValue { code = digits }
                }

            HStack(spacing: 6) {
                ForEach(0..<length, id: \.self) { index in
                    box(at: index)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }
            .modifier(ShakeEffect(animatableData: CGFloat(shakeTrigger)))
            .animation(.linear(duration: 0.35), value: shakeTrigger)
            .accessibilityHidden(true)
        }
        // Codes read left-to-right in Hebrew and Arabic too.
        .environment(\.layoutDirection, .leftToRight)
        .onAppear {
            if autoFocus { isFocused = true }
        }
    }

    private func box(at index: Int) -> some View {
        let characters = Array(code)
        let digit = index < characters.count ? String(characters[index]) : ""
        let isCurrent = isFocused && index == min(characters.count, length - 1)
            && (characters.count < length || index == length - 1)
        let isFilled = !digit.isEmpty
        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.12))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isCurrent ? theme.accent : (isFilled ? theme.accent.opacity(0.45) : Color.white.opacity(0.1)),
                    lineWidth: isCurrent ? 1.6 : 1
                )
            if isFilled {
                Text(verbatim: digit)
                    .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            } else if isCurrent {
                BlinkingCaret(color: theme.accent)
            }
        }
        .frame(maxWidth: 44)
        .frame(height: 52)
        .shadow(color: isCurrent ? theme.accent.opacity(0.25) : .clear, radius: 8)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: digit)
        .animation(.easeOut(duration: 0.15), value: isCurrent)
    }
}

private struct BlinkingCaret: View {
    let color: Color
    @State private var visible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(color)
            .frame(width: 2, height: 22)
            .opacity(visible ? 1 : 0.1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

/// Horizontal shake used when a code is rejected.
private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}

/// "Didn't get it? Check spam" — held back until the email has had time to
/// arrive, and only while nothing has been typed, so it helps the people who
/// are actually waiting instead of cluttering the screen for everyone.
/// Restarts its wait after a resend.
private struct DelayedSpamHint: View {
    let isWaiting: Bool
    var restartToken: Int = 0
    static let delay: Duration = .seconds(8)

    @State private var isShown = false

    var body: some View {
        // A VStack (not a Group) so the view — and its timer task — exists even
        // while the hint is hidden.
        VStack(spacing: 0) {
            if isShown && isWaiting {
                Label(L10n.accountCheckSpamHint, systemImage: "tray.full")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.35), value: isShown && isWaiting)
        .task(id: restartToken) {
            isShown = false
            try? await Task.sleep(for: Self.delay)
            isShown = true
        }
    }
}

/// Solid accent fill with real depth (shadow that compresses on press) —
/// the "this is the one action to take" button.
private struct PremiumPrimaryButtonStyle: ButtonStyle {
    var accent: Color
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accent.opacity(isDisabled ? 0.35 : 1))
            )
            .shadow(
                color: isDisabled ? .clear : accent.opacity(configuration.isPressed ? 0.2 : 0.4),
                radius: configuration.isPressed ? 6 : 14,
                y: configuration.isPressed ? 2 : 7
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Fixed Cyan→Green gradient — the brief calls for this one specific button
/// (Account's "Sync Now"), distinct from the personalized-accent style above.
private struct CyanGreenGradientButtonStyle: ButtonStyle {
    var isDisabled: Bool = false
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .subheadline.weight(.bold) : .headline)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 11 : 16)
            .background(
                RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "00E5FF"), Color(hex: "26F273")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .opacity(isDisabled ? 0.35 : 1)
                    )
            )
            .shadow(
                color: isDisabled ? .clear : Color(hex: "26F273").opacity(configuration.isPressed ? 0.2 : 0.4),
                radius: configuration.isPressed ? 6 : 14,
                y: configuration.isPressed ? 2 : 7
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Transparent, quiet — for the one secondary action next to a primary CTA.
private struct PremiumSecondaryButtonStyle: ButtonStyle {
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 11 : 14)
            .background(
                RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.1 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// A glowing icon badge — the pulsing halo the app already uses behind the
/// Home clock button, reused here so the "keep your data safe" moment reads
/// as premium rather than a plain SF Symbol in a circle.
private struct GlowIconBadge: View {
    let systemName: String
    var accent: Color = HomeNeon.accent
    var size: CGFloat = 76
    /// The animated pulse rings read great on the Home clock button and the
    /// welcome screen, but busy on dense form screens — callers opt out there.
    var pulse: Bool = true

    var body: some View {
        ZStack {
            if pulse {
                HomePulseRings(color: accent, size: size - 10)
            }

            Circle()
                .fill(
                    LinearGradient(
                        colors: [accent, accent.darkened(by: 0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: accent.opacity(pulse ? 0.45 : 0.25), radius: pulse ? 20 : 10, y: 4)

            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Welcome

/// Premium dark welcome screen: a glowing Cyan/Green hourglass header, three
/// stacked social sign-in options, and a quiet "already have an account?"
/// footer. Google signs in through Supabase's hosted OAuth page; Apple uses
/// the native `ASAuthorizationController` flow — both call into
/// `SupabaseAuthManager`. Apple's capability/entitlement isn't enabled yet
/// (needs a paid Apple Developer account, see docs/SOCIAL_SIGN_IN.md), so
/// tapping it compiles and runs but currently fails at the OS layer. Email
/// routes into the existing, fully-functional Supabase email flow below.
private struct AccountWelcomeView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    let onCreateAccount: () -> Void
    let onSignIn: () -> Void

    @State private var isSigningInWithApple = false
    @State private var isSigningInWithGoogle = false
    @State private var errorMessage: String?
    /// Kept alive for the duration of one Apple request — `ASAuthorizationController`
    /// needs its delegate to outlive the async call it's bridging into a continuation.
    @State private var appleCoordinator: AppleSignInCoordinator?

    private static let cyan = Color(hex: "00E5FF")
    private static let green = Color(hex: "26F273")

    var body: some View {
        VStack(spacing: 32) {
            Spacer(minLength: 12)

            VStack(spacing: 18) {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 40, height: 1)

                Image(systemName: "hourglass")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Self.cyan, Self.green],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Self.cyan.opacity(0.5), radius: 18)
                    .shadow(color: Self.green.opacity(0.35), radius: 12)
                    .accessibilityHidden(true)

                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 40, height: 1)
            }

            Text(L10n.accountWelcomeHeroTitle)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer(minLength: 12)

            VStack(spacing: 16) {
                Button {
                    signInWithApple()
                } label: {
                    HStack(spacing: 10) {
                        if isSigningInWithApple {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "apple.logo")
                        }
                        Text(L10n.accountContinueWithApple)
                    }
                }
                .buttonStyle(SocialLoginButtonStyle(
                    fill: Color.white.opacity(0.1),
                    border: Color.white.opacity(0.3),
                    foreground: .white
                ))
                .disabled(isSigningInWithApple || isSigningInWithGoogle)

                Button {
                    signInWithGoogle()
                } label: {
                    HStack(spacing: 10) {
                        if isSigningInWithGoogle {
                            ProgressView().tint(.white)
                        } else {
                            // Placeholder until a real Google "G" asset is added —
                            // no bundled brand mark exists in this project yet.
                            Image(systemName: "g.circle")
                        }
                        Text(L10n.accountContinueWithGoogle)
                    }
                }
                .buttonStyle(SocialLoginButtonStyle(
                    fill: Color(white: 0.15),
                    border: .clear,
                    foreground: .white
                ))
                .disabled(isSigningInWithGoogle || isSigningInWithApple)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: onCreateAccount) {
                    HStack(spacing: 10) {
                        Image(systemName: "envelope.fill")
                        Text(L10n.accountContinueWithEmail)
                    }
                }
                .buttonStyle(SocialLoginButtonStyle(
                    fill: .clear,
                    border: Color.cyan,
                    borderWidth: 2,
                    foreground: .cyan
                ))
            }
            .padding(.horizontal, 24)

            Button(action: onSignIn) {
                (
                    Text(L10n.accountAlreadyHaveAccountQuestion + " ")
                        .foregroundStyle(.white.opacity(0.5))
                    + Text(L10n.accountLogInAction)
                        .foregroundStyle(.white.opacity(0.85))
                        .fontWeight(.bold)
                )
                .font(.subheadline)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Requires the Sign in with Apple capability + entitlement, which in turn
    // requires a paid Apple Developer Program membership — not added yet (see
    // docs/SOCIAL_SIGN_IN.md). This compiles and is harmless on a free team;
    // it will throw an ASAuthorizationError at runtime until that capability
    // is enabled on the App ID.
    private func signInWithApple() {
        errorMessage = nil
        isSigningInWithApple = true
        let nonce = AppleSignInNonce.make()
        let coordinator = AppleSignInCoordinator()
        appleCoordinator = coordinator
        Task {
            do {
                let authorization = try await coordinator.perform(rawNonce: nonce)
                guard
                    let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                    let tokenData = credential.identityToken,
                    let idToken = String(data: tokenData, encoding: .utf8)
                else {
                    throw AccountAuthError.server(L10n.accountErrorSocial)
                }
                // Unlike fullName/email, Apple issues a fresh authorizationCode on
                // EVERY sign-in, not just the first — so this keeps the stored
                // refresh token current even if a user signs out and back in later.
                let authorizationCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
                try await SupabaseAuthManager.shared.signInWithApple(
                    idToken: idToken,
                    rawNonce: nonce,
                    fullName: credential.fullName,
                    authorizationCode: authorizationCode
                )
                let restored = await SocialSignInFinisher.finish(viewModel: viewModel)
                await MainActor.run {
                    isSigningInWithApple = false
                    appleCoordinator = nil
                    viewModel.showSuccessToast(restored ? L10n.accountRestoreSuccess : L10n.accountSyncSuccess)
                    dismiss()
                }
            } catch let error as ASAuthorizationError where error.code == .canceled {
                await MainActor.run {
                    isSigningInWithApple = false
                    appleCoordinator = nil
                }
            } catch {
                await MainActor.run {
                    isSigningInWithApple = false
                    appleCoordinator = nil
                    errorMessage = error.localizedDescription.isEmpty ? L10n.accountErrorSocial : error.localizedDescription
                }
            }
        }
    }

    private func signInWithGoogle() {
        errorMessage = nil
        isSigningInWithGoogle = true
        Task {
            do {
                try await SupabaseAuthManager.shared.signInWithGoogle()
                let restored = await SocialSignInFinisher.finish(viewModel: viewModel)
                await MainActor.run {
                    isSigningInWithGoogle = false
                    viewModel.showSuccessToast(restored ? L10n.accountRestoreSuccess : L10n.accountSyncSuccess)
                    dismiss()
                }
            } catch AccountAuthError.cancelled {
                await MainActor.run { isSigningInWithGoogle = false }
            } catch {
                await MainActor.run {
                    isSigningInWithGoogle = false
                    errorMessage = error.localizedDescription.isEmpty ? L10n.accountErrorSocial : error.localizedDescription
                }
            }
        }
    }
}

/// What a social sign-in does once a session exists: bring the account's
/// saved backup into this device (merged, so nothing here is lost), or — when
/// the account has no backup yet, i.e. it was just created through Google or
/// Apple — upload this device's data so the new account starts with it.
/// Mirrors the restore/upload steps `SignInFormView`/`VerifyCodeView` run
/// inline, but unlike those two a social tap can't tell in advance whether
/// it's a first-time signup or a returning sign-in.
@MainActor
private enum SocialSignInFinisher {
    /// `true` when an existing backup was restored, `false` for a fresh upload.
    static func finish(viewModel: AppViewModel) async -> Bool {
        if let backup = try? await SupabaseAccountSyncManager.shared.downloadBackup() {
            let document = FullDataExportDocument(
                exportedAt: ISO8601DateFormatter().string(from: Date()),
                appVersion: FullDataExportManager.appVersionString(),
                settings: backup.settings,
                sessions: backup.sessions,
                computedBreakdowns: [],
                activityLog: []
            )
            try? viewModel.importFullDataExport(document, mode: .merge)
            return true
        }
        let names = SupabaseAuthManager.shared.currentUserNames
        try? await SupabaseAccountSyncManager.shared.uploadBackup(
            settings: viewModel.settings,
            sessions: viewModel.sessions,
            fullName: names.fullName,
            familyName: names.familyName
        )
        return false
    }
}

/// Bridges the delegate-based `ASAuthorizationController` into async/await so
/// a plain custom-styled `Button` can trigger native Apple sign-in — SwiftUI's
/// own `SignInWithAppleButton` only offers Apple's fixed black/white/outline
/// look, which doesn't match this screen's custom button style.
private final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorization, Error>?

    func perform(rawNonce: String) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = AppleSignInNonce.sha256(rawNonce)
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        continuation?.resume(returning: authorization)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

/// Stacked social sign-in button: 55pt tall, fully rounded, with a
/// configurable fill/border/foreground per provider.
private struct SocialLoginButtonStyle: ButtonStyle {
    var fill: Color
    var border: Color
    var borderWidth: CGFloat = 1
    var foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 55)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(border, lineWidth: borderWidth)
            )
            .shadow(color: border == Color.cyan ? Color.cyan.opacity(0.25) : .clear, radius: 10)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Sign up

private struct SignUpFormView: View {
    @ObservedObject private var theme = HomeAccentTheme.shared
    let onCodeSent: (_ email: String, _ fullName: String, _ familyName: String) -> Void

    @State private var fullName = ""
    @State private var familyName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private var isFormValid: Bool {
        !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && SupabaseAuthManager.isValidEmail(email)
            && password.count >= 6
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text(L10n.accountSignUpTitle)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 12)

                VStack(spacing: 12) {
                    AccountTextField(
                        icon: "person.fill",
                        placeholder: L10n.accountNamePlaceholder,
                        text: $fullName,
                        autocapitalization: .words
                    )
                    AccountTextField(
                        icon: "person.2.fill",
                        placeholder: L10n.accountFamilyNamePlaceholder,
                        text: $familyName,
                        autocapitalization: .words
                    )
                    AccountTextField(
                        icon: "envelope.fill",
                        placeholder: L10n.accountEmailPlaceholder,
                        text: $email,
                        keyboardType: .emailAddress,
                        textContentType: .username,
                        autocapitalization: .never
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        AccountTextField(
                            icon: "lock.fill",
                            placeholder: L10n.accountPasswordPlaceholder,
                            text: $password,
                            isSecure: true,
                            textContentType: .newPassword,
                            autocapitalization: .never
                        )
                        Text(errorMessage ?? L10n.accountPasswordHint)
                            .font(.caption)
                            .foregroundStyle(errorMessage != nil ? .red : .white.opacity(0.4))
                            .padding(.horizontal, 4)
                    }
                }

                Button {
                    sendCode()
                } label: {
                    HStack(spacing: 8) {
                        if isSending {
                            ProgressView().tint(.black)
                        }
                        Text(L10n.accountSendCodeButton)
                    }
                }
                .buttonStyle(PremiumPrimaryButtonStyle(accent: theme.accent, isDisabled: !isFormValid || isSending))
                .disabled(!isFormValid || isSending)
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func sendCode() {
        errorMessage = nil
        isSending = true
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFamily = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                try await SupabaseAuthManager.shared.beginSignUp(
                    fullName: trimmedName,
                    familyName: trimmedFamily,
                    email: trimmedEmail,
                    password: password
                )
                await MainActor.run {
                    isSending = false
                    onCodeSent(trimmedEmail, trimmedName, trimmedFamily)
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Verify code

private struct VerifyCodeView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var theme = HomeAccentTheme.shared
    @Environment(\.dismiss) private var dismiss
    let email: String
    let fullName: String
    let familyName: String

    @State private var code = ""
    @State private var isVerifying = false
    @State private var isVerified = false
    @State private var errorMessage: String?
    @State private var resendMessage: String?
    @State private var resendCount = 0
    @State private var rejectedCount = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    GlowIconBadge(systemName: "envelope.badge.shield.half.filled", accent: theme.accent, size: 52, pulse: false)
                    Text(L10n.accountVerifyHint(email))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    // The code can land in spam, especially the first time.
                    DelayedSpamHint(isWaiting: code.isEmpty, restartToken: resendCount)
                }
                .padding(.top, 12)

                VStack(spacing: 8) {
                    OneTimeCodeField(code: $code, shakeTrigger: rejectedCount)

                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    } else if let resendMessage {
                        Text(resendMessage).font(.caption).foregroundStyle(.green)
                    }
                }
                .padding(.horizontal, 20)

                VStack(spacing: 12) {
                    Button {
                        verify()
                    } label: {
                        HStack(spacing: 8) {
                            if isVerifying {
                                ProgressView().tint(.black)
                            } else if isVerified {
                                Image(systemName: "checkmark")
                            }
                            Text(isVerified ? L10n.accountVerifiedBadge : L10n.accountVerifyButton)
                        }
                    }
                    .buttonStyle(PremiumPrimaryButtonStyle(
                        accent: isVerified ? .green : theme.accent,
                        isDisabled: code.count != 8 || isVerifying || isVerified
                    ))
                    .disabled(code.count != 8 || isVerifying || isVerified)

                    Button(L10n.accountResendCode) {
                        resend()
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .disabled(isVerifying)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func verify() {
        errorMessage = nil
        isVerifying = true
        Task {
            do {
                try await SupabaseAuthManager.shared.verifySignUp(email: email, code: code)
                // Newly created account: push whatever is already on this
                // device up to Supabase so nothing already tracked is lost.
                try? await SupabaseAccountSyncManager.shared.uploadBackup(
                    settings: viewModel.settings,
                    sessions: viewModel.sessions,
                    fullName: fullName,
                    familyName: familyName
                )
                await MainActor.run {
                    isVerifying = false
                    isVerified = true
                    viewModel.showSuccessToast(L10n.accountSyncSuccess)
                }
                try? await Task.sleep(for: .seconds(0.6))
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    isVerifying = false
                    errorMessage = error.localizedDescription
                    // Whatever was just rejected can never become valid by
                    // resubmitting it — clearing it stops a stale code from
                    // silently being retried after a resend.
                    code = ""
                    rejectedCount += 1
                }
            }
        }
    }

    private func resend() {
        errorMessage = nil
        resendMessage = nil
        Task {
            do {
                try await SupabaseAuthManager.shared.resendSignUpCode(email: email)
                await MainActor.run {
                    resendMessage = L10n.accountResendSent
                    resendCount += 1
                    // The old code is now invalid the moment a new one is
                    // issued — force fresh entry instead of leaving the
                    // stale value sitting there to be resubmitted by mistake.
                    code = ""
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
}

// MARK: - Sign in

private struct SignInFormView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var theme = HomeAccentTheme.shared
    @Environment(\.dismiss) private var dismiss
    let onForgotPassword: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                GlowIconBadge(systemName: "arrow.right.circle.fill", accent: theme.accent, size: 60)
                    .padding(.top, 8)

                Text(L10n.accountSignInTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)

                VStack(spacing: 12) {
                    AccountTextField(
                        icon: "envelope.fill",
                        placeholder: L10n.accountEmailPlaceholder,
                        text: $email,
                        keyboardType: .emailAddress,
                        textContentType: .username,
                        autocapitalization: .never
                    )
                    AccountTextField(
                        icon: "lock.fill",
                        placeholder: L10n.accountPasswordPlaceholder,
                        text: $password,
                        isSecure: true,
                        textContentType: .password,
                        autocapitalization: .never
                    )
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }

                    Button(L10n.accountForgotPassword, action: onForgotPassword)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 20)

                Button {
                    signIn()
                } label: {
                    HStack(spacing: 8) {
                        if isSigningIn {
                            ProgressView().tint(.black)
                        }
                        Text(L10n.accountSignInButton)
                    }
                }
                .buttonStyle(PremiumPrimaryButtonStyle(
                    accent: theme.accent,
                    isDisabled: !SupabaseAuthManager.isValidEmail(email) || password.isEmpty || isSigningIn
                ))
                .disabled(!SupabaseAuthManager.isValidEmail(email) || password.isEmpty || isSigningIn)
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func signIn() {
        errorMessage = nil
        isSigningIn = true
        Task {
            do {
                try await SupabaseAuthManager.shared.signIn(email: email, password: password)
                // Restore whatever this account already has saved — merged
                // into local data so nothing on this device is lost either.
                if let backup = try? await SupabaseAccountSyncManager.shared.downloadBackup() {
                    let document = FullDataExportDocument(
                        exportedAt: ISO8601DateFormatter().string(from: Date()),
                        appVersion: FullDataExportManager.appVersionString(),
                        settings: backup.settings,
                        sessions: backup.sessions,
                        computedBreakdowns: [],
                        activityLog: []
                    )
                    try? viewModel.importFullDataExport(document, mode: .merge)
                }
                await MainActor.run {
                    isSigningIn = false
                    viewModel.showSuccessToast(L10n.accountRestoreSuccess)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSigningIn = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Forgot password

private struct ForgotPasswordFormView: View {
    @ObservedObject private var theme = HomeAccentTheme.shared
    let onCodeSent: (_ email: String) -> Void
    let onBack: () -> Void

    @State private var email = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                GlowIconBadge(systemName: "key.fill", accent: theme.accent, size: 60)
                    .padding(.top, 8)

                VStack(spacing: 6) {
                    Text(L10n.accountResetTitle)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text(L10n.accountResetHint)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                VStack(spacing: 12) {
                    AccountTextField(
                        icon: "envelope.fill",
                        placeholder: L10n.accountEmailPlaceholder,
                        text: $email,
                        keyboardType: .emailAddress,
                        textContentType: .username,
                        autocapitalization: .never
                    )
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 20)

                VStack(spacing: 12) {
                    Button {
                        sendCode()
                    } label: {
                        HStack(spacing: 8) {
                            if isSending {
                                ProgressView().tint(.black)
                            }
                            Text(L10n.accountSendCodeButton)
                        }
                    }
                    .buttonStyle(PremiumPrimaryButtonStyle(
                        accent: theme.accent,
                        isDisabled: !SupabaseAuthManager.isValidEmail(email) || isSending
                    ))
                    .disabled(!SupabaseAuthManager.isValidEmail(email) || isSending)

                    Button(L10n.accountBackToSignIn, action: onBack)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func sendCode() {
        errorMessage = nil
        isSending = true
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                try await SupabaseAuthManager.shared.beginPasswordReset(email: trimmedEmail)
                await MainActor.run {
                    isSending = false
                    onCodeSent(trimmedEmail)
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Reset password (verify code + set new password)

private struct ResetPasswordView: View {
    @ObservedObject private var theme = HomeAccentTheme.shared
    @Environment(\.dismiss) private var dismiss
    let email: String

    @State private var code = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSubmitting = false
    @State private var isDone = false
    @State private var errorMessage: String?
    @State private var resendMessage: String?
    @State private var resendCount = 0
    @State private var rejectedCount = 0

    private var isFormValid: Bool {
        code.count == 8 && newPassword.count >= 6 && newPassword == confirmPassword
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    GlowIconBadge(systemName: "envelope.badge.shield.half.filled", accent: theme.accent, size: 52, pulse: false)
                    Text(L10n.accountVerifyHint(email))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    // The code can land in spam, especially the first time.
                    DelayedSpamHint(isWaiting: code.isEmpty, restartToken: resendCount)
                }
                .padding(.top, 12)

                VStack(spacing: 12) {
                    OneTimeCodeField(code: $code, shakeTrigger: rejectedCount)
                        .padding(.bottom, 4)

                    AccountTextField(
                        icon: "lock.fill",
                        placeholder: L10n.accountNewPassword,
                        text: $newPassword,
                        isSecure: true,
                        textContentType: .newPassword,
                        autocapitalization: .never
                    )
                    AccountTextField(
                        icon: "lock.rotation",
                        placeholder: L10n.accountConfirmPassword,
                        text: $confirmPassword,
                        isSecure: true,
                        textContentType: .newPassword,
                        autocapitalization: .never
                    )

                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    } else if let resendMessage {
                        Text(resendMessage).font(.caption).foregroundStyle(.green)
                    } else {
                        Text(L10n.accountPasswordRule)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .padding(.horizontal, 20)

                VStack(spacing: 12) {
                    Button {
                        submit()
                    } label: {
                        HStack(spacing: 8) {
                            if isSubmitting {
                                ProgressView().tint(.black)
                            } else if isDone {
                                Image(systemName: "checkmark")
                            }
                            Text(isDone ? L10n.accountVerifiedBadge : L10n.accountResetSubmitButton)
                        }
                    }
                    .buttonStyle(PremiumPrimaryButtonStyle(
                        accent: isDone ? .green : theme.accent,
                        isDisabled: !isFormValid || isSubmitting || isDone
                    ))
                    .disabled(!isFormValid || isSubmitting || isDone)

                    Button(L10n.accountResendCode) {
                        resend()
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .disabled(isSubmitting)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func submit() {
        errorMessage = nil
        isSubmitting = true
        Task {
            do {
                try await SupabaseAuthManager.shared.verifyPasswordReset(email: email, code: code)
                try await SupabaseAuthManager.shared.updatePassword(newPassword)
                await MainActor.run {
                    isSubmitting = false
                    isDone = true
                }
                try? await Task.sleep(for: .seconds(0.6))
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.localizedDescription
                    // Whatever was just rejected can never become valid by
                    // resubmitting it — clearing it stops a stale code from
                    // silently being retried after a resend.
                    code = ""
                    rejectedCount += 1
                }
            }
        }
    }

    private func resend() {
        errorMessage = nil
        resendMessage = nil
        Task {
            do {
                try await SupabaseAuthManager.shared.beginPasswordReset(email: email)
                await MainActor.run {
                    resendMessage = L10n.accountResendSent
                    resendCount += 1
                    code = ""
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
}

// MARK: - Signed in (account details)

/// A quiet rounded card grouping the account screen's sections — same visual
/// language as the app's dark fields, without the glow-heavy floating look.
private struct AccountCard<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content

    /// Fixed Neon Cyan, matching the Settings tab's card styling — not the
    /// personalized accent, so every account card reads consistently even if
    /// the user picked a different theme color. Computed, not `static let`:
    /// stored static properties aren't allowed in a generic type.
    private static var cyan: Color { Color(hex: "00E5FF") }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 4)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(hex: "0D0D0D"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Self.cyan.opacity(0.3), lineWidth: 1)
        )
    }
}

/// A static "label + value" row inside an account card.
private struct AccountSignedInView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var auth = SupabaseAuthManager.shared
    @ObservedObject private var theme = HomeAccentTheme.shared
    @ObservedObject private var profile = AccountProfileStore.shared
    @State private var isSyncing = false
    @State private var errorMessage: String?
    @State private var profileName = ""
    @State private var memberSince: Date?
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var showPhotoPicker = false
    @State private var showRemovePhotoConfirm = false
    // Change-password fields.
    @State private var newPassword = ""
    @State private var confirmNewPassword = ""
    @State private var isChangingPassword = false
    @State private var passwordMessage: String?
    @State private var passwordMessageIsError = false

    private var displayName: String {
        let name = profileName.isEmpty ? viewModel.settings.workerFullName : profileName
        if !name.isEmpty { return name }
        // Fall back to the email's local part ("hmam.kaadna@x.com" → "hmam.kaadna").
        return auth.currentEmail?.split(separator: "@").first.map(String.init) ?? ""
    }

    private var initials: String {
        AccountProfileStore.initials(for: displayName)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                compactHeaderCard
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                passwordCard
                    .padding(.horizontal, 20)

                AccountCard(title: L10n.accountBackupSection) {
                    Text(L10n.accountSyncHint)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))

                    // Side by side, not stacked — the two actions here don't need
                    // a full-width row each.
                    HStack(spacing: 8) {
                        Button {
                            syncNow()
                        } label: {
                            HStack(spacing: 6) {
                                if isSyncing {
                                    ProgressView().tint(.black)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
                                Text(isSyncing ? L10n.accountSyncing : L10n.accountSyncNow)
                            }
                        }
                        .buttonStyle(CyanGreenGradientButtonStyle(isDisabled: isSyncing, compact: true))
                        .disabled(isSyncing)

                        Button {
                            Task { try? await SupabaseAuthManager.shared.signOut() }
                        } label: {
                            // Dark gray fill, not a red-tinted one — red is reserved for the
                            // text/icon only, so this stays quiet next to the Cyan→Green
                            // "Sync Now" button rather than competing with it.
                            Label(L10n.accountSignOut, systemImage: "rectangle.portrait.and.arrow.right")
                                .font(.subheadline.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.white.opacity(0.06))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

                // App Store 5.1.1(v): an account created in the app can be deleted in it.
                // Isolated in its own red-tinted card, away from the ordinary cards
                // above, so a careless tap while scrolling can't land on it.
                HStack(spacing: 10) {
                    Text(L10n.settingsDangerZone.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.red.opacity(0.85))
                        .tracking(0.4)
                        .fixedSize()

                    Button(role: .destructive) {
                        showDeleteAccountConfirm = true
                    } label: {
                        HStack(spacing: 6) {
                            if isDeletingAccount {
                                ProgressView()
                            } else {
                                Image(systemName: "person.crop.circle.badge.xmark")
                            }
                            Text(L10n.accountDelete)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .disabled(isDeletingAccount)
                    .accessibilityIdentifier("account.delete")
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.red.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .alert(L10n.accountDeleteConfirmTitle, isPresented: $showDeleteAccountConfirm) {
            Button(L10n.accountDelete, role: .destructive) { deleteAccount() }
            Button(L10n.editCancel, role: .cancel) {}
        } message: {
            Text(L10n.accountDeleteConfirmMessage)
        }
        .task {
            if let user = auth.client.auth.currentUser {
                memberSince = user.createdAt
            }
            if let fetched = await SupabaseAccountSyncManager.shared.fetchProfile(),
               !fetched.fullName.isEmpty {
                profileName = fetched.fullName
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: Binding(get: { nil }, set: { selection in
            guard let selection else { return }
            loadPickedPhoto(selection)
        }), matching: .images)
        .confirmationDialog(
            L10n.accountAvatarRemove,
            isPresented: $showRemovePhotoConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.accountAvatarRemove, role: .destructive) { profile.delete() }
            Button(L10n.editCancel, role: .cancel) {}
        }
    }

    // MARK: Compact header — avatar + identity + Member Since, one card

    /// Everything that used to be a tall, centered avatar block *plus* a
    /// separate "Profile Info" card below it, merged into one compact,
    /// horizontal header: avatar on the side (not centered above), identity
    /// stacked beside it, Member Since as a single trailing line underneath.
    private var compactHeaderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                avatarButton

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let email = auth.currentEmail {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Text(verbatim: LocalPlaceholderUserID.current())
                            .font(.caption2.monospaced().weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                        Button {
                            UIPasteboard.general.string = LocalPlaceholderUserID.current()
                            UISelectionFeedbackGenerator().selectionChanged()
                            viewModel.showSuccessToast(L10n.settingsUserIDCopied)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.settingsCopyUserID)
                    }
                }

                Spacer(minLength: 0)
            }

            if let memberSince {
                Divider().overlay(Color.white.opacity(0.08))
                HStack {
                    Text(L10n.accountMemberSinceLabel)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Text(AppLocale.makeDateFormatter(dateStyle: .medium, timeStyle: .none).string(from: memberSince))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(16)
        .background(Color(hex: "0D0D0D"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Self.cyanGlow.opacity(0.3), lineWidth: 1)
        )
        // `.compositingGroup()` forces the card (background + stroke + avatar's own
        // shadow) to flatten into a single layer before the `.clipShape` below runs —
        // without it, a child's `.shadow()` can still render outside an ancestor's
        // `.clipShape` in SwiftUI, because the shadow is otherwise composited as its
        // own separate pass rather than being part of what gets clipped.
        .compositingGroup()
        // Hard-clips the whole card to its own rounded shape — the avatar's stroke/shadow
        // sat right at the card's top-trailing corner (first in the HStack, which RTL
        // mirrors to the right) and could visually poke past the rounded corner's curve
        // even with correct padding. Clipping the card itself, not just the avatar,
        // guarantees nothing inside it can ever escape the card's bounds.
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var avatarButton: some View {
        Button {
            if profile.avatarImage != nil {
                showRemovePhotoConfirm = true
            } else {
                showPhotoPicker = true
            }
        } label: {
            Group {
                if let image = profile.avatarImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [theme.accent, theme.accent.darkened(by: 0.55)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text(initials)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(width: 60, height: 60)
            // Clip to a circle BEFORE the stroke/shadow — the shadow is then
            // computed from the already-circular shape, so its halo reads as a
            // clean ring instead of a square-ish blur. The header card's own
            // `.clipShape` (below) is the actual guarantee against this glow
            // bleeding past the card's edge.
            .clipShape(Circle())
            .overlay(
                Circle().stroke(Self.cyanGlow.opacity(0.6), lineWidth: 1.5)
            )
            .shadow(color: Self.cyanGlow.opacity(0.35), radius: 5)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: profile.avatarImage == nil ? "plus.circle.fill" : "photo.circle.fill")
                    .font(.system(size: 17))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.accent, .black)
                    .offset(x: 3, y: 3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(L10n.accountAvatarChange))
    }

    /// Fixed Neon Cyan glow — the avatar ring stays on-brand regardless of the
    /// user's personalized accent, matching the Settings profile card.
    private static let cyanGlow = Color(hex: "00E5FF")

    // MARK: Change password

    private var passwordCard: some View {
        AccountCard(title: L10n.accountSecuritySection) {
            VStack(spacing: 8) {
                AccountTextField(
                    icon: "lock.fill",
                    placeholder: L10n.accountNewPassword,
                    text: $newPassword,
                    isSecure: true,
                    textContentType: .newPassword,
                    autocapitalization: .never
                )
                AccountTextField(
                    icon: "lock.rotation",
                    placeholder: L10n.accountConfirmPassword,
                    text: $confirmNewPassword,
                    isSecure: true,
                    textContentType: .newPassword,
                    autocapitalization: .never
                )
                Text(passwordMessage ?? L10n.accountPasswordRule)
                    .font(.caption)
                    .foregroundStyle(passwordMessageIsError ? .red : .white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    changePassword()
                } label: {
                    HStack(spacing: 8) {
                        if isChangingPassword {
                            ProgressView().tint(.cyan)
                        }
                        Text(L10n.accountChangePassword)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.cyan)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func changePassword() {
        guard newPassword == confirmNewPassword else {
            passwordMessage = L10n.accountPasswordMismatch
            passwordMessageIsError = true
            return
        }
        passwordMessage = nil
        passwordMessageIsError = false
        isChangingPassword = true
        Task {
            do {
                try await SupabaseAuthManager.shared.updatePassword(newPassword)
                await MainActor.run {
                    isChangingPassword = false
                    newPassword = ""
                    confirmNewPassword = ""
                    passwordMessage = L10n.accountPasswordChanged
                    passwordMessageIsError = false
                    viewModel.showSuccessToast(L10n.accountPasswordChanged)
                }
            } catch {
                await MainActor.run {
                    isChangingPassword = false
                    passwordMessage = error.localizedDescription
                    passwordMessageIsError = true
                }
            }
        }
    }

    // MARK: Actions

    private func loadPickedPhoto(_ selection: PhotosPickerItem) {
        Task {
            guard let data = try? await selection.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            profile.save(image)
        }
    }

    private func deleteAccount() {
        errorMessage = nil
        isDeletingAccount = true
        Task {
            do {
                try await SupabaseAuthManager.shared.deleteAccount()
                AppViewModel.shared.showSuccessToast(L10n.accountDeleted)
            } catch {
                errorMessage = error.localizedDescription
            }
            isDeletingAccount = false
        }
    }

    private func syncNow() {
        errorMessage = nil
        isSyncing = true
        Task {
            do {
                try await SupabaseAccountSyncManager.shared.uploadBackup(
                    settings: viewModel.settings,
                    sessions: viewModel.sessions,
                    fullName: viewModel.settings.workerFullName,
                    familyName: nil
                )
                await MainActor.run {
                    isSyncing = false
                    viewModel.showSuccessToast(L10n.accountSyncSuccess)
                }
            } catch {
                await MainActor.run {
                    isSyncing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
