import Foundation
import CoreLocation
import UserNotifications

protocol LocationReminderManaging: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var areNotificationsDenied: Bool { get }
    func configure(settings: WorkplaceSettings, sessions: [WorkSession])
    /// Staged: notifications + When-In-Use first, then Always once When-In-Use is granted.
    func requestArrivalReminderPermissions()
    func stopArrivalReminders()
    func updateWorkplaceLocation(latitude: Double, longitude: Double, radius: Double)
    func refreshPermissionStatuses()
}

final class LocationReminderManager: NSObject, LocationReminderManaging {
    static let shared = LocationReminderManager()

    private let locationManager = CLLocationManager()
    private let notificationCenter = UNUserNotificationCenter.current()

    private var settings = WorkplaceSettings.default
    private var sessions: [WorkSession] = []
    private var workplaceRegion: CLCircularRegion?
    /// True while we still need to upgrade When-In-Use → Always for arrival reminders.
    private var pendingAlwaysAuthorization = false

    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var areNotificationsDenied = false

    private let workplaceRegionID = "workplace-geofence"
    private let clockOutReminderID = "clock-out-reminder"
    private let forgotClockOutID = "forgot-clock-out"

    private override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        // Region monitoring (geofencing) relaunches the app on entry even when
        // terminated. It does not require UIBackgroundModes: location or
        // allowsBackgroundLocationUpdates — those are continuous tracking APIs.
    }

    func configure(settings: WorkplaceSettings, sessions: [WorkSession]) {
        self.settings = settings
        self.sessions = sessions
        if settings.arrivalRemindersEnabled {
            setupGeofence()
        } else {
            clearGeofence()
        }
        scheduleClockOutReminder()
        scheduleForgotClockOutReminder()
    }

    func requestArrivalReminderPermissions() {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.areNotificationsDenied = !granted
                // Still stage location auth so the geofence can arm if the user
                // later enables notifications in system Settings.
                self.beginLocationAuthorizationFlow()
            }
        }
    }

    func stopArrivalReminders() {
        pendingAlwaysAuthorization = false
        clearGeofence()
    }

    func updateWorkplaceLocation(latitude: Double, longitude: Double, radius: Double) {
        settings.locationLatitude = latitude
        settings.locationLongitude = longitude
        settings.locationRadiusMeters = radius
        if settings.arrivalRemindersEnabled {
            setupGeofence()
        }
    }

    func refreshPermissionStatuses() {
        authorizationStatus = locationManager.authorizationStatus
        notificationCenter.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.areNotificationsDenied = settings.authorizationStatus == .denied
            }
        }
    }

    // MARK: - Authorization staging

    private func beginLocationAuthorizationFlow() {
        authorizationStatus = locationManager.authorizationStatus
        switch authorizationStatus {
        case .notDetermined:
            pendingAlwaysAuthorization = true
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            pendingAlwaysAuthorization = true
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            pendingAlwaysAuthorization = false
            setupGeofence()
        case .denied, .restricted:
            pendingAlwaysAuthorization = false
        @unknown default:
            pendingAlwaysAuthorization = false
        }
    }

    // MARK: - Geofence

    private func clearGeofence() {
        if let existing = workplaceRegion {
            locationManager.stopMonitoring(for: existing)
            workplaceRegion = nil
        }
    }

    private func setupGeofence() {
        guard settings.arrivalRemindersEnabled,
              let lat = settings.locationLatitude,
              let lon = settings.locationLongitude else {
            clearGeofence()
            return
        }

        // Region monitoring works with Always (preferred) and can be armed while
        // When-In-Use; delivery while terminated requires Always.
        let status = locationManager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            clearGeofence()
            return
        }

        if let existing = workplaceRegion {
            locationManager.stopMonitoring(for: existing)
        }

        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            radius: min(settings.locationRadiusMeters, locationManager.maximumRegionMonitoringDistance),
            identifier: workplaceRegionID
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false
        workplaceRegion = region
        locationManager.startMonitoring(for: region)
    }

    // MARK: - Notifications

    /// Any open session counts, not just today's — a session left open past
    /// midnight still needs its clock-out reminders.
    private func hasOpenSession() -> Bool {
        sessions.contains(where: \.isOpen)
    }

    private func hasAnySessionToday() -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        return sessions.contains { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }

    private func sendClockInNotification() {
        guard !hasAnySessionToday() else { return }
        let content = UNMutableNotificationContent()
        content.title = settings.workplaceName
        content.body = AppLocale.clockInPrompt()
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "clock-in-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        notificationCenter.add(request)
    }

    func scheduleClockOutReminder() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [clockOutReminderID])
        guard hasOpenSession() else { return }
        guard let reminderTime = estimatedClockOutTime() else { return }

        var components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        components.second = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let content = UNMutableNotificationContent()
        content.title = settings.workplaceName
        content.body = AppLocale.clockOutReminder()
        content.sound = .default

        let request = UNNotificationRequest(identifier: clockOutReminderID, content: content, trigger: trigger)
        notificationCenter.add(request)
    }

    func scheduleForgotClockOutReminder() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [forgotClockOutID])
        guard hasOpenSession() else { return }

        var components = DateComponents()
        components.hour = 23
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let content = UNMutableNotificationContent()
        content.title = settings.workplaceName
        content.body = AppLocale.forgotClockOut()
        content.sound = .default

        let request = UNNotificationRequest(identifier: forgotClockOutID, content: content, trigger: trigger)
        notificationCenter.add(request)
    }

    func estimatedClockOutTime() -> Date? {
        Self.estimatedClockOutTime(from: sessions)
    }

    /// Average clock-out time of the last up-to-10 completed sessions,
    /// rounded up to the nearest 10 minutes, projected onto today.
    static func estimatedClockOutTime(
        from sessions: [WorkSession],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        let completed = sessions
            .filter { $0.clockOut != nil }
            .sorted { ($0.clockOut ?? .distantPast) > ($1.clockOut ?? .distantPast) }
            .prefix(10)

        guard !completed.isEmpty else { return nil }

        let secondsFromMidnight = completed.compactMap { session -> Double? in
            guard let out = session.clockOut else { return nil }
            let components = calendar.dateComponents([.hour, .minute, .second], from: out)
            let h = Double(components.hour ?? 0)
            let m = Double(components.minute ?? 0)
            let s = Double(components.second ?? 0)
            return h * 3600 + m * 60 + s
        }

        guard !secondsFromMidnight.isEmpty else { return nil }
        let average = secondsFromMidnight.reduce(0, +) / Double(secondsFromMidnight.count)

        let roundedMinutes = Int(ceil(average / 600) * 600 / 60)
        let hours = roundedMinutes / 60
        let minutes = roundedMinutes % 60

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hours
        components.minute = minutes
        components.second = 0
        return calendar.date(from: components)
    }
}

extension LocationReminderManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == workplaceRegionID else { return }
        sendClockInNotification()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .authorizedWhenInUse:
            if pendingAlwaysAuthorization {
                manager.requestAlwaysAuthorization()
            } else if settings.arrivalRemindersEnabled {
                setupGeofence()
            }
        case .authorizedAlways:
            pendingAlwaysAuthorization = false
            if settings.arrivalRemindersEnabled {
                setupGeofence()
            }
        case .denied, .restricted:
            pendingAlwaysAuthorization = false
            clearGeofence()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        // Geofence monitoring can fail on simulator or without location permission.
    }
}
