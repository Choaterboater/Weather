import CoreLocation
import SwiftUI

struct RootView: View {
    @Environment(LocationManager.self) private var location
    @Environment(WeatherStore.self) private var weather
    @Environment(SpotStore.self) private var spots

    /// Selected saved spot wins; otherwise the device's current location.
    private var activeLocation: CLLocation? {
        spots.selectedSpot?.location ?? location.location
    }

    /// Changes when the *active* coordinate changes: the spot's identity while
    /// a saved spot is selected (GPS drift must not re-key it), otherwise the
    /// GPS coordinate rounded to ~0.7 mi so every minor fix doesn't cancel an
    /// in-flight fetch and refetch the full forecast.
    private var loadKey: String {
        if let spot = spots.selectedSpot {
            return "spot-\(spot.id.uuidString)"
        }
        guard let coord = location.location?.coordinate else { return "gps-none" }
        let lat = (coord.latitude * 100).rounded() / 100
        let lon = (coord.longitude * 100).rounded() / 100
        return "gps-\(lat),\(lon)"
    }

    var body: some View {
        content
            .task(id: loadKey) {
                if let coordinate = activeLocation {
                    await weather.load(for: coordinate)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch location.authorizationStatus {
        case .notDetermined:
            NavigationStack {
                LocationPromptView { location.requestPermission() }
            }
        case .denied, .restricted:
            // Still usable if the angler has saved spots from before.
            if Self.canEnterMainContent(
                status: location.authorizationStatus,
                hasSavedSpots: !spots.spots.isEmpty
            ) {
                MainTabView()
            } else {
                NavigationStack { LocationDeniedView() }
            }
        default:
            MainTabView()
        }
    }

    nonisolated static func canEnterMainContent(
        status: CLAuthorizationStatus,
        hasSavedSpots: Bool
    ) -> Bool {
        switch status {
        case .denied, .restricted:
            hasSavedSpots
        case .notDetermined:
            false
        default:
            true
        }
    }
}
