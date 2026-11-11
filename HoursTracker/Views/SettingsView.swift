import SwiftUI
import UIKit
import CoreLocation
import UniformTypeIdentifiers

/// UI state for the inline "Test Key" check next to each Smart Scanner API key field.
enum KeyCheckUIState: Equatable {
    case idle
    case checking
    case result(APIKeyCheckResult)
}

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var appBackground = AppBackgroundTheme.shared
    @ObservedObject private var homeTheme = HomeAccentTheme.shared
    @ObservedObject private var accountAuth = SupabaseAuthManager.shared
    @ObservedObject private var notificationPrefs = NotificationPreferences.shared
    @EnvironmentObject private var appLock: AppLockController
    @EnvironmentObject private var appLanguage: AppLanguageController

    @State private var draft: WorkplaceSettings
    @State private var saved: SavedSnapshot
    @ObservedObject private var unsavedChanges = SettingsUnsavedChanges.shared
    @State private var showAccountSheet = false
    @State private var showDeleteAllConfirm = false
    @State private var showFullDataExport = false
    @State private var showFullDataImporter = false
    @State private var pendingImportDocument: FullDataExportDocument?
    @State private var showImportConfirm = false
    @State private var importErrorMessage: String?
    @State private var showContactSupport = false
    @State private var showWidgetGuide = false
    @State private var widgetInstallCount: Int?
    @State private var showDisableSyncConfirm = false
    @State private var isEditingIDNumber = false
    @State private var smartScannerCloudEnabled = UserDefaultsSmartScannerCloudPreference.shared.isEnabled
    @State private var geminiAPIKeyDraft = KeychainStore.string(for: .geminiAPIKey) ?? ""
    @State private var secondaryAPIKeyDraft = KeychainStore.string(for: .secondaryAPIKey) ?? ""
    @State private var geminiKeyCheck: KeyCheckUIState = .idle
    @State private var secondaryKeyCheck: KeyCheckUIState = .idle

    private var syncDateFormatter: DateFormatter {
        AppLocale.makeDateFormatter(dateStyle: .short, timeStyle: .short)
    }

    @State private var showAddWorkplace = false
    @State private var newWorkplaceName = ""
    @State private var workplacePendingDelete: AppViewModel.WorkplaceOption?
    /// Bumped on `.onDisappear` to pop the inner NavigationStack back to root —
    /// see where that stack opens for why this is scoped to just the stack.
    @State private var navigationResetID = 0

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        _draft = State(initialValue: viewModel.activeSettings)
        _saved = State(initialValue: SavedSnapshot(settings: viewModel.activeSettings))
    }

    private struct SavedSnapshot: Equatable {
        var settings: WorkplaceSettings
        var scannerCloudEnabled = UserDefaultsSmartScannerCloudPreference.shared.isEnabled
        var geminiKey = KeychainStore.string(for: .geminiAPIKey) ?? ""
        var secondaryKey = KeychainStore.string(for: .secondaryAPIKey) ?? ""
    }

    private var hasUnsavedChanges: Bool {
        draft != saved.settings
            || smartScannerCloudEnabled != saved.scannerCloudEnabled
            || geminiAPIKeyDraft != saved.geminiKey
            || secondaryAPIKeyDraft != saved.secondaryKey
    }

    private func reloadFromStore() {
        let snapshot = SavedSnapshot(settings: viewModel.activeSettings)
        saved = snapshot
        draft = snapshot.settings
        smartScannerCloudEnabled = snapshot.scannerCloudEnabled
        geminiAPIKeyDraft = snapshot.geminiKey
        secondaryAPIKeyDraft = snapshot.secondaryKey
    }

    private func discardChanges() {
        withAnimation(.none) { reloadFromStore() }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label {
            Text(title)
                .dsFont(.sectionHeader)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(homeTheme.accent)
        }
    }

    // MARK: - Navigation Components

    private func groupLink<Destination: View>(
        _ key: String,
        title: String,
        icon: String,
        summary: String,
        tint: Color? = nil,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination() // NO AnyView
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint ?? homeTheme.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier("settings.group.\(key)")
    }

    private func accentLabel(_ title: String, icon: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon).foregroundStyle(homeTheme.accent)
        }
    }

    private func subLink<Destination: View>(
        _ key: String,
        title: String,
        icon: String,
        tint: Color? = nil,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination() // NO AnyView
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon).foregroundStyle(tint ?? homeTheme.accent)
            }
        }
        .accessibilityIdentifier("settings.sub.\(key)")
    }

    private func settingsPage<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Form {
            content()
        }
        // `Form`/`List` apply an implicit insertion animation while diffing their
        // content on first render — on a pushed screen that reads as rows hidden
        // then popping in (e.g. `dataGroupPage`'s `if isAdmin`/`if isCloudSyncSupported`
        // sections). `disablesAnimations` kills that unconditionally so every page
        // built from this helper renders complete on the very first frame.
        .transaction { $0.disablesAnimations = true }
        .listStyle(.insetGrouped)
        .tint(homeTheme.accent)
        .toggleStyle(SwitchToggleStyle(tint: homeTheme.accent))
        .symbolRenderingMode(.monochrome)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .keyboardDismissible()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(appBackground.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { saveButton }
        }
    }

    // MARK: - Pages

    private var workGroupPage: some View {
        settingsPage(L10n.settingsGroupWork) {
            Section {
                subLink("workplace", title: L10n.settingsSubWorkplace, icon: "building.2.fill") {
                    settingsPage(L10n.settingsSubWorkplace) {
                        Section { AnyView(workplacesRows) }
                        Section { AnyView(workerRows) }
                        Section { AnyView(workplaceRows) }
                    }
                }
                subLink("pay", title: L10n.settingsPayHours, icon: "banknote.fill") {
                    settingsPage(L10n.settingsPayHours) { Section { AnyView(payRows) } }
                }
                subLink("rules", title: L10n.settingsWorkRules, icon: "clock.badge.checkmark.fill") {
                    WorkRulesView(draft: $draft)
                }
                subLink("payroll", title: L10n.settingsSubPayrollTax, icon: "calendar.badge.clock") {
                    settingsPage(L10n.settingsSubPayrollTax) {
                        Section { AnyView(payrollRows) }
                        Section { AnyView(taxRows) }
                    }
                }
            } footer: {
                Text(L10n.settingsWorkGroupFooter)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
        }
    }

    private var remindersGroupPage: some View {
        RemindersView(viewModel: viewModel, draft: $draft)
    }

    private var privacyGroupPage: some View {
        settingsPage(L10n.settingsGroupPrivacy) {
            Section {
                subLink("lock", title: L10n.appLockSection, icon: "lock.shield.fill") {
                    settingsPage(L10n.appLockSection) { Section { AnyView(securityRows) } }
                }
                subLink("widgets", title: L10n.settingsHideWidgetPaySection, icon: "square.grid.2x2.fill") {
                    settingsPage(L10n.settingsHideWidgetPaySection) { Section { AnyView(widgetPrivacyRows) } }
                }
                subLink("scanner", title: L10n.scannerSection, icon: "doc.text.viewfinder") {
                    settingsPage(L10n.scannerSection) { Section { AnyView(smartScannerRows) } }
                }
                subLink("safety", title: L10n.dataSafetySection, icon: "externaldrive.badge.checkmark") {
                    settingsPage(L10n.dataSafetySection) { Section { AnyView(dataSafetyRows) } }
                }
            }
        }
    }

    private var dataGroupPage: some View {
        settingsPage(L10n.settingsGroupData) {
            if viewModel.isCloudSyncSupported {
                Section { AnyView(syncRows) }
            }
            if viewModel.isAdmin {
                Section { AnyView(adminRows) }
            }
            Section { AnyView(toolsRows) }
        }
    }

    var body: some View {
        ZStack {
            appBackground.background.ignoresSafeArea()

            // Scoped to just the stack itself — popping a NavigationStack back to
            // root by resetting its `.id()` is a routine, well-understood operation
            // (apps do it constantly). This is deliberately narrower than the removed
            // tab-level `.id(tabResetTokens[.settings])`, which reset SettingsView's
            // entire view (and the UIKit UIHostingController TabView backs it with) —
            // the suspected actual cause of the EXC_BAD_ACCESS this is fixing.
            NavigationStack {
                Form {
                    accountSection
                    Section {
                        groupLink("work", title: L10n.settingsGroupWork, icon: "briefcase.fill", summary: L10n.settingsGroupWorkSummary) { workGroupPage }
                        groupLink("reminders", title: L10n.settingsGroupReminders, icon: "bell.badge.fill", summary: L10n.settingsGroupRemindersSummary) { remindersGroupPage }
                        groupLink("privacy", title: L10n.settingsGroupPrivacy, icon: "lock.shield.fill", summary: L10n.settingsGroupPrivacySummary) { privacyGroupPage }
                        groupLink("data", title: L10n.settingsGroupData, icon: "externaldrive.fill", summary: L10n.settingsGroupDataSummary) { dataGroupPage }
                    }
                    languageSection
                    aboutSection
                    dangerZoneSection
                    shareAppSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .tint(homeTheme.accent)
                .toggleStyle(SwitchToggleStyle(tint: homeTheme.accent))
                .symbolRenderingMode(.monochrome)
                .scrollDismissesKeyboard(.interactively)
                .keyboardDismissible()
                .navigationTitle(L10n.settingsTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(appBackground.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        saveButton
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        AssistantToolbarButton(onOpen: { viewModel.showAssistant = true })
                    }
                }
                .onAppear {
                    if !hasUnsavedChanges {
                        reloadFromStore()
                    }
                    viewModel.refreshLocationPermissionStatuses()
                }
                .onChange(of: viewModel.activeSettings) { _, _ in
                    if !hasUnsavedChanges {
                        reloadFromStore()
                    }
                }
                .onChange(of: viewModel.activeWorkplaceID) { _, _ in
                    reloadFromStore()
                }
                .onChange(of: hasUnsavedChanges, initial: true) { _, dirty in
                    unsavedChanges.update(hasChanges: dirty, save: saveSettings, discard: discardChanges)
                }
                .confirmationDialog(
                    L10n.privacyDeleteAllConfirm,
                    isPresented: $showDeleteAllConfirm,
                    titleVisibility: .visible
                ) {
                    Button(L10n.privacyDeleteAll, role: .destructive) {
                        viewModel.deleteAllUserData()
                        draft = viewModel.activeSettings
                        viewModel.showSuccessToast(L10n.feedbackDataDeleted)
                    }
                    Button(L10n.editCancel, role: .cancel) {}
                }
                .confirmationDialog(
                    L10n.syncDisableConfirm,
                    isPresented: $showDisableSyncConfirm,
                    titleVisibility: .visible
                ) {
                    Button(L10n.syncDisableKeepCloud, role: .destructive) {
                        viewModel.disableICloudSync(deleteRemoteData: false)
                    }
                    Button(L10n.syncDisableDeleteCloud, role: .destructive) {
                        viewModel.disableICloudSync(deleteRemoteData: true)
                    }
                    Button(L10n.editCancel, role: .cancel) {
                        viewModel.isICloudSyncEnabled = true
                    }
                }
                .sheet(isPresented: $showFullDataExport) {
                    FullDataExportSheet(viewModel: viewModel)
                }
                .sheet(isPresented: $showContactSupport) {
                    ContactSupportSheet(viewModel: viewModel)
                }
                .onReceive(NotificationCenter.default.publisher(for: WidgetNudge.openGuide)) { _ in
                    openWidgetGuideFromReminder()
                }
                .onAppear {
                    if WidgetNudge.pendingGuide { openWidgetGuideFromReminder() }
                }
                .sheet(isPresented: $showWidgetGuide) {
                    WidgetInstallGuideView(installedCount: widgetInstallCount)
                }
                .sheet(isPresented: $showAccountSheet) {
                    AccountSheet(viewModel: viewModel)
                }
                .fileImporter(
                    isPresented: $showFullDataImporter,
                    allowedContentTypes: [.json],
                    allowsMultipleSelection: false
                ) { result in
                    handleFullDataImport(result)
                }
                .confirmationDialog(
                    L10n.fullImportConfirmTitle,
                    isPresented: $showImportConfirm,
                    titleVisibility: .visible
                ) {
                    Button(L10n.fullImportReplace, role: .destructive) {
                        applyFullDataImport(mode: .replace)
                    }
                    Button(L10n.fullImportMerge) {
                        applyFullDataImport(mode: .merge)
                    }
                    Button(L10n.editCancel, role: .cancel) {
                        pendingImportDocument = nil
                    }
                } message: {
                    if let doc = pendingImportDocument {
                        Text(L10n.fullImportConfirmMessage(doc.sessions.count, doc.appVersion))
                    } else {
                        Text(L10n.fullImportConfirmFallback)
                    }
                }
                .alert(
                    L10n.errorTitle,
                    isPresented: Binding(
                        get: { importErrorMessage != nil },
                        set: { if !$0 { importErrorMessage = nil } }
                    )
                ) {
                    Button(L10n.errorOK, role: .cancel) { importErrorMessage = nil }
                } message: {
                    Text(importErrorMessage ?? "")
                }
            }
            // Scoped to the stack itself, not the whole view — see the comment above
            // where this NavigationStack opens. Bumping this pops any pushed
            // sub-settings page back to root; it's a routine, well-understood
            // operation for a NavigationStack, unlike destroying SettingsView's
            // entire view (which the removed tab-level `.id()` used to do).
            .id(navigationResetID)
            .onDisappear {
                // "Comes back closed" — same intent as the removed tab-level `.id()`
                // reset in MainTabView.
                //
                // The id bump specifically is deferred one run-loop tick (plain
                // `.async`, no delay): bumping it synchronously here lands in the
                // SAME SwiftUI transaction as TabView's own tab-switch update, and
                // two navigation-identity changes in one transaction is exactly what
                // produced "NavigationRequestObserver tried to update multiple times
                // per frame" and the follow-on freeze. `disablesAnimations` on top of
                // the dispatch: without it, the bump can still inherit whatever
                // animation is active on the tick it lands on and merge back into the
                // TabView's own transition — the same double-update the dispatch
                // alone is trying to avoid. The plain state resets below aren't
                // navigation-identity changes, so they stay synchronous.
                DispatchQueue.main.async {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { navigationResetID += 1 }
                }
                if !hasUnsavedChanges { reloadFromStore() }
                showAccountSheet = false
                showDeleteAllConfirm = false
                showFullDataExport = false
                showFullDataImporter = false
                pendingImportDocument = nil
                showImportConfirm = false
                importErrorMessage = nil
                showContactSupport = false
                showWidgetGuide = false
                showDisableSyncConfirm = false
                isEditingIDNumber = false
                showAddWorkplace = false
                newWorkplaceName = ""
                workplacePendingDelete = nil
            }
        }
    }

    // MARK: - Row Components & Helpers

    private var accountSection: some View {
        Section {
            Button {
                showAccountSheet = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(homeTheme.accent.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: accountAuth.isSignedIn ? "checkmark.seal.fill" : "person.crop.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(homeTheme.accent)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profileDisplayName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(
                            accountAuth.isSignedIn
                                ? L10n.accountSignedInAs(accountAuth.currentEmail ?? "")
                                : L10n.accountSignedOutHint
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(verbatim: LocalPlaceholderUserID.current())
                                .font(.caption2.monospaced().weight(.semibold))
                                .foregroundStyle(.secondary)
                            Button(action: copyPlaceholderUserID) {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.settingsCopyUserID)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.account")
        }
    }

    private var workerRows: some View {
        Group {
            sectionHeader(L10n.settingsWorkerInfo, icon: "person.text.rectangle.fill")
            TextField(L10n.settingsFullName, text: $draft.workerFullName)
                .accessibilityIdentifier("settings.fullName")
            if isEditingIDNumber {
                TextField(L10n.settingsIDNumber, text: $draft.workerIDNumber)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("settings.idNumber")
                if IsraeliIDValidator.shouldWarn(for: draft.workerIDNumber) {
                    Text(L10n.settingsIDChecksumWarning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button(L10n.settingsHideIDNumber) {
                    isEditingIDNumber = false
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.settingsIDNumber)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(AppLockPolicy.maskedNationalID(draft.workerIDNumber))
                            .font(.body.monospacedDigit())
                            .accessibilityLabel(L10n.settingsIDNumberMasked)
                    }
                    Spacer()
                    Button(L10n.settingsEditIDNumber) {
                        isEditingIDNumber = true
                    }
                }
            }
            TextField(L10n.settingsEmployeeNumber, text: $draft.employeeNumber)
                .accessibilityIdentifier("settings.employeeNumber")
        }
    }

    private var workplaceRows: some View {
        Group {
            sectionHeader(L10n.settingsWorkplace, icon: "building.2.fill")
            TextField(L10n.settingsWorkplaceName, text: $draft.workplaceName)
                .accessibilityIdentifier("settings.workplaceName")
            EmploymentSettingsRows(draft: $draft)
        }
    }

    private var payRows: some View {
        Group {
            sectionHeader(L10n.settingsPayHours, icon: "banknote.fill")
            HStack {
                Text(L10n.settingsHourlyRate)
                Spacer()
                TextField("0", value: $draft.hourlyRate, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .accessibilityIdentifier("settings.hourlyRate")
                Text(PayFormatter.symbol(for: draft.currencyCode))
            }
            HStack {
                Text(L10n.settingsGasAllowance)
                Spacer()
                TextField("35", value: $draft.dailyGasAllowance, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .accessibilityIdentifier("settings.gasAllowance")
                Text(PayFormatter.symbol(for: draft.currencyCode))
            }
            HStack {
                Text(L10n.settingsStandardHours)
                Spacer()
                TextField("8.6", value: $draft.standardDayHours, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .accessibilityIdentifier("settings.standardDayHours")
            }
            HStack {
                Text(L10n.settingsOTCap)
                Spacer()
                TextField("2.0", value: $draft.ot125HoursCap, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .accessibilityIdentifier("settings.ot125Cap")
            }
            HStack {
                Text(L10n.settingsWeeklyStandardHours)
                Spacer()
                TextField("42", value: $draft.weeklyStandardHours, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .accessibilityIdentifier("settings.weeklyStandardHours")
            }
            HStack {
                Text(L10n.settingsWeeklyOTCap)
                Spacer()
                TextField("12", value: $draft.weeklyOvertimeCapHours, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .accessibilityIdentifier("settings.weeklyOvertimeCap")
            }
        }
    }

    private var payrollRows: some View {
        Group {
            sectionHeader(AppLocale.tr("payroll.section"), icon: "calendar.badge.clock")
            Text(AppLocale.tr("payroll.startDayHelp"))
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(1...28, id: \.self) { day in
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    draft.payrollStartDay = day
                                }
                            } label: {
                                Text("\(day)")
                                    .font(.subheadline.weight(draft.payrollStartDay == day ? .bold : .regular).monospacedDigit())
                                    .frame(width: 38, height: 38)
                                    .background(
                                        Circle()
                                            .fill(draft.payrollStartDay == day ? Color.appAccent : Color(.tertiarySystemFill))
                                    )
                                    .foregroundStyle(draft.payrollStartDay == day ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                            .id(day)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
                .onAppear {
                    proxy.scrollTo(draft.payrollStartDay, anchor: .center)
                }
            }

            let preview = HistoryPeriodHelper.payrollPeriod(
                containing: Date(),
                startDay: draft.payrollStartDay
            )
            Text(String(
                format: AppLocale.tr("payroll.currentWindow %@"),
                HistoryPeriodHelper.shortRangeLabel(for: preview)
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var taxRows: some View {
        Group {
            sectionHeader(AppLocale.tr("tax.section"), icon: "percent")
            DatePicker(
                AppLocale.tr("tax.birthDate"),
                selection: Binding(
                    get: {
                        draft.birthDate ?? Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
                    },
                    set: { draft.birthDate = $0 }
                ),
                displayedComponents: .date
            )

            Picker(
                AppLocale.tr("tax.maritalStatus"),
                selection: $draft.maritalStatus
            ) {
                ForEach(MaritalStatus.allCases) { status in
                    Text(status.displayName).tag(status)
                }
            }

            Toggle(
                AppLocale.tr("tax.hasChildren"),
                isOn: $draft.hasChildren
            )

            if draft.hasChildren {
                Stepper(
                    value: $draft.numberOfChildren,
                    in: 0...15
                ) {
                    Text("\(AppLocale.tr("tax.numberOfChildren")): \(draft.numberOfChildren)")
                }
            }

            if draft.maritalStatus == .married {
                Toggle(
                    AppLocale.tr("tax.spouseEmployed"),
                    isOn: $draft.spouseEmployed
                )
            }

            LabeledContent(
                AppLocale.tr("tax.creditPoints")
            ) {
                Text(String(format: "%.2f", TaxCreditPointsCalculator.creditPoints(for: draft)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Text(AppLocale.tr("tax.estimateNote"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var syncRows: some View {
        Group {
            sectionHeader(L10n.syncSection, icon: "icloud.fill")
            Toggle(L10n.syncEnabled, isOn: Binding(
                get: { viewModel.isICloudSyncEnabled },
                set: { newValue in
                    if newValue {
                        viewModel.isICloudSyncEnabled = true
                    } else if viewModel.isICloudSyncEnabled {
                        showDisableSyncConfirm = true
                    }
                }
            ))

            Text(L10n.syncEnabledHint)
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.isICloudSyncEnabled {
                HStack {
                    Image(systemName: syncIcon)
                        .foregroundStyle(syncColor)
                    Text(syncStatusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if case .unavailable = viewModel.syncState {
                    Text(L10n.syncUnavailableHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        viewModel.syncNow()
                    } label: {
                        accentLabel(L10n.syncNow, icon: "icloud.and.arrow.up")
                    }
                    .disabled(viewModel.isSyncing)
                }
            }
        }
    }

    private var toolsRows: some View {
        Group {
            sectionHeader(L10n.settingsTools, icon: "wrench.and.screwdriver.fill")
            NavigationLink {
                ActivityLogView(viewModel: viewModel)
            } label: {
                accentLabel(L10n.logTitle, icon: "list.bullet.rectangle")
            }
        }
    }

    private var smartScannerRows: some View {
        Group {
            sectionHeader(L10n.scannerSection, icon: "doc.text.viewfinder")
            Toggle(L10n.scannerCloudEnabled, isOn: $smartScannerCloudEnabled)

            Text(L10n.scannerCloudPrivacyNotice)
                .font(.caption)
                .foregroundStyle(.secondary)

            if smartScannerCloudEnabled {
                SecureField(L10n.scannerGeminiAPIKey, text: $geminiAPIKeyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: geminiAPIKeyDraft) { _, _ in geminiKeyCheck = .idle }
                keyCheckRow(state: geminiKeyCheck) {
                    testKey(draft: geminiAPIKeyDraft, result: $geminiKeyCheck) {
                        await ScannerAPIKeyValidator.checkGeminiKey($0)
                    }
                }
                Text(L10n.scannerGeminiAPIKeyHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SecureField(L10n.scannerSecondaryAPIKey, text: $secondaryAPIKeyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: secondaryAPIKeyDraft) { _, _ in secondaryKeyCheck = .idle }
                keyCheckRow(state: secondaryKeyCheck) {
                    testKey(draft: secondaryAPIKeyDraft, result: $secondaryKeyCheck) {
                        await ScannerAPIKeyValidator.checkOpenAICompatibleKey($0)
                    }
                }
                Text(L10n.scannerSecondaryAPIKeyHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func testKey(
        draft: String,
        result: Binding<KeyCheckUIState>,
        check: @escaping (String) async -> APIKeyCheckResult
    ) {
        let key = draft
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        result.wrappedValue = .checking
        Task {
            let outcome = await check(key)
            result.wrappedValue = .result(outcome)
        }
    }

    private func keyCheckRow(state: KeyCheckUIState, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Button(L10n.scannerTestKey, action: action)
                .font(.caption.weight(.semibold))
                .disabled(state == .checking)

            switch state {
            case .idle:
                EmptyView()
            case .checking:
                ProgressView()
                    .controlSize(.mini)
                Text(L10n.scannerKeyCheckChecking)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .result(let outcome):
                Image(systemName: outcome.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(outcome.isValid ? .green : .red)
                Text(keyCheckMessage(for: outcome))
                    .font(.caption)
                    .foregroundStyle(outcome.isValid ? .green : .red)
            }
        }
    }

    private func keyCheckMessage(for outcome: APIKeyCheckResult) -> String {
        switch outcome {
        case .valid: return L10n.scannerKeyCheckValid
        case .invalid: return L10n.scannerKeyCheckInvalid
        case .networkError: return L10n.scannerKeyCheckNetworkError
        }
    }

    private var profileDisplayName: String {
        let trimmed = draft.workerFullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L10n.settingsProfileFallbackName : trimmed
    }

    private func copyPlaceholderUserID() {
        UIPasteboard.general.string = LocalPlaceholderUserID.current()
        UISelectionFeedbackGenerator().selectionChanged()
        viewModel.showSuccessToast(L10n.settingsUserIDCopied)
    }

    private func openWidgetGuideFromReminder() {
        WidgetNudge.pendingGuide = false
        Task {
            widgetInstallCount = await WidgetBridge.installedWidgetCount()
            showWidgetGuide = true
        }
    }

    private var addWidgetButton: some View {
        Button {
            Task {
                widgetInstallCount = await WidgetBridge.installedWidgetCount()
                showWidgetGuide = true
            }
        } label: {
            HStack {
                Label(L10n.settingsAddWidgetButton, systemImage: "square.grid.2x2")
                    .foregroundStyle(homeTheme.accent)
                Spacer()
                HStack(spacing: 4) {
                    Text(L10n.settingsWidgetInstalled(widgetInstallCount ?? 0))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .redacted(reason: widgetInstallCount == nil ? .placeholder : [])
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            widgetInstallCount = await WidgetBridge.installedWidgetCount()
        }
    }

    private var dataSafetyRows: some View {
        Group {
            sectionHeader(L10n.dataSafetySection, icon: "externaldrive.badge.checkmark")
            NavigationLink {
                RecentlyDeletedView(viewModel: viewModel)
            } label: {
                accentLabel(L10n.dataSafetyRecentlyDeleted, icon: "trash")
            }
            NavigationLink {
                LocalBackupsView(viewModel: viewModel)
            } label: {
                accentLabel(L10n.dataSafetyBackups, icon: "clock.arrow.circlepath")
            }
            Text(L10n.dataSafetyHint).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var adminRows: some View {
        Group {
            sectionHeader(L10n.adminTitle, icon: "crown.fill")
            NavigationLink {
                AdminDashboardView()
            } label: {
                accentLabel(L10n.adminSettingsEntry, icon: "crown")
            }
            .badge(AdminMockBadges.unreadSupport)
            Text(L10n.adminSettingsFooter).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var securityRows: some View {
        Group {
            sectionHeader(L10n.appLockSection, icon: "lock.shield.fill")
            Toggle(L10n.appLockEnabled, isOn: $appLock.isEnabled)
            Text(L10n.appLockHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var widgetPrivacyRows: some View {
        Group {
            sectionHeader(L10n.settingsHideWidgetPaySection, icon: "square.grid.2x2.fill")
            addWidgetButton
            Text(L10n.settingsAddWidgetHint)
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle(
                L10n.settingsHideWidgetPay,
                isOn: Binding(
                    get: { WidgetBridge.hidePay },
                    set: { newValue in
                        WidgetBridge.hidePay = newValue
                        viewModel.refreshLiveSurfaces()
                    }
                )
            )
            Text(L10n.settingsHideWidgetPayHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var workplacesRows: some View {
        Group {
            sectionHeader(L10n.workplacesTitle, icon: "building.2.crop.circle")
            if viewModel.hasMultipleWorkplaces {
                WorkplaceSwitcher(viewModel: viewModel)
                ForEach(viewModel.workplaceOptions.dropFirst()) { option in
                    HStack(spacing: 10) {
                        Circle().fill(option.color).frame(width: 10, height: 10)
                        Text(option.name)
                        Spacer()
                        Button(role: .destructive) {
                            workplacePendingDelete = option
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(L10n.workplaceDelete)
                    }
                }
            }
            Button {
                newWorkplaceName = ""
                showAddWorkplace = true
            } label: {
                accentLabel(L10n.workplaceAdd, icon: "plus.circle.fill")
            }
            .accessibilityIdentifier("settings.addWorkplace")
            Text(viewModel.hasMultipleWorkplaces ? L10n.workplacesHintActive : L10n.workplacesHint)
        }
        .alert(L10n.workplaceAdd, isPresented: $showAddWorkplace) {
            TextField(L10n.workplaceNamePlaceholder, text: $newWorkplaceName)
            Button(L10n.workplaceAddConfirm) {
                if hasUnsavedChanges { saveSettings() }
                viewModel.addWorkplace(named: newWorkplaceName)
            }
            Button(L10n.editCancel, role: .cancel) {}
        } message: {
            Text(L10n.workplaceAddMessage)
        }
        .alert(
            L10n.workplaceDeleteConfirmTitle,
            isPresented: Binding(
                get: { workplacePendingDelete != nil },
                set: { if !$0 { workplacePendingDelete = nil } }
            )
        ) {
            Button(L10n.workplaceDelete, role: .destructive) {
                if let id = workplacePendingDelete?.workplaceID {
                    viewModel.deleteWorkplace(id)
                }
                workplacePendingDelete = nil
            }
            Button(L10n.editCancel, role: .cancel) { workplacePendingDelete = nil }
        } message: {
            Text(L10n.workplaceDeleteConfirmMessage(
                workplacePendingDelete?.workplaceID.map { viewModel.shiftCount(in: $0) } ?? 0
            )).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var shareAppSection: some View {
        Section {
            if let appURL = URL(string: "https://apps.apple.com/app/id6790862413") {
                ShareLink(
                    item: appURL,
                    subject: Text(L10n.brandName),
                    message: Text(L10n.settingsShareAppMessage)
                ) {
                    accentLabel(L10n.settingsShareApp, icon: "square.and.arrow.up")
                }
                .accessibilityIdentifier("settings.shareApp")
            }
        } footer: {
            Text(L10n.settingsShareAppHint)
        }
    }

    private var languageSection: some View {
        Section {
            Picker(L10n.settingsAppLanguage, selection: $appLanguage.preference) {
                ForEach(AppLanguageOption.allCases) { option in
                    Text(option.pickerLabel).tag(option)
                }
            }
            .accessibilityIdentifier("settings.appLanguage")
        } header: {
            sectionHeader(L10n.settingsAppLanguage, icon: "globe")
        } footer: {
            Text(L10n.settingsAppLanguageHint)
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent(L10n.settingsVersion, value: appVersionString)

            NavigationLink {
                PrivacyPolicyView()
            } label: {
                accentLabel(L10n.privacyTitle, icon: "hand.raised.fill")
            }

            NavigationLink {
                TermsOfUseView()
            } label: {
                accentLabel(AppLocale.tr("terms.title"), icon: "doc.text")
            }

            if let agreedOn = LegalConsent.shared.acceptedAt {
                Text(String(
                    format: AppLocale.tr("legal.acceptedOn %@"),
                    AppLocale.makeDateFormatter(dateStyle: .medium).string(from: agreedOn)
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button {
                showContactSupport = true
            } label: {
                accentLabel(L10n.settingsSupport, icon: "envelope")
            }
            .accessibilityIdentifier("settings.contactSupport")

            if let rateURL = URL(string: "https://apps.apple.com/app/id6790862413?action=write-review") {
                Link(destination: rateURL) {
                    Label {
                        Text(L10n.settingsRateApp).foregroundStyle(.yellow)
                    } icon: {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                    }
                }
            }

            Button {
                showFullDataExport = true
            } label: {
                accentLabel(L10n.fullExportTitle, icon: "externaldrive.badge.timemachine")
            }

            Button {
                showFullDataImporter = true
            } label: {
                accentLabel(L10n.fullImportTitle, icon: "square.and.arrow.down.on.square")
            }
        } header: {
            sectionHeader(L10n.settingsAbout, icon: "info.circle.fill")
        }
    }

    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteAllConfirm = true
            } label: {
                Label(L10n.privacyDeleteAll, systemImage: "trash")
                    .foregroundStyle(.red)
            }
            .accessibilityIdentifier("settings.deleteAllData")
        } header: {
            Label(L10n.settingsDangerZone, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.red)
        } footer: {
            Text(L10n.settingsDangerZoneHint)
        }
    }

    private var saveButton: some View {
        Button(action: saveSettings) {
            HStack(spacing: 5) {
                if hasUnsavedChanges {
                    Circle()
                        .fill(DS.Palette.ink)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(L10n.settingsSave)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(hasUnsavedChanges ? DS.Palette.ink : Color.secondary)
            .animation(DS.Motion.state, value: hasUnsavedChanges)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(homeTheme.accent)
        .disabled(!hasUnsavedChanges)
        .accessibilityValue(hasUnsavedChanges ? L10n.settingsUnsavedTitle : "")
        .accessibilityIdentifier("settings.save")
    }

    private func saveSettings() {
        var toSave = draft
        toSave.leaveDays = viewModel.activeSettings.leaveDays
        viewModel.saveActiveWorkplaceSettings(toSave)
        UserDefaultsSmartScannerCloudPreference.shared.isEnabled = smartScannerCloudEnabled
        let trimmedKey = geminiAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        try? KeychainStore.setString(trimmedKey, for: .geminiAPIKey)
        let trimmedSecondary = secondaryAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        try? KeychainStore.setString(trimmedSecondary, for: .secondaryAPIKey)
        reloadFromStore()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        viewModel.showSuccessToast(L10n.settingsSaved)
    }

    private func handleFullDataImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let document = try FullDataExportManager().loadJSONDocument(from: url)
                pendingImportDocument = document
                showImportConfirm = true
            } catch {
                importErrorMessage = error.localizedDescription
            }
        }
    }

    private func applyFullDataImport(mode: FullDataImportMode) {
        guard let document = pendingImportDocument else { return }
        pendingImportDocument = nil
        do {
            try viewModel.importFullDataExport(document, mode: mode)
            draft = viewModel.activeSettings
            viewModel.showSuccessToast(L10n.fullImportSuccess)
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    private var appVersionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    private var syncIcon: String {
        switch viewModel.syncState {
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .synced: return "checkmark.icloud"
        case .failed: return "exclamationmark.icloud"
        case .unavailable: return "icloud.slash"
        case .idle: return "icloud"
        }
    }

    private var syncColor: Color {
        switch viewModel.syncState {
        case .synced: return .green
        case .failed: return .red
        case .unavailable: return .orange
        default: return .secondary
        }
    }

    private var syncStatusText: String {
        switch viewModel.syncState {
        case .idle:
            return L10n.syncSynced
        case .syncing:
            return L10n.syncSyncing
        case .synced(let date):
            return L10n.syncLastSync(syncDateFormatter.string(from: date))
        case .failed(let message):
            return L10n.syncFailed(message)
        case .unavailable:
            return L10n.syncUnavailable
        }
    }
}

struct UsualScheduleView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        let schedule = ShiftSchedule.learn(from: viewModel.workSessions)
        Form {
            Section {
                if schedule.windows.isEmpty {
                    Text(L10n.settingsNotificationsScheduleLearning)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(orderedWeekdays(in: schedule), id: \.self) { weekday in
                        if let window = schedule.windows[weekday] {
                            HStack {
                                Text(weekdayName(weekday))
                                Spacer()
                                Text(usualHoursLabel(window))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } footer: {
                Text(L10n.settingsNotificationsHint)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.settingsNotificationsUsualSchedule)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func orderedWeekdays(in schedule: ShiftSchedule) -> [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }.filter { schedule.windows[$0] != nil }
    }

    private func weekdayName(_ weekday: Int) -> String {
        let symbols = AppLocale.makeDateFormatter().weekdaySymbols ?? Calendar.current.weekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : ""
    }

    private func usualHoursLabel(_ window: ShiftSchedule.Window) -> String {
        let formatter = AppLocale.makeDateFormatter(timeStyle: .short)
        let day = Calendar.current.startOfDay(for: Date())
        let start = day.addingTimeInterval(TimeInterval(window.startMinutes * 60))
        let end = start.addingTimeInterval(TimeInterval(window.durationMinutes * 60))
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }
}