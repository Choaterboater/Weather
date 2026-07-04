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
    /// Two-letter US state code for the current location (e.g. "FL"), or nil
    /// offshore / outside the US. Used to default state-specific data like
    /// fishing regulations when no saved spot is active.
    var administrativeArea: String?
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
        let address = item.addressRepresentations
        // Prefer the locality (e.g. "Santa Rosa Beach"); fall back to the
        // map item's display name.
        placeName = address?.cityName ?? item.name
        administrativeArea = Self.usStateCode(from: address)
    }

    /// iOS 26's MapKit exposes no structured administrative-area field — the
    /// two-letter US state code only appears as text in
    /// `cityWithContext(.short)` ("Naples, FL"). `regionCode` is the *country*
    /// code, not the state. We take the trailing token (already the USPS
    /// abbreviation for US addresses) and accept it only if it's two letters;
    /// callers further validate it against the states they have data for. This
    /// keeps us off the iOS-26-deprecated `CLGeocoder`/`CLPlacemark` path.
    private static func usStateCode(from address: MKAddressRepresentations?) -> String? {
        guard let cityWithState = address?.cityWithContext(.short),
              let token = cityWithState.split(separator: ",").last?
                  .trimmingCharacters(in: .whitespaces),
              token.count == 2,
              token.allSatisfy(\.isLetter)
        else { return nil }
        return token.uppercased()
    }
}
