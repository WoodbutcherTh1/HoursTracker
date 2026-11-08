import SwiftUI

/// Settings → Reminders & location.
struct RemindersView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var draft: WorkplaceSettings
    @ObservedObject private var homeTheme = HomeAccentTheme.shared
    @ObservedObject private var appBackground = AppBackgroundTheme.shared
    @ObservedObject private var notificationPrefs = NotificationPreferences.shared

    @State private var locationStatus = ""
    @State private var showArrivalExplainer = false

    private var showsLocationPermissionDenied: Bool {
        let status = viewModel.locationAuthorizationStatus
        return status == .denied || status == .restricted
    }

    private var breakTargetChoices: [Int] {
        let options = NotificationPreferences.breakTargetOptions
        let current = notificationPrefs.breakTargetMinutes
        return options.contains(current) ? options : (options + [current]).sorted()
    }

    var body: some View {
        Form {
            Section {
                arrivalRemindersToggle
                Text(L10n.settingsArrivalHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Both permission flags below are resolved synchronously from
                // already-cached authorization state by the time this page can
                // be opened — the jump risk `Form` has is for rows that pop in
                // sometime *after* first render from an async result, not for
                // a value that's already settled before the page exists.
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
                        .accessibilityIdentifier("settings.locationRadius")
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

                setLocationButton
            } header: {
                sectionHeader(L10n.settingsLocationReminders, icon: "location.fill")
            }

            Section {
                Picker(L10n.settingsNotificationsBreakLength, selection: $notificationPrefs.breakTargetMinutes) {
                    ForEach(breakTargetChoices, id: \.self) { minutes in
                        Text(L10n.settingsNotificationsMinutes(minutes)).tag(minutes)
                    }
                }

                Toggle(L10n.settingsNotificationsBreakEndingSoon, isOn: $notificationPrefs.breakEndingSoonEnabled)

                if notificationPrefs.breakEndingSoonEnabled {
                    Picker(L10n.settingsNotificationsBreakLead, selection: $notificationPrefs.breakLeadMinutes) {
                        ForEach(NotificationPreferences.breakLeadTimeOptions, id: \.self) { minutes in
                            Text(L10n.settingsNotificationsMinutes(minutes)).tag(minutes)
                        }
                    }
                }

                Toggle(L10n.settingsNotificationsBreakOver, isOn: $notificationPrefs.breakOverEnabled)

                Toggle(L10n.settingsNotificationsShiftStart, isOn: $notificationPrefs.shiftStartReminderEnabled)
                    .onChange(of: notificationPrefs.shiftStartReminderEnabled) { _, _ in viewModel.refreshShiftReminders() }
                Toggle(L10n.settingsNotificationsShiftEnd, isOn: $notificationPrefs.shiftEndReminderEnabled)
                    .onChange(of: notificationPrefs.shiftEndReminderEnabled) { _, _ in viewModel.refreshShiftReminders() }

                if notificationPrefs.shiftStartReminderEnabled || notificationPrefs.shiftEndReminderEnabled {
                    NavigationLink {
                        UsualScheduleView(viewModel: viewModel)
                    } label: {
                        accentLabel(L10n.settingsNotificationsUsualSchedule, icon: "calendar.badge.clock")
                    }
                }

                Toggle(L10n.settingsNotificationsShiftSummary, isOn: $notificationPrefs.shiftSummaryEnabled)

                Toggle(L10n.settingsNotificationsAnnouncements, isOn: $notificationPrefs.announcementsEnabled)
                    .onChange(of: notificationPrefs.announcementsEnabled) { _, _ in
                        AnnouncementCenter.shared.refresh(force: true)
                    }

                if viewModel.areLocationNotificationsDenied {
                    Text(L10n.settingsNotificationsDenied)
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button(L10n.settingsOpenSystemSettings) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                Text(L10n.settingsNotificationsHint).font(.footnote).foregroundStyle(.secondary)
            } header: {
                sectionHeader(L10n.settingsNotificationsSection, icon: "bell.badge.fill")
            }
        }
        .transaction { $0.disablesAnimations = true }
        .tint(homeTheme.accent)
        .toggleStyle(SwitchToggleStyle(tint: homeTheme.accent))
        .symbolRenderingMode(.monochrome)
        .scrollContentBackground(.hidden)
        .background(appBackground.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 32) }
        .scrollDismissesKeyboard(.interactively)
        .keyboardDismissible()
        .navigationTitle(L10n.settingsGroupReminders)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.refreshLocationPermissionStatuses() }
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
        .onReceive(viewModel.locationUpdates) { location in
            guard location != nil else { return }
            viewModel.applyCapturedLocationIfAvailable()
            draft = viewModel.activeSettings
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
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label {
            Text(title.uppercased(with: AppLocale.resolvedLocale))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(0.5)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(homeTheme.accent)
        }
    }

    private func accentLabel(_ title: String, icon: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon).foregroundStyle(homeTheme.accent)
        }
    }

    private var arrivalRemindersToggle: some View {
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
        .accessibilityIdentifier("settings.arrivalReminders")
    }

    private var setLocationButton: some View {
        Button {
            locationStatus = L10n.settingsRequestingLocation
            viewModel.captureCurrentLocation()
        } label: {
            accentLabel(L10n.settingsSetLocation, icon: "location.fill")
        }
        .overlay(alignment: .trailing) {
            if !locationStatus.isEmpty {
                Text(locationStatus)
                    .font(.caption)
                    .foregroundStyle(
                        locationStatus == L10n.settingsLocationFailed
                            || locationStatus == L10n.settingsLocationDenied
                            ? .red : .green
                    )
            }
        }
    }
}
