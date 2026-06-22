import CoreLocation
import MapKit
import Observation

/// Wraps `CLLocationManager` and exposes the current location and authorization
/// status to SwiftUI. Delegate callbacks arrive off the main actor, so each one
/// hops back onto the main actor before touching observable state.
@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    var location: CLLocation?
    var placeName: String?
    var authorizationStatus: CLAuthorizationStatus
    var lastError: String?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func refresh() {
        guard authorizationStatus == .authorizedWhenInUse
            || authorizationStatus == .authorizedAlways else { return }
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let latest = locations.last else { return }
        // Extract Sendable scalars; CLLocation itself must not cross the hop.
        let coordinate = latest.coordinate
        Task { @MainActor in
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            self.location = location
            self.lastError = nil
            await self.reverseGeocode(location)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        let message = error.localizedDescription
        Task { @MainActor in
            // A failure here keeps the last known location; only surface the message.
            self.lastError = message
        }
    }

    private func reverseGeocode(_ location: CLLocation) async {
        guard let request = MKReverseGeocodingRequest(location: location) else { return }
        let items = try? await request.mapItems
        guard let item = items?.first else { return }
        // Prefer the locality (e.g. "Santa Rosa Beach"); fall back to the
        // map item's display name.
        placeName = item.addressRepresentations?.cityName ?? item.name
    }
}
