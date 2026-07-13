import Foundation
import CoreLocation
import UserNotifications

protocol LocationReminderManaging: AnyObject {
    func configure(settings: WorkplaceSettings, sessions: [WorkSession])
    func requestPermissions()
    func updateWorkplaceLocation(latitude: Double, longitude: Double, radius: Double)
}

final class LocationReminderManager: NSObject, LocationReminderManaging {
    static let shared = LocationReminderManager()

    private let locationManager = CLLocationManager()
    private let notificationCenter = UNUserNotificationCenter.current()

    private var settings = WorkplaceSettings.default
    private var sessions: [WorkSession] = []
    private var workplaceRegion: CLCircularRegion?

    private let workplaceRegionID = "workplace-geofence"
    private let clockOutReminderID = "clock-out-reminder"
    private let forgotClockOutID = "forgot-clock-out"

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.pausesLocationUpdatesAutomatically = false
        // Only enable background updates after Always authorization — enabling earlier can crash.
    }

    func configure(settings: WorkplaceSettings, sessions: [WorkSession]) {
        self.settings = settings
        self.sessions = sessions
        setupGeofence()
        scheduleClockOutReminder()
        scheduleForgotClockOutReminder()
    }

    func requestPermissions() {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        locationManager.requestAlwaysAuthorization()
    }

    func updateWorkplaceLocation(latitude: Double, longitude: Double, radius: Double) {
        settings.locationLatitude = latitude
        settings.locationLongitude = longitude
        settings.locationRadiusMeters = radius
        setupGeofence()
    }

    // MARK: - Geofence

    private func setupGeofence() {
        guard let lat = settings.locationLatitude,
              let lon = settings.locationLongitude else { return }

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
        if manager.authorizationStatus == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
            setupGeofence()
        } else if manager.authorizationStatus == .authorizedWhenInUse {
            manager.allowsBackgroundLocationUpdates = false
            setupGeofence()
        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        // Geofence monitoring can fail on simulator or without location permission.
    }
}
