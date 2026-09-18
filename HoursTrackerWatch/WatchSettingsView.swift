import SwiftUI

/// Watch mirror of the phone's Settings tab, same section grouping (Worker Info,
/// Workplace, Pay & Hours, Work Rules, Payroll, Tax, App Lock, Widget privacy,
/// iCloud Sync, Language, About). Free-text/numeric fields (name, hourly rate, tax
/// profile…), location capture, Smart Scanner API keys, and destructive actions
/// (delete all data, full import/export) are read-only here with an "Edit on
/// iPhone" note — a watch keyboard isn't where anyone wants to type a pay rate or
/// confirm a data wipe. The toggles that are safe and useful one-tap on a watch
/// (App Lock, hide widget pay, iCloud Sync, app language) are fully interactive.
struct WatchSettingsView: View {
    @EnvironmentObject private var store: WatchSessionStore

    private var summary: WatchSettingsSummary { store.snapshot.settingsSummary }

    var body: some View {
        List {
            Section("Worker Info") {
                readOnlyRow("Name", summary.workerFullName.isEmpty ? "—" : summary.workerFullName)
            }

            Section("Workplace") {
                readOnlyRow("Workplace", summary.workplaceName.isEmpty ? "—" : summary.workplaceName)
            }

            Section("Pay & Hours") {
                readOnlyRow("Hourly rate", formattedPay(summary.hourlyRate))
                readOnlyRow("Gas allowance", formattedPay(summary.dailyGasAllowance))
                readOnlyRow("Standard day", String(format: "%.1fh", summary.standardDayHours))
                readOnlyRow("OT cap (day)", String(format: "%.1fh", summary.ot125HoursCap))
                readOnlyRow("Weekly standard", String(format: "%.0fh", summary.weeklyStandardHours))
                readOnlyRow("Weekly OT cap", String(format: "%.0fh", summary.weeklyOvertimeCapHours))
            }

            Section("Work Rules") {
                readOnlyRow("Rest day", summary.restDayName)
                if let second = summary.secondRestDayName {
                    readOnlyRow("2nd rest day", second)
                }
            }

            Section("Payroll") {
                readOnlyRow("Starts on", "Day \(summary.payrollStartDay)")
                readOnlyRow("Current window", summary.payrollWindowLabel)
            }

            Section("Tax Profile") {
                readOnlyRow("Marital status", summary.maritalStatusName)
                if summary.hasChildren {
                    readOnlyRow("Children", "\(summary.numberOfChildren)")
                }
                readOnlyRow("Credit points", String(format: "%.2f", summary.creditPoints))
            }

            Section("App Lock") {
                Toggle("Require Face/Touch ID", isOn: Binding(
                    get: { summary.appLockEnabled },
                    set: { store.toggleAppLock($0) }
                ))
            }

            Section("Widget Privacy") {
                Toggle("Hide pay on widgets", isOn: Binding(
                    get: { summary.hideWidgetPay },
                    set: { store.toggleHideWidgetPay($0) }
                ))
            }

            if summary.isCloudSyncSupported {
                Section("iCloud Sync") {
                    Toggle("Sync across devices", isOn: Binding(
                        get: { summary.isCloudSyncEnabled },
                        set: { store.toggleCloudSync($0) }
                    ))
                    if summary.isCloudSyncEnabled {
                        Text(summary.cloudSyncStatusText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Language") {
                Picker("App language", selection: Binding(
                    get: { summary.languageOptionRaw },
                    set: { store.setLanguage($0) }
                )) {
                    ForEach(summary.languageOptions) { option in
                        Text(option.label).tag(option.raw)
                    }
                }
            }

            Section("About") {
                readOnlyRow("Version", summary.appVersion)
                Text("Full data export/import, Smart Scanner keys, and Delete All Data stay on iPhone.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }

    private func readOnlyRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func formattedPay(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = summary.currencyCode.isEmpty ? "ILS" : summary.currencyCode
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.0f", amount)
    }
}
