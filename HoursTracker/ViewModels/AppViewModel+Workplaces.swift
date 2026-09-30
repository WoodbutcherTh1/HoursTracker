import SwiftUI

/// Multiple workplaces. Storage is unchanged — every shift is still saved, backed
/// up and synced in the one list (`sessions`), and every workplace's settings live
/// inside the main settings (`settings.additionalWorkplaces`). What changes is what
/// the app *shows and prices*: `workSessions` / `activeSettings` are the active
/// workplace only, so its hours and pay never mix with another job's. With a single
/// workplace (everyone until they add one) both equal `sessions` / `settings`.
extension AppViewModel {
    nonisolated static let activeWorkplaceKey = "activeWorkplaceID"
    nonisolated static let showAllWorkplacesKey = "showAllWorkplaces"

    struct WorkplaceOption: Identifiable, Equatable {
        /// `nil` = the main workplace.
        let workplaceID: UUID?
        let name: String
        let colorIndex: Int

        var id: String { workplaceID?.uuidString ?? "main" }
        var color: Color { WorkplacePalette.color(colorIndex) }
    }

    var hasMultipleWorkplaces: Bool {
        !settings.additionalWorkplaces.isEmpty
    }

    /// Main first, then the others in the order they were added.
    var workplaceOptions: [WorkplaceOption] {
        var options = [WorkplaceOption(
            workplaceID: nil,
            name: Self.displayName(settings.workplaceName, fallbackNumber: 1),
            colorIndex: 0
        )]
        for (index, extra) in settings.additionalWorkplaces.enumerated() {
            options.append(WorkplaceOption(
                workplaceID: extra.id,
                name: Self.displayName(extra.settings.workplaceName, fallbackNumber: index + 2),
                colorIndex: extra.colorIndex
            ))
        }
        return options
    }

    static func displayName(_ name: String, fallbackNumber: Int) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L10n.workplaceNumbered(fallbackNumber) : trimmed
    }

    /// A shift's workplace, with ids of workplaces that no longer exist (or were
    /// never known on this device) folded into the main one — so no shift is ever
    /// hidden from every view.
    func workplaceKey(for workplaceID: UUID?) -> UUID? {
        guard let workplaceID,
              settings.additionalWorkplaces.contains(where: { $0.id == workplaceID }) else { return nil }
        return workplaceID
    }

    /// The workplace the app is showing (nil = main).
    var activeWorkplaceKey: UUID? {
        workplaceKey(for: activeWorkplaceID)
    }

    var activeWorkplace: WorkplaceOption {
        workplaceOption(for: activeWorkplaceKey)
    }

    func workplaceOption(for workplaceID: UUID?) -> WorkplaceOption {
        let key = workplaceKey(for: workplaceID)
        let options = workplaceOptions
        return options.first { $0.workplaceID == key } ?? options[0]
    }

    /// Full settings of one workplace. The national ID is only ever kept on the
    /// main settings (Keychain), so it is filled in here for the others.
    func workplaceSettings(for workplaceID: UUID?) -> WorkplaceSettings {
        guard let key = workplaceKey(for: workplaceID),
              let extra = settings.additionalWorkplaces.first(where: { $0.id == key }) else {
            return settings
        }
        var own = extra.settings
        own.workerIDNumber = settings.workerIDNumber
        return own
    }

    /// Every shift of one workplace.
    func workplaceSessions(for workplaceID: UUID?) -> [WorkSession] {
        guard hasMultipleWorkplaces else { return sessions }
        let key = workplaceKey(for: workplaceID)
        return sessions.filter { workplaceKey(for: $0.workplaceID) == key }
    }

    /// The active workplace's settings — what every pay figure and pay screen uses.
    var activeSettings: WorkplaceSettings {
        hasMultipleWorkplaces ? workplaceSettings(for: activeWorkplaceKey) : settings
    }

    /// The active workplace's shifts — what Home, History, Export, widgets, the
    /// Watch and Siri show.
    var workSessions: [WorkSession] {
        workplaceSessions(for: activeWorkplaceKey)
    }

    /// History's list: the active workplace, or every workplace when merged.
    var isShowingAllWorkplaces: Bool {
        showAllWorkplaces && hasMultipleWorkplaces
    }

    var historySessions: [WorkSession] {
        isShowingAllWorkplaces ? sessions : workSessions
    }

    // MARK: - Switching

    /// Shows another workplace. Not while a shift is open, so the running shift,
    /// its Live Activity and its pay always belong to the workplace on screen.
    @discardableResult
    func switchWorkplace(to workplaceID: UUID?) -> Bool {
        let key = workplaceKey(for: workplaceID)
        guard key != activeWorkplaceKey else { return true }
        guard activeSession == nil else {
            errorMessage = L10n.workplaceSwitchWhileClockedIn
            return false
        }
        activeWorkplaceID = key
        Self.storeActiveWorkplaceID(key)
        workplaceDidChange()
        return true
    }

    func setShowAllWorkplaces(_ show: Bool) {
        showAllWorkplaces = show
        UserDefaults.standard.set(show, forKey: Self.showAllWorkplacesKey)
    }

    nonisolated static func loadActiveWorkplaceID() -> UUID? {
        UserDefaults.standard.string(forKey: activeWorkplaceKey).flatMap(UUID.init(uuidString:))
    }

    nonisolated static func storeActiveWorkplaceID(_ id: UUID?) {
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: activeWorkplaceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeWorkplaceKey)
        }
    }

    // MARK: - Managing workplaces

    /// Adds a workplace that starts from the current one's pay rules (rate,
    /// overtime, rest days, tax) with its own name, and switches to it.
    @discardableResult
    func addWorkplace(named name: String) -> UUID? {
        guard activeSession == nil else {
            errorMessage = L10n.workplaceSwitchWhileClockedIn
            return nil
        }
        var template = activeSettings
        template.workplaceName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        template.workerIDNumber = ""
        template.leaveDays = []
        template.locationLatitude = nil
        template.locationLongitude = nil
        template.arrivalRemindersEnabled = false
        template.modifiedAt = Date()
        let extra = AdditionalWorkplace(
            colorIndex: WorkplacePalette.nextIndex(used: settings.additionalWorkplaces.map(\.colorIndex)),
            settings: template
        )
        var updated = settings
        updated.additionalWorkplaces.append(extra)
        saveSettings(updated)
        switchWorkplace(to: extra.id)
        return extra.id
    }

    func renameWorkplace(_ workplaceID: UUID?, to name: String) {
        var edited = workplaceSettings(for: workplaceID)
        edited.workplaceName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        saveWorkplaceSettings(edited, for: workplaceID)
    }

    /// Shifts that belong to an extra workplace (for the delete confirmation).
    func shiftCount(in workplaceID: UUID) -> Int {
        sessions.filter { $0.workplaceID == workplaceID }.count
    }

    /// Removes an extra workplace. Its shifts go to Recently deleted (30 days) —
    /// never silently into the main workplace's pay.
    func deleteWorkplace(_ workplaceID: UUID) {
        guard settings.additionalWorkplaces.contains(where: { $0.id == workplaceID }) else { return }
        guard !sessions.contains(where: { $0.workplaceID == workplaceID && $0.isOpen }) else {
            errorMessage = L10n.workplaceSwitchWhileClockedIn
            return
        }
        trashSessions(sessions.filter { $0.workplaceID == workplaceID })
        if activeWorkplaceKey == workplaceID {
            activeWorkplaceID = nil
            Self.storeActiveWorkplaceID(nil)
        }
        var updated = settings
        updated.additionalWorkplaces.removeAll { $0.id == workplaceID }
        saveSettings(updated)
        workplaceDidChange()
    }

    /// Saves one workplace's settings (the Settings screen edits the active one).
    func saveWorkplaceSettings(_ edited: WorkplaceSettings, for workplaceID: UUID?) {
        guard let key = workplaceKey(for: workplaceID),
              let index = settings.additionalWorkplaces.firstIndex(where: { $0.id == key }) else {
            // Main workplace: keep the live list of other workplaces.
            var main = edited
            main.additionalWorkplaces = settings.additionalWorkplaces
            saveSettings(main)
            return
        }
        var own = edited
        own.workerIDNumber = ""          // the national ID stays on the main settings only
        own.additionalWorkplaces = []
        own.modifiedAt = Date()
        var updated = settings
        updated.additionalWorkplaces[index].settings = own
        saveSettings(updated)
    }

    func saveActiveWorkplaceSettings(_ edited: WorkplaceSettings) {
        saveWorkplaceSettings(edited, for: activeWorkplaceKey)
    }

    /// Everything that shows the active workplace refreshes.
    func workplaceDidChange() {
        objectWillChange.send()
        refreshLiveCurve()
        refreshReminders()
        syncWidget()
        refreshAppShortcuts()
        WatchConnectivityManager.shared.pushSnapshot()
    }
}
