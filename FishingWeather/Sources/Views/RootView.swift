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

    /// Changes whenever the selected spot or the GPS coordinate changes, so the
    /// load task re-runs on either.
    private var loadKey: String {
        let selection = spots.selectedSpotID?.uuidString ?? "gps"
        let lat = location.location?.coordinate.latitude ?? 0
        return "\(selection)-\(lat)"
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
            if spots.selectedSpot != nil {
                MainTabView()
            } else {
                NavigationStack { LocationDeniedView() }
            }
        default:
            MainTabView()
        }
    }
}
