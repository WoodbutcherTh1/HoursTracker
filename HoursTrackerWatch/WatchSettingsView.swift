import SwiftUI

/// Watch mirror of the phone's Settings tab, same section grouping (Worker Info,
/// Workplace, Pay & Hours, Work Rules, Payroll, Tax, App Lock, Widget privacy,
/// iCloud Sync, Language, About). Free-text/numeric fields (name, hourly rate, tax
/// profile…), location capture, Smart Scanner API keys, and destructive actions
/// (delete all data, full import/export) are read-only here with an "Edit on
/// iPhone" note — a watch keyboard isn't where anyone wants to type a pay rate or
/// confirm a data wipe. The toggles that are safe and useful one-tap on a watch
/// (App Lock, hide widget pay, iCloud Sync, app language) are fully interactive.
///
/// Fully localized: section headers and row labels come from the shared String
/// Catalog (`watch.settings.*`), resolved in the phone-mirrored language via
/// `AppLocale`. Layout direction is applied at the root (`WatchMainTabView`).
struct WatchSettingsView: View {
    @EnvironmentObject private var store: WatchSessionStore

    private var summary: WatchSettingsSummary { store.snapshot.settingsSummary }

    var body: some View {
        List {
            Section {
                readOnlyRow(AppLocale.tr("watch.settings.name"), summary.workerFullName.isEmpty ? "—" : summary.workerFullName)
            } header: {
                sectionHeader(AppLocale.tr("watch.settings.workerInfo"), "person.fill")
            }

            Section {
                readOnlyRow(AppLocale.tr("watch.settings.workplaceRow"), summary.workplaceName.isEmpty ? "—" : summary.workplaceName)
            } header: {
                sectionHeader(AppLocale.tr("watch.settings.workplace"), "building.2.fill")
            }

            Section {
                readOnlyRow(AppLocale.tr("watch.settings.hourlyRate"), formattedPay(summary.hourlyRate))
                readOnlyRow(AppLocale.tr("watch.settings.gasAllowance"), formattedPay(summary.dailyGasAllowance))
                readOnlyRow(AppLocale.tr("watch.settings.standardDay"), hours(summary.standardDayHours))
                readOnlyRow(AppLocale.tr("watch.settings.otCapDay"), hours(summary.ot125HoursCap))
                readOnlyRow(AppLocale.tr("watch.settings.weeklyStandard"), hours(summary.weeklyStandardHours, decimals: 0))
                readOnlyRow(AppLocale.tr("watch.settings.weeklyOTCap"), hours(summary.weeklyOvertimeCapHours, decimals: 0))
            } header: {
                sectionHeader(AppLocale.tr("watch.settings.payHours"), "dollarsign.circle.fill")
            }

            Section {
                readOnlyRow(AppLocale.tr("watch.settings.restDay"), summary.restDayName)
                if let second = summary.secondRestDayName {
                    readOnlyRow(AppLocale.tr("watch.settings.secondRestDay"), second)
                }
            } header: {
                sectionHeader(AppLocale.tr("watch.settings.workRules"), "calendar.badge.clock")
            }

            Section {
                readOnlyRow(
                    AppLocale.tr("watch.settings.startsOnLabel"),
                    String(format: AppLocale.tr("watch.settings.startsOnDay %@"), "\(summary.payrollStartDay)")
                )
                readOnlyRow(AppLocale.tr("watch.settings.currentWindow"), summary.payrollWindowLabel)
            } header: {
                sectionHeader(AppLocale.tr("watch.settings.payroll"), "calendar")
            }

            Section {
                readOnlyRow(AppLocale.tr("watch.settings.maritalStatus"), summary.maritalStatusName)
                if summary.hasChildren {
                    readOnlyRow(AppLocale.tr("watch.settings.children"), "\(summary.numberOfChildren)")
                }
                readOnlyRow(AppLocale.tr("watch.settings.creditPoints"), String(format: "%.2f", summary.creditPoints))
            } header: {
                sectionHeader(AppLocale.tr("watch.settings.taxProfile"), "percent")
            }

            Section {
                Toggle(AppLocale.tr("watch.settings.requireBiometrics"), isOn: Binding(
                    get: { summary.appLockEnabled },
                    set: { store.toggleAppLock($0) }
                ))
            } header: {
                sectionHeader(AppLocale.tr("watch.settings.appLock"), "lock.fill")
            }

            Section {
                Toggle(AppLocale.tr("watch.settings.hidePayOnWidgets"), isOn: Binding(
                    get: { summary.hideWidgetPay },
                    set: { store.toggleHideWidgetPay($0) }
                ))
            } header: {
                sectionHeader(AppLocale.tr("watch.settings.widgetPrivacy"), "eye.slash.fill")
            }

            if summary.isCloudSyncSupported {
                Section {
                    Toggle(AppLocale.tr("watch.settings.syncAcrossDevices"), isOn: Binding(
                        get: { summary.isCloudSyncEnabled },
                        set: { store.toggleCloudSync($0) }
                    ))
                    if summary.isCloudSyncEnabled {
                        Text(summary.cloudSyncStatusText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    sectionHeader(AppLocale.tr("watch.settings.icloudSync"), "icloud.fill")
                }
            }

            Section {
                Picker(AppLocale.tr("watch.settings.appLanguage"), selection: Binding(
                    get: { summary.languageOptionRaw },
                    set: { store.setLanguage($0) }
                )) {
                    ForEach(summary.languageOptions) { option in
                        Text(option.label).tag(option.raw)
                    }
                }
            } header: {
                sectionHeader(AppLocale.tr("watch.settings.language"), "globe")
            }

            Section {
                readOnlyRow(AppLocale.tr("watch.settings.version"), summary.appVersion)
                Text(AppLocale.tr("watch.settings.phoneOnly"))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            } header: {
                sectionHeader(AppLocale.tr("watch.settings.about"), "info.circle.fill")
            }
        }
        .navigationTitle(L10n.tabSettings)
    }

    /// `"%.1fh"` was an English-only literal ("8.6h"); a bare `h` reads wrong
    /// under RTL. Format through `MeasurementFormatter` in the mirrored locale so
    /// the unit is localized ("8.6 hr" / "8.6 שע'").
    private func hours(_ value: Double, decimals: Int = 1) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = AppLocale.resolvedLocale
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = decimals
        formatter.numberFormatter.minimumFractionDigits = 0
        return formatter.string(from: Measurement(value: value, unit: UnitDuration.hours))
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
