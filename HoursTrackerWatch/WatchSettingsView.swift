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
            Section {
                readOnlyRow("Name", summary.workerFullName.isEmpty ? "—" : summary.workerFullName)
            } header: {
                sectionHeader("Worker Info", "person.fill")
            }

            Section {
                readOnlyRow("Workplace", summary.workplaceName.isEmpty ? "—" : summary.workplaceName)
            } header: {
                sectionHeader("Workplace", "building.2.fill")
            }

            Section {
                readOnlyRow("Hourly rate", formattedPay(summary.hourlyRate))
                readOnlyRow("Gas allowance", formattedPay(summary.dailyGasAllowance))
                readOnlyRow("Standard day", String(format: "%.1fh", summary.standardDayHours))
                readOnlyRow("OT cap (day)", String(format: "%.1fh", summary.ot125HoursCap))
                readOnlyRow("Weekly standard", String(format: "%.0fh", summary.weeklyStandardHours))
                readOnlyRow("Weekly OT cap", String(format: "%.0fh", summary.weeklyOvertimeCapHours))
            } header: {
                sectionHeader("Pay & Hours", "dollarsign.circle.fill")
            }

            Section {
                readOnlyRow("Rest day", summary.restDayName)
                if let second = summary.secondRestDayName {
                    readOnlyRow("2nd rest day", second)
                }
            } header: {
                sectionHeader("Work Rules", "calendar.badge.clock")
            }

            Section {
                readOnlyRow("Starts on", "Day \(summary.payrollStartDay)")
                readOnlyRow("Current window", summary.payrollWindowLabel)
            } header: {
                sectionHeader("Payroll", "calendar")
            }

            Section {
                readOnlyRow("Marital status", summary.maritalStatusName)
                if summary.hasChildren {
                    readOnlyRow("Children", "\(summary.numberOfChildren)")
                }
                readOnlyRow("Credit points", String(format: "%.2f", summary.creditPoints))
            } header: {
                sectionHeader("Tax Profile", "percent")
            }

            Section {
                Toggle("Require Face/Touch ID", isOn: Binding(
                    get: { summary.appLockEnabled },
                    set: { store.toggleAppLock($0) }
                ))
            } header: {
                sectionHeader("App Lock", "lock.fill")
            }

            Section {
                Toggle("Hide pay on widgets", isOn: Binding(
                    get: { summary.hideWidgetPay },
                    set: { store.toggleHideWidgetPay($0) }
                ))
            } header: {
                sectionHeader("Widget Privacy", "eye.slash.fill")
            }

            if summary.isCloudSyncSupported {
                Section {
                    Toggle("Sync across devices", isOn: Binding(
                        get: { summary.isCloudSyncEnabled },
                        set: { store.toggleCloudSync($0) }
                    ))
                    if summary.isCloudSyncEnabled {
                        Text(summary.cloudSyncStatusText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    sectionHeader("iCloud Sync", "icloud.fill")
                }
            }

            Section {
                Picker("App language", selection: Binding(
                    get: { summary.languageOptionRaw },
                    set: { store.setLanguage($0) }
                )) {
                    ForEach(summary.languageOptions) { option in
                        Text(option.label).tag(option.raw)
                    }
                }
            } header: {
                sectionHeader("Language", "globe")
            }

            Section {
                readOnlyRow("Version", summary.appVersion)
                Text("Full data export/import, Smart Scanner keys, and Delete All Data stay on iPhone.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            } header: {
                sectionHeader("About", "info.circle.fill")
            }
        }
        .navigationTitle("Settings")
    }

    private func sectionHeader(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon)
            .labelStyle(.titleAndIcon)
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
