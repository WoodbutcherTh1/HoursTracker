import SwiftUI

/// Which screen of the sign-up / sign-in flow is showing. Kept as one sheet
/// with an internal step, rather than a `NavigationStack` push per step, so
/// the whole flow can Cancel from a single toolbar button at any point.
private enum AccountFlowStep: Equatable {
    case welcome
    case signUp
    case verify(email: String, fullName: String, familyName: String)
    case signIn
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
                    Button(L10n.editCancel) { dismiss() }
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
        switch step {
        case .welcome:
            AccountWelcomeView(
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
            SignInFormView(viewModel: viewModel)
        }
    }
}

private struct AccountWelcomeView: View {
    @ObservedObject private var theme = HomeAccentTheme.shared
    let onCreateAccount: () -> Void
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [theme.accent, theme.accent.darkened(by: 0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 76, height: 76)
                    .shadow(color: theme.accent.opacity(0.35), radius: 16, y: 6)

                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 8) {
                Text(L10n.accountSignedOutTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text(L10n.accountSignedOutHint)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer(minLength: 12)

            VStack(spacing: 12) {
                Button(action: onCreateAccount) {
                    Text(L10n.accountCreateButton)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .foregroundStyle(.black)

                Button(action: onSignIn) {
                    Text(L10n.accountAlreadyHaveAccount)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        Form {
            Section {
                TextField(L10n.accountNamePlaceholder, text: $fullName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .listRowBackground(HomeNeon.card)

                TextField(L10n.accountFamilyNamePlaceholder, text: $familyName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .listRowBackground(HomeNeon.card)
            }

            Section {
                TextField(L10n.accountEmailPlaceholder, text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .listRowBackground(HomeNeon.card)

                SecureField(L10n.accountPasswordPlaceholder, text: $password)
                    .textContentType(.newPassword)
                    .listRowBackground(HomeNeon.card)
            } footer: {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                } else {
                    Text(L10n.accountPasswordHint)
                }
            }

            Section {
                Button {
                    sendCode()
                } label: {
                    HStack {
                        if isSending {
                            ProgressView().tint(.black)
                        }
                        Text(L10n.accountSendCodeButton)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .foregroundStyle(.black)
                .disabled(!isFormValid || isSending)
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(L10n.accountSignUpTitle)
        .navigationBarTitleDisplayMode(.inline)
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

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Image(systemName: "envelope.badge.shield.half.filled")
                        .font(.system(size: 32))
                        .foregroundStyle(theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)
                    Text(L10n.accountVerifyHint(email))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
            }

            Section {
                TextField(L10n.accountCodePlaceholder, text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .listRowBackground(HomeNeon.card)
                    .onChange(of: code) { _, newValue in
                        code = String(newValue.filter(\.isNumber).prefix(6))
                    }
            } footer: {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else if let resendMessage {
                    Text(resendMessage).foregroundStyle(.green)
                }
            }

            Section {
                Button {
                    verify()
                } label: {
                    HStack {
                        if isVerifying {
                            ProgressView().tint(.black)
                        } else if isVerified {
                            Image(systemName: "checkmark")
                        }
                        Text(isVerified ? L10n.accountVerifiedBadge : L10n.accountVerifyButton)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(isVerified ? .green : theme.accent)
                .foregroundStyle(isVerified ? .white : .black)
                .disabled(code.count != 6 || isVerifying || isVerified)
                .listRowBackground(Color.clear)

                Button(L10n.accountResendCode) {
                    resend()
                }
                .font(.footnote)
                .disabled(isVerifying)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(L10n.accountVerifyTitle)
        .navigationBarTitleDisplayMode(.inline)
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
                }
            }
        }
    }

    private func resend() {
        errorMessage = nil
        Task {
            do {
                try await SupabaseAuthManager.shared.resendSignUpCode(email: email)
                await MainActor.run { resendMessage = L10n.accountResendSent }
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

    @State private var email = ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField(L10n.accountEmailPlaceholder, text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .listRowBackground(HomeNeon.card)

                SecureField(L10n.accountPasswordPlaceholder, text: $password)
                    .textContentType(.password)
                    .listRowBackground(HomeNeon.card)
            } footer: {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    signIn()
                } label: {
                    HStack {
                        if isSigningIn {
                            ProgressView().tint(.black)
                        }
                        Text(L10n.accountSignInButton)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .foregroundStyle(.black)
                .disabled(!SupabaseAuthManager.isValidEmail(email) || password.isEmpty || isSigningIn)
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(L10n.accountSignInTitle)
        .navigationBarTitleDisplayMode(.inline)
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

// MARK: - Signed in

private struct AccountSignedInView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var auth = SupabaseAuthManager.shared
    @ObservedObject private var theme = HomeAccentTheme.shared
    @State private var isSyncing = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(theme.accent.opacity(0.18))
                            .frame(width: 44, height: 44)
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(theme.accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.accountSignedInAs(auth.currentEmail ?? ""))
                            .font(.subheadline.weight(.semibold))
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(HomeNeon.card)
            }

            Section {
                Button {
                    syncNow()
                } label: {
                    HStack {
                        if isSyncing {
                            ProgressView()
                            Text(L10n.accountSyncing)
                        } else {
                            Label(L10n.accountSyncNow, systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                }
                .disabled(isSyncing)

                Button(role: .destructive) {
                    Task { try? await SupabaseAuthManager.shared.signOut() }
                } label: {
                    Label(L10n.accountSignOut, systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .scrollContentBackground(.hidden)
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
