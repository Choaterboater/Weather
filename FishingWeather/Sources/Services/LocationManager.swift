import CoreLocation
import MapKit
import Observation

/// Wraps `CLLocationManager` and exposes the current location and authorization
/// status to SwiftUI. Delegate callbacks arrive off the main actor, so each one
/// hops back onto the main actor before touching observable state.
@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    struct GeocodeResult: Sendable {
        let placeName: String?
        let stateCode: String?
        let featureName: String?

        init(placeName: String?, stateCode: String?, featureName: String? = nil) {
            self.placeName = placeName
            self.stateCode = stateCode
            self.featureName = featureName
        }
    }

    typealias ReverseGeocoder = @MainActor (CLLocation) async -> GeocodeResult?

    private let manager = CLLocationManager()
    private let reverseGeocoder: ReverseGeocoder

    var location: CLLocation?
    var placeName: String?
    /// Two-letter US state code for the current location (e.g. "FL"), or nil
    /// offshore / outside the US. Used to default state-specific data like
    /// fishing regulations when no saved spot is active.
    var administrativeArea: String?
    private(set) var descriptor = LocationDescriptor.make(
        city: nil,
        stateCode: nil,
        featureName: nil
    )
    var authorizationStatus: CLAuthorizationStatus
    var lastError: String?
    private var geocodeTask: Task<Void, Never>?

    init(reverseGeocoder: ReverseGeocoder? = nil) {
        self.reverseGeocoder = reverseGeocoder ?? Self.liveReverseGeocode
        #if DEBUG
        if Self.usesUITestingFixture {
            authorizationStatus = .authorizedWhenInUse
            location = Self.uiTestingLocation
            placeName = "St. Petersburg"
            administrativeArea = "FL"
            descriptor = LocationDescriptor.make(
                city: "St. Petersburg",
                stateCode: "FL",
                featureName: nil
            )
        } else {
            authorizationStatus = manager.authorizationStatus
        }
        #else
        authorizationStatus = manager.authorizationStatus
        #endif
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestPermission() {
        #if DEBUG
        guard !Self.usesUITestingFixture else { return }
        #endif
        manager.requestWhenInUseAuthorization()
    }

    func refresh() {
        guard authorizationStatus == .authorizedWhenInUse
            || authorizationStatus == .authorizedAlways else { return }
        #if DEBUG
        guard !Self.usesUITestingFixture else { return }
        #endif
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        #if DEBUG
        guard !Self.usesUITestingFixture else { return }
        #endif
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
        #if DEBUG
        guard !Self.usesUITestingFixture else { return }
        #endif
        guard let latest = locations.last else { return }
        // Extract Sendable scalars; CLLocation itself must not cross the hop.
        let coordinate = latest.coordinate
        Task { @MainActor in
            self.acceptLocation(coordinate)
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

    func acceptLocation(_ coordinate: CLLocationCoordinate2D) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        self.location = location
        placeName = nil
        administrativeArea = nil
        lastError = nil

        geocodeTask?.cancel()
        geocodeTask = Task { [weak self] in
            await self?.reverseGeocode(location)
        }
    }

    private func reverseGeocode(_ location: CLLocation) async {
        #if DEBUG
        guard !Self.usesUITestingFixture else { return }
        #endif
        let result = await reverseGeocoder(location)
        guard !Task.isCancelled,
              Self.isCurrentGeocode(location.coordinate, current: self.location)
        else { return }
        guard let result else { return }
        placeName = result.placeName
        administrativeArea = result.stateCode
        descriptor = LocationDescriptor.make(
            city: result.placeName,
            stateCode: result.stateCode,
            featureName: result.featureName
        )
    }

    private static func liveReverseGeocode(_ location: CLLocation) async -> GeocodeResult? {
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first
        else { return nil }
        let address = item.addressRepresentations
        return GeocodeResult(
            placeName: address?.cityName,
            stateCode: usStateCode(from: address),
            featureName: item.name
        )
    }

    nonisolated static func isCurrentGeocode(
        _ requested: CLLocationCoordinate2D,
        current: CLLocation?
    ) -> Bool {
        guard let current else { return false }
        let coordinate = current.coordinate
        return abs(requested.latitude - coordinate.latitude) < 0.000_000_1
            && abs(requested.longitude - coordinate.longitude) < 0.000_000_1
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

    #if DEBUG
    nonisolated private static var usesUITestingFixture: Bool {
        CommandLine.arguments.contains("-uiTesting")
    }

    nonisolated private static var uiTestingLocation: CLLocation {
        CLLocation(latitude: 27.7634, longitude: -82.6403)
    }
    #endif
}
