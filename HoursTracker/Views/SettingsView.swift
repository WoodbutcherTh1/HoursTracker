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
    @EnvironmentObject private var appLock: AppLockController
    @EnvironmentObject private var appLanguage: AppLanguageController

    @State private var draft: WorkplaceSettings
    @State private var locationStatus: String = ""
    @State private var showDeleteAllConfirm = false
    @State private var showFullDataExport = false
    @State private var showFullDataImporter = false
    @State private var pendingImportDocument: FullDataExportDocument?
    @State private var showImportConfirm = false
    @State private var importErrorMessage: String?
    @State private var showArrivalExplainer = false
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

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        _draft = State(initialValue: viewModel.settings)
    }

    var body: some View {
        NavigationStack {
            Form {
                workerSection
                workplaceSection
                paySection
                workRulesSection
                payrollSection
                taxSection
                locationSection
                securitySection
                smartScannerSection
                if viewModel.isCloudSyncSupported {
                    syncSection
                }
                toolsSection
                languageSection
                aboutSection
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDismissible()
            .navigationTitle(L10n.settingsTitle)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.settingsSave) {
                        saveSettings()
                    }
                }
            }
            .onAppear {
                draft = viewModel.settings
                viewModel.refreshLocationPermissionStatuses()
                smartScannerCloudEnabled = UserDefaultsSmartScannerCloudPreference.shared.isEnabled
                geminiAPIKeyDraft = KeychainStore.string(for: .geminiAPIKey) ?? ""
                secondaryAPIKeyDraft = KeychainStore.string(for: .secondaryAPIKey) ?? ""
            }
            .confirmationDialog(
                L10n.privacyDeleteAllConfirm,
                isPresented: $showDeleteAllConfirm,
                titleVisibility: .visible
            ) {
                Button(L10n.privacyDeleteAll, role: .destructive) {
                    viewModel.deleteAllUserData()
                    draft = viewModel.settings
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
            .alert(L10n.settingsArrivalTitle, isPresented: $showArrivalExplainer) {
                Button(L10n.settingsArrivalContinue) {
                    draft.arrivalRemindersEnabled = true
                }
                Button(L10n.editCancel, role: .cancel) {
                    draft.arrivalRemindersEnabled = false
                }
            } message: {
                Text(L10n.settingsArrivalBody)
            }
            .sheet(isPresented: $showFullDataExport) {
                FullDataExportSheet(viewModel: viewModel)
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
            draft = viewModel.settings
            viewModel.showSuccessToast(L10n.fullImportSuccess)
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    private func saveSettings() {
        viewModel.saveSettings(draft)
        draft = viewModel.settings
        UserDefaultsSmartScannerCloudPreference.shared.isEnabled = smartScannerCloudEnabled
        let trimmedKey = geminiAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        try? KeychainStore.setString(trimmedKey, for: .geminiAPIKey)
        let trimmedSecondary = secondaryAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        try? KeychainStore.setString(trimmedSecondary, for: .secondaryAPIKey)
        viewModel.showSuccessToast(L10n.settingsSaved)
    }

    private var smartScannerSection: some View {
        Section {
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
        } header: {
            Text(L10n.scannerSection)
        }
    }

    /// Fires an async key check against `draft` and stores the outcome in `result`.
    /// Shared by the Gemini and secondary-key rows — only the network call differs.
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

    /// "Test Key" button + inline red/green status, shown under each API key field.
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

    private var workerSection: some View {
        Section(L10n.settingsWorkerInfo) {
            TextField(L10n.settingsFullName, text: $draft.workerFullName)
            if isEditingIDNumber {
                TextField(L10n.settingsIDNumber, text: $draft.workerIDNumber)
                    .keyboardType(.numberPad)
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
        }
    }

    private var securitySection: some View {
        Section {
            Toggle(L10n.appLockEnabled, isOn: $appLock.isEnabled)
            Text(L10n.appLockHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(L10n.appLockSection)
        }
    }

    private var workplaceSection: some View {
        Section(L10n.settingsWorkplace) {
            TextField(L10n.settingsWorkplaceName, text: $draft.workplaceName)
            TextField(L10n.settingsContractor, text: Binding(
                get: { draft.contractorName ?? "" },
                set: { draft.contractorName = $0.isEmpty ? nil : $0 }
            ))
        }
    }

    private var paySection: some View {
        Section(L10n.settingsPayHours) {
            HStack {
                Text(L10n.settingsHourlyRate)
                Spacer()
                TextField("0", value: $draft.hourlyRate, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                Text(PayFormatter.symbol(for: draft.currencyCode))
            }
            HStack {
                Text(L10n.settingsGasAllowance)
                Spacer()
                TextField("35", value: $draft.dailyGasAllowance, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                Text(PayFormatter.symbol(for: draft.currencyCode))
            }
            HStack {
                Text(L10n.settingsStandardHours)
                Spacer()
                TextField("8.6", value: $draft.standardDayHours, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
            }
            HStack {
                Text(L10n.settingsOTCap)
                Spacer()
                TextField("2.0", value: $draft.ot125HoursCap, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
            }
        }
    }

    private var workRulesSection: some View {
        Section(L10n.settingsWorkRules) {
            Picker(L10n.settingsRestDay, selection: $draft.restDayWeekday) {
                ForEach(1...7, id: \.self) { weekday in
                    Text(Calendar.current.weekdaySymbols[weekday - 1]).tag(weekday)
                }
            }
            .onChange(of: draft.restDayWeekday) { _, newValue in
                if draft.secondRestDayWeekday == newValue {
                    draft.secondRestDayWeekday = nil
                }
            }

            Picker(
                L10n.settingsSecondRestDay,
                selection: Binding(
                    get: { draft.secondRestDayWeekday ?? 0 },
                    set: { draft.secondRestDayWeekday = $0 == 0 ? nil : $0 }
                )
            ) {
                Text(L10n.settingsSecondRestDayNone).tag(0)
                ForEach(1...7, id: \.self) { weekday in
                    if weekday != draft.restDayWeekday {
                        Text(Calendar.current.weekdaySymbols[weekday - 1]).tag(weekday)
                    }
                }
            }

            Stepper(value: $draft.defaultBreakMinutes, in: 0...120, step: 5) {
                HStack {
                    Text(L10n.settingsDefaultBreak)
                    Spacer()
                    Text("\(draft.defaultBreakMinutes)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Picker(L10n.settingsCurrency, selection: $draft.currencyCode) {
                ForEach(PayFormatter.supportedCurrencyCodes, id: \.self) { code in
                    Text("\(code) (\(PayFormatter.symbol(for: code)))").tag(code)
                }
            }

            Text(L10n.settingsWorkRulesNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var payrollSection: some View {
        Section {
            Text(AppLocale.tr("payroll.startDayHelp"))
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(1...28, id: \.self) { day in
                    Button {
                        draft.payrollStartDay = day
                    } label: {
                        Text("\(day)")
                            .font(.subheadline.weight(draft.payrollStartDay == day ? .bold : .regular).monospacedDigit())
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(draft.payrollStartDay == day ? Color.accentColor : Color(.tertiarySystemFill))
                            )
                            .foregroundStyle(draft.payrollStartDay == day ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)

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
        } header: {
            Text(AppLocale.tr("payroll.section"))
        }
    }

    private var taxSection: some View {
        Section {
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
        } header: {
            Text(AppLocale.tr("tax.section"))
        }
    }

    private var locationSection: some View {
        Section {
            Toggle(L10n.settingsArrivalReminders, isOn: Binding(
                get: { draft.arrivalRemindersEnabled },
                set: { newValue in
                    if newValue {
                        if draft.hasWorkplaceLocation {
                            showArrivalExplainer = true
                        } else {
                            locationStatus = L10n.settingsArrivalNeedLocation
                            draft.arrivalRemindersEnabled = false
                        }
                    } else {
                        draft.arrivalRemindersEnabled = false
                    }
                }
            ))

            Text(L10n.settingsArrivalHint)
                .font(.caption)
                .foregroundStyle(.secondary)

            if showsLocationPermissionDenied {
                Text(L10n.settingsLocationDenied)
                    .font(.caption)
                    .foregroundStyle(.red)
                Button(L10n.settingsOpenSystemSettings) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }

            if viewModel.areLocationNotificationsDenied && draft.arrivalRemindersEnabled {
                Text(L10n.settingsNotificationsDenied)
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button(L10n.settingsOpenSystemSettings) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }

            HStack {
                Text(L10n.settingsGeofenceRadius)
                Spacer()
                TextField("150", value: $draft.locationRadiusMeters, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("m")
            }

            if let lat = draft.locationLatitude, let lon = draft.locationLongitude {
                Text(L10n.settingsLocationCoords(lat: lat, lon: lon))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.settingsNoLocation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                locationStatus = L10n.settingsRequestingLocation
                viewModel.captureCurrentLocation()
            } label: {
                Label(L10n.settingsSetLocation, systemImage: "location.fill")
            }
            .onReceive(viewModel.locationUpdates) { location in
                guard location != nil else { return }
                viewModel.applyCapturedLocationIfAvailable()
                draft = viewModel.settings
                locationStatus = L10n.settingsLocationUpdated
            }
            .onReceive(viewModel.locationCaptureErrors) { error in
                guard error != nil else { return }
                viewModel.refreshLocationPermissionStatuses()
                if viewModel.locationAuthorizationStatus == .denied
                    || viewModel.locationAuthorizationStatus == .restricted {
                    locationStatus = L10n.settingsLocationDenied
                } else {
                    locationStatus = L10n.settingsLocationFailed
                }
            }

            if !locationStatus.isEmpty {
                Text(locationStatus)
                    .font(.caption)
                    .foregroundStyle(
                        locationStatus == L10n.settingsLocationFailed
                            || locationStatus == L10n.settingsLocationDenied
                            ? .red : .green
                    )
            }
        } header: {
            Text(L10n.settingsLocationReminders)
        }
    }

    private var showsLocationPermissionDenied: Bool {
        let status = viewModel.locationAuthorizationStatus
        return status == .denied || status == .restricted
    }

    private var syncSection: some View {
        Section {
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
                        Label(L10n.syncNow, systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(viewModel.isSyncing)
                }
            }
        } header: {
            Text(L10n.syncSection)
        }
    }

    private var toolsSection: some View {
        Section(L10n.settingsTools) {
            NavigationLink {
                ActivityLogView(viewModel: viewModel)
            } label: {
                Label(L10n.logTitle, systemImage: "list.bullet.rectangle")
            }
        }
    }

    private var languageSection: some View {
        Section {
            Picker(L10n.settingsAppLanguage, selection: $appLanguage.preference) {
                ForEach(AppLanguageOption.allCases) { option in
                    Text(option.pickerLabel).tag(option)
                }
            }
        } header: {
            Text(L10n.settingsAppLanguage)
        } footer: {
            Text(L10n.settingsAppLanguageHint)
        }
    }

    private var aboutSection: some View {
        Section(L10n.settingsAbout) {
            LabeledContent(L10n.settingsVersion, value: appVersionString)

            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Label(L10n.privacyTitle, systemImage: "hand.raised.fill")
            }

            if let mailURL = URL(string: "mailto:support@hourstracker.app") {
                Link(destination: mailURL) {
                    Label(L10n.settingsSupport, systemImage: "envelope")
                }
            }

            Button {
                showFullDataExport = true
            } label: {
                Label(L10n.fullExportTitle, systemImage: "externaldrive.badge.timemachine")
            }

            Button {
                showFullDataImporter = true
            } label: {
                Label(L10n.fullImportTitle, systemImage: "square.and.arrow.down.on.square")
            }

            Button(role: .destructive) {
                showDeleteAllConfirm = true
            } label: {
                Label(L10n.privacyDeleteAll, systemImage: "trash")
            }
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
