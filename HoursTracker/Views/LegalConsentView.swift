import SwiftUI

/// Full-screen agreement to the Terms of Use and the Privacy Policy. Shown to new
/// and existing users until `LegalConsent.currentVersion` is accepted; the app
/// can't be used behind it. Consent is an explicit, unticked checkbox plus a
/// button — never pre-checked.
struct LegalConsentView: View {
    @ObservedObject var consent: LegalConsent
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var appBackground = AppBackgroundTheme.shared

    @State private var agreed = false
    @State private var showDeclined = false
    @State private var showExport = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(HomeNeon.accent)
                        .accessibilityHidden(true)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)

                    Text(AppLocale.tr(consent.isReconsent ? "legal.gate.titleUpdated" : "legal.gate.title"))
                        .font(.title2.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)

                    Text(AppLocale.tr("legal.gate.body"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 12) {
                        point("banknote", AppLocale.tr("legal.gate.point.estimates"))
                        point("iphone", AppLocale.tr("legal.gate.point.data"))
                        point("square.and.arrow.up.on.square", AppLocale.tr("legal.gate.point.control"))
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(spacing: 0) {
                        NavigationLink {
                            TermsOfUseView()
                        } label: {
                            linkRow(AppLocale.tr("terms.title"), icon: "doc.text")
                        }
                        .accessibilityIdentifier("legal.readTerms")
                        Divider().padding(.leading, 44)
                        NavigationLink {
                            PrivacyPolicyView()
                        } label: {
                            linkRow(L10n.privacyTitle, icon: "hand.raised.fill")
                        }
                        .accessibilityIdentifier("legal.readPrivacy")
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button {
                        agreed.toggle()
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: agreed ? "checkmark.square.fill" : "square")
                                .font(.title3)
                                .foregroundStyle(agreed ? HomeNeon.accent : .secondary)
                            Text(AppLocale.tr("legal.gate.checkbox"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(agreed ? .isSelected : [])
                    .accessibilityIdentifier("legal.checkbox")
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        consent.accept()
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        Text(AppLocale.tr("legal.gate.accept"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HomeNeon.accent)
                    .foregroundStyle(.black)
                    .disabled(!agreed)
                    .accessibilityIdentifier("legal.accept")

                    Button(AppLocale.tr("legal.gate.decline")) {
                        showDeclined = true
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("legal.decline")
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(appBackground.background.opacity(0.96))
            }
            .background(appBackground.background.ignoresSafeArea())
            .alert(AppLocale.tr("legal.gate.declineTitle"), isPresented: $showDeclined) {
                Button(AppLocale.tr("legal.gate.readAgain"), role: .cancel) {}
                Button(L10n.fullExportTitle) { showExport = true }
            } message: {
                Text(AppLocale.tr("legal.gate.declineMessage"))
            }
            .sheet(isPresented: $showExport) {
                FullDataExportSheet(viewModel: viewModel)
            }
        }
        .interactiveDismissDisabled()
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(HomeNeon.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func linkRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(HomeNeon.accent)
                .frame(width: 24)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
