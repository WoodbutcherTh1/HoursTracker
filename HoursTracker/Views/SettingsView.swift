import SwiftUI
import CoreLocation

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var draft: WorkplaceSettings
    @State private var locationStatus: String = ""

    private let syncDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

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
                locationSection
                syncSection
            }
            .navigationTitle(L10n.settingsTitle)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.settingsSave) {
                        viewModel.saveSettings(draft)
                    }
                }
            }
            .onAppear {
                draft = viewModel.settings
            }
        }
    }

    private var workerSection: some View {
        Section(L10n.settingsWorkerInfo) {
            TextField(L10n.settingsFullName, text: $draft.workerFullName)
            TextField(L10n.settingsIDNumber, text: $draft.workerIDNumber)
                .keyboardType(.numberPad)
            TextField(L10n.settingsEmployeeNumber, text: $draft.employeeNumber)
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
                Text("₪")
            }
            HStack {
                Text(L10n.settingsGasAllowance)
                Spacer()
                TextField("35", value: $draft.dailyGasAllowance, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                Text("₪")
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

    private var locationSection: some View {
        Section(L10n.settingsLocationReminders) {
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
                viewModel.captureCurrentLocation()
            } label: {
                Label(L10n.settingsSetLocation, systemImage: "location.fill")
            }
            .onReceive(viewModel.locationUpdates) { _ in
                viewModel.applyCapturedLocationIfAvailable()
                draft = viewModel.settings
                locationStatus = draft.hasWorkplaceLocation ? L10n.settingsLocationUpdated : L10n.settingsRequestingLocation
            }

            if !locationStatus.isEmpty {
                Text(locationStatus)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private var syncSection: some View {
        Section(L10n.syncSection) {
            HStack {
                Image(systemName: syncIcon)
                    .foregroundStyle(syncColor)
                Text(syncStatusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                viewModel.syncNow()
            } label: {
                Label(L10n.syncNow, systemImage: "icloud.and.arrow.up")
            }
            .disabled(viewModel.isSyncing)
        }
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
