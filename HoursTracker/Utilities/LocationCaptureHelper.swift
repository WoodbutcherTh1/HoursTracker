import Foundation
import CoreLocation

enum LocationCaptureError: LocalizedError {
    case denied

    var errorDescription: String? {
        switch self {
        case .denied:
            return L10n.settingsLocationDenied
        }
    }
}

@MainActor
final class LocationCaptureHelper: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var lastLocation: CLLocation?
    @Published var error: Error?

    private let manager = CLLocationManager()
    /// True after `capture()` while waiting for the When-In-Use prompt to resolve.
    private var pendingCapture = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func capture() {
        error = nil
        switch manager.authorizationStatus {
        case .notDetermined:
            pendingCapture = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            pendingCapture = false
            manager.requestLocation()
        case .denied, .restricted:
            pendingCapture = false
            error = LocationCaptureError.denied
        @unknown default:
            pendingCapture = false
            error = LocationCaptureError.denied
        }
    }

    /// Pure helper for tests: only request a fix after When-In-Use/Always is granted.
    nonisolated static func shouldRequestLocation(for status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard pendingCapture else { return }
            if Self.shouldRequestLocation(for: status) {
                pendingCapture = false
                manager.requestLocation()
            } else if status == .denied || status == .restricted {
                pendingCapture = false
                error = LocationCaptureError.denied
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            lastLocation = location
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.error = error
        }
    }
}
