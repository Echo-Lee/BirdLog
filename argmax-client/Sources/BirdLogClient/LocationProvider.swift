// GPS capture. Per the BirdLog data model, a location fix is taken exactly
// once per checklist — when the user says "start checklist". Nothing else
// is geotagged.

import CoreLocation
import Foundation

final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// Returns the best available fix, prompting for permission if needed.
    /// Gracefully returns nil when location is denied/unavailable — the
    /// checklist then falls back to its spoken location name.
    func currentLocation() async -> CLLocation? {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            return nil
        }
        return await withCheckedContinuation { cont in
            self.continuation = cont
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
                // The delegate's didChangeAuthorization will fire, then we request.
            } else {
                manager.requestLocation()
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted, .notDetermined:
            if manager.authorizationStatus != .notDetermined { finish(nil) }
        @unknown default:
            finish(nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.first)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("  (GPS unavailable: \(error.localizedDescription) — say the place name instead)")
        finish(nil)
    }

    private func finish(_ location: CLLocation?) {
        continuation?.resume(returning: location)
        continuation = nil
    }
}